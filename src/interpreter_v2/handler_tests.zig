//! Target-level discriminators; source-oracle agreement is checked separately.
const std = @import("std");
const data = @import("boundary_data_v2");
const process = @import("process.zig");
const p = data.program;
const allocator = std.testing.allocator;
const overflow: []const p.InstructionFailure = &.{.{ .kind = .arithmetic_overflow, .value = 5 }};

pub const deep: p.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 0 },
    .schemas = &.{
        .u64,                                                                                                                           .unit,
        .{ .internal = .{ .capability = 0 } },                                                                                          .{ .internal = .{ .computation = .{ .parameters = &.{2}, .result = 0, .effects = &.{0} } } },
        .{ .internal = .{ .resumption = .{ .effect = 0, .input = 0, .answer = 0, .handled = &.{0}, .mode = .deep, .use = .linear } } },
    },
    .constants = &.{
        .{ .schema = 1, .bytes = &.{} },
        .{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } },
        .{ .schema = 0, .bytes = &.{ 10, 0, 0, 0, 0, 0, 0, 0 } },
        .{ .schema = 0, .bytes = &.{ 5, 0, 0, 0, 0, 0, 0, 0 } },
        .{ .schema = 0, .bytes = &.{ 7, 0, 0, 0, 0, 0, 0, 0 } },
        .{ .schema = 0, .bytes = &.{ 255, 0, 0, 0, 0, 0, 0, 0 } },
    },
    .effects = &.{.{ .identity = "example.ask", .payload = 1, .result = 0, .external = false }},
    .functions = &.{
        .{ .entry = 0, .parameters = &.{}, .result = 0 },
        .{ .entry = 2, .parameters = &.{2}, .result = 0, .effects = &.{0} },
        .{ .entry = 4, .parameters = &.{0}, .result = 0 },
        .{ .entry = 5, .parameters = &.{ 1, 4 }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .parameters = &.{}, .instructions = &.{.{ .opcode = .computation, .result_type = 3 }}, .terminator = .{ .handle = .{ .handler = 0, .body = 0, .arguments = &.{}, .state = &.{}, .next = .{ .block = 1, .arguments = &.{.returned} } } } },
        .{ .function = 0, .parameters = &.{0}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 1, .parameters = &.{2}, .instructions = &.{.{ .opcode = .constant, .result_type = 1 }}, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 1, .next = .{ .block = 3, .arguments = &.{.returned} } } } },
        .{ .function = 1, .parameters = &.{0}, .instructions = &.{
            .{ .opcode = .constant, .result_type = 0, .immediate = 1 },
            .{ .opcode = .integer_add, .result_type = 0, .operands = &.{ 0, 1 }, .failures = overflow },
        }, .terminator = .{ .return_value = 2 } },
        .{ .function = 2, .parameters = &.{0}, .instructions = &.{
            .{ .opcode = .constant, .result_type = 0, .immediate = 2 },
            .{ .opcode = .integer_mul, .result_type = 0, .operands = &.{ 0, 1 }, .failures = overflow },
        }, .terminator = .{ .return_value = 2 } },
        .{ .function = 3, .parameters = &.{ 1, 4 }, .instructions = &.{.{ .opcode = .constant, .result_type = 0, .immediate = 3 }}, .terminator = .{ .resume_value = .{ .resumption = 1, .argument = 2, .next = .{ .block = 6, .arguments = &.{.returned} } } } },
        .{ .function = 3, .parameters = &.{0}, .instructions = &.{
            .{ .opcode = .constant, .result_type = 0, .immediate = 4 },
            .{ .opcode = .integer_add, .result_type = 0, .operands = &.{ 0, 1 }, .failures = overflow },
        }, .terminator = .{ .return_value = 2 } },
    },
    .handlers = &.{.{ .mode = .deep, .input = 0, .answer = 0, .return_function = 2, .clauses = &.{.{ .effect = 0, .function = 3, .resumption = 4 }} }},
    .scopes = .{ .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 3 }},
};

