//! Capturing a lexical region copies its cells; an outer region remains shared.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const process = @import("process.zig");
const allocator = std.testing.allocator;
const Unit = 0;
const Int = 1;
const Bool = 2;
const Answers = 3;
const Cap = 4;
const Region = 5;
const Cell = 6;
const Wrapper = 7;
const Body = 8;
const Resume = 9;
const overflow: []const p.InstructionFailure = &.{.{ .kind = .arithmetic_overflow, .value = 0 }};

pub fn program(comptime local: bool) p.Program {
    const wrapper_result = if (local) Int else Answers;
    return .{
        .roots = .{ .entry = 0, .result = Answers, .failure = Unit },
        .schemas = &.{
            .unit,                                                                                                                                                                                            .u64,                                                                                                                                                                                                           .boolean,                                                       .{ .seq = Int },
            .{ .internal = .{ .capability = 0 } },                                                                                                                                                            .{ .internal = .{ .region = 0 } },                                                                                                                                                                              .{ .internal = .{ .cell = .{ .element = Int, .region = 0 } } }, .{ .internal = .{ .computation = .{ .parameters = if (local) &.{Cap} else &.{Region}, .result = wrapper_result, .effects = if (local) &.{0} else &.{}, .regions = if (local) &.{} else &.{0} } } },
            .{ .internal = .{ .computation = .{ .parameters = if (local) &.{Region} else &.{Cap}, .result = Int, .effects = &.{0}, .capture_bound = if (local) &.{Cap} else &.{Cell}, .regions = &.{0} } } }, .{ .internal = .{ .resumption = .{ .effect = 0, .input = Bool, .answer = Answers, .capture_bound = &.{Cell}, .handled = &.{0}, .mode = .deep, .use = .multi, .owned_regions = if (local) &.{0} else &.{} } } },
        },
        .constants = &.{
            .{ .schema = Unit, .bytes = &.{} },
            .{ .schema = Int, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } },
            .{ .schema = Int, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } },
            .{ .schema = Bool, .bytes = &.{0} },
            .{ .schema = Bool, .bytes = &.{1} },
        },
        .effects = &.{.{ .identity = "choice.boolean", .payload = Unit, .result = Bool, .control_use = .multi, .external = false }},
        .functions = &.{
            .{ .entry = 0, .parameters = &.{}, .result = Answers },
            .{ .entry = 2, .parameters = if (local) &.{Cap} else &.{Region}, .result = wrapper_result, .effects = if (local) &.{0} else &.{}, .regions = if (local) &.{} else &.{0} },
            .{ .entry = 4, .parameters = if (local) &.{ Cap, Region } else &.{ Cell, Cap }, .result = Int, .effects = &.{0}, .regions = &.{0} },
            .{ .entry = 6, .parameters = &.{Int}, .result = Answers },
            .{ .entry = 7, .parameters = &.{ Unit, Resume }, .result = Answers, .regions = if (local) &.{} else &.{0} },
        },
        .blocks = &.{
            .{ .function = 0, .parameters = &.{}, .instructions = &.{.{ .opcode = .computation, .result_type = Wrapper }}, .terminator = if (local) .{ .handle = .{ .handler = 0, .body = 0, .arguments = &.{}, .state = &.{}, .next = .{ .block = 1, .arguments = &.{.returned} } } } else .{ .with_region = .{ .region = 0, .body = 0, .arguments = &.{}, .next = .{ .block = 1, .arguments = &.{.returned} } } } },
            .{ .function = 0, .parameters = &.{Answers}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 1, .parameters = if (local) &.{Cap} else &.{Region}, .instructions = if (local) &.{.{ .opcode = .computation, .result_type = Body, .immediate = 1, .operands = &.{0} }} else &.{
                .{ .opcode = .constant, .result_type = Int, .immediate = 1 },
                .{ .opcode = .cell_new, .result_type = Cell, .operands = &.{ 0, 1 } },
                .{ .opcode = .computation, .result_type = Body, .immediate = 1, .operands = &.{2} },
            }, .terminator = if (local) .{ .with_region = .{ .region = 0, .body = 1, .arguments = &.{}, .next = .{ .block = 3, .arguments = &.{.returned} } } } else .{ .handle = .{ .handler = 0, .body = 3, .arguments = &.{}, .state = &.{}, .next = .{ .block = 3, .arguments = &.{.returned} } } } },
            .{ .function = 1, .parameters = &.{wrapper_result}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 2, .parameters = if (local) &.{ Cap, Region } else &.{ Cell, Cap }, .instructions = if (local) &.{
                .{ .opcode = .constant, .result_type = Int, .immediate = 1 },
                .{ .opcode = .cell_new, .result_type = Cell, .operands = &.{ 1, 2 } },
                .{ .opcode = .constant, .result_type = Unit },
            } else &.{.{ .opcode = .constant, .result_type = Unit }}, .terminator = .{ .perform = .{ .effect = 0, .capability = if (local) 0 else 1, .payload = if (local) 4 else 2, .next = .{ .block = 5, .arguments = &.{ .{ .slot = if (local) 3 else 0 }, .returned } } } } },
            .{ .function = 2, .parameters = &.{ Cell, Bool }, .instructions = &.{
                .{ .opcode = .cell_get, .result_type = Int, .operands = &.{0} },
                .{ .opcode = .constant, .result_type = Int, .immediate = 2 },
                .{ .opcode = .integer_add, .result_type = Int, .operands = &.{ 2, 3 }, .failures = overflow },
                .{ .opcode = .cell_set, .result_type = Unit, .operands = &.{ 0, 4 } },
            }, .terminator = .{ .return_value = 4 } },
            .{ .function = 3, .parameters = &.{Int}, .instructions = &.{.{ .opcode = .sequence, .result_type = Answers, .operands = &.{0} }}, .terminator = .{ .return_value = 1 } },
            .{ .function = 4, .parameters = &.{ Unit, Resume }, .instructions = &.{.{ .opcode = .constant, .result_type = Bool, .immediate = 3 }}, .terminator = .{ .resume_value = .{ .resumption = 1, .argument = 2, .next = .{ .block = 8, .arguments = &.{ .{ .slot = 1 }, .returned } } } } },
            .{ .function = 4, .parameters = &.{ Resume, Answers }, .instructions = &.{.{ .opcode = .constant, .result_type = Bool, .immediate = 4 }}, .terminator = .{ .resume_value = .{ .resumption = 0, .argument = 2, .next = .{ .block = 9, .arguments = &.{ .{ .slot = 1 }, .returned } } } } },
            .{ .function = 4, .parameters = &.{ Answers, Answers }, .instructions = &.{.{ .opcode = .sequence_concat, .result_type = Answers, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 2 } },
        },
        .handlers = &.{.{ .mode = .deep, .input = Int, .answer = Answers, .return_function = 3, .clauses = &.{.{ .effect = 0, .function = 4, .resumption = Resume }} }},
        .scopes = .{ .captures = &.{ .{ .fields = &.{}, .use = .reusable }, .{ .fields = if (local) &.{Cap} else &.{Cell}, .use = .reusable } }, .region_count = 1 },
        .constructors = &.{ .{ .function = 1, .capture = 0, .schema = Wrapper }, .{ .function = 2, .capture = 1, .schema = Body } },
    };
}

