//! Reentry uses the same template while its first activation is still running.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const process = @import("process.zig");
const allocator = std.testing.allocator;
const Unit = 0;
const Int = 1;
const Bool = 2;
const Region = 3;
const Cap = 4;
const Resume = 5;
const MaybeResume = 6;
const TemplateCell = 7;
const CounterCell = 8;
const Wrapper = 9;
const Body = 10;
const overflow: []const p.InstructionFailure = &.{.{ .kind = .arithmetic_overflow, .value = 0 }};

pub const reentrant: p.Program = .{
    .roots = .{ .entry = 0, .result = Int, .failure = Unit },
    .schemas = &.{
        .unit,                                                                                               .u64,                                                                                                                                                                 .boolean,
        .{ .internal = .{ .region = 0 } },                                                                   .{ .internal = .{ .capability = 0 } },                                                                                                                                .{ .internal = .{ .resumption = .{ .effect = 0, .input = Unit, .answer = Int, .capture_bound = &.{ TemplateCell, CounterCell }, .handled = &.{0}, .mode = .deep, .use = .multi } } },
        .{ .sum = &.{ Unit, Resume } },                                                                      .{ .internal = .{ .cell = .{ .element = MaybeResume, .region = 0 } } },                                                                                               .{ .internal = .{ .cell = .{ .element = Int, .region = 0 } } },
        .{ .internal = .{ .computation = .{ .parameters = &.{Region}, .result = Int, .regions = &.{0} } } }, .{ .internal = .{ .computation = .{ .parameters = &.{Cap}, .result = Int, .effects = &.{0}, .capture_bound = &.{ TemplateCell, CounterCell }, .regions = &.{0} } } },
    },
    .constants = &.{
        .{ .schema = Unit, .bytes = &.{} },
        .{ .schema = Int, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } },
        .{ .schema = Int, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } },
        .{ .schema = Int, .bytes = &.{ 10, 0, 0, 0, 0, 0, 0, 0 } },
        .{ .schema = Int, .bytes = &.{ 100, 0, 0, 0, 0, 0, 0, 0 } },
    },
    .effects = &.{.{ .identity = "reentry.capture", .payload = Unit, .result = Unit, .control_use = .multi, .external = false }},
    .functions = &.{
        .{ .entry = 0, .parameters = &.{}, .result = Int },
        .{ .entry = 2, .parameters = &.{Region}, .result = Int, .regions = &.{0} },
        .{ .entry = 4, .parameters = &.{ TemplateCell, CounterCell, Cap }, .result = Int, .effects = &.{0}, .regions = &.{0} },
        .{ .entry = 11, .parameters = &.{ TemplateCell, CounterCell, Int }, .result = Int, .regions = &.{0} },
        .{ .entry = 12, .parameters = &.{ TemplateCell, CounterCell, Unit, Resume }, .result = Int, .regions = &.{0} },
    },
    .blocks = &.{
        .{ .function = 0, .parameters = &.{}, .instructions = &.{.{ .opcode = .computation, .result_type = Wrapper }}, .terminator = .{ .with_region = .{ .region = 0, .body = 0, .arguments = &.{}, .next = .{ .block = 1, .arguments = &.{.returned} } } } },
        .{ .function = 0, .parameters = &.{Int}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 1, .parameters = &.{Region}, .instructions = &.{
            .{ .opcode = .constant, .result_type = Unit },
            .{ .opcode = .variant, .result_type = MaybeResume, .operands = &.{1} },
            .{ .opcode = .cell_new, .result_type = TemplateCell, .operands = &.{ 0, 2 } },
            .{ .opcode = .constant, .result_type = Int, .immediate = 1 },
            .{ .opcode = .cell_new, .result_type = CounterCell, .operands = &.{ 0, 4 } },
            .{ .opcode = .computation, .result_type = Body, .immediate = 1, .operands = &.{ 3, 5 } },
        }, .terminator = .{ .handle = .{ .handler = 0, .body = 6, .arguments = &.{}, .state = &.{ 3, 5 }, .next = .{ .block = 3, .arguments = &.{.returned} } } } },
        .{ .function = 1, .parameters = &.{Int}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 2, .parameters = &.{ TemplateCell, CounterCell, Cap }, .instructions = &.{.{ .opcode = .constant, .result_type = Unit }}, .terminator = .{ .perform = .{ .effect = 0, .capability = 2, .payload = 3, .next = .{ .block = 5, .arguments = &.{ .{ .slot = 0 }, .{ .slot = 1 }, .returned } } } } },
        .{ .function = 2, .parameters = &.{ TemplateCell, CounterCell, Unit }, .instructions = &.{
            .{ .opcode = .cell_get, .result_type = Int, .operands = &.{1} },
            .{ .opcode = .constant, .result_type = Int, .immediate = 1 },
            .{ .opcode = .equal, .result_type = Bool, .operands = &.{ 3, 4 } },
        }, .terminator = .{ .branch = .{ .condition = 5, .when_true = .{ .block = 6, .arguments = &.{ .{ .slot = 0 }, .{ .slot = 1 } } }, .when_false = .{ .block = 10, .arguments = &.{} } } } },
        .{ .function = 2, .parameters = &.{ TemplateCell, CounterCell }, .instructions = &.{
            .{ .opcode = .constant, .result_type = Int, .immediate = 2 },
            .{ .opcode = .cell_set, .result_type = Unit, .operands = &.{ 1, 2 } },
            .{ .opcode = .cell_get, .result_type = MaybeResume, .operands = &.{0} },
        }, .terminator = .{ .switch_variant = .{ .value = 4, .cases = &.{ .{ .block = 9, .arguments = &.{.returned} }, .{ .block = 7, .arguments = &.{.returned} } } } } },
        .{ .function = 2, .parameters = &.{Resume}, .instructions = &.{.{ .opcode = .constant, .result_type = Unit }}, .terminator = .{ .resume_value = .{ .resumption = 0, .argument = 1, .next = .{ .block = 8, .arguments = &.{.returned} } } } },
        .{ .function = 2, .parameters = &.{Int}, .instructions = &.{
            .{ .opcode = .constant, .result_type = Int, .immediate = 4 },
            .{ .opcode = .integer_add, .result_type = Int, .operands = &.{ 0, 1 }, .failures = overflow },
        }, .terminator = .{ .return_value = 2 } },
        .{ .function = 2, .parameters = &.{Unit}, .instructions = &.{}, .terminator = .{ .fail = 0 } },
        .{ .function = 2, .parameters = &.{}, .instructions = &.{.{ .opcode = .constant, .result_type = Int, .immediate = 3 }}, .terminator = .{ .return_value = 0 } },
        .{ .function = 3, .parameters = &.{ TemplateCell, CounterCell, Int }, .instructions = &.{
            .{ .opcode = .constant, .result_type = Int, .immediate = 2 },
            .{ .opcode = .integer_add, .result_type = Int, .operands = &.{ 2, 3 }, .failures = overflow },
        }, .terminator = .{ .return_value = 4 } },
        .{ .function = 4, .parameters = &.{ TemplateCell, CounterCell, Unit, Resume }, .instructions = &.{
            .{ .opcode = .variant, .result_type = MaybeResume, .immediate = 1, .operands = &.{3} },
            .{ .opcode = .cell_set, .result_type = Unit, .operands = &.{ 0, 4 } },
        }, .terminator = .{ .resume_value = .{ .resumption = 3, .argument = 2, .next = .{ .block = 13, .arguments = &.{.returned} } } } },
        .{ .function = 4, .parameters = &.{Int}, .instructions = &.{
            .{ .opcode = .constant, .result_type = Int, .immediate = 2 },
            .{ .opcode = .integer_add, .result_type = Int, .operands = &.{ 0, 1 }, .failures = overflow },
        }, .terminator = .{ .return_value = 2 } },
    },
    .handlers = &.{.{ .mode = .deep, .input = Int, .answer = Int, .return_function = 3, .state = &.{ TemplateCell, CounterCell }, .clauses = &.{.{ .effect = 0, .function = 4, .resumption = Resume }} }},
    .scopes = .{ .captures = &.{ .{ .fields = &.{}, .use = .reusable }, .{ .fields = &.{ TemplateCell, CounterCell }, .use = .reusable } }, .region_count = 1 },
    .constructors = &.{ .{ .function = 1, .capture = 0, .schema = Wrapper }, .{ .function = 2, .capture = 1, .schema = Body } },
};

