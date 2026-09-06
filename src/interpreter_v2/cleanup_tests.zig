// Copyright (c) 2026 World contributors. MIT license.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const process = @import("process.zig");

/// Two nested protections. Both finalizers are authored computations whose
/// external Boolean result chooses success or a typed failure.
pub fn program() p.Program {
    return .{
        .roots = .{ .entry = 0, .result = 1, .failure = 1 },
        .schemas = &.{
            .unit,                         .u8,                                                                                              .text,                                                                                                                .bytes,
            .{ .sum = &.{ 2, 3 } },        .{ .sum = &.{ 0, 1, 4, 0 } },                                                                     .{ .sum = &.{ 0, 4 } },                                                                                               .{ .seq = 1 },
            .{ .product = &.{ 5, 6, 7 } }, .{ .internal = .{ .computation = .{ .parameters = &.{}, .result = 1, .effects = &.{ 0, 1 } } } }, .{ .internal = .{ .computation = .{ .parameters = &.{8}, .result = 0, .effects = &.{1}, .capture_bound = &.{1} } } }, .{ .product = &.{ 1, 8 } },
            .boolean,
        },
        .constants = &.{ .{ .schema = 1, .bytes = &.{22} }, .{ .schema = 1, .bytes = &.{11} }, .{ .schema = 0, .bytes = &.{} }, .{ .schema = 1, .bytes = &.{9} } },
        .effects = &.{ .{ .identity = "fixture/body", .payload = 0, .result = 1 }, .{ .identity = "fixture/cleanup", .payload = 11, .result = 12 } },
        .functions = &.{
            .{ .entry = 0, .parameters = &.{}, .result = 1, .effects = &.{ 0, 1 } },
            .{ .entry = 2, .parameters = &.{}, .result = 1, .effects = &.{ 0, 1 } },
            .{ .entry = 4, .parameters = &.{}, .result = 1, .effects = &.{0} },
            .{ .entry = 8, .parameters = &.{ 1, 8 }, .result = 0, .effects = &.{1} },
        },
        .blocks = &.{
            .{ .function = 0, .parameters = &.{}, .instructions = &.{
                .{ .opcode = .constant, .result_type = 1, .immediate = 0 },
                .{ .opcode = .computation, .result_type = 9, .immediate = 0 },
                .{ .opcode = .computation, .result_type = 10, .immediate = 2, .operands = &.{0} },
            }, .terminator = .{ .protect = .{ .body = 1, .cleanup = 2, .arguments = &.{}, .next = .{ .block = 1, .arguments = &.{.returned} } } } },
            .{ .function = 0, .parameters = &.{1}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 1, .parameters = &.{}, .instructions = &.{
                .{ .opcode = .constant, .result_type = 1, .immediate = 1 },
                .{ .opcode = .computation, .result_type = 9, .immediate = 1 },
                .{ .opcode = .computation, .result_type = 10, .immediate = 2, .operands = &.{0} },
            }, .terminator = .{ .protect = .{ .body = 1, .cleanup = 2, .arguments = &.{}, .next = .{ .block = 3, .arguments = &.{.returned} } } } },
            .{ .function = 1, .parameters = &.{1}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 2, .parameters = &.{}, .instructions = &.{.{ .opcode = .constant, .result_type = 0, .immediate = 2 }}, .terminator = .{ .perform = .{ .effect = 0, .payload = 0, .next = .{ .block = 5, .arguments = &.{.returned} } } } },
            .{ .function = 2, .parameters = &.{1}, .instructions = &.{ .{ .opcode = .constant, .result_type = 1, .immediate = 3 }, .{ .opcode = .equal, .result_type = 12, .operands = &.{ 0, 1 } } }, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 6, .arguments = &.{.{ .slot = 0 }} }, .when_false = .{ .block = 7, .arguments = &.{.{ .slot = 0 }} } } } },
            .{ .function = 2, .parameters = &.{1}, .instructions = &.{}, .terminator = .{ .fail = 0 } },
            .{ .function = 2, .parameters = &.{1}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 3, .parameters = &.{ 1, 8 }, .instructions = &.{.{ .opcode = .product, .result_type = 11, .operands = &.{ 0, 1 } }}, .terminator = .{ .perform = .{ .effect = 1, .payload = 2, .next = .{ .block = 9, .arguments = &.{ .{ .slot = 0 }, .returned } } } } },
            .{ .function = 3, .parameters = &.{ 1, 12 }, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 1, .when_true = .{ .block = 10, .arguments = &.{.{ .slot = 0 }} }, .when_false = .{ .block = 11, .arguments = &.{} } } } },
            .{ .function = 3, .parameters = &.{1}, .instructions = &.{}, .terminator = .{ .fail = 0 } },
            .{ .function = 3, .parameters = &.{}, .instructions = &.{.{ .opcode = .constant, .result_type = 0, .immediate = 2 }}, .terminator = .{ .return_value = 0 } },
        },
        .scopes = .{ .captures = &.{ .{ .fields = &.{}, .use = .reusable }, .{ .fields = &.{1}, .use = .reusable } } },
        .constructors = &.{ .{ .function = 1, .capture = 0, .schema = 9 }, .{ .function = 2, .capture = 0, .schema = 9 }, .{ .function = 3, .capture = 1, .schema = 10 } },
    };
}

