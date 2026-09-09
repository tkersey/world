// Copyright (c) 2026 World contributors. MIT license.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const process = @import("process.zig");

pub fn program(comptime failing: bool) p.Program {
    return .{
        .roots = .{ .entry = 0, .result = 1, .failure = 1 },
        .schemas = &.{
            .unit,                                                                                                               .u8,                                                                                          .text,                                                                                                                                                                 .bytes,
            .{ .sum = &.{ 2, 3 } },                                                                                              .{ .sum = &.{ 0, 1, 4, 0 } },                                                                 .{ .sum = &.{ 0, 4 } },                                                                                                                                                .{ .seq = 1 },
            .{ .product = &.{ 5, 6, 7 } },                                                                                       .{ .internal = .{ .capability = 0 } },                                                        .{ .internal = .{ .resumption = .{ .effect = 0, .input = 1, .answer = 1, .effects = &.{1}, .handled = &.{0}, .mode = .deep, .use = .linear, .obligations = true } } }, .{ .internal = .{ .computation = .{ .parameters = &.{9}, .result = 1, .effects = &.{ 0, 1 } } } },
            .{ .internal = .{ .computation = .{ .parameters = &.{}, .result = 1, .effects = &.{0}, .capture_bound = &.{9} } } }, .{ .internal = .{ .computation = .{ .parameters = &.{8}, .result = 0, .effects = &.{1} } } },
        },
        .constants = &.{ .{ .schema = 0, .bytes = &.{} }, .{ .schema = 1, .bytes = &.{7} }, .{ .schema = 1, .bytes = &.{9} } },
        .effects = &.{ .{ .identity = "fixture/stop", .payload = 0, .result = 1, .external = false }, .{ .identity = "fixture/release", .payload = 8, .result = 0 } },
        .functions = &.{
            .{ .entry = 0, .parameters = &.{}, .result = 1, .effects = &.{1} },
            .{ .entry = 2, .parameters = &.{9}, .result = 1, .effects = &.{ 0, 1 } },
            .{ .entry = 4, .parameters = &.{9}, .result = 1, .effects = &.{0} },
            .{ .entry = 6, .parameters = &.{1}, .result = 1 },
            .{ .entry = 7, .parameters = &.{ 0, 10 }, .result = 1, .effects = &.{1} },
            .{ .entry = 9, .parameters = &.{8}, .result = 0, .effects = &.{1} },
        },
        .blocks = &.{
            .{ .function = 0, .parameters = &.{}, .instructions = &.{.{ .opcode = .computation, .result_type = 11, .immediate = 0 }}, .terminator = .{ .handle = .{ .handler = 0, .body = 0, .arguments = &.{}, .state = &.{}, .next = .{ .block = 1, .arguments = &.{.returned} } } } },
            .{ .function = 0, .parameters = &.{1}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 1, .parameters = &.{9}, .instructions = &.{ .{ .opcode = .computation, .result_type = 12, .immediate = 1, .operands = &.{0} }, .{ .opcode = .computation, .result_type = 13, .immediate = 2 } }, .terminator = .{ .protect = .{ .body = 1, .cleanup = 2, .arguments = &.{}, .next = .{ .block = 3, .arguments = &.{.returned} } } } },
            .{ .function = 1, .parameters = &.{1}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 2, .parameters = &.{9}, .instructions = &.{.{ .opcode = .constant, .result_type = 0, .immediate = 0 }}, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 1, .next = .{ .block = 5, .arguments = &.{.returned} } } } },
            .{ .function = 2, .parameters = &.{1}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 3, .parameters = &.{1}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 4, .parameters = &.{ 0, 10 }, .instructions = if (failing) &.{.{ .opcode = .constant, .result_type = 1, .immediate = 2 }} else &.{}, .terminator = if (failing) .{ .fail = 2 } else .{ .dispose = .{ .owned = 1, .next = .{ .block = 8, .arguments = &.{} } } } },
            .{ .function = 4, .parameters = &.{}, .instructions = &.{.{ .opcode = .constant, .result_type = 1, .immediate = 1 }}, .terminator = .{ .return_value = 0 } },
            .{ .function = 5, .parameters = &.{8}, .instructions = &.{}, .terminator = .{ .perform = .{ .effect = 1, .payload = 0, .next = .{ .block = 10, .arguments = &.{.returned} } } } },
            .{ .function = 5, .parameters = &.{0}, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        },
        .handlers = &.{.{ .mode = .deep, .input = 1, .answer = 1, .return_function = 3, .clauses = &.{.{ .effect = 0, .function = 4, .resumption = 10 }}, .effects = &.{1} }},
        .scopes = .{ .captures = &.{ .{ .fields = &.{}, .use = .reusable }, .{ .fields = &.{9}, .use = .reusable } } },
        .constructors = &.{ .{ .function = 1, .capture = 0, .schema = 11 }, .{ .function = 2, .capture = 1, .schema = 12 }, .{ .function = 5, .capture = 0, .schema = 13 } },
    };
}

test "explicit disposal and abrupt failure unwind an owned capture before continuing" {
    const allocator = std.testing.allocator;
    inline for (.{ false, true }) |failing| {
        const image = program(failing);
        var current = try process.advance(allocator, .{ .program = .{ .records = image }, .instance = .{ .initial_args = &.{} } });
        defer current.deinit();
        while (current.record == .progressed) {
            const next = try process.advance(allocator, .{ .program = .{ .records = image }, .instance = .{ .snapshot = current.record.progressed } });
            current.deinit();
            current = next;
        }
        const request = try data.protocol.decode(data.protocol.Request, allocator, current.record.requested.request);
        try std.testing.expectEqualStrings("fixture/release", request.semantic_identity);
        try std.testing.expectEqual(@as(u8, if (failing) 1 else 3), request.payload[0]);
        const result: data.protocol.Result = .{ .request_identity = request.request_identity, .resume_schema_digest = data.wire.digest(request.resume_schema), .value = &.{} };
        const bytes = try allocator.alloc(u8, try data.protocol.encodedLength(data.protocol.Result, result));
        defer allocator.free(bytes);
        _ = try data.protocol.encode(data.protocol.Result, allocator, result, bytes);
        var terminal = try process.run(allocator, .{ .program = .{ .records = image }, .instance = .{ .snapshot = current.record.requested.state }, .control = .{ .continue_value = bytes } });
        defer terminal.deinit();
        try std.testing.expectEqualSlices(u8, if (failing) &.{9} else &.{7}, if (failing) terminal.record.failed.value else terminal.record.completed);
    }
}

test "a false empty-obligation bound cannot grant affine dropping or multi capture" {
    const allocator = std.testing.allocator;
    var image = program(false);
    const schemas = try allocator.dupe(p.Schema, image.schemas);
    defer allocator.free(schemas);
    image.schemas = schemas;
    schemas[10].internal.resumption.obligations = false;
    schemas[10].internal.resumption.use = .affine;
    try std.testing.expectError(error.InvalidOwnership, data.admission.program(allocator, image));
    schemas[10].internal.resumption.use = .multi;
    try std.testing.expectError(error.InvalidOwnership, data.admission.program(allocator, image));
}