test "Choice outside a region copies its cells; Choice inside shares the outer cell" {
    inline for (.{ true, false }) |local| {
        var outcome = try process.run(allocator, .{ .program = .{ .records = program(local) }, .instance = .{ .initial_args = &.{} } });
        defer outcome.deinit();
        try std.testing.expectEqual(@as(u8, 2), outcome.record.completed[0]);
        try std.testing.expectEqual(@as(u64, 1), std.mem.readInt(u64, outcome.record.completed[1..9], .little));
        try std.testing.expectEqual(@as(u64, if (local) 1 else 2), std.mem.readInt(u64, outcome.record.completed[9..17], .little));
    }
}

test "region captures and active branches transfer after every transition" {
    inline for (.{ true, false }) |local| {
        var outcome = try process.advance(allocator, .{ .program = .{ .records = program(local) }, .instance = .{ .initial_args = &.{} } });
        defer outcome.deinit();
        while (outcome.record == .progressed) {
            const successor = try process.advance(allocator, .{ .program = .{ .records = program(local) }, .instance = .{ .snapshot = outcome.record.progressed } });
            outcome.deinit();
            outcome = successor;
        }
        try std.testing.expectEqual(@as(u64, if (local) 1 else 2), std.mem.readInt(u64, outcome.record.completed[9..17], .little));
    }
}
