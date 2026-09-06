const std = @import("std");
const data = @import("boundary_data_v2");
const process = @import("process.zig");
const p = data.program;

pub const program: p.Program = .{
    .roots = .{ .entry = 0, .result = 1, .failure = 0 },
    .schemas = &.{ .u8, .{ .array = .{ .element = 0, .length = 2 } }, .{ .bounded_text = 2 }, .u64, .unit, .{ .sum = &.{ 4, 0 } } },
    .constants = &.{
        .{ .schema = 2, .bytes = &.{ 2, 0xc3, 0xa9 } }, .{ .schema = 3, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } },
        .{ .schema = 0, .bytes = &.{255} },             .{ .schema = 0, .bytes = &.{8} },
    },
    .effects = &.{.{ .identity = "fixture.bounded", .payload = 2, .result = 1 }},
    .functions = &.{.{ .entry = 0, .parameters = &.{}, .result = 1, .effects = &.{0} }},
    .blocks = &.{
        .{ .function = 0, .parameters = &.{}, .instructions = &.{.{ .opcode = .constant, .result_type = 2 }}, .terminator = .{ .perform = .{
            .effect = 0,
            .payload = 0,
            .next = .{ .block = 1, .arguments = &.{.returned} },
        } } },
        .{ .function = 0, .parameters = &.{1}, .instructions = &.{
            .{ .opcode = .constant, .result_type = 3, .immediate = 1 },
            .{ .opcode = .sequence_get, .result_type = 5, .operands = &.{ 0, 1 } },
        }, .terminator = .{ .switch_variant = .{ .value = 2, .cases = &.{
            .{ .block = 2, .arguments = &.{.returned} }, .{ .block = 3, .arguments = &.{.returned} },
        } } } },
        .{ .function = 0, .parameters = &.{4}, .instructions = &.{.{ .opcode = .constant, .result_type = 0, .immediate = 2 }}, .terminator = .{ .fail = 1 } },
        .{ .function = 0, .parameters = &.{0}, .instructions = &.{
            .{ .opcode = .constant, .result_type = 0, .immediate = 3 },
            .{ .opcode = .sequence, .result_type = 1, .operands = &.{ 0, 1 } },
        }, .terminator = .{ .return_value = 2 } },
    },
};

test "bounded request contracts reject short arrays and execute admitted arrays" {
    const allocator = std.testing.allocator;
    var parked = try process.run(allocator, .{ .program = .{ .records = program }, .instance = .{ .initial_args = &.{} } });
    defer parked.deinit();
    const request = try data.protocol.decode(data.protocol.Request, allocator, parked.record.requested.request);
    try std.testing.expectEqualSlices(u8, &.{ 2, 0xc3, 0xa9 }, request.payload);
    var buffer: [256]u8 = undefined;
    var result: data.protocol.Result = .{
        .request_identity = request.request_identity,
        .resume_schema_digest = data.wire.digest(request.resume_schema),
        .value = &.{9},
    };
    const short = try data.protocol.encode(data.protocol.Result, allocator, result, &buffer);
    try std.testing.expectError(error.InvalidValue, process.run(allocator, .{
        .program = .{ .records = program },
        .instance = .{ .snapshot = parked.record.requested.state },
        .control = .{ .continue_value = short },
    }));
    result.value = &.{ 9, 4 };
    const response = try data.protocol.encode(data.protocol.Result, allocator, result, &buffer);
    var completed = try process.run(allocator, .{
        .program = .{ .records = program },
        .instance = .{ .snapshot = parked.record.requested.state },
        .control = .{ .continue_value = response },
    });
    defer completed.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 9, 8 }, completed.record.completed);
}