fn response(allocator: std.mem.Allocator, requested: process.Outcome, value: u8) ![]u8 {
    const request = try data.protocol.decode(data.protocol.Request, allocator, requested.record.requested.request);
    const result: data.protocol.Result = .{ .request_identity = request.request_identity, .resume_schema_digest = data.wire.digest(request.resume_schema), .value = &.{value} };
    const bytes = try allocator.alloc(u8, try data.protocol.encodedLength(data.protocol.Result, result));
    errdefer allocator.free(bytes);
    _ = try data.protocol.encode(data.protocol.Result, allocator, result, bytes);
    return bytes;
}
fn continueWith(allocator: std.mem.Allocator, requested: process.Outcome, value: u8) !process.Outcome {
    const result = try response(allocator, requested, value);
    defer allocator.free(result);
    return process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .snapshot = requested.record.requested.state }, .control = .{ .continue_value = result } });
}
fn payload(outcome: process.Outcome) ![]const u8 {
    return (try data.protocol.decode(data.protocol.Request, std.testing.allocator, outcome.record.requested.request)).payload;
}

test "normal cleanup runs innermost first and every unwind checkpoint transfers" {
    const allocator = std.testing.allocator;
    var body = try process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .initial_args = &.{} } });
    defer body.deinit();
    const result = try response(allocator, body, 7);
    defer allocator.free(result);
    var current = try process.advance(allocator, .{ .program = .{ .records = program() }, .instance = .{ .snapshot = body.record.requested.state }, .control = .{ .continue_value = result } });
    defer current.deinit();
    var unwind_count: usize = 0;
    while (current.record == .progressed) {
        var state = try data.snapshot.decodeGraph(allocator, current.record.progressed);
        defer state.deinit();
        if (state.state.status == .unwinding) unwind_count += 1;
        const next = try process.advance(allocator, .{ .program = .{ .records = program() }, .instance = .{ .records = state.state } });
        current.deinit();
        current = next;
    }
    try std.testing.expect(unwind_count != 0);
    try std.testing.expectEqualSlices(u8, &.{ 11, 0, 0, 0 }, try payload(current));
    var outer = try continueWith(allocator, current, 0);
    defer outer.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 22, 0, 0, 0 }, try payload(outer));
    var terminal = try continueWith(allocator, outer, 0);
    defer terminal.deinit();
    try std.testing.expectEqualSlices(u8, &.{7}, terminal.record.completed);
}

test "cancellation rebinds a parked cleanup without repeating it or changing its payload" {
    const allocator = std.testing.allocator;
    var body = try process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .initial_args = &.{} } });
    defer body.deinit();
    var cleanup = try continueWith(allocator, body, 7);
    defer cleanup.deinit();
    const completed_io = try response(allocator, cleanup, 0);
    defer allocator.free(completed_io);
    var cancelled = try process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .snapshot = cleanup.record.requested.state }, .control = .{ .cancel = .{ .text = "stop" } } });
    defer cancelled.deinit();
    try std.testing.expectEqualSlices(u8, try payload(cleanup), try payload(cancelled));
    try std.testing.expect(!std.mem.eql(u8, cleanup.record.requested.request, cancelled.record.requested.request));
    try std.testing.expectError(error.InvalidResult, process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .snapshot = cancelled.record.requested.state }, .control = .{ .continue_value = completed_io } }));
    var repeated = try process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .snapshot = cancelled.record.requested.state }, .control = .{ .cancel = .{ .text = "later" } } });
    defer repeated.deinit();
    try std.testing.expectEqualSlices(u8, cancelled.record.requested.state, repeated.record.requested.state);
    try std.testing.expectEqualSlices(u8, cancelled.record.requested.request, repeated.record.requested.request);
    var outer = try continueWith(allocator, repeated, 0);
    defer outer.deinit();
    try std.testing.expectEqual(@as(u8, 22), (try payload(outer))[0]);
    try std.testing.expectEqual(@as(u8, 2), (try payload(outer))[1]);
    var terminal = try continueWith(allocator, outer, 0);
    defer terminal.deinit();
    try std.testing.expectEqualStrings("stop", terminal.record.cancelled.reason.text);
    try std.testing.expectEqualSlices(u8, &.{0}, terminal.record.cancelled.cleanup_failures);
}