test "one template reenters through a cyclic cell while another activation runs" {
    var outcome = try process.run(allocator, .{ .program = .{ .records = reentrant }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    try std.testing.expectEqual(@as(u64, 113), std.mem.readInt(u64, outcome.record.completed[0..8], .little));
}

test "the live continuation-cell cycle and reentrant activation transfer together" {
    var outcome = try process.advance(allocator, .{ .program = .{ .records = reentrant }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    while (outcome.record == .progressed) {
        const successor = try process.advance(allocator, .{ .program = .{ .records = reentrant }, .instance = .{ .snapshot = outcome.record.progressed } });
        outcome.deinit();
        outcome = successor;
    }
    try std.testing.expectEqual(@as(u64, 113), std.mem.readInt(u64, outcome.record.completed[0..8], .little));
}

test "an authored caller retains the template after the original clause returns" {
    var blocks: [17]p.Block = undefined;
    @memcpy(blocks[0..14], reentrant.blocks);
    blocks[2].terminator.handle.next.arguments = &.{ .{ .slot = 3 }, .returned };
    blocks[3] = .{ .function = 1, .parameters = &.{ TemplateCell, Int }, .instructions = &.{.{ .opcode = .cell_get, .result_type = MaybeResume, .operands = &.{0} }}, .terminator = .{ .switch_variant = .{ .value = 2, .cases = &.{ .{ .block = 16, .arguments = &.{.returned} }, .{ .block = 14, .arguments = &.{.returned} } } } } };
    blocks[14] = .{ .function = 1, .parameters = &.{Resume}, .instructions = &.{.{ .opcode = .constant, .result_type = Unit }}, .terminator = .{ .resume_value = .{ .resumption = 0, .argument = 1, .next = .{ .block = 15, .arguments = &.{.returned} } } } };
    blocks[15] = .{ .function = 1, .parameters = &.{Int}, .instructions = &.{}, .terminator = .{ .return_value = 0 } };
    blocks[16] = .{ .function = 1, .parameters = &.{Unit}, .instructions = &.{}, .terminator = .{ .fail = 0 } };
    var retained = reentrant;
    retained.blocks = &blocks;
    var outcome = try process.advance(allocator, .{ .program = .{ .records = retained }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    while (outcome.record == .progressed) {
        const successor = try process.advance(allocator, .{ .program = .{ .records = retained }, .instance = .{ .snapshot = outcome.record.progressed } });
        outcome.deinit();
        outcome = successor;
    }
    try std.testing.expectEqual(@as(u64, 11), std.mem.readInt(u64, outcome.record.completed[0..8], .little));
}

test "unreachable continuation-cell cycles are reclaimed before the next return" {
    var machine: @import("machine.zig").Machine = .{ .allocator = allocator, .program = reentrant, .identity = try data.image.identity(reentrant), .store = .{ .allocator = allocator } };
    defer machine.store.deinit();
    try machine.initialize(&.{});
    var saw_cycle = false;
    var saw_reclamation = false;
    while (true) {
        if (try machine.step()) |terminal| {
            var outcome = terminal;
            outcome.deinit();
            break;
        }
        try machine.store.collect(machine.roots);
        var templates: usize = 0;
        for (machine.store.nodes.items, machine.store.alive.items) |node, live| if (live and node == .multi_template) {
            templates += 1;
        };
        saw_cycle = saw_cycle or templates > 0;
        if (saw_cycle and templates == 0) saw_reclamation = true;
    }
    try std.testing.expect(saw_cycle and saw_reclamation);
}
