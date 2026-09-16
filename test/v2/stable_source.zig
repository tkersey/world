const std = @import("std");
const boundary = @import("boundary");
const source = boundary.source;
const Session = @import("stable_runtime").Session;
const testing = std.testing;
const Resident = @import("stable_runtime").Resident;

fn releaseResident(resident: *Resident) void {
    resident.close() catch |err| switch (err) {
        error.UnfinishedSession => {
            const bytes = resident.takeCheckpoint(testing.allocator) catch unreachable;
            testing.allocator.free(bytes); // Explicit fixture custody transfer.
        },
        error.InvalidState => {},
        else => unreachable,
    };
}

fn residentFailureSweep(prepared: *const @import("stable_runtime").Prepared, checkpoint: []const u8, control: boundary.data_v2.invocation.Control, checkpoint_mode: bool) !void {
    var reference = try Resident.restore(testing.allocator, prepared, checkpoint);
    defer releaseResident(&reference);
    var expected = try reference.drive(testing.allocator, control, .{ .checkpoint = checkpoint_mode });
    defer expected.deinit();
    var failures: usize = 0;
    var failed_after_mutation = false;
    while (true) : (failures += 1) {
        var failing = testing.FailingAllocator.init(testing.allocator, .{});
        var resident = try Resident.restore(failing.allocator(), prepared, checkpoint);
        defer releaseResident(&resident);
        var statistics: std.meta.Child(@typeInfo(@FieldType(Session, "statistics")).optional.child) = .{};
        resident.session.?.statistics = &statistics;
        resident.session.?.store.statistics = &statistics.storage;
        failing.fail_index = failing.alloc_index + failures;
        failing.resize_fail_index = failing.resize_index;
        var output = resident.drive(failing.allocator(), control, .{ .checkpoint = checkpoint_mode }) catch |err| {
            failing.fail_index = std.math.maxInt(usize);
            failing.resize_fail_index = std.math.maxInt(usize);
            try testing.expectEqual(error.OutOfMemory, err);
            failed_after_mutation = failed_after_mutation or statistics.transitions != 0 or statistics.storage.added_nodes != 0 or statistics.storage.journal_nodes != 0;
            const unchanged = try resident.checkpoint(testing.allocator);
            defer testing.allocator.free(unchanged);
            try testing.expectEqualSlices(u8, checkpoint, unchanged);
            var retried = try resident.drive(testing.allocator, control, .{ .checkpoint = checkpoint_mode });
            defer retried.deinit();
            try testing.expectEqualDeep(expected.record, retried.record);
            continue;
        };
        defer output.deinit();
        failing.fail_index = std.math.maxInt(usize);
        failing.resize_fail_index = std.math.maxInt(usize);
        try testing.expectEqualDeep(expected.record, output.record);
        try testing.expect(failures != 0 and failed_after_mutation);
        break;
    }
}

test "resident rollback preserves acquired replies, cleanup custody, and reentrant captures at every allocation failure" {
    const protocol = boundary.data_v2.invocation;
    inline for (.{ retainedInputExample, source.examples.unwind, source.examples.reentrant }, 0..) |example, index| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try example(&builder));
        defer compiled.deinit();
        const image = try programBytes(compiled.program);
        defer testing.allocator.free(image);
        var prepared = try @import("stable_runtime").Prepared.init(testing.allocator, image);
        defer prepared.deinit();
        const arguments: []const u8 = switch (index) {
            0 => &.{ 42, 0, 0, 0, 0, 0, 0, 0 },
            1 => &.{0},
            else => &.{},
        };
        var session = try Session.start(testing.allocator, &prepared, arguments);
        defer session.deinit();
        const observation = try session.run(null);
        const checkpoint = try session.checkpoint(testing.allocator);
        defer testing.allocator.free(checkpoint);
        if (index == 2) {
            try testing.expect(observation == .yielded);
            for ([_]bool{ false, true }) |with_checkpoint| try residentFailureSweep(&prepared, checkpoint, .resume_yield, with_checkpoint);
        } else {
            try testing.expect(observation == .requested);
            var pending = try session.pendingRequest(testing.allocator);
            defer pending.deinit();
            const reply = try protocol.encodeOwned(protocol.Result, testing.allocator, .{ .request_identity = pending.request.request_identity, .value = &.{} });
            defer testing.allocator.free(reply);
            for ([_]bool{ false, true }) |with_checkpoint| try residentFailureSweep(&prepared, checkpoint, .{ .reply = reply }, with_checkpoint);
            if (index == 1) for ([_]bool{ false, true }) |with_checkpoint| try residentFailureSweep(&prepared, checkpoint, .{ .cancel = .{ .text = "stop" } }, with_checkpoint);
        }
    }
}

test "resident output capacity and checkpoint transfer preserve custody on failure" {
    const protocol = boundary.data_v2.invocation;
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try retainedInputExample(&builder));
    defer compiled.deinit();
    const image = try programBytes(compiled.program);
    defer testing.allocator.free(image);
    var prepared = try @import("stable_runtime").Prepared.init(testing.allocator, image);
    defer prepared.deinit();
    var resident = try Resident.start(testing.allocator, &prepared, &.{ 42, 0, 0, 0, 0, 0, 0, 0 });
    defer releaseResident(&resident);
    try testing.expectError(error.UnfinishedSession, resident.close());
    var pending = try resident.drive(testing.allocator, .none, .{ .checkpoint = true });
    defer pending.deinit();
    const engine = &resident.session.?;
    const copies = engine.frames.slots.statistics.value_copies;
    const custody_copies = engine.frames.custody.nodes.statistics.value_copies;
    {
        var transaction = try engine.begin();
        defer transaction.rollback(engine);
        try testing.expectEqual(copies, engine.frames.slots.statistics.value_copies);
        try testing.expectEqual(custody_copies, engine.frames.custody.nodes.statistics.value_copies);
    }
    var request = try protocol.decode(protocol.Request, testing.allocator, pending.record.requested.request);
    defer request.deinit();
    const reply = try protocol.encodeOwned(protocol.Result, testing.allocator, .{ .request_identity = request.value.request_identity, .value = &.{} });
    defer testing.allocator.free(reply);
    var output = [_]u8{0xa5} ** 512;
    try testing.expectError(error.Capacity, resident.driveInto(.{ .reply = reply }, .{ .checkpoint = true }, output[0..1]));
    for (output) |byte| try testing.expectEqual(0xa5, byte);
    const unchanged = try resident.checkpoint(testing.allocator);
    defer testing.allocator.free(unchanged);
    try testing.expectEqualSlices(u8, pending.record.requested.state.?, unchanged);
    var empty: [0]u8 = .{};
    var failed_output = std.heap.FixedBufferAllocator.init(&empty);
    try testing.expectError(error.OutOfMemory, resident.takeCheckpoint(failed_output.allocator()));
    const transferred = try resident.takeCheckpoint(testing.allocator);
    defer testing.allocator.free(transferred);
    try testing.expectEqualSlices(u8, unchanged, transferred);
    try testing.expectError(error.InvalidState, resident.checkpoint(testing.allocator));
    var restored = try Resident.restore(testing.allocator, &prepared, transferred);
    defer releaseResident(&restored);
    const bytes = try restored.driveInto(.{ .reply = reply }, .{ .checkpoint = true }, &output);
    var decoded = try protocol.decode(protocol.Outcome, testing.allocator, bytes);
    defer decoded.deinit();
    try testing.expectEqualSlices(u8, &.{ 42, 0, 0, 0, 0, 0, 0, 0 }, decoded.value.completed);
    try restored.close();
    try testing.expectError(error.InvalidState, restored.close());
    try testing.expectError(error.InvalidState, restored.drive(testing.allocator, .none, .{ .quantum = 0 }));
}

test "resident progress defers checkpoint publication until explicitly requested" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try retainedInputExample(&builder));
    defer compiled.deinit();
    const image = try programBytes(compiled.program);
    defer testing.allocator.free(image);
    var prepared = try @import("stable_runtime").Prepared.init(testing.allocator, image);
    defer prepared.deinit();
    var resident = try Resident.start(testing.allocator, &prepared, &.{ 42, 0, 0, 0, 0, 0, 0, 0 });
    defer releaseResident(&resident);
    var empty: [0]u8 = .{};
    var output = std.heap.FixedBufferAllocator.init(&empty);
    var progress = try resident.drive(output.allocator(), .none, .{ .quantum = 1 });
    defer progress.deinit();
    try testing.expect(progress.record == .progressed and progress.record.progressed == null);
    var pending = try resident.drive(testing.allocator, .none, .{});
    defer pending.deinit();
    try testing.expect(pending.record == .requested and pending.record.requested.state == null);
    const checkpoint = try resident.checkpoint(testing.allocator);
    defer testing.allocator.free(checkpoint);
    var restored = try Resident.restore(testing.allocator, &prepared, checkpoint);
    defer releaseResident(&restored);
    var polled = try restored.drive(testing.allocator, .none, .{});
    defer polled.deinit();
    try testing.expectEqualDeep(pending.record, polled.record);
}

