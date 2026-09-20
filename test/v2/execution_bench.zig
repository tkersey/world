//! Frozen source-pair controls; complete fresh invocations and independent traces.
//! Usage: execution-bench FORMAT FIXTURE COUNT. COUNT is 1..256 for
//! install/retained_loop/mixed/irregular and zero for the fixed examples. Three warmups precede
//! nine samples; allocation counters use a separate replay. Host reply encoding
//! and oracle checks are outside invocation clocks. Requests receive fixture
//! replies; no external operation is dispatched.
//! Add --emit-input to write the initial canonical invocation for runtime-only replay.
const std = @import("std");
const boundary = @import("boundary");
const world = @import("world");
const data = if (@hasDecl(boundary, "data")) boundary.data else boundary.data_v2;
const source = boundary.source;
const current = @hasDecl(world, "Session");
const protocol = if (current) data.invocation else data.protocol;
const runtime = if (current) world else world.process_v2;

const Fixture = enum { scalar, install, retained_loop, mixed, irregular, deep, residual, reentrant, shallow, generator, scheduler, queens_dfs, queens_bfs, cleanup };
const Command = struct { bytes: []u8, image: []u8 };
fn command(a: std.mem.Allocator, compact: bool, fixture: Fixture, count: usize) !Command {
    var b = source.Builder.init(a);
    defer b.deinit();
    const input = switch (fixture) {
        .install => try source.examples.installations(&b, count),
        .retained_loop => try @import("retained_loop_bench.zig").build(&b, count),
        .deep => try source.examples.deep(&b),
        .mixed => try @import("compact_fixtures").mixed(&b, count, 0, false),
        .irregular => try @import("compact_fixtures").variedMixed(&b, count, .{ .seed = 11 }),
        .reentrant => try source.examples.reentrant(&b),
        .shallow => try source.examples.shallowResumptions(&b),
        .generator => try source.examples.generator(&b),
        .scheduler => try source.examples.schedulerFifo(&b),
        .queens_dfs => try source.examples.queensDfs(&b),
        .queens_bfs => try source.examples.queensBfs(&b),
        .cleanup => try source.examples.yieldingCleanup(&b),
        .residual => blk: {
            const integer = try b.scalar(u64);
            const unit = try b.scalar(void);
            const effect = try b.effect(.{ .identity = "benchmark/read", .payload = integer, .result = integer });
            const entry = try b.declare(&.{}, integer, &.{effect}, &.{});
            try b.define(entry, try b.term(.{ .perform = .{ .effect = effect, .payload = try b.constant(u64, 7) } }));
            break :blk b.module(entry, unit);
        },
        .scalar => blk: {
            const integer = try b.scalar(u64);
            const unit = try b.scalar(void);
            const entry = try b.declare(&.{}, integer, &.{}, &.{});
            try b.define(entry, try b.pure(try b.constant(u64, 42)));
            break :blk b.module(entry, unit);
        },
    };
    var compiled = try source.lower(a, input);
    defer compiled.deinit();
    const length = if (current) try data.program_image.encodedLength(compiled.program) else if (compact) try data.compact_image.encodedLength(a, compiled.program) else try data.image.encodedLength(compiled.program);
    const image = try a.alloc(u8, length);
    errdefer a.free(image);
    if (current) {
        _ = try compiled.encode(a, image);
    } else if (compact) {
        _ = try data.compact_image.encode(a, compiled.program, image);
    } else {
        _ = try compiled.encode(a, image);
    }
    const initial_args: []const u8 = if (fixture == .cleanup) &.{1} else &.{};
    const invocation: protocol.Input = if (current)
        .{ .image = image, .instance = .{ .initial_args = initial_args } }
    else
        .{ .mode = .run, .image = image, .instance = .{ .initial_args = initial_args }, .control = .{ .continue_value = null } };
    const encoded = try a.alloc(u8, try protocol.encodedLength(protocol.Input, invocation));
    errdefer a.free(encoded);
    _ = try protocol.encode(protocol.Input, a, invocation, encoded);
    return .{ .bytes = encoded, .image = image };
}

