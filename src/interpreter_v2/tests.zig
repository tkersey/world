const std = @import("std");
pub const cleanup = @import("cleanup_tests.zig").program();
const data = @import("boundary_data_v2");
const process = @import("process.zig");
const p = data.program;
const allocator = std.testing.allocator;
pub const deep = @import("handler_tests.zig").deep;
pub const choice = @import("choice_tests.zig").all;
pub const local_regions = @import("region_tests.zig").program(true);
pub const shared_regions = @import("region_tests.zig").program(false);
pub const shallow = @import("shallow_tests.zig").protocol;
pub const reentrant = @import("reentrant_tests.zig").reentrant;
pub const bounded = @import("bounded_tests.zig").program;

const forty_two: p.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 0 },
    .schemas = &.{.u64},
    .constants = &.{.{ .schema = 0, .bytes = &.{ 42, 0, 0, 0, 0, 0, 0, 0 } }},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .parameters = &.{}, .result = 0 }},
    .blocks = &.{.{ .function = 0, .parameters = &.{}, .instructions = &.{.{ .opcode = .constant, .result_type = 0 }}, .terminator = .{ .return_value = 0 } }},
};

test "native records and BPI2 execute identical code and own their results" {
    var buffer: [1024]u8 = undefined;
    const image = try data.image.encode(allocator, forty_two, &buffer);
    var direct = try process.run(allocator, .{ .program = .{ .records = forty_two }, .instance = .{ .initial_args = &.{} } });
    defer direct.deinit();
    var serialized = try process.run(allocator, .{ .program = .{ .image = image }, .instance = .{ .initial_args = &.{} } });
    defer serialized.deinit();
    @memset(&buffer, 0xa5);
    try std.testing.expectEqualSlices(u8, direct.record.completed, serialized.record.completed);
    try std.testing.expectEqual(@as(u8, 42), serialized.record.completed[0]);
}

pub const suspended: p.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 0 },
    .schemas = &.{.u64},
    .constants = forty_two.constants,
    .effects = &.{.{ .identity = "fixture.read", .payload = 0, .result = 0 }},
    .functions = &.{.{ .entry = 0, .parameters = &.{}, .result = 0, .effects = &.{0} }},
    .blocks = &.{
        .{ .function = 0, .parameters = &.{}, .instructions = &.{.{ .opcode = .constant, .result_type = 0 }}, .terminator = .{ .perform = .{ .effect = 0, .payload = 0, .next = .{ .block = 1, .arguments = &.{.returned} } } } },
        .{ .function = 0, .parameters = &.{0}, .instructions = &.{}, .terminator = .{ .yield_value = .{ .block = 2, .arguments = &.{.{ .slot = 0 }} } } },
        .{ .function = 0, .parameters = &.{0}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
    },
};

test "parked requests round trip and results resume exactly the saved position" {
    var parked = try process.run(allocator, .{ .program = .{ .records = suspended }, .instance = .{ .initial_args = &.{} } });
    defer parked.deinit();
    var transfer = try process.run(allocator, .{ .program = .{ .records = suspended }, .instance = .{ .snapshot = parked.record.requested.state } });
    defer transfer.deinit();
    try std.testing.expectEqualSlices(u8, parked.record.requested.state, transfer.record.requested.state);
    try std.testing.expectEqualSlices(u8, parked.record.requested.request, transfer.record.requested.request);
    const request = try data.protocol.decode(data.protocol.Request, allocator, parked.record.requested.request);
    var buffer: [256]u8 = undefined;
    const result = try data.protocol.encode(data.protocol.Result, allocator, .{
        .request_identity = request.request_identity,
        .resume_schema_digest = data.wire.digest(request.resume_schema),
        .value = &.{ 7, 0, 0, 0, 0, 0, 0, 0 },
    }, &buffer);
    var yielded = try process.run(allocator, .{ .program = .{ .records = suspended }, .instance = .{ .snapshot = parked.record.requested.state }, .control = .{ .continue_value = result } });
    defer yielded.deinit();
    var final = try process.run(allocator, .{ .program = .{ .records = suspended }, .instance = .{ .snapshot = yielded.record.yielded } });
    defer final.deinit();
    try std.testing.expectEqual(@as(u8, 7), final.record.completed[0]);
    try std.testing.expectError(error.InvalidControl, process.run(allocator, .{ .program = .{ .records = suspended }, .instance = .{ .snapshot = yielded.record.yielded }, .control = .{ .continue_value = result } }));
}

test "allocation failure cannot mutate input or publish an incomplete result" {
    try std.testing.checkAllAllocationFailures(allocator, allocationCase, .{});
}