test "a long resident drive journals entry state rather than transition history" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.recursive(&builder));
    defer compiled.deinit();
    const image = try programBytes(compiled.program);
    defer testing.allocator.free(image);
    var prepared = try @import("stable_runtime").Prepared.init(testing.allocator, image);
    defer prepared.deinit();
    var resident = try Resident.start(testing.allocator, &prepared, &.{ 16, 39, 0, 0, 0, 0, 0, 0 });
    defer releaseResident(&resident);
    var statistics: std.meta.Child(@typeInfo(@FieldType(Session, "statistics")).optional.child) = .{};
    resident.session.?.statistics = &statistics;
    resident.session.?.store.statistics = &statistics.storage;
    const entry_nodes = resident.session.?.store.nodes.items.len;
    var result = try resident.drive(testing.allocator, .none, .{});
    defer result.deinit();
    try testing.expectEqualSlices(u8, &.{1}, result.record.completed);
    try testing.expect(statistics.transitions >= 10_000);
    try testing.expect(statistics.storage.journal_nodes <= entry_nodes);
    try testing.expect(resident.session.?.store.nodes.items.len <= 512);
}

test "resident gate rejects reentrant observation during allocator callbacks" {
    const Callback = struct {
        child: std.mem.Allocator,
        resident: ?*Resident = null,
        attempted: bool = false,
        observed: ?anyerror = null,
        fn alloc(pointer: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
            const self: *@This() = @ptrCast(@alignCast(pointer));
            if (self.resident != null and !self.attempted) {
                self.attempted = true;
                if (self.resident.?.checkpoint(self.child)) |bytes| {
                    self.child.free(bytes);
                    self.observed = error.AcceptedReentrancy;
                } else |err| self.observed = err;
            }
            return self.child.rawAlloc(len, alignment, ra);
        }
        fn free(pointer: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ra: usize) void {
            const self: *@This() = @ptrCast(@alignCast(pointer));
            self.child.rawFree(bytes, alignment, ra);
        }
    };
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try retainedInputExample(&builder));
    defer compiled.deinit();
    const image = try programBytes(compiled.program);
    defer testing.allocator.free(image);
    var prepared = try @import("stable_runtime").Prepared.init(testing.allocator, image);
    defer prepared.deinit();
    var callback: Callback = .{ .child = testing.allocator };
    const allocator: std.mem.Allocator = .{ .ptr = &callback, .vtable = &.{
        .alloc = Callback.alloc,
        .free = Callback.free,
        .resize = std.mem.Allocator.noResize,
        .remap = std.mem.Allocator.noRemap,
    } };
    var resident = try Resident.start(allocator, &prepared, &.{ 42, 0, 0, 0, 0, 0, 0, 0 });
    defer releaseResident(&resident);
    callback.resident = &resident;
    var result = try resident.drive(testing.allocator, .none, .{ .quantum = 0 });
    defer result.deinit();
    try testing.expect(callback.attempted);
    try testing.expectEqual(error.Busy, callback.observed.?);
}

fn answerWithValue(subject: *Session, value: []const u8) !void {
    const protocol = boundary.data_v2.invocation;
    var pending = try subject.pendingRequest(testing.allocator);
    defer pending.deinit();
    const response = try protocol.encodeOwned(protocol.Result, testing.allocator, .{
        .request_identity = pending.request.request_identity,
        .value = value,
    });
    defer testing.allocator.free(response);
    try subject.answer(response);
}

fn checkedCheckpoint(subject: *Session) !void {
    const bytes = try subject.checkpoint(testing.allocator);
    defer testing.allocator.free(bytes);
    var decoded = try boundary.data_v2.state_image.decodeGraph(testing.allocator, bytes);
    defer decoded.deinit();
    try boundary.data_v2.state_admission.validateStable(testing.allocator, subject.program, decoded.state);
    const reencoded = try boundary.data_v2.state_image.emit(testing.allocator, decoded.state);
    defer testing.allocator.free(reencoded);
    try testing.expectEqualSlices(u8, bytes, reencoded);
    const repeated = try subject.checkpoint(testing.allocator);
    defer testing.allocator.free(repeated);
    try testing.expectEqualSlices(u8, bytes, repeated);
    try testing.expectEqual(subject.program_identity, decoded.state.program_identity);
}

fn drive(subject: *Session, quantum: ?usize) !@import("stable_runtime").Observation {
    const before = try subject.checkpoint(testing.allocator);
    defer testing.allocator.free(before);
    const codec = boundary.data_v2.program_image;
    const image = try testing.allocator.alloc(u8, try codec.encodedLength(subject.program));
    defer testing.allocator.free(image);
    _ = try codec.encode(testing.allocator, subject.program, image);
    var restored = try Session.restoreImage(testing.allocator, image, before);
    defer restored.deinit();
    var fresh = try @import("stable_runtime").invocation.invoke(testing.allocator, .{
        .image = image,
        .instance = .{ .state = before },
        .quantum = quantum,
    });
    defer fresh.deinit();
    var prepared = try @import("stable_runtime").Prepared.init(testing.allocator, image);
    defer prepared.deinit();
    var resident = try Resident.restore(testing.allocator, &prepared, before);
    defer releaseResident(&resident);
    var committed = try resident.drive(testing.allocator, .none, .{ .quantum = quantum, .checkpoint = true });
    defer committed.deinit();
    try testing.expectEqualDeep(fresh.record, committed.record);
    @memset(image, 0xff);
    @memset(before, 0xff);
    const result = try subject.run(quantum);
    _ = try restored.run(quantum);
    const expected = try subject.checkpoint(testing.allocator);
    defer testing.allocator.free(expected);
    const actual = try restored.checkpoint(testing.allocator);
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(u8, expected, actual);
    switch (result) {
        .progressed => try testing.expectEqualSlices(u8, expected, fresh.record.progressed.?),
        .yielded => try testing.expectEqualSlices(u8, expected, fresh.record.yielded.?),
        .requested => {
            try testing.expectEqualSlices(u8, expected, fresh.record.requested.state.?);
            var pending = try subject.pendingRequest(testing.allocator);
            defer pending.deinit();
            var decoded = try boundary.data_v2.invocation.decode(boundary.data_v2.invocation.Request, testing.allocator, fresh.record.requested.request);
            defer decoded.deinit();
            try testing.expectEqualDeep(pending.request, decoded.value);
        },
        .completed => |value| try testing.expectEqualSlices(u8, try subject.bytes(&value), fresh.record.completed),
        .failed => |value| {
            try testing.expectEqualSlices(u8, try subject.bytes(&value), fresh.record.failed.value);
            try testing.expectEqualDeep(subject.exit.?.cancellation, fresh.record.failed.cancellation);
            try expectCleanupFailures(subject, fresh.record.failed.cleanup_failures);
        },
        .cancelled => |reason| {
            try testing.expectEqualDeep(reason, fresh.record.cancelled.reason);
            try expectCleanupFailures(subject, fresh.record.cancelled.cleanup_failures);
        },
    }
    try checkedCheckpoint(subject);
    return result;
}

fn expectCleanupFailures(subject: *Session, bytes: []const u8) !void {
    var reader: boundary.data_v2.wire.Reader = .{ .input = bytes };
    const failures = subject.exit.?.cleanup_failures;
    try testing.expectEqual(failures.len, try reader.count());
    for (failures) |value| try testing.expectEqualSlices(u8, try subject.bytes(&value), try reader.bytes());
    try reader.finish();
}

fn checkpointFailure(allocator: std.mem.Allocator, subject: *Session, before: []const u8) !void {
    const bytes = subject.checkpoint(allocator) catch |err| {
        const after = try subject.checkpoint(testing.allocator);
        defer testing.allocator.free(after);
        try testing.expectEqualSlices(u8, before, after);
        return err;
    };
    defer allocator.free(bytes);
    try testing.expectEqualSlices(u8, before, bytes);
}

