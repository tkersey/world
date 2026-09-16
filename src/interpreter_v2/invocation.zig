// Copyright (c) 2026 World contributors. MIT license.
//! Fresh current-format invocation through the same stable Session evaluator.
const std = @import("std");
const data = @import("boundary_data_v2");
const protocol = data.invocation;
const runtime = @import("stable_session.zig");
const heap = @import("store.zig");
pub const Error = runtime.Error;
pub const Outcome = struct {
    arena: std.heap.ArenaAllocator,
    record: protocol.Outcome,
    pub fn deinit(self: *Outcome) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Own all mutable caller bytes before trust checks or execution.
pub fn invoke(allocator: std.mem.Allocator, input: protocol.Input) Error!Outcome {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const owned = try heap.duplicate(protocol.Input, arena.allocator(), input);
    return execute(allocator, owned);
}

fn execute(allocator: std.mem.Allocator, input: protocol.Input) Error!Outcome {
    try protocol.validate(protocol.Input, allocator, input);
    var session = switch (input.instance) {
        .initial_args => |args| try runtime.Session.initImage(allocator, input.image, args),
        .state => |state| try runtime.Session.restoreImage(allocator, input.image, state),
    };
    defer session.deinit();
    switch (input.control) {
        .none => {},
        .reply => |bytes| try session.answer(bytes),
        .resume_yield => try session.resumeYield(),
        .cancel => |reason| try session.cancel(reason),
    }
    const observation = try session.run(input.quantum);
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();
    const result: protocol.Outcome = switch (observation) {
        .progressed => .{ .progressed = try session.checkpoint(a) },
        .yielded => .{ .yielded = try session.checkpoint(a) },
        .requested => blk: {
            const pending = try session.pendingRequest(a);
            // This invocation arena owns all Pending allocations.
            break :blk .{ .requested = .{ .state = pending.state, .request = try protocol.encodeOwned(protocol.Request, a, pending.request) } };
        },
        .completed => |value| .{ .completed = try a.dupe(u8, try session.bytes(&value)) },
        .failed => |value| .{ .failed = .{
            .value = try a.dupe(u8, try session.bytes(&value)),
            .cleanup_failures = try failures(a, &session),
            .cancellation = if (session.exit.?.cancellation) |reason| try heap.duplicate(protocol.Reason, a, reason) else null,
        } },
        .cancelled => |reason| .{ .cancelled = .{ .reason = try heap.duplicate(protocol.Reason, a, reason), .cleanup_failures = try failures(a, &session) } },
    };
    return .{ .arena = arena, .record = result };
}

fn failures(allocator: std.mem.Allocator, session: *runtime.Session) Error![]const u8 {
    const values = session.exit.?.cleanup_failures;
    var measure: data.wire.Writer = .{};
    try measure.natural(values.len);
    for (values) |value| try measure.bytes(try session.bytes(&value));
    const bytes = try allocator.alloc(u8, measure.position);
    errdefer allocator.free(bytes);
    var writer: data.wire.Writer = .{ .output = bytes };
    try writer.natural(values.len);
    for (values) |value| try writer.bytes(try session.bytes(&value));
    return bytes;
}

/// No output is returned on operational failure; the original input is reusable.
pub fn invokeBytes(allocator: std.mem.Allocator, input: []const u8) Error![]u8 {
    var decoded = try protocol.decode(protocol.Input, allocator, input);
    defer decoded.deinit();
    var result = try execute(allocator, decoded.value);
    defer result.deinit();
    return protocol.encodeOwned(protocol.Outcome, allocator, result.record);
}

/// The completed invocation is private until all output checks pass. Input and
/// output may overlap because decode owns the complete command before execution.
pub fn invokeInto(allocator: std.mem.Allocator, input: []const u8, output: []u8) Error![]const u8 {
    var decoded = try protocol.decode(protocol.Input, allocator, input);
    defer decoded.deinit();
    var result = try execute(allocator, decoded.value);
    defer result.deinit();
    return protocol.encode(protocol.Outcome, allocator, result.record, output);
}
