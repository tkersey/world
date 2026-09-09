//! Protocol phase is authored handler state; the kernel does not know the protocol.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const process = @import("process.zig");
const allocator = std.testing.allocator;
const Bool = 0;
const Unit = 1;
const Cap = 2;
const Body = 3;
const Resume = 4;

pub const protocol: p.Program = .{
    .roots = .{ .entry = 0, .result = Bool, .failure = Unit },
    .schemas = &.{
        .boolean,                                                                                                                                                                            .unit,
        .{ .internal = .{ .capability = 0 } },                                                                                                                                               .{ .internal = .{ .computation = .{ .parameters = &.{Cap}, .result = Bool, .effects = &.{0}, .capture_bound = &.{Bool} } } },
        .{ .internal = .{ .resumption = .{ .effect = 0, .input = Bool, .answer = Bool, .effects = &.{0}, .capture_bound = &.{Cap}, .handled = &.{0}, .mode = .shallow, .use = .linear } } },
    },
    .constants = &.{ .{ .schema = Bool, .bytes = &.{0} }, .{ .schema = Bool, .bytes = &.{1} }, .{ .schema = Unit, .bytes = &.{} } },
    .effects = &.{.{ .identity = "protocol.send-receive", .payload = Bool, .result = Bool, .external = false }},
    .functions = &.{
        .{ .entry = 0, .parameters = &.{Bool}, .result = Bool },
        .{ .entry = 2, .parameters = &.{ Bool, Cap }, .result = Bool, .effects = &.{0} },
        .{ .entry = 5, .parameters = &.{ Bool, Bool }, .result = Bool },
        .{ .entry = 6, .parameters = &.{ Bool, Bool, Resume }, .result = Bool },
    },
    .blocks = &.{
        .{ .function = 0, .parameters = &.{Bool}, .instructions = &.{ .{ .opcode = .constant, .result_type = Bool }, .{ .opcode = .computation, .result_type = Body, .operands = &.{0} } }, .terminator = .{ .handle = .{ .handler = 0, .body = 2, .arguments = &.{}, .state = &.{1}, .next = .{ .block = 1, .arguments = &.{.returned} } } } },
        .{ .function = 0, .parameters = &.{Bool}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 1, .parameters = &.{ Bool, Cap }, .instructions = &.{}, .terminator = .{ .perform = .{ .effect = 0, .capability = 1, .payload = 0, .next = .{ .block = 3, .arguments = &.{ .{ .slot = 1 }, .returned } } } } },
        .{ .function = 1, .parameters = &.{ Cap, Bool }, .instructions = &.{.{ .opcode = .constant, .result_type = Bool, .immediate = 1 }}, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 2, .next = .{ .block = 4, .arguments = &.{.returned} } } } },
        .{ .function = 1, .parameters = &.{Bool}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 2, .parameters = &.{ Bool, Bool }, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
        .{ .function = 3, .parameters = &.{ Bool, Bool, Resume }, .instructions = &.{.{ .opcode = .equal, .result_type = Bool, .operands = &.{ 0, 1 } }}, .terminator = .{ .branch = .{ .condition = 3, .when_true = .{ .block = 7, .arguments = &.{ .{ .slot = 0 }, .{ .slot = 1 }, .{ .slot = 2 } } }, .when_false = .{ .block = 9, .arguments = &.{.{ .slot = 2 }} } } } },
        .{ .function = 3, .parameters = &.{ Bool, Bool, Resume }, .instructions = &.{.{ .opcode = .boolean_not, .result_type = Bool, .operands = &.{0} }}, .terminator = .{ .resume_with = .{ .resumption = 2, .argument = 1, .handler = 0, .state = &.{3}, .next = .{ .block = 8, .arguments = &.{.returned} } } } },
        .{ .function = 3, .parameters = &.{Bool}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 3, .parameters = &.{Resume}, .instructions = &.{.{ .opcode = .constant, .result_type = Unit, .immediate = 2 }}, .terminator = .{ .fail = 1 } },
    },
    .handlers = &.{.{ .mode = .shallow, .input = Bool, .answer = Bool, .return_function = 2, .state = &.{Bool}, .clauses = &.{.{ .effect = 0, .function = 3, .resumption = Resume }} }},
    .scopes = .{ .captures = &.{.{ .fields = &.{Bool}, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = Body }},
};

test "shallow resumeWith changes send/receive phase and rejects an invalid phase" {
    var valid = try process.run(allocator, .{ .program = .{ .records = protocol }, .instance = .{ .initial_args = &.{0} } });
    defer valid.deinit();
    try std.testing.expectEqualSlices(u8, &.{1}, valid.record.completed);
    var invalid = try process.run(allocator, .{ .program = .{ .records = protocol }, .instance = .{ .initial_args = &.{1} } });
    defer invalid.deinit();
    try std.testing.expectEqualSlices(u8, &.{}, invalid.record.failed.value);
}

test "the successor shallow handler survives every transfer boundary" {
    var outcome = try process.advance(allocator, .{ .program = .{ .records = protocol }, .instance = .{ .initial_args = &.{0} } });
    defer outcome.deinit();
    while (outcome.record == .progressed) {
        const successor = try process.advance(allocator, .{ .program = .{ .records = protocol }, .instance = .{ .snapshot = outcome.record.progressed } });
        outcome.deinit();
        outcome = successor;
    }
    try std.testing.expectEqualSlices(u8, &.{1}, outcome.record.completed);
}