test "failed PST3 export retains exactly the same resident instruction boundary" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.installations(&builder, 1));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    try testing.expect(try session.run(1) == .progressed);
    const before = try session.checkpoint(testing.allocator);
    defer testing.allocator.free(before);
    try testing.checkAllAllocationFailures(testing.allocator, checkpointFailure, .{ &session, before });
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqual(1, result.completed.body.scalar[0]);
}

fn initFromImage(allocator: std.mem.Allocator, program: boundary.data_v2.activation.Program, arguments: []const u8) !Session {
    const codec = boundary.data_v2.program_image;
    const image = try allocator.alloc(u8, try codec.encodedLength(program));
    defer allocator.free(image);
    _ = try codec.encode(allocator, program, image);
    const result = try Session.initImage(allocator, image, arguments);
    @memset(image, 0xff);
    return result;
}

fn programBytes(program: boundary.data_v2.activation.Program) ![]u8 {
    const codec = boundary.data_v2.program_image;
    const bytes = try testing.allocator.alloc(u8, try codec.encodedLength(program));
    errdefer testing.allocator.free(bytes);
    _ = try codec.encode(testing.allocator, program, bytes);
    return bytes;
}

test "prepared Programs reuse immutable code and facts across sequential Sessions" {
    const Prepared = @import("stable_runtime").Prepared;
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try retainedInputExample(&builder));
    defer compiled.deinit();
    const bytes = try programBytes(compiled.program);
    defer testing.allocator.free(bytes);
    var prepared = try Prepared.init(testing.allocator, bytes);
    defer prepared.deinit();
    @memset(bytes, 0xff);
    const retained = try prepared.storageBytes();
    var shared_code: ?[*]const boundary.data_v2.activation.Function = null;
    for ([_]u8{ 1, 2, 3 }) |input| {
        var session = try Session.start(testing.allocator, &prepared, &.{ input, 0, 0, 0, 0, 0, 0, 0 });
        defer session.deinit();
        if (shared_code) |pointer| try testing.expect(pointer == session.program.functions.ptr) else shared_code = session.program.functions.ptr;
        const base = session.flow.facts.pool.base.?;
        const nodes = base.nodeCount();
        try testing.expect(try session.run(null) == .requested);
        const checkpoint = try session.checkpoint(testing.allocator);
        defer testing.allocator.free(checkpoint);
        var restored = try Session.restore(testing.allocator, &prepared, checkpoint);
        defer restored.deinit();
        try testing.expect(session.program.functions.ptr == restored.program.functions.ptr);
        try testing.expect(session.flow.facts.live.ptr == restored.flow.facts.live.ptr);
        try testing.expect(session.flow.facts.pool != restored.flow.facts.pool);
        try testing.expect(restored.flow.facts.pool.base.? == base);
        try answerWithValue(&session, &.{});
        try answerWithValue(&restored, &.{});
        const result = try session.run(null);
        const other = try restored.run(null);
        try testing.expectEqual(input, result.completed.body.scalar[0]);
        try testing.expectEqualDeep(result, other);
        try testing.expectEqual(nodes, base.nodeCount());
        try testing.expectEqual(retained, try prepared.storageBytes());
    }
}

test "Sessions retain preparation after all external prepared handles are released" {
    const Prepared = @import("stable_runtime").Prepared;
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try retainedInputExample(&builder));
    defer compiled.deinit();
    const bytes = try programBytes(compiled.program);
    defer testing.allocator.free(bytes);
    var prepared = try Prepared.init(testing.allocator, bytes);
    defer prepared.deinit();
    var clone = try prepared.clone();
    defer clone.deinit();
    var session = try Session.start(testing.allocator, &prepared, &.{ 42, 0, 0, 0, 0, 0, 0, 0 });
    defer session.deinit();
    prepared.deinit();
    clone.deinit();
    try testing.expectError(error.InvalidState, Session.start(testing.allocator, &prepared, &.{}));
    try testing.expectError(error.InvalidState, Session.restore(testing.allocator, &clone, &.{}));
    try testing.expect(try session.run(null) == .requested);
    try answerWithValue(&session, &.{});
    const result = try session.run(null);
    try testing.expectEqual(42, result.completed.body.scalar[0]);
}

fn startPreparedFailure(allocator: std.mem.Allocator, prepared: *const @import("stable_runtime").Prepared) !void {
    var session = try Session.start(allocator, prepared, &.{ 1, 0, 0, 0, 0, 0, 0, 0 });
    defer session.deinit();
}
fn restorePreparedFailure(allocator: std.mem.Allocator, prepared: *const @import("stable_runtime").Prepared, checkpoint: []const u8) !void {
    var session = try Session.restore(allocator, prepared, checkpoint);
    defer session.deinit();
}
test "failed prepared starts and restores preserve the reusable owner" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try retainedInputExample(&builder));
    defer compiled.deinit();
    const bytes = try programBytes(compiled.program);
    defer testing.allocator.free(bytes);
    var prepared = try @import("stable_runtime").Prepared.init(testing.allocator, bytes);
    defer prepared.deinit();
    const retained = try prepared.storageBytes();
    try testing.checkAllAllocationFailures(testing.allocator, startPreparedFailure, .{&prepared});
    var session = try Session.start(testing.allocator, &prepared, &.{ 1, 0, 0, 0, 0, 0, 0, 0 });
    defer session.deinit();
    try testing.expect(try session.run(null) == .requested);
    const checkpoint = try session.checkpoint(testing.allocator);
    defer testing.allocator.free(checkpoint);
    try testing.checkAllAllocationFailures(testing.allocator, restorePreparedFailure, .{ &prepared, checkpoint });
    try testing.expectEqual(retained, try prepared.storageBytes());
    try answerWithValue(&session, &.{});
    try testing.expect(try session.run(null) == .completed);
}

fn retainedInputExample(builder: *source.Builder) !source.Module {
    const integer = try builder.scalar(u64);
    const unit = try builder.scalar(void);
    const effect = try builder.effect(.{ .identity = "binding/read", .payload = unit, .result = unit });
    const main = try builder.declare(&.{integer}, integer, &.{effect}, &.{});
    const operation = try builder.term(.{ .perform = .{ .effect = effect, .payload = try builder.constant(void, {}) } });
    try builder.define(main, try builder.bind(try builder.variable(unit), operation, try builder.pure(try builder.reference(builder.parameter(main, 0)))));
    return builder.module(main, unit);
}

fn invocationFailure(allocator: std.mem.Allocator, command: []const u8) !void {
    var output = [_]u8{0xa5} ** 1024;
    const bytes = @import("stable_runtime").invocation.invokeInto(allocator, command, &output) catch |err| {
        for (output) |byte| try testing.expectEqual(0xa5, byte);
        return err;
    };
    var decoded = try boundary.data_v2.invocation.decode(boundary.data_v2.invocation.Outcome, testing.allocator, bytes);
    defer decoded.deinit();
    try testing.expectEqualSlices(u8, &.{ 2, 0, 0, 0, 0, 0, 0, 0 }, decoded.value.completed);
}