test "deep non-tail resume separates return-clause and operation-clause answers" {
    var outcome = try process.run(allocator, .{ .program = .{ .records = deep }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    // resume(5): body adds 1, return clause multiplies by 10, clause adds 7.
    try std.testing.expectEqual(@as(u64, 67), std.mem.readInt(u64, outcome.record.completed[0..8], .little));
}

test "every deep capture and return position transfers through canonical State" {
    var outcome = try process.advance(allocator, .{ .program = .{ .records = deep }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    var saw_capture = false;
    while (outcome.record == .progressed) {
        var decoded = try data.snapshot.decodeGraph(allocator, outcome.record.progressed);
        defer decoded.deinit();
        for (decoded.state.nodes) |node| if (node == .one_shot) {
            saw_capture = true;
        };
        const next = try process.advance(allocator, .{ .program = .{ .records = deep }, .instance = .{ .records = decoded.state } });
        outcome.deinit();
        outcome = next;
    }
    try std.testing.expect(saw_capture);
    try std.testing.expectEqual(@as(u8, 67), outcome.record.completed[0]);
}

test "a second use of one-shot ownership rejects during code admission" {
    var blocks: [8]p.Block = undefined;
    @memcpy(blocks[0..7], deep.blocks);
    blocks[5].terminator.resume_value.next = .{ .block = 6, .arguments = &.{ .{ .slot = 1 }, .returned } };
    blocks[6] = .{ .function = 3, .parameters = &.{ 4, 0 }, .instructions = &.{}, .terminator = .{ .resume_value = .{ .resumption = 0, .argument = 1, .next = .{ .block = 7, .arguments = &.{.returned} } } } };
    blocks[7] = .{ .function = 3, .parameters = &.{0}, .instructions = &.{}, .terminator = .{ .return_value = 0 } };
    var invalid = deep;
    invalid.blocks = &blocks;
    try std.testing.expectError(error.InvalidOwnership, data.admission.program(allocator, invalid));
}

test "a call cannot silently discard a returned linear continuation" {
    var blocks: [8]p.Block = undefined;
    @memcpy(blocks[0..7], deep.blocks);
    blocks[5].terminator = .{ .call = .{ .function = 4, .arguments = &.{1}, .next = .{ .block = 6, .arguments = &.{.{ .slot = 2 }} } } };
    blocks[7] = .{ .function = 4, .parameters = &.{4}, .instructions = &.{}, .terminator = .{ .return_value = 0 } };
    var functions: [5]p.Function = undefined;
    @memcpy(functions[0..4], deep.functions);
    functions[4] = .{ .entry = 7, .parameters = &.{4}, .result = 4 };
    var invalid = deep;
    invalid.blocks = &blocks;
    invalid.functions = &functions;
    try std.testing.expectError(error.InvalidOwnership, data.admission.program(allocator, invalid));
}

test "nested non-tail handlers preserve borrowed outer capabilities and both answers" {
    var schemas: [7]p.Schema = undefined;
    @memcpy(schemas[0..5], deep.schemas);
    schemas[4].internal.resumption.capture_bound = &.{ 0, 2, 6 };
    schemas[5] = .{ .internal = .{ .computation = .{ .parameters = &.{2}, .result = 0, .effects = &.{0}, .capture_bound = &.{2} } } };
    schemas[6] = schemas[4];
    schemas[6].internal.resumption.effects = &.{0};
    var functions: [6]p.Function = undefined;
    @memcpy(functions[0..4], deep.functions);
    functions[4] = .{ .entry = 7, .parameters = &.{ 2, 2 }, .result = 0, .effects = &.{0} };
    functions[5] = .{ .entry = 10, .parameters = &.{ 1, 6 }, .result = 0, .effects = &.{0} };
    var blocks: [12]p.Block = undefined;
    @memcpy(blocks[0..7], deep.blocks);
    blocks[2] = .{ .function = 1, .parameters = &.{2}, .instructions = &.{.{ .opcode = .computation, .result_type = 5, .immediate = 1, .operands = &.{0} }}, .terminator = .{ .handle = .{ .handler = 1, .body = 1, .arguments = &.{}, .state = &.{}, .next = .{ .block = 3, .arguments = &.{.returned} } } } };
    blocks[3].instructions = &.{};
    blocks[3].terminator = .{ .return_value = 0 };
    blocks[7] = .{ .function = 4, .parameters = &.{ 2, 2 }, .instructions = &.{.{ .opcode = .constant, .result_type = 1 }}, .terminator = .{ .perform = .{ .effect = 0, .capability = 1, .payload = 2, .next = .{ .block = 8, .arguments = &.{ .{ .slot = 0 }, .returned } } } } };
    blocks[8] = .{ .function = 4, .parameters = &.{ 2, 0 }, .instructions = &.{.{ .opcode = .constant, .result_type = 1 }}, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 2, .next = .{ .block = 9, .arguments = &.{.returned} } } } };
    blocks[9] = .{ .function = 4, .parameters = &.{0}, .instructions = deep.blocks[3].instructions, .terminator = .{ .return_value = 2 } };
    blocks[10] = deep.blocks[5];
    blocks[10].function = 5;
    blocks[10].parameters = &.{ 1, 6 };
    blocks[10].terminator.resume_value.next.block = 11;
    blocks[11] = deep.blocks[6];
    blocks[11].function = 5;
    var handlers: [2]p.Handler = .{ deep.handlers[0], deep.handlers[0] };
    handlers[1].effects = &.{0};
    handlers[1].clauses = &.{.{ .effect = 0, .function = 5, .resumption = 6 }};
    var nested = deep;
    nested.schemas = &schemas;
    nested.functions = &functions;
    nested.blocks = &blocks;
    nested.handlers = &handlers;
    nested.scopes.captures = &.{ .{ .fields = &.{}, .use = .reusable }, .{ .fields = &.{2}, .use = .reusable } };
    nested.constructors = &.{ .{ .function = 1, .capture = 0, .schema = 3 }, .{ .function = 4, .capture = 1, .schema = 5 } };
    var outcome = try process.advance(allocator, .{ .program = .{ .records = nested }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    while (outcome.record == .progressed) {
        const successor = try process.advance(allocator, .{ .program = .{ .records = nested }, .instance = .{ .snapshot = outcome.record.progressed } });
        outcome.deinit();
        outcome = successor;
    }
    // Inner: 6*10+7=67. Outer: 67*10+7=677.
    try std.testing.expectEqual(@as(u64, 677), std.mem.readInt(u64, outcome.record.completed[0..8], .little));
}

test "resumeWithComputation injects a thunk before the suspended operation returns" {
    var schemas: [6]p.Schema = undefined;
    @memcpy(schemas[0..5], deep.schemas);
    schemas[5] = .{ .internal = .{ .computation = .{ .parameters = &.{}, .result = 0 } } };
    var functions: [5]p.Function = undefined;
    @memcpy(functions[0..4], deep.functions);
    functions[4] = .{ .entry = 7, .parameters = &.{}, .result = 0 };
    var blocks: [8]p.Block = undefined;
    @memcpy(blocks[0..7], deep.blocks);
    blocks[5].instructions = &.{.{ .opcode = .computation, .result_type = 5, .immediate = 1 }};
    blocks[5].terminator = .{ .resume_computation = .{ .resumption = 1, .computation = 2, .next = .{ .block = 6, .arguments = &.{.returned} } } };
    blocks[7] = .{ .function = 4, .parameters = &.{}, .instructions = &.{.{ .opcode = .constant, .result_type = 0, .immediate = 3 }}, .terminator = .{ .return_value = 0 } };
    var injected = deep;
    injected.schemas = &schemas;
    injected.functions = &functions;
    injected.blocks = &blocks;
    injected.constructors = &.{ .{ .function = 1, .capture = 0, .schema = 3 }, .{ .function = 4, .capture = 0, .schema = 5 } };
    var outcome = try process.advance(allocator, .{ .program = .{ .records = injected }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    var saw_injection = false;
    while (outcome.record == .progressed) {
        var saved = try data.snapshot.decodeGraph(allocator, outcome.record.progressed);
        defer saved.deinit();
        for (saved.state.nodes) |record| if (record == .injection) {
            saw_injection = true;
        };
        const successor = try process.advance(allocator, .{ .program = .{ .records = injected }, .instance = .{ .snapshot = outcome.record.progressed } });
        outcome.deinit();
        outcome = successor;
    }
    try std.testing.expect(saw_injection);
    try std.testing.expectEqual(@as(u64, 67), std.mem.readInt(u64, outcome.record.completed[0..8], .little));
}