fn allocationCase(failing: std.mem.Allocator) !void {
    var outcome = try process.run(failing, .{ .program = .{ .records = suspended }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    try std.testing.expectEqual(.requested, std.meta.activeTag(outcome.record));
}

pub const loop: p.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 0 },
    .schemas = &.{ .u64, .boolean },
    .constants = &.{
        .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } },
        .{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } },
    },
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .parameters = &.{0}, .result = 0 }},
    .blocks = &.{
        .{ .function = 0, .parameters = &.{0}, .instructions = &.{
            .{ .opcode = .constant, .result_type = 0 },
            .{ .opcode = .equal, .result_type = 1, .operands = &.{ 0, 1 } },
        }, .terminator = .{ .branch = .{
            .condition = 2,
            .when_true = .{ .block = 3, .arguments = &.{.{ .slot = 0 }} },
            .when_false = .{ .block = 1, .arguments = &.{.{ .slot = 0 }} },
        } } },
        .{ .function = 0, .parameters = &.{0}, .instructions = &.{
            .{ .opcode = .constant, .result_type = 0, .immediate = 1 },
            .{ .opcode = .integer_sub, .result_type = 0, .operands = &.{ 0, 1 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 0 }} },
        }, .terminator = .{ .call = .{ .function = 0, .arguments = &.{2}, .next = .{ .block = 2, .arguments = &.{.returned} } } } },
        .{ .function = 0, .parameters = &.{0}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 0, .parameters = &.{0}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
    },
};

test "tail-recursive calls reuse dead control slots without semantic fuel" {
    try data.admission.program(allocator, loop);
    var machine: @import("machine.zig").Machine = .{ .allocator = allocator, .program = loop, .identity = try data.image.identity(loop), .store = .{ .allocator = allocator } };
    defer machine.store.deinit();
    var initial: [8]u8 = undefined;
    std.mem.writeInt(u64, &initial, 10000, .little);
    try machine.initialize(&initial);
    while (true) {
        if (try machine.step()) |result| {
            var terminal = result;
            defer terminal.deinit();
            try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, terminal.record.completed[0..8], .little));
            break;
        }
        try machine.store.collect(machine.roots);
        try std.testing.expect(machine.store.nodes.items.len <= 2);
    }
}

test "recurrent execution fits reusable bounded working storage" {
    var buffer: [32768]u8 align(16) = undefined;
    var workspace = process.Workspace.init(&buffer);
    const initial = [_]u8{ 16, 39, 0, 0, 0, 0, 0, 0 }; // 10,000 iterations.
    var result = try process.run(workspace.allocator(), .{ .program = .{ .records = loop }, .instance = .{ .initial_args = &initial } });
    try std.testing.expectEqual(@as(u8, 0), result.record.completed[0]);
    result.deinit();
    try std.testing.expectEqual(@as(usize, 0), workspace.live_blocks);
    try std.testing.expectEqual(@as(usize, 0), workspace.live_payload);
}

test "repeated advance and run reach the same terminal bytes" {
    const initial = [_]u8{ 12, 0, 0, 0, 0, 0, 0, 0 };
    var direct = try process.run(allocator, .{ .program = .{ .records = loop }, .instance = .{ .initial_args = &initial } });
    defer direct.deinit();
    var stepped = try process.advance(allocator, .{ .program = .{ .records = loop }, .instance = .{ .initial_args = &initial } });
    defer stepped.deinit();
    while (stepped.record == .progressed) {
        const next = try process.advance(allocator, .{ .program = .{ .records = loop }, .instance = .{ .snapshot = stepped.record.progressed } });
        stepped.deinit();
        stepped = next;
    }
    try std.testing.expectEqualSlices(u8, direct.record.completed, stepped.record.completed);
}

test "forged pending result type and cyclic return frames reject before evaluation" {
    var parked = try process.run(allocator, .{ .program = .{ .records = suspended }, .instance = .{ .initial_args = &.{} } });
    defer parked.deinit();
    var decoded = try data.snapshot.decodeGraph(allocator, parked.record.requested.state);
    defer decoded.deinit();
    const nodes = try allocator.dupe(data.graph.Node, decoded.state.nodes);
    defer allocator.free(nodes);
    var forged = decoded.state;
    forged.nodes = nodes;
    const pending = nodes[@intCast(forged.roots.pending.?.id)].pending;
    const continuation = &nodes[@intCast(pending.continuation.id)].continuation;
    continuation.parent = pending.continuation;
    try std.testing.expectError(error.InvalidOwnership, process.run(allocator, .{ .program = .{ .records = suspended }, .instance = .{ .records = forged } }));
    continuation.parent = null;
    nodes[@intCast(forged.roots.pending.?.id)].pending.source_block = 1;
    try std.testing.expectError(error.InvalidState, process.run(allocator, .{ .program = .{ .records = suspended }, .instance = .{ .records = forged } }));
}

test {
    _ = @import("cleanup_tests.zig");
    _ = @import("abandon_tests.zig");
    _ = @import("choice_tests.zig");
    _ = @import("region_tests.zig");
    _ = @import("shallow_tests.zig");
    _ = @import("reentrant_tests.zig");
    _ = @import("clone.zig");
    _ = @import("handler_tests.zig");
    _ = @import("economy_tests.zig");
    _ = @import("admission_tests.zig");
}