test "current fresh invocation binds captured values and rejects stale replies without mutation" {
    const protocol = boundary.data_v2.invocation;
    const fresh = @import("stable_runtime").invocation;
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try retainedInputExample(&builder));
    defer compiled.deinit();
    const image = try programBytes(compiled.program);
    defer testing.allocator.free(image);
    var first = try fresh.invoke(testing.allocator, .{ .image = image, .instance = .{ .initial_args = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } } });
    defer first.deinit();
    var second = try fresh.invoke(testing.allocator, .{ .image = image, .instance = .{ .initial_args = &.{ 2, 0, 0, 0, 0, 0, 0, 0 } } });
    defer second.deinit();
    var first_request = try protocol.decode(protocol.Request, testing.allocator, first.record.requested.request);
    defer first_request.deinit();
    var second_request = try protocol.decode(protocol.Request, testing.allocator, second.record.requested.request);
    defer second_request.deinit();
    try testing.expectEqualDeep(first_request.value.binding.semantic_identity, second_request.value.binding.semantic_identity);
    try testing.expectEqualSlices(u8, first_request.value.binding.payload, second_request.value.binding.payload);
    try testing.expect(!std.mem.eql(u8, &first_request.value.request_identity, &second_request.value.request_identity));
    var poll = try fresh.invoke(testing.allocator, .{ .image = image, .instance = .{ .state = first.record.requested.state.? } });
    defer poll.deinit();
    try testing.expectEqualDeep(first.record, poll.record);
    const stale = try protocol.encodeOwned(protocol.Result, testing.allocator, .{ .request_identity = first_request.value.request_identity, .value = &.{} });
    defer testing.allocator.free(stale);
    try testing.expectError(error.InvalidResult, fresh.invoke(testing.allocator, .{
        .image = image,
        .instance = .{ .state = second.record.requested.state.? },
        .control = .{ .reply = stale },
    }));
    var resident = try Session.restoreImage(testing.allocator, image, second.record.requested.state.?);
    defer resident.deinit();
    try testing.expectError(error.InvalidResult, resident.answer(stale));
    const unchanged = try resident.checkpoint(testing.allocator);
    defer testing.allocator.free(unchanged);
    try testing.expectEqualSlices(u8, second.record.requested.state.?, unchanged);
    const response = try protocol.encodeOwned(protocol.Result, testing.allocator, .{ .request_identity = second_request.value.request_identity, .value = &.{} });
    defer testing.allocator.free(response);
    var zero = try fresh.invoke(testing.allocator, .{
        .image = image,
        .instance = .{ .state = second.record.requested.state.? },
        .control = .{ .reply = response },
        .quantum = 0,
    });
    defer zero.deinit();
    try testing.expect(zero.record == .progressed);
    try testing.expectError(error.InvalidState, fresh.invoke(testing.allocator, .{
        .image = image,
        .instance = .{ .state = zero.record.progressed.? },
        .control = .{ .reply = response },
    }));
    var completed = try fresh.invoke(testing.allocator, .{ .image = image, .instance = .{ .state = zero.record.progressed.? } });
    defer completed.deinit();
    try testing.expectEqualSlices(u8, &.{ 2, 0, 0, 0, 0, 0, 0, 0 }, completed.record.completed);
    const command = try protocol.encodeOwned(protocol.Input, testing.allocator, .{
        .image = image,
        .instance = .{ .state = second.record.requested.state.? },
        .control = .{ .reply = response },
    });
    defer testing.allocator.free(command);
    const original = try testing.allocator.dupe(u8, command);
    defer testing.allocator.free(original);
    try testing.checkAllAllocationFailures(testing.allocator, invocationFailure, .{command});
    try testing.expectEqualSlices(u8, original, command);
    var output = [_]u8{0xa5} ** 32;
    try testing.expectError(error.Capacity, fresh.invokeInto(testing.allocator, command, output[0..1]));
    for (output) |byte| try testing.expectEqual(0xa5, byte);
    try testing.expectEqualSlices(u8, original, command);
}

test "current invocation preserves explicit yield polling and cancellation before work" {
    const fresh = @import("stable_runtime").invocation;
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const main = try builder.declare(&.{}, integer, &.{}, &.{});
    try builder.define(main, try builder.term(.{ .yield_then = try builder.pure(try builder.constant(u64, 42)) }));
    var compiled = try source.construct(testing.allocator, builder.module(main, try builder.scalar(void)));
    defer compiled.deinit();
    const image = try programBytes(compiled.program);
    defer testing.allocator.free(image);
    var yielded = try fresh.invoke(testing.allocator, .{ .image = image, .instance = .{ .initial_args = &.{} } });
    defer yielded.deinit();
    var poll = try fresh.invoke(testing.allocator, .{ .image = image, .instance = .{ .state = yielded.record.yielded.? } });
    defer poll.deinit();
    try testing.expectEqualDeep(yielded.record, poll.record);
    var resumed = try fresh.invoke(testing.allocator, .{
        .image = image,
        .instance = .{ .state = yielded.record.yielded.? },
        .control = .resume_yield,
        .quantum = 0,
    });
    defer resumed.deinit();
    try testing.expect(resumed.record == .progressed);
    var completed = try fresh.invoke(testing.allocator, .{ .image = image, .instance = .{ .state = resumed.record.progressed.? } });
    defer completed.deinit();
    try testing.expectEqualSlices(u8, &.{ 42, 0, 0, 0, 0, 0, 0, 0 }, completed.record.completed);
    var cancelled = try fresh.invoke(testing.allocator, .{
        .image = image,
        .instance = .{ .initial_args = &.{} },
        .control = .{ .cancel = .{ .text = "stop" } },
        .quantum = 0,
    });
    defer cancelled.deinit();
    // Zero work can initiate cancellation; an unwind may need further quanta.
    if (cancelled.record == .progressed) {
        var done = try fresh.invoke(testing.allocator, .{ .image = image, .instance = .{ .state = cancelled.record.progressed.? } });
        defer done.deinit();
        try testing.expectEqualStrings("stop", done.record.cancelled.reason.text);
    } else try testing.expectEqualStrings("stop", cancelled.record.cancelled.reason.text);
}

test "cancellation rebinds a pending cleanup without repeating its semantic operation" {
    const protocol = boundary.data_v2.invocation;
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.unwind(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{0});
    defer session.deinit();
    try testing.expect(try session.run(null) == .requested);
    var before = try session.pendingRequest(testing.allocator);
    defer before.deinit();
    const acquired_result = try protocol.encodeOwned(protocol.Result, testing.allocator, .{ .request_identity = before.request.request_identity, .value = &.{} });
    defer testing.allocator.free(acquired_result);
    try session.cancel(.{ .text = "stop" });
    var after = try session.pendingRequest(testing.allocator);
    defer after.deinit();
    try testing.expectEqualStrings(before.request.binding.semantic_identity, after.request.binding.semantic_identity);
    try testing.expectEqualSlices(u8, before.request.binding.payload, after.request.binding.payload);
    try testing.expect(!std.mem.eql(u8, &before.request.request_identity, &after.request.request_identity));
    try testing.expectError(error.InvalidResult, session.answer(acquired_result));
    // The host explicitly re-encodes the already obtained typed result against
    // the successor challenge; no external operation runs inside this helper.
    try answerWithValue(&session, &.{});
    try testing.expect(try session.run(null) == .requested);
    try answerWithValue(&session, &.{});
    const result = try session.run(null);
    try testing.expect(result == .failed);
    try testing.expectEqualStrings("stop", session.exit.?.cancellation.?.text);
}

fn restoreFailure(allocator: std.mem.Allocator, image: []const u8, checkpoint: []const u8) !void {
    var session = try Session.restoreImage(allocator, image, checkpoint);
    defer session.deinit();
    const bytes = try session.checkpoint(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, checkpoint, bytes);
}

test "PST3 restore releases every partial owner on allocation failure" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.installations(&builder, 1));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    _ = try session.run(1);
    const checkpoint = try session.checkpoint(testing.allocator);
    defer testing.allocator.free(checkpoint);
    const image = try programBytes(compiled.program);
    defer testing.allocator.free(image);
    try testing.checkAllAllocationFailures(testing.allocator, restoreFailure, .{ image, checkpoint });
}

fn rejectCheckpoint(image: []const u8, state: boundary.data_v2.process_state.State) !void {
    const bytes = try boundary.data_v2.state_image.emit(testing.allocator, state);
    defer testing.allocator.free(bytes);
    if (Session.restoreImage(testing.allocator, image, bytes)) |value| {
        var accepted = value;
        accepted.deinit();
        return error.AcceptedCorruptCheckpoint;
    } else |err| try testing.expect(err != error.OutOfMemory);
}

