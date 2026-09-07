const std = @import("std");
const data = @import("boundary_data_v2");
const process = @import("process.zig");
const p = data.program;
const maximum = std.math.maxInt(u64);

pub const program: p.Program = .{
    .roots = .{ .entry = 0, .result = 5, .failure = 0 },
    .schemas = &.{
        .unit,                                                .u64,                                               .{ .seq = 0 },
        .{ .vector = .{ .element = 0, .maximum = maximum } }, .{ .array = .{ .element = 0, .length = maximum } }, .{ .product = &.{ 1, 1, 1 } },
    },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .parameters = &.{ 2, 3, 4 }, .result = 5 }},
    .blocks = &.{
        .{ .function = 0, .parameters = &.{ 2, 3, 4 }, .instructions = &.{}, .terminator = .{ .yield_value = .{ .block = 1, .arguments = &.{
            .{ .slot = 0 }, .{ .slot = 1 }, .{ .slot = 2 },
        } } } },
        .{ .function = 0, .parameters = &.{ 2, 3, 4 }, .instructions = &.{
            .{ .opcode = .sequence_length, .result_type = 1, .operands = &.{0} },
            .{ .opcode = .sequence_length, .result_type = 1, .operands = &.{1} },
            .{ .opcode = .sequence_length, .result_type = 1, .operands = &.{2} },
            .{ .opcode = .product, .result_type = 5, .operands = &.{ 3, 4, 5 } },
        }, .terminator = .{ .return_value = 6 } },
    },
};

test "full-width compact cardinalities survive native yield and snapshot transfer" {
    const allocator = std.testing.allocator;
    var normalized = try data.canonical.normalize(allocator, program);
    defer normalized.deinit();
    var image_buffer: [1024]u8 = undefined;
    const image = try data.image.encode(allocator, normalized.program, &image_buffer);
    for ([_]u64{ 0, 1, 1 << 32, 768614336404564650, maximum }) |count| {
        var input_buffer: [20]u8 = undefined;
        var writer: data.wire.Writer = .{ .output = &input_buffer };
        try writer.natural(count);
        try writer.natural(count);
        const initial = input_buffer[0..writer.position];
        inline for (.{ process.run, process.advance }) |execute| {
            var first = try execute(allocator, .{
                .program = .{ .image = image },
                .instance = .{ .initial_args = initial },
            });
            defer first.deinit();
            try std.testing.expect(first.record == .yielded);
            var last = try execute(allocator, .{
                .program = .{ .records = normalized.program },
                .instance = .{ .snapshot = first.record.yielded },
            });
            defer last.deinit();
            try std.testing.expect(last.record == .completed);
            const bytes = last.record.completed;
            try std.testing.expectEqual(count, std.mem.readInt(u64, bytes[0..8], .little));
            try std.testing.expectEqual(count, std.mem.readInt(u64, bytes[8..16], .little));
            try std.testing.expectEqual(maximum, std.mem.readInt(u64, bytes[16..24], .little));
        }
    }
}
