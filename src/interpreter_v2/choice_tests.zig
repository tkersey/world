//! The same two-choice body under all-result and first-result interpretations.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const process = @import("process.zig");
const allocator = std.testing.allocator;

const Unit = 0;
const Bool = 1;
const Pair = 2;
const Answers = 3;
const Cap = 4;
const Body = 5;
const Resume = 6;

pub const all: p.Program = .{
    .roots = .{ .entry = 0, .result = Answers, .failure = Unit },
    .schemas = &.{
        .unit,
        .boolean,
        .{ .product = &.{ Bool, Bool } },
        .{ .seq = Pair },
        .{ .internal = .{ .capability = 0 } },
        .{ .internal = .{ .computation = .{ .parameters = &.{Cap}, .result = Pair, .effects = &.{0} } } },
        .{ .internal = .{ .resumption = .{ .effect = 0, .input = Bool, .answer = Answers, .capture_bound = &.{ Bool, Cap }, .handled = &.{0}, .mode = .deep, .use = .multi } } },
    },
    .constants = &.{ .{ .schema = Unit, .bytes = &.{} }, .{ .schema = Bool, .bytes = &.{0} }, .{ .schema = Bool, .bytes = &.{1} } },
    .effects = &.{.{ .identity = "choice.boolean", .payload = Unit, .result = Bool, .control_use = .multi, .external = false }},
    .functions = &.{
        .{ .entry = 0, .parameters = &.{}, .result = Answers },
        .{ .entry = 2, .parameters = &.{Cap}, .result = Pair, .effects = &.{0} },
        .{ .entry = 5, .parameters = &.{Pair}, .result = Answers },
        .{ .entry = 6, .parameters = &.{ Unit, Resume }, .result = Answers },
    },
    .blocks = &.{
        .{ .function = 0, .parameters = &.{}, .instructions = &.{.{ .opcode = .computation, .result_type = Body }}, .terminator = .{ .handle = .{ .handler = 0, .body = 0, .arguments = &.{}, .state = &.{}, .next = .{ .block = 1, .arguments = &.{.returned} } } } },
        .{ .function = 0, .parameters = &.{Answers}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 1, .parameters = &.{Cap}, .instructions = &.{.{ .opcode = .constant, .result_type = Unit }}, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 1, .next = .{ .block = 3, .arguments = &.{ .{ .slot = 0 }, .returned } } } } },
        .{ .function = 1, .parameters = &.{ Cap, Bool }, .instructions = &.{.{ .opcode = .constant, .result_type = Unit }}, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 2, .next = .{ .block = 4, .arguments = &.{ .{ .slot = 1 }, .returned } } } } },
        .{ .function = 1, .parameters = &.{ Bool, Bool }, .instructions = &.{.{ .opcode = .product, .result_type = Pair, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 2 } },
        .{ .function = 2, .parameters = &.{Pair}, .instructions = &.{.{ .opcode = .sequence, .result_type = Answers, .operands = &.{0} }}, .terminator = .{ .return_value = 1 } },
        .{ .function = 3, .parameters = &.{ Unit, Resume }, .instructions = &.{.{ .opcode = .constant, .result_type = Bool, .immediate = 1 }}, .terminator = .{ .resume_value = .{ .resumption = 1, .argument = 2, .next = .{ .block = 7, .arguments = &.{ .{ .slot = 1 }, .returned } } } } },
        .{ .function = 3, .parameters = &.{ Resume, Answers }, .instructions = &.{.{ .opcode = .constant, .result_type = Bool, .immediate = 2 }}, .terminator = .{ .resume_value = .{ .resumption = 0, .argument = 2, .next = .{ .block = 8, .arguments = &.{ .{ .slot = 1 }, .returned } } } } },
        .{ .function = 3, .parameters = &.{ Answers, Answers }, .instructions = &.{.{ .opcode = .sequence_concat, .result_type = Answers, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 2 } },
    },
    .handlers = &.{.{ .mode = .deep, .input = Pair, .answer = Answers, .return_function = 2, .clauses = &.{.{ .effect = 0, .function = 3, .resumption = Resume }} }},
    .scopes = .{ .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = Body }},
};

test "nested Boolean choice enumerates in left-first order with fresh attachments" {
    var outcome = try process.run(allocator, .{ .program = .{ .records = all }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 4, 0, 0, 0, 1, 1, 0, 1, 1 }, outcome.record.completed);
}

test "each retained template and nested activation survives a fresh transfer" {
    var outcome = try process.advance(allocator, .{ .program = .{ .records = all }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    var maximum_templates: usize = 0;
    while (outcome.record == .progressed) {
        var state = try data.snapshot.decodeGraph(allocator, outcome.record.progressed);
        defer state.deinit();
        var count: usize = 0;
        for (state.state.nodes) |record| if (record == .multi_template) {
            count += 1;
        };
        maximum_templates = @max(maximum_templates, count);
        const successor = try process.advance(allocator, .{ .program = .{ .records = all }, .instance = .{ .snapshot = outcome.record.progressed } });
        outcome.deinit();
        outcome = successor;
    }
    try std.testing.expect(maximum_templates >= 2);
    try std.testing.expectEqualSlices(u8, &.{ 4, 0, 0, 0, 1, 1, 0, 1, 1 }, outcome.record.completed);
}

test "a first-result clause interprets the unchanged body" {
    var blocks: [9]p.Block = all.blocks[0..9].*;
    blocks[6].terminator.resume_value.next = .{ .block = 8, .arguments = &.{ .returned, .returned } };
    blocks[8].instructions = &.{};
    blocks[8].terminator = .{ .return_value = 0 };
    var first = all;
    first.blocks = &blocks;
    var outcome = try process.run(allocator, .{ .program = .{ .records = first }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 1, 0, 0 }, outcome.record.completed);
}

test "allocation failure during capture and branch creation preserves retry input" {
    const Attempt = struct {
        fn run(failing: std.mem.Allocator, state: []const u8) !void {
            var outcome = try process.advance(failing, .{ .program = .{ .records = all }, .instance = .{ .snapshot = state } });
            defer outcome.deinit();
            try std.testing.expect(outcome.record == .progressed);
        }
    };
    var outcome = try process.advance(allocator, .{ .program = .{ .records = all }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    var verified: usize = 0;
    while (outcome.record == .progressed and verified != 2) {
        var saved = try data.snapshot.decodeGraph(allocator, outcome.record.progressed);
        defer saved.deinit();
        const block = saved.state.nodes[@intCast(saved.state.roots.current.?.id)].control.block;
        if (block == 2 or block == 6) {
            const identity = data.wire.digest(outcome.record.progressed);
            try std.testing.checkAllAllocationFailures(allocator, Attempt.run, .{outcome.record.progressed});
            try std.testing.expectEqual(identity, data.wire.digest(outcome.record.progressed));
            verified += 1;
        }
        const successor = try process.advance(allocator, .{ .program = .{ .records = all }, .instance = .{ .snapshot = outcome.record.progressed } });
        outcome.deinit();
        outcome = successor;
    }
    try std.testing.expectEqual(@as(usize, 2), verified);
}