test "PST3 restore rejects wrong identity, code position, slots, and cleanup status" {
    const data = boundary.data_v2;
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.resourceScalar(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    try testing.expect(try session.run(null) == .requested);
    try answerWithValue(&session, &.{ 41, 0, 0, 0, 0, 0, 0, 0 });
    try testing.expect(try session.run(null) == .requested);
    const image = try programBytes(compiled.program);
    defer testing.allocator.free(image);
    const checkpoint = try session.checkpoint(testing.allocator);
    defer testing.allocator.free(checkpoint);
    var decoded = try data.state_image.decodeGraph(testing.allocator, checkpoint);
    defer decoded.deinit();
    try data.state_admission.validateStable(testing.allocator, compiled.program, decoded.state);
    var forged = decoded.state;
    forged.program_identity[0] ^= 1;
    try rejectCheckpoint(image, forged);
    forged = decoded.state;
    const nodes = try testing.allocator.dupe(data.process_state.Node, forged.nodes);
    defer testing.allocator.free(nodes);
    forged.nodes = nodes;
    var checked_frame = false;
    var checked_binding = false;
    var checked_cleanup = false;
    for (nodes) |*node| {
        const original = node.*;
        if (node.activation) |*activation| {
            if (!checked_frame) {
                activation.position = std.math.maxInt(u64);
                try rejectCheckpoint(image, forged);
                node.* = original;
                checked_frame = true;
            }
            if (!checked_binding and original.activation.?.bindings.len != 0) {
                const bindings = try testing.allocator.dupe(data.process_state.Binding, original.activation.?.bindings);
                defer testing.allocator.free(bindings);
                node.activation.?.bindings = bindings;
                bindings[0].slot = std.math.maxInt(u64);
                // A single-row view avoids failing only the sorted-slot shape rule.
                node.activation.?.bindings = bindings[0..1];
                node.activation.?.owners = &.{};
                if (bindings[0].value.body == .owned) node.activation.?.owners = &.{.{ .scope = node.activation.?.scope, .slot = std.math.maxInt(u64) }};
                try rejectCheckpoint(image, forged);
                node.* = original;
                node.activation.?.bindings = &.{};
                node.activation.?.owners = &.{};
                try rejectCheckpoint(image, forged);
                node.* = original;
                checked_binding = true;
            }
        }
        if (node.record == .obligation and !checked_cleanup) {
            node.record.obligation.status = .completed;
            try rejectCheckpoint(image, forged);
            node.* = original;
            checked_cleanup = true;
        }
    }
    try testing.expect(checked_frame and checked_binding and checked_cleanup);
}

test "PST3 restore rejects aliased unique packages after graph renumbering" {
    const data = boundary.data_v2;
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.custodyOrder(&builder, 0));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    try testing.expect(try session.run(null) == .yielded);
    const checkpoint = try session.checkpoint(testing.allocator);
    defer testing.allocator.free(checkpoint);
    var decoded = try data.state_image.decodeGraph(testing.allocator, checkpoint);
    defer decoded.deinit();
    const nodes = try testing.allocator.dupe(data.process_state.Node, decoded.state.nodes);
    defer testing.allocator.free(nodes);
    const image = try programBytes(compiled.program);
    defer testing.allocator.free(image);
    try data.state_admission.validateStable(testing.allocator, compiled.program, decoded.state);
    var first: ?data.graph.Value = null;
    for (nodes) |*node| if (node.record == .package) {
        if (first) |token| {
            try testing.expectEqual(token.schema, node.record.package.continuation.schema);
            node.record.package.continuation = token;
            var forged = decoded.state;
            forged.nodes = nodes;
            try rejectCheckpoint(image, forged);
            return;
        } else first = node.record.package.continuation;
    };
    return error.MissingIndependentPackages;
}

test "imported storage avoids payload copies and releases a large dead backing" {
    const data = boundary.data_v2;
    const Store = @FieldType(Session, "store");
    const big = try testing.allocator.alloc(u8, 128 * 1024);
    defer testing.allocator.free(big);
    @memset(big, 0x5a);
    const small: data.graph.Value = .{ .schema = 0, .body = .{ .blob = .{ .id = 1 } } };
    // This is a physical Store test: no executable Program or control transition.
    const state: data.process_state.State = .{
        .program_identity = .{0} ** 32,
        .status = .active,
        .roots = .{ .current = .{ .id = 0 } },
        .nodes = &.{.{ .record = .{ .environment = .{ .values = &.{
            .{ .schema = 0, .body = .{ .blob = .{ .id = 0 } } }, small,
        }, .tail = null } } }},
        .blobs = &.{ .{ .schema = 0, .bytes = big }, .{ .schema = 0, .bytes = "small" } },
    };
    const bytes = try data.state_image.emit(testing.allocator, state);
    defer testing.allocator.free(bytes);
    var decoded = try data.state_image.decodeGraph(testing.allocator, bytes);
    var moved = false;
    defer if (!moved) decoded.deinit();
    var store: Store = .{ .allocator = testing.allocator };
    defer store.deinit();
    var statistics: std.meta.Child(@typeInfo(@FieldType(Session, "statistics")).optional.child) = .{};
    store.statistics = &statistics.storage;
    var baseline: Store = .{ .allocator = testing.allocator };
    defer baseline.deinit();
    var baseline_statistics: @TypeOf(statistics) = .{};
    baseline.statistics = &baseline_statistics.storage;
    try baseline.import(.{
        .program_identity = state.program_identity,
        .status = .active,
        .roots = state.roots,
        .nodes = &.{state.nodes[0].record},
        .blobs = state.blobs,
    });
    try testing.expectEqual(big.len + 5, baseline_statistics.storage.copied_blob_bytes);
    try store.importOwned(&decoded);
    moved = true;
    try testing.expectEqual(0, statistics.storage.copied_blob_bytes);
    try testing.expect(store.imported.?.arena.queryCapacity() >= big.len);
    try store.replace(.{ .id = 0 }, .{ .environment = .{ .values = &.{small}, .tail = null } });
    try store.collect(state.roots);
    try testing.expect(store.imported == null);
    try testing.expectEqual(5, statistics.storage.copied_blob_bytes);
    try testing.expectEqualStrings("small", store.blobs.items[1].bytes);
    const interned = try store.literal(&.{.bytes}, .{ .schema = 0, .bytes = "small" });
    try testing.expectEqual(1, interned.body.blob.id);
}

test "BPI3 scalar and collection faults preserve the existing independent expectations" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.scalarContracts(&builder));
    defer compiled.deinit();
    const expected = [_]?u64{ 3, null, null, null, null, null, null, null, null, null, null, 8, 2, 0, 4, 20, 240, 9, null };
    const faults = [_]u8{ 0, 3, 2, 3, 2, 2, 4, 5, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 5 };
    for (expected, faults, 0..) |value, fault, index| {
        var session = try initFromImage(testing.allocator, compiled.program, &.{@intCast(index)});
        defer session.deinit();
        const outcome = try drive(&session, null);
        if (value) |n| {
            try testing.expect(outcome == .completed);
            try testing.expectEqual(n, std.mem.readInt(u64, (try session.bytes(&outcome.completed))[0..8], .little));
        } else {
            try testing.expect(outcome == .failed);
            try testing.expectEqualSlices(u8, &.{fault}, try session.bytes(&outcome.failed));
        }
    }
}

test "stable borrow admission distinguishes older from fresh references through return clauses" {
    const fixture = @import("borrow_return_fixtures");
    for (std.enums.values(fixture.ResultFrom)) |from| {
        for ([_]bool{ false, true }) |initial| {
            for ([_]bool{ false, true }) |delegated| {
                for ([_]bool{ false, true }) |younger| {
                    var builder = source.Builder.init(testing.allocator);
                    defer builder.deinit();
                    const module = try fixture.scenario(&builder, from, initial, younger, delegated);
                    if (younger) {
                        try testing.expectError(error.InvalidOwnership, source.construct(testing.allocator, module));
                    } else {
                        var compiled = try source.construct(testing.allocator, module);
                        defer compiled.deinit();
                        var session = try initFromImage(testing.allocator, compiled.program, &.{});
                        defer session.deinit();
                        try testing.expect(try drive(&session, null) == .yielded);
                        try session.resumeYield();
                        const result = try drive(&session, null);
                        try testing.expect(result == .completed);
                        try testing.expectEqual(0, (try session.bytes(&result.completed)).len);
                    }
                }
            }
        }
    }
}

test "stable resource implementations preserve private authority and loans across requests" {
    inline for (.{ source.examples.resourceScalar, source.examples.resourcePair }) |example| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try example(&builder));
        defer compiled.deinit();
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        var borrowed = false;
        for ([_][]const u8{ "example/resource-acquire", "example/resource-use", "example/resource-release" }, 0..) |name, index| {
            const pending = try drive(&session, null);
            try testing.expect(pending == .requested);
            try testing.expectEqualStrings(name, session.program.effects[@intCast(pending.requested.effect)].identity);
            if (index != 0) try testing.expectEqual(41, pending.requested.payload.body.scalar[0]);
            for (session.store.nodes.items, session.store.alive.items) |node, alive| {
                if (alive and node == .borrow) borrowed = true;
            }
            try session.store.collectWith(session.roots, &session.frames);
            try answerWithValue(&session, if (index == 0) &.{ 41, 0, 0, 0, 0, 0, 0, 0 } else &.{});
        }
        const result = try drive(&session, null);
        try testing.expect(borrowed and result == .completed);
        try testing.expectEqual(42, result.completed.body.scalar[0]);
    }
}