fn invoke(a: std.mem.Allocator, input: []const u8, output: []u8) ![]const u8 {
    if (current) return world.invocation.invokeInto(a, input, output);
    const decoded = try protocol.decode(protocol.Input, a, input);
    var result = try runtime.invoke(a, decoded);
    defer result.deinit();
    return protocol.encode(protocol.Outcome, a, result.record, output);
}

// Expected observations come from the independent source oracle, not a runtime
// recording. Every yield, request identity/payload and terminal value is checked.
fn integers(comptime values: []const u64) [values.len * 8]u8 {
    var result: [values.len * 8]u8 = undefined;
    for (values, 0..) |value, i| std.mem.writeInt(u64, result[i * 8 ..][0..8], value, .little);
    return result;
}
const board_a = [_]u8{4} ++ integers(&.{ 2, 4, 1, 3 });
const board_b = [_]u8{4} ++ integers(&.{ 3, 1, 4, 2 });
const Event = struct {
    yielded: bool = false,
    identity: []const u8 = &.{},
    payload: []const u8 = &.{},
    reply: [8]u8 = @splat(0),
    reply_length: usize = 0,
};
fn request(identity: []const u8, payload: []const u8, reply: ?u64) Event {
    var result: Event = .{ .identity = identity, .payload = payload };
    if (reply) |value| {
        std.mem.writeInt(u64, &result.reply, value, .little);
        result.reply_length = 8;
    }
    return result;
}
const Oracle = struct {
    value: [4096]u8 = undefined,
    value_length: usize = 0,
    events: [258]Event = undefined,
    event_count: usize = 0,
    failed: bool = false,
    failures: []const u8 = &.{0},
    fn append(self: *Oracle, bytes: []const u8) void {
        @memcpy(self.value[self.value_length..][0..bytes.len], bytes);
        self.value_length += bytes.len;
    }
    fn scalar(self: *Oracle, value: u64) void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, value, .little);
        self.append(&bytes);
    }
    fn event(self: *Oracle, value: Event) void {
        self.events[self.event_count] = value;
        self.event_count += 1;
    }
};
fn expected(fixture: Fixture, count: usize) Oracle {
    var result: Oracle = .{};
    switch (fixture) {
        .scalar, .residual => {
            result.scalar(42);
            if (fixture == .residual) result.event(request("benchmark/read", &comptime integers(&.{7}), 42));
        },
        .install => result.scalar(count * (count + 1) / 2),
        .retained_loop => result.scalar(2 * (count + 1)),
        .deep => result.scalar(67),
        .mixed, .irregular => {
            for (0..count) |index| {
                var kind = index % 3;
                if (fixture == .irregular) {
                    var bits = @as(u64, index) *% 0x9e3779b97f4a7c15 +% 11;
                    bits ^= bits >> 30;
                    bits *%= 0xbf58476d1ce4e5b9;
                    kind = @intCast((bits ^ (bits >> 27)) % 3);
                }
                var event = request(([_][]const u8{ "compact/bool", "compact/u64", "compact/u32" })[kind], &.{}, index + 1);
                event.reply_length = ([_]usize{ 1, 8, 4 })[kind];
                if (kind == 0) event.reply[0] = 1;
                result.append(event.reply[0..event.reply_length]);
                result.event(event);
            }
            const first = result.events[0];
            for (0..2) |_| result.append(first.reply[0..first.reply_length]);
        },
        .reentrant => {
            result.scalar(113);
            result.event(.{ .yielded = true });
        },
        .shallow => result.append(&comptime integers(&.{ 99, 99, 99, 99, 42, 42, 42, 42 })),
        .generator => {
            result.append(&comptime integers(&.{ 42, 43 }));
            result.event(.{ .yielded = true });
            result.event(request("example/generator-release", &comptime integers(&.{43}), null));
        },
        .scheduler => {
            result.scalar(30);
            result.append(&.{4});
            result.append(&comptime integers(&.{ 1, 2, 3, 4 }));
            result.event(.{ .yielded = true });
        },
        .queens_dfs, .queens_bfs => {
            result.append(&.{2});
            result.append(&board_a);
            result.append(&board_b);
            result.scalar(60);
            result.event(.{ .yielded = true });
            result.event(request("example/queens-acquire", &board_a, 201));
            result.event(request("example/queens-use", if (fixture == .queens_dfs) &comptime (integers(&.{201}) ++ board_a ++ integers(&.{26})) else &comptime (integers(&.{201}) ++ board_a ++ integers(&.{51})), null));
            result.event(request("example/queens-release", &comptime integers(&.{201}), null));
            result.event(request("example/queens-acquire", &board_b, 202));
            result.event(request("example/queens-use", if (fixture == .queens_dfs) &comptime (integers(&.{202}) ++ board_b ++ integers(&.{38})) else &comptime (integers(&.{202}) ++ board_b ++ integers(&.{54})), null));
            result.event(request("example/queens-release", &comptime integers(&.{202}), null));
        },
        .cleanup => {
            result.failed = true;
            result.scalar(9);
            result.failures = &comptime ([_]u8{ 2, 8 } ++ integers(&.{7}) ++ [_]u8{8} ++ integers(&.{8}));
            result.event(.{ .yielded = true });
            result.event(request("example/middle-cleanup", &comptime ([_]u8{1} ++ integers(&.{9}) ++ [_]u8{ 0, 1 } ++ integers(&.{7})), null));
            result.event(.{ .yielded = true });
            result.event(request("example/outer-cleanup", &comptime ([_]u8{1} ++ integers(&.{9}) ++ [_]u8{ 0, 2 } ++ integers(&.{ 7, 8 })), null));
        },
    }
    return result;
}
fn decode(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8) !T {
    // The caller's short-lived arena owns all decoding allocations on either ABI.
    return if (current) (try protocol.decode(T, allocator, bytes)).value else protocol.decode(T, allocator, bytes);
}
fn encodeInput(allocator: std.mem.Allocator, input: protocol.Input) ![]u8 {
    const bytes = try allocator.alloc(u8, try protocol.encodedLength(protocol.Input, input));
    errdefer allocator.free(bytes);
    _ = try protocol.encode(protocol.Input, allocator, input, bytes);
    return bytes;
}
const Observation = struct { ns: u64 = 0, calls: usize = 0, peak: usize = 0, allocations: usize = 0, allocated_bytes: usize = 0, state_bytes: usize = 0 };
fn run(io: std.Io, allocator: std.mem.Allocator, command_: Command, oracle: *const Oracle, storage: []u8, output: []u8, comptime tracked: bool) !Observation {
    var input = try allocator.dupe(u8, command_.bytes);
    defer allocator.free(input);
    var result: Observation = .{};
    for (0..oracle.event_count + 1) |index| {
        const start = std.Io.Clock.awake.now(io);
        var workspace = runtime.Workspace.init(storage);
        var counter = std.testing.FailingAllocator.init(workspace.allocator(), .{});
        const encoded = try invoke(if (tracked) counter.allocator() else workspace.allocator(), input, output);
        result.ns += @intCast(start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds);
        result.calls += 1;
        result.peak = @max(result.peak, workspace.peak_payload);
        if (tracked) {
            result.allocations += counter.allocations;
            result.allocated_bytes += counter.allocated_bytes;
        }
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();
        const a = scratch.allocator();
        const outcome = try decode(protocol.Outcome, a, encoded);
        if (index == oracle.event_count) {
            const value = if (oracle.failed) blk: {
                if (outcome != .failed or outcome.failed.cancellation != null or
                    !std.mem.eql(u8, outcome.failed.cleanup_failures, oracle.failures)) return error.UnexpectedFailure;
                break :blk outcome.failed.value;
            } else blk: {
                if (outcome != .completed) return error.UnexpectedOutcome;
                break :blk outcome.completed;
            };
            if (!std.mem.eql(u8, value, oracle.value[0..oracle.value_length])) return error.UnexpectedValue;
            return result;
        }
        const event = oracle.events[index];
        var state: []const u8 = undefined;
        var reply: ?[]const u8 = null;
        if (event.yielded) {
            if (outcome != .yielded) return error.ExpectedYield;
            state = if (current) outcome.yielded orelse return error.MissingState else outcome.yielded;
        } else {
            if (outcome != .requested) return error.ExpectedRequest;
            state = if (current) outcome.requested.state orelse return error.MissingState else outcome.requested.state;
            const req = try decode(protocol.Request, a, outcome.requested.request);
            const binding = if (current) req.binding else req;
            if (!std.mem.eql(u8, binding.semantic_identity, event.identity) or
                !std.mem.eql(u8, binding.payload, event.payload)) return error.UnexpectedRequest;
            const response: protocol.Result = if (current)
                .{ .request_identity = req.request_identity, .value = event.reply[0..event.reply_length] }
            else
                .{ .request_identity = req.request_identity, .resume_schema_digest = data.wire.digest(req.resume_schema), .value = event.reply[0..event.reply_length] };
            try protocol.validateResult(a, req, response);
            const bytes = try a.alloc(u8, try protocol.encodedLength(protocol.Result, response));
            reply = try protocol.encode(protocol.Result, a, response, bytes);
        }
        result.state_bytes = @max(result.state_bytes, state.len);
        const next = try encodeInput(allocator, if (current)
            .{ .image = command_.image, .instance = .{ .state = state }, .control = if (reply) |bytes| .{ .reply = bytes } else .resume_yield }
        else
            .{ .mode = .run, .image = command_.image, .instance = .{ .state = state }, .control = .{ .continue_value = reply } });
        allocator.free(input);
        input = next;
    }
    unreachable;
}

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const format = args.next() orelse return error.ExpectedFormat;
    const fixture = std.meta.stringToEnum(Fixture, args.next() orelse return error.ExpectedFixture) orelse return error.InvalidFixture;
    const count = try std.fmt.parseInt(usize, args.next() orelse return error.ExpectedCount, 10);
    const option = args.next();
    const emit_input = if (option) |value| std.mem.eql(u8, value, "--emit-input") else false;
    const sized = fixture == .install or fixture == .retained_loop or fixture == .mixed or fixture == .irregular;
    if (count > 256 or (sized and count == 0) or (!sized and count != 0) or
        (option != null and !emit_input) or args.next() != null) return error.InvalidFixture;
    if (!std.mem.eql(u8, format, if (current) "bpi3" else "bpi2") and (current or !std.mem.eql(u8, format, "bpc1"))) return error.InvalidFormat;
    const start = std.Io.Clock.awake.now(init.io);
    const produced = try command(init.gpa, std.mem.eql(u8, format, "bpc1"), fixture, count);
    const producer_ns: u64 = @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
    defer init.gpa.free(produced.bytes);
    defer init.gpa.free(produced.image);
    if (emit_input) {
        var buffer: [4096]u8 = undefined;
        var stdout = std.Io.File.stdout().writer(init.io, &buffer);
        try stdout.interface.writeAll(produced.bytes);
        try stdout.interface.flush();
        return;
    }
    const oracle = expected(fixture, count);
    const storage = try init.gpa.alloc(u8, 128 << 20);
    defer init.gpa.free(storage);
    const output = try init.gpa.alloc(u8, 1 << 20);
    defer init.gpa.free(output);
    var samples: [9]u64 = undefined;
    for (0..12) |iteration| {
        const observed = try run(init.io, init.gpa, produced, &oracle, storage, output, false);
        if (iteration >= 3) samples[iteration - 3] = observed.ns;
    }
    const diagnostic = try run(init.io, init.gpa, produced, &oracle, storage, output, true);
    var buffer: [8192]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{
        .format = format,
        .fixture = @tagName(fixture),
        .count = count,
        .image_bytes = produced.image.len,
        .producer_ns = producer_ns,
        .input_bytes = produced.bytes.len,
        .input_sha256 = std.fmt.bytesToHex(data.wire.digest(produced.bytes), .lower),
        .samples_ns = samples,
        .invocations = diagnostic.calls,
        .peak_state_bytes = diagnostic.state_bytes,
        .working_capacity = storage.len,
        .peak_working_payload_bytes = diagnostic.peak,
        .allocation_calls = diagnostic.allocations,
        .allocated_bytes = diagnostic.allocated_bytes,
        .expected_sha256 = std.fmt.bytesToHex(data.wire.digest(oracle.value[0..oracle.value_length]), .lower),
        .sample_unit = "sum of complete fresh invocation clocks; fixture replies and oracle checks excluded",
    }, .{}, &stdout.interface);
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();
}