test "body failure wins over later cancellation and both failing finalizers run" {
    const allocator = std.testing.allocator;
    var body = try process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .initial_args = &.{} } });
    defer body.deinit();
    var cleanup = try continueWith(allocator, body, 9);
    defer cleanup.deinit();
    var cancelled = try process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .snapshot = cleanup.record.requested.state }, .control = .{ .cancel = .{ .text = "stop" } } });
    defer cancelled.deinit();
    var outer = try continueWith(allocator, cancelled, 1);
    defer outer.deinit();
    const info = try payload(outer);
    try std.testing.expectEqualSlices(u8, &.{ 22, 1, 9 }, info[0..3]);
    var terminal = try continueWith(allocator, outer, 1);
    defer terminal.deinit();
    try std.testing.expectEqualSlices(u8, &.{9}, terminal.record.failed.value);
    try std.testing.expectEqualSlices(u8, &.{ 2, 1, 11, 1, 22 }, terminal.record.failed.cleanup_failures);
    try std.testing.expectEqualStrings("stop", terminal.record.failed.cancellation.?.text);
}

test "cancelling the body abandons its request and starts cleanup" {
    const allocator = std.testing.allocator;
    var body = try process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .initial_args = &.{} } });
    defer body.deinit();
    var cleanup = try process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .snapshot = body.record.requested.state }, .control = .{ .cancel = .{ .bytes = &.{ 0xff, 0 } } } });
    defer cleanup.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 11, 2, 1, 2, 0xff, 0 }, (try payload(cleanup))[0..6]);
    var outer = try continueWith(allocator, cleanup, 0);
    defer outer.deinit();
    var terminal = try continueWith(allocator, outer, 0);
    defer terminal.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0 }, terminal.record.cancelled.reason.bytes);
}

test "unwind allocation failure leaves the input checkpoint available for retry" {
    const allocator = std.testing.allocator;
    const Attempt = struct {
        fn run(failing: std.mem.Allocator, snapshot: []const u8) !void {
            var next = try process.advance(failing, .{ .program = .{ .records = program() }, .instance = .{ .snapshot = snapshot } });
            defer next.deinit();
            try std.testing.expect(next.record == .progressed);
        }
    };
    var body = try process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .initial_args = &.{} } });
    defer body.deinit();
    const result = try response(allocator, body, 7);
    defer allocator.free(result);
    var current = try process.advance(allocator, .{ .program = .{ .records = program() }, .instance = .{ .snapshot = body.record.requested.state }, .control = .{ .continue_value = result } });
    defer current.deinit();
    while (true) {
        var saved = try data.snapshot.decodeGraph(allocator, current.record.progressed);
        defer saved.deinit();
        if (saved.state.status == .unwinding) break;
        const next = try process.advance(allocator, .{ .program = .{ .records = program() }, .instance = .{ .snapshot = current.record.progressed } });
        current.deinit();
        current = next;
    }
    const identity = data.wire.digest(current.record.progressed);
    try std.testing.checkAllAllocationFailures(allocator, Attempt.run, .{current.record.progressed});
    try std.testing.expectEqual(identity, data.wire.digest(current.record.progressed));
}

test "portable obligations reject duplicate custody and a forged running continuation" {
    const allocator = std.testing.allocator;
    var canonical = try data.canonical.normalize(allocator, program());
    defer canonical.deinit();
    var body = try process.run(allocator, .{ .program = .{ .records = program() }, .instance = .{ .initial_args = &.{} } });
    defer body.deinit();
    var saved = try data.snapshot.decodeGraph(allocator, body.record.requested.state);
    defer saved.deinit();
    const nodes = try allocator.dupe(data.graph.Node, saved.state.nodes);
    defer allocator.free(nodes);
    var forged = saved.state;
    forged.nodes = nodes;
    var first: ?data.graph.OwnedRef = null;
    for (nodes) |*node| if (node.* == .protection) {
        if (first) |owned| {
            node.protection.obligation = owned;
            break;
        }
        first = node.protection.obligation;
    };
    try std.testing.expectError(error.InvalidOwnership, data.state_admission.validate(allocator, canonical.program, forged));
    var cleanup = try continueWith(allocator, body, 7);
    defer cleanup.deinit();
    var running = try data.snapshot.decodeGraph(allocator, cleanup.record.requested.state);
    defer running.deinit();
    const altered = try allocator.dupe(data.graph.Node, running.state.nodes);
    defer allocator.free(altered);
    forged = running.state;
    forged.nodes = altered;
    for (altered) |*node| if (node.* == .obligation and node.obligation.status == .running) {
        node.obligation.status.running = forged.roots.pending.?;
        break;
    };
    try std.testing.expectError(error.InvalidState, data.state_admission.validate(allocator, canonical.program, forged));
}