test "stable cancellation releases the resource while its protected borrow is suspended" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.resourceScalar(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    try testing.expect(try drive(&session, null) == .requested);
    try answerWithValue(&session, &.{ 41, 0, 0, 0, 0, 0, 0, 0 });
    const use = try drive(&session, null);
    try testing.expect(use == .requested);
    try testing.expectEqualStrings("example/resource-use", session.program.effects[@intCast(use.requested.effect)].identity);
    try session.cancel(.{ .text = "stop" });
    const release = try drive(&session, null);
    try testing.expect(release == .requested);
    try testing.expectEqualStrings("example/resource-release", session.program.effects[@intCast(release.requested.effect)].identity);
    try testing.expectEqual(41, release.requested.payload.body.scalar[0]);
    try answerWithValue(&session, &.{});
    try testing.expect(try drive(&session, null) == .cancelled);
}

test "stable admission rejects a fresh store hidden by a later same-slot rebind" {
    const fixture = @import("borrow_return_fixtures");
    const data = boundary.data_v2;
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try fixture.scenario(&builder, .pair, true, false, false));
    defer compiled.deinit();
    var image = compiled.program;
    const blocks = try testing.allocator.dupe(data.activation.Block, image.blocks);
    defer testing.allocator.free(blocks);
    image.blocks = blocks;
    for (blocks) |*block| {
        for (block.instructions, 0..) |write, at| {
            if (write.opcode != .cell_set) continue;
            for (block.instructions[0..at], 0..) |selected, position| {
                if (selected.opcode != .field or selected.immediate != 1 or
                    selected.destination != write.operands[1]) continue;
                const operations = try testing.allocator.alloc(data.activation.Instruction, block.instructions.len + 1);
                defer testing.allocator.free(operations);
                @memcpy(operations[0..block.instructions.len], block.instructions);
                // Store the fresh field, then overwrite the same slot with the
                // older field. End-of-block provenance would miss the bad store.
                operations[position].immediate = 0;
                operations[operations.len - 1] = selected;
                block.instructions = operations;
                try testing.expectError(error.InvalidOwnership, data.activation_ownership.analyze(testing.allocator, image));
                return;
            }
        }
    }
    return error.TestUnexpectedResult;
}

test "stable source installs real handlers and keeps the final checked sum after them" {
    for ([_]usize{ 1, 8, 64, 128, 256 }) |count| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try source.examples.installations(&builder, count));
        defer compiled.deinit();
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        const result = try drive(&session, null);
        try testing.expect(result == .completed);
        try testing.expectEqual(count * (count + 1) / 2, std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
        try testing.expectEqual(0, session.frames.entries.count());
        try testing.expect(session.frames.slots.statistics.value_copies <= 32 * count + 128);
        for (session.store.nodes.items, session.store.alive.items) |node, alive| {
            if (!alive) continue;
            if (node == .continuation) try testing.expectEqual(0, node.continuation.arguments.len);
            if (node == .control) try testing.expectEqual(0, node.control.arguments.len);
        }
    }
}

test "stable source preserves non-tail resumption and handler answer transformation" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.deep(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqual(67, std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
}

test "stable source keeps two one-shot owners across an explicit yield" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.ownership(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    try testing.expect(try drive(&session, null) == .yielded);
    try session.resumeYield();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqual(1, std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
}

test "stable source retains an external request and joins into the same activation" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const boolean = try builder.scalar(bool);
    const unit = try builder.scalar(void);
    const effect = try builder.effect(.{ .identity = "stable/read", .payload = unit, .result = integer });
    const main = try builder.declare(&.{boolean}, integer, &.{effect}, &.{});
    const value = try builder.variable(integer);
    const branch = try builder.term(.{ .conditional = .{
        .condition = try builder.reference(builder.parameter(main, 0)),
        .when_true = try builder.pure(try builder.reference(value)),
        .when_false = try builder.pure(try builder.constant(u64, 9)),
    } });
    const request = try builder.term(.{ .perform = .{
        .effect = effect,
        .payload = try builder.constant(void, {}),
    } });
    try builder.define(main, try builder.bind(value, request, branch));
    var compiled = try source.construct(testing.allocator, builder.module(main, unit));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{1});
    defer session.deinit();
    try testing.expect(try drive(&session, 0) == .progressed);
    const pending = try drive(&session, null);
    try testing.expect(pending == .requested);
    try testing.expectEqual(effect, pending.requested.effect);
    try testing.expectError(error.InvalidValue, answerWithValue(&session, &.{2}));
    try testing.expect(try session.observe() == .requested);
    try answerWithValue(&session, &.{ 42, 0, 0, 0, 0, 0, 0, 0 });
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqual(42, std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
}

test "stable source owns its input and keeps tail-recursive control bounded" {
    var builder = source.Builder.init(testing.allocator);
    var compiled = try source.construct(testing.allocator, try source.examples.recursive(&builder));
    var session = initFromImage(testing.allocator, compiled.program, &.{ 16, 39, 0, 0, 0, 0, 0, 0 }) catch |err| {
        compiled.deinit();
        builder.deinit();
        return err;
    };
    defer session.deinit();
    compiled.deinit();
    builder.deinit();
    var result = try drive(&session, 31);
    while (result == .progressed) {
        try testing.expect(session.frames.entries.count() <= 2);
        try testing.expect(session.store.nodes.items.len <= 512);
        result = try drive(&session, 31);
    }
    try testing.expect(result == .completed);
    try testing.expectEqual(1, result.completed.body.scalar[0]);
}

test "stable source resumes an owned package after its handler clause has returned" {
    var b = source.Builder.init(testing.allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const effect = try b.effect(.{ .identity = "stable/escape", .payload = unit, .result = integer, .external = false });
    const cap = try b.schema(.{ .internal = .{ .capability = effect } });
    const token = try b.reserveSchema();
    const package = try b.schema(.{ .internal = .{ .suspension_package = token } });
    const answer = try b.schema(.{ .sum = &.{ integer, package } });
    try b.defineSchema(token, .{ .internal = .{ .resumption = .{
        .effect = effect,
        .input = integer,
        .answer = answer,
        .handled = &.{effect},
        .mode = .deep,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{integer}, answer, &.{}, &.{});
    try b.define(returns, try b.pure(try b.primitive(answer, .variant, &.{try b.reference(b.parameter(returns, 0))}, 0)));
    const clause = try b.declare(&.{ unit, token }, answer, &.{}, &.{});
    const packaged = try b.primitive(package, .package, &.{try b.reference(b.parameter(clause, 1))}, 0);
    try b.define(clause, try b.pure(try b.primitive(answer, .variant, &.{packaged}, 1)));
    const handler = try b.handler(.{ .mode = .deep, .input = integer, .answer = answer, .return_function = returns, .clauses = &.{.{ .effect = effect, .function = clause, .resumption = token }} });
    const body = try b.declare(&.{cap}, integer, &.{effect}, &.{});
    try b.define(body, try b.term(.{ .perform = .{
        .effect = effect,
        .capability = try b.reference(b.parameter(body, 0)),
        .payload = try b.constant(void, {}),
    } }));
    const finish = try b.declare(&.{answer}, integer, &.{}, &.{});
    const ordinary = try b.variable(integer);
    const suspended = try b.variable(package);
    const k = try b.variable(token);
    const resumed = try b.variable(answer);
    const again = try b.term(.{ .call = .{ .function = finish, .arguments = &.{try b.reference(resumed)} } });
    const resume_value = try b.term(.{ .resume_value = .{
        .resumption = try b.reference(k),
        .argument = try b.constant(u64, 42),
    } });
    const recover = try b.bind(k, try b.pure(try b.primitive(token, .unpack, &.{try b.reference(suspended)}, 0)), try b.bind(resumed, resume_value, again));
    try b.define(finish, try b.term(.{ .match_sum = .{
        .value = try b.reference(b.parameter(finish, 0)),
        .cases = &.{
            .{ .variable = ordinary, .body = try b.pure(try b.reference(ordinary)) },
            .{ .variable = suspended, .body = recover },
        },
    } }));
    const main = try b.declare(&.{}, integer, &.{}, &.{});
    const result = try b.variable(answer);
    const signature = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{cap},
        .result = integer,
        .effects = &.{effect},
    } } });
    const handled = try b.term(.{ .handle = .{
        .handler = handler,
        .body = try b.lambda(body, signature),
    } });
    try b.define(main, try b.bind(result, handled, try b.term(.{ .call = .{
        .function = finish,
        .arguments = &.{try b.reference(result)},
    } })));
    var compiled = try source.construct(testing.allocator, b.module(main, unit));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    const observed = try drive(&session, null);
    try testing.expect(observed == .completed);
    try testing.expectEqual(42, std.mem.readInt(u64, observed.completed.body.scalar[0..8], .little));
}

fn failingSession(allocator: std.mem.Allocator, program: boundary.data_v2.activation.Program) !void {
    var session = try initFromImage(allocator, program, &.{});
    defer session.deinit();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
}

test "stable source releases partial native owners at every allocation failure" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.deep(&builder));
    defer compiled.deinit();
    try testing.checkAllAllocationFailures(testing.allocator, failingSession, .{compiled.program});
}

test "stable source preserves multi-shot choice and branch-local versus outer shared cells" {
    const examples = .{ source.examples.choicesAll, source.examples.choicesFirst, source.examples.stateLocal, source.examples.stateShared, source.examples.answers };
    const expected = [_][]const u8{
        &.{ 4, 0, 0, 0, 1, 1, 0, 1, 1 },                                                   &.{ 1, 0, 0 },
        &.{ 2, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0 },                           &.{ 2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0 },
        &.{ 1, 10, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0 },
    };
    inline for (examples, 0..) |example, index| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try example(&builder));
        defer compiled.deinit();
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        const result = try drive(&session, null);
        try testing.expect(result == .completed);
        try testing.expectEqualSlices(u8, expected[index], try session.bytes(&result.completed));
    }
}

test "stable source reenters a live template-cell cycle without sharing branch control" {
    inline for (.{ source.examples.reentrant, source.examples.cloned }) |example| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try example(&builder));
        defer compiled.deinit();
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        var result = try drive(&session, 1);
        var yielded = false;
        while (result == .progressed or result == .yielded) {
            const before = try session.checkpoint(testing.allocator);
            defer testing.allocator.free(before);
            // Replace every private view handle without changing logical values.
            var frames = session.frames.entries.valueIterator();
            while (frames.next()) |frame| {
                const replacement = try session.frames.forkFrame(frame.*);
                session.frames.releaseFrame(frame.*);
                frame.* = replacement;
            }
            // An aggressive correctness lane: every live frame must participate
            // in graph tracing, including the cyclic retained template.
            try session.store.collectWith(session.roots, &session.frames);
            const after = try session.checkpoint(testing.allocator);
            defer testing.allocator.free(after);
            try testing.expectEqualSlices(u8, before, after);
            if (result == .yielded) {
                yielded = true;
                try session.resumeYield();
            }
            result = try drive(&session, 1);
        }
        try testing.expect(yielded and result == .completed);
        try testing.expectEqualSlices(u8, &.{ 113, 0, 0, 0, 0, 0, 0, 0 }, try session.bytes(&result.completed));
    }
}

test "stable source does not read a reclaimed copyable result only assigned to a dead binding" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const unit = try builder.scalar(void);
    const main = try builder.declare(&.{}, integer, &.{}, &.{});
    const unused = try builder.variable(integer);
    try builder.define(main, try builder.bind(unused, try builder.pure(try builder.constant(u64, 7)), try builder.pure(try builder.constant(u64, 42))));
    var compiled = try source.construct(testing.allocator, builder.module(main, unit));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqual(42, result.completed.body.scalar[0]);
}

test "stable retained template preserves an older activation across loop-slot rebindings" {
    const d = boundary.data_v2;
    const program: d.activation.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 2 },
        .schemas = &.{
            .u64,                                  .boolean,                                                                                                                                              .unit,
            .{ .internal = .{ .capability = 0 } }, .{ .internal = .{ .resumption = .{ .effect = 0, .input = 1, .answer = 0, .capture_bound = &.{0}, .handled = &.{0}, .mode = .deep, .use = .multi } } }, .{ .internal = .{ .computation = .{ .parameters = &.{3}, .result = 0, .effects = &.{0} } } },
        },
        .constants = &.{
            .{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } },
            .{ .schema = 0, .bytes = &.{ 2, 0, 0, 0, 0, 0, 0, 0 } },
            .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } },
            .{ .schema = 1, .bytes = &.{0} },
            .{ .schema = 1, .bytes = &.{1} },
            .{ .schema = 2, .bytes = &.{} },
        },
        .effects = &.{.{ .identity = "stable/loop", .payload = 2, .result = 1, .control_use = .multi, .external = false }},
        .functions = &.{
            .{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = &.{ 5, 0 } }, .result = 0 },
            .{ .entry = 2, .inputs = &.{0}, .layout = .{ .slots = &.{ 3, 0, 0, 2, 1, 0, 0, 0, 1, 0 } }, .result = 0, .effects = &.{0} },
            .{ .entry = 5, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
            .{ .entry = 6, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 2, 4, 1, 0, 1, 0, 0 } }, .result = 0 },
        },
        .blocks = &.{
            .{ .function = 0, .instructions = &.{.{ .destination = 0, .opcode = .computation }}, .terminator = .{ .handle = .{ .handler = 0, .body = 0, .arguments = &.{}, .state = &.{}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 1, .source = .returned }} } } } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
            .{ .function = 1, .instructions = &.{
                .{ .destination = 1, .opcode = .constant, .immediate = 0 },
                .{ .destination = 2, .opcode = .constant, .immediate = 1 },
                .{ .destination = 3, .opcode = .constant, .immediate = 5 },
                .{ .destination = 9, .opcode = .constant, .immediate = 2 },
            }, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 3, .next = .{ .block = 3, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
            .{ .function = 1, .instructions = &.{
                .{ .destination = 5, .opcode = .constant, .immediate = 0 },
                .{ .destination = 6, .opcode = .integer_add, .operands = &.{ 1, 5 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 5 }} },
                .{ .destination = 7, .opcode = .integer_sub, .operands = &.{ 2, 5 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 5 }} },
                .{ .destination = 8, .opcode = .equal, .operands = &.{ 7, 9 } },
            }, .terminator = .{ .branch = .{
                .condition = 8,
                .when_true = .{ .block = 4, .assignments = &.{
                    .{ .destination = 1, .source = .{ .slot = 6 } },
                    .{ .destination = 2, .source = .{ .slot = 7 } },
                } },
                .when_false = .{ .block = 3, .assignments = &.{
                    .{ .destination = 1, .source = .{ .slot = 6 } },
                    .{ .destination = 2, .source = .{ .slot = 7 } },
                } },
            } } },
            .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
            .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 3, .instructions = &.{.{ .destination = 2, .opcode = .constant, .immediate = 4 }}, .terminator = .{ .resume_value = .{ .resumption = 1, .argument = 2, .next = .{ .block = 7, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
            .{ .function = 3, .instructions = &.{.{ .destination = 4, .opcode = .constant, .immediate = 3 }}, .terminator = .{ .resume_value = .{ .resumption = 1, .argument = 4, .next = .{ .block = 8, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
            .{ .function = 3, .instructions = &.{.{ .destination = 6, .opcode = .integer_add, .operands = &.{ 3, 5 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 5 }} }}, .terminator = .{ .return_value = 6 } },
        },
        .handlers = &.{.{ .mode = .deep, .input = 0, .answer = 0, .return_function = 2, .clauses = &.{.{ .effect = 0, .function = 3, .resumption = 4 }} }},
        .scopes = .{ .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
        .constructors = &.{.{ .function = 1, .capture = 0, .schema = 5 }},
    };
    var session = try initFromImage(testing.allocator, program, &.{});
    defer session.deinit();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    // Each activation starts at x=1, count=2, then returns 3. The retained
    // template must not inherit the first branch's x=3/count=0 bindings.
    try testing.expectEqual(6, result.completed.body.scalar[0]);
}

test "stable shallow value and computation resumptions omit the original return clause" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.shallowResumptions(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    var result = try drive(&session, 1);
    while (result == .progressed) {
        try session.store.collectWith(session.roots, &session.frames);
        result = try drive(&session, 1);
    }
    try testing.expect(result == .completed);
    const bytes = try session.bytes(&result.completed);
    try testing.expectEqual(64, bytes.len);
    for (0..8) |index| {
        const expected: u64 = if (index < 4) 99 else 42;
        try testing.expectEqual(expected, std.mem.readInt(u64, bytes[index * 8 ..][0..8], .little));
    }
}

test "stable injection selects definition-site versus use-site capabilities" {
    inline for (.{ source.examples.injection, source.examples.shallowInjection }) |example| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try example(&builder));
        defer compiled.deinit();
        for ([_]u8{ 0, 1 }) |injecting| {
            var session = try initFromImage(testing.allocator, compiled.program, &.{injecting});
            defer session.deinit();
            var result = try drive(&session, 1);
            var saw_injection = false;
            while (result == .progressed) {
                for (session.store.nodes.items, session.store.alive.items) |node, alive|
                    if (alive and node == .injection) {
                        saw_injection = true;
                    };
                try session.store.collectWith(session.roots, &session.frames);
                result = try drive(&session, 1);
            }
            try testing.expect(result == .completed);
            try testing.expectEqual(@as(u64, if (injecting == 0) 109 else 209), std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
            try testing.expectEqual(injecting == 1, saw_injection);
        }
    }
}

test "stable successor handling preserves the shallow protocol" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.shallow(&builder));
    defer compiled.deinit();
    for ([_]u8{ 0, 1 }) |invalid| {
        var session = try initFromImage(testing.allocator, compiled.program, &.{invalid});
        defer session.deinit();
        const result = try drive(&session, null);
        if (invalid == 0) {
            try testing.expect(result == .completed);
            try testing.expectEqual(1, result.completed.body.scalar[0]);
        } else {
            try testing.expect(result == .failed);
            try testing.expectEqual(0, (try session.bytes(&result.failed)).len);
        }
    }
}

test "stable cleanup preserves primary failure and resumes external cleanup" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.unwind(&builder));
    defer compiled.deinit();
    for ([_]u8{ 0, 1 }) |primary| {
        var session = try initFromImage(testing.allocator, compiled.program, &.{primary});
        defer session.deinit();
        for ([_][]const u8{ "example/middle-cleanup", "example/outer-cleanup" }) |name| {
            const pending = try drive(&session, null);
            try testing.expect(pending == .requested);
            try testing.expectEqualStrings(name, session.program.effects[@intCast(pending.requested.effect)].identity);
            try session.store.collectWith(session.roots, &session.frames);
            try answerWithValue(&session, &.{});
        }
        const result = try drive(&session, null);
        try testing.expect(result == .failed);
        try testing.expectEqual(@as(u8, if (primary == 1) 9 else 7), result.failed.body.scalar[0]);
        try testing.expectEqual(2, session.exit.?.cleanup_failures.len);
        try testing.expectEqual(7, session.exit.?.cleanup_failures[0].body.scalar[0]);
        try testing.expectEqual(8, session.exit.?.cleanup_failures[1].body.scalar[0]);
    }
}

test "stable cancellation during yielded cleanup preserves the first reason" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.yieldingCleanup(&builder));
    defer compiled.deinit();
    for ([_]u8{ 0, 1 }) |primary| {
        var session = try initFromImage(testing.allocator, compiled.program, &.{primary});
        defer session.deinit();
        for (0..2) |round| {
            try testing.expect(try drive(&session, null) == .yielded);
            try session.cancel(.{ .text = if (round == 0) "stop" else "later" });
            try session.resumeYield();
            const pending = try drive(&session, null);
            try testing.expect(pending == .requested);
            try answerWithValue(&session, &.{});
        }
        const result = try drive(&session, null);
        try testing.expect(result == .failed);
        try testing.expectEqual(@as(u8, if (primary == 1) 9 else 7), result.failed.body.scalar[0]);
        try testing.expectEqualStrings("stop", session.exit.?.cancellation.?.text);
    }
}

test "stable unwind preserves lexical and temporary-owner cleanup order" {
    for (0..10) |mode| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try source.examples.custodyOrder(&builder, @intCast(mode)));
        defer compiled.deinit();
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        var requests: usize = 0;
        var yields: usize = 0;
        var result = try drive(&session, 1);
        while (result == .progressed or result == .yielded or result == .requested) {
            if (result == .yielded) {
                yields += 1;
                try session.resumeYield();
            }
            if (result == .requested) {
                try testing.expect(requests < 2);
                const reversed = mode == 1 or mode == 3 or mode >= 4;
                const label: u64 = if (reversed) 2 - requests else requests + 1;
                try testing.expectEqual(label, std.mem.readInt(u64, result.requested.payload.body.scalar[0..8], .little));
                requests += 1;
                try answerWithValue(&session, &.{});
            }
            try session.store.collectWith(session.roots, &session.frames);
            result = try drive(&session, 1);
        }
        try testing.expect(result == .failed);
        try testing.expectEqual(8, result.failed.body.scalar[0]);
        try testing.expectEqual(2, requests);
        try testing.expectEqual(1, yields);
    }
}

test "stable cancellation preserves cleanup at entry yield request and answered boundaries" {
    var b = source.Builder.init(testing.allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const info = try boundary.library.cleanup.exitInfo(&b, integer);
    const read_effect = try b.effect(.{ .identity = "cancel/read", .payload = unit, .result = integer });
    const release = try b.effect(.{ .identity = "cancel/release", .payload = info, .result = unit });
    const body = try b.declare(&.{}, integer, &.{read_effect}, &.{});
    const request = try b.term(.{ .perform = .{ .effect = read_effect, .payload = try b.constant(void, {}) } });
    const repeated = try b.bind(try b.variable(integer), request, request);
    try b.define(body, try b.term(.{ .yield_then = repeated }));
    const cleanup = try b.declare(&.{info}, unit, &.{release}, &.{});
    try b.define(cleanup, try b.term(.{ .perform = .{ .effect = release, .payload = try b.reference(b.parameter(cleanup, 0)) } }));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = integer,
        .effects = &.{read_effect},
    } } });
    const cleanup_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{info},
        .result = unit,
        .effects = &.{release},
    } } });
    const main = try b.declare(&.{}, integer, &.{ read_effect, release }, &.{});
    try b.define(main, try b.term(.{ .protect = .{
        .body = try b.lambda(body, body_type),
        .cleanup = try b.lambda(cleanup, cleanup_type),
    } }));
    var compiled = try source.construct(testing.allocator, b.module(main, integer));
    defer compiled.deinit();
    for (0..4) |phase| {
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        try testing.expectError(error.InvalidUtf8, session.cancel(.{ .text = &.{0xff} }));
        if (phase >= 1) try testing.expect(try drive(&session, null) == .yielded);
        if (phase >= 2) {
            try session.resumeYield();
            const pending = try drive(&session, null);
            try testing.expect(pending == .requested and pending.requested.effect == read_effect);
        }
        if (phase == 3) try answerWithValue(&session, &.{ 7, 0, 0, 0, 0, 0, 0, 0 });
        try session.cancel(.{ .text = "stop" });
        var result = try drive(&session, null);
        if (phase != 0) {
            try testing.expect(result == .requested and result.requested.effect == release);
            try answerWithValue(&session, &.{});
            result = try drive(&session, null);
        }
        try testing.expect(result == .cancelled);
        try testing.expectEqualStrings("stop", result.cancelled.text);
        try testing.expectEqual(0, session.exit.?.cleanup_failures.len);
    }
}

test "stable clause failure abandons a captured cleanup without losing its primary exit" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.clauseAbort(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    const pending = try drive(&session, null);
    try testing.expect(pending == .requested);
    try testing.expectEqualStrings("example/abandoned-release", session.program.effects[@intCast(pending.requested.effect)].identity);
    try testing.expectEqualSlices(u8, &.{ 1, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, try session.bytes(&pending.requested.payload));
    try session.store.collectWith(session.roots, &session.frames);
    try answerWithValue(&session, &.{});
    const result = try drive(&session, null);
    try testing.expect(result == .failed);
    try testing.expectEqual(9, result.failed.body.scalar[0]);
}

test "stable generator resumes private state and closes its retained cleanup" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.generator(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    var yields: usize = 0;
    var releases: usize = 0;
    var result = try drive(&session, 1);
    while (result != .completed) {
        switch (result) {
            .progressed => {},
            .yielded => {
                yields += 1;
                try session.resumeYield();
            },
            .requested => |pending| {
                releases += 1;
                try testing.expectEqualStrings("example/generator-release", session.program.effects[@intCast(pending.effect)].identity);
                try testing.expectEqual(43, pending.payload.body.scalar[0]);
                try answerWithValue(&session, &.{});
            },
            else => return error.TestUnexpectedResult,
        }
        try session.store.collectWith(session.roots, &session.frames);
        result = try drive(&session, 1);
    }
    try testing.expectEqual(1, yields);
    try testing.expectEqual(1, releases);
    try testing.expectEqualSlices(u8, &.{ 42, 0, 0, 0, 0, 0, 0, 0, 43, 0, 0, 0, 0, 0, 0, 0 }, try session.bytes(&result.completed));
}

test "stable successor return clauses retain older capability and cell references" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.successorState(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    try testing.expect(try drive(&session, null) == .yielded);
    try session.store.collectWith(session.roots, &session.frames);
    try session.resumeYield();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqualSlices(u8, &.{ 42, 0, 0, 0, 0, 0, 0, 0, 37, 0, 0, 0, 0, 0, 0, 0 }, try session.bytes(&result.completed));
}
