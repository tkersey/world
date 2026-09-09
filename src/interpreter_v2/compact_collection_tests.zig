const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const g = data.graph;
const Values = @import("values.zig").Values;
const Store = @import("store.zig").Store;
const maximum = std.math.maxInt(u64);

fn evaluate(v: *Values, opcode: p.Opcode, result: p.Id, args: []const g.Value) !g.Value {
    var operands: [3]p.Id = undefined;
    for (args, 0..) |_, index| operands[index] = index;
    const value = try v.evaluate(.{
        .opcode = opcode,
        .result_type = result,
        .operands = operands[0..args.len],
    }, args);
    const facts = try data.admission.schemas(v.allocator, v.program.schemas);
    try data.admission.value(v.allocator, v.program.schemas, facts, .{
        .schema = result,
        .bytes = try v.bytes(&value),
    });
    return value;
}

fn expectCount(v: *Values, value: g.Value, count: u64) !void {
    var expected: [10]u8 = undefined;
    var writer: data.wire.Writer = .{ .output = &expected };
    if (v.program.schemas[@intCast(value.schema)] != .array) try writer.natural(count);
    try std.testing.expectEqualSlices(u8, expected[0..writer.position], try v.bytes(&value));
}

fn checkCollection(v: *Values, count: u64) !void {
    var buffer: [10]u8 = undefined;
    var writer: data.wire.Writer = .{ .output = &buffer };
    const array = v.program.schemas[1] == .array;
    if (!array) try writer.natural(count);
    const literal: p.Literal = .{ .schema = 1, .bytes = buffer[0..writer.position] };
    const facts = try data.admission.schemas(v.allocator, v.program.schemas);
    try data.admission.value(v.allocator, v.program.schemas, facts, literal);
    const items = try v.store.literal(v.program, literal);
    const unit = try v.store.literal(v.program, .{ .schema = 0, .bytes = &.{} });
    const length = try evaluate(v, .sequence_length, 3, &.{items});
    try std.testing.expectEqual(count, std.mem.readInt(u64, length.body.scalar[0..8], .little));
    const absent = try evaluate(v, .sequence_get, 4, &.{ items, Values.natural(3, count) });
    try std.testing.expectEqualSlices(u8, &.{0}, try v.bytes(&absent));
    if (count != 0) {
        const index = Values.natural(3, count - 1);
        const found = try evaluate(v, .sequence_get, 4, &.{ items, index });
        try std.testing.expectEqualSlices(u8, &.{1}, try v.bytes(&found));
        try expectCount(v, try evaluate(v, .sequence_set, 1, &.{ items, index, unit }), count);
    }
    try std.testing.expectError(error.ElementIndex, evaluate(v, .sequence_set, 1, &.{ items, Values.natural(3, count), unit }));
    if (array) return;
    try expectCount(v, try evaluate(v, .sequence_take, 1, &.{ items, Values.natural(3, 3) }), @min(count, 3));
    const empty = try v.store.literal(v.program, .{ .schema = 1, .bytes = &.{0} });
    try expectCount(v, try evaluate(v, .sequence_concat, 1, &.{ items, empty }), count);
    if (count == maximum) {
        const err = if (v.program.schemas[1] == .vector)
            error.CollectionCapacity
        else
            error.InvalidLength;
        try std.testing.expectError(err, evaluate(v, .sequence_append, 1, &.{ items, unit }));
    } else try expectCount(v, try evaluate(v, .sequence_append, 1, &.{ items, unit }), count + 1);
    const popped = try evaluate(v, .sequence_pop, 6, &.{items});
    const selected = try v.split(popped);
    try std.testing.expectEqual(@as(u64, @intFromBool(count != 0)), selected.tag);
    if (count != 0) try expectCount(v, (try v.split(selected.fields[0])).fields[1], count - 1);
    const last = try v.split(try evaluate(v, .sequence_pop_last, 7, &.{items}));
    try expectCount(v, last.fields[0], if (count == 0) 0 else count - 1);
    try std.testing.expectEqualSlices(u8, &.{@intFromBool(count != 0)}, try v.bytes(&last.fields[1]));
}

test "zero-width collection operations preserve full cardinality in fixed storage" {
    for ([_]u64{ 0, 1, 1 << 32, 768614336404564650, maximum }) |count| {
        for (0..3) |kind| for (0..3) |element| {
            var buffer: [65536]u8 = undefined;
            var fixed = std.heap.FixedBufferAllocator.init(&buffer);
            var arena = std.heap.ArenaAllocator.init(fixed.allocator());
            defer arena.deinit();
            const allocator = arena.allocator();
            const schemas = [_]p.Schema{
                switch (element) {
                    0 => .unit,
                    1 => .{ .product = &.{ 2, 2 } },
                    else => .{ .array = .{ .element = 2, .length = 17 } },
                },
                switch (kind) {
                    0 => .{ .seq = 0 },
                    1 => .{ .vector = .{ .element = 0, .maximum = maximum } },
                    else => .{ .array = .{ .element = 0, .length = count } },
                },
                .unit,
                .u64,
                .{ .sum = &.{ 2, 0 } },
                .{ .product = &.{ 0, 1 } },
                .{ .sum = &.{ 2, 5 } },
                .{ .product = &.{ 1, 4 } },
            };
            const program: p.Program = .{
                .roots = .{ .entry = 0, .result = 3, .failure = 2 },
                .schemas = &schemas,
                .constants = &.{},
                .effects = &.{},
                .functions = &.{},
                .blocks = &.{},
            };
            var store: Store = .{ .allocator = allocator };
            defer store.deinit();
            var values: Values = .{ .allocator = allocator, .program = program, .store = &store };
            try checkCollection(&values, count);
        };
    }
}

test "encoded collection slices preserve variable-width elements and their order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const program: p.Program = .{
        .roots = .{ .entry = 0, .result = 3, .failure = 2 },
        .schemas = &.{
            .bytes,                 .{ .seq = 0 },              .unit,                  .u64,
            .{ .sum = &.{ 2, 0 } }, .{ .product = &.{ 0, 1 } }, .{ .sum = &.{ 2, 5 } }, .{ .product = &.{ 1, 4 } },
        },
        .constants = &.{},
        .effects = &.{},
        .functions = &.{},
        .blocks = &.{},
    };
    var store: Store = .{ .allocator = allocator };
    defer store.deinit();
    var v: Values = .{ .allocator = allocator, .program = program, .store = &store };
    const items = try store.literal(program, .{
        .schema = 1,
        .bytes = &.{ 3, 1, 'a', 0, 2, 'b', 'c' },
    });
    const other = try store.literal(program, .{ .schema = 1, .bytes = &.{ 1, 1, 'x' } });
    const replacement = try store.literal(program, .{ .schema = 0, .bytes = &.{ 2, 'd', 'e' } });
    const index = Values.natural(3, 1);
    const got = try evaluate(&v, .sequence_get, 4, &.{ items, index });
    try std.testing.expectEqualSlices(u8, &.{ 1, 0 }, try v.bytes(&got));
    const set = try evaluate(&v, .sequence_set, 1, &.{ items, index, replacement });
    try std.testing.expectEqualSlices(u8, &.{ 3, 1, 'a', 2, 'd', 'e', 2, 'b', 'c' }, try v.bytes(&set));
    const joined = try evaluate(&v, .sequence_concat, 1, &.{ items, other });
    try std.testing.expectEqualSlices(u8, &.{ 4, 1, 'a', 0, 2, 'b', 'c', 1, 'x' }, try v.bytes(&joined));
    const prefix = try evaluate(&v, .sequence_take, 1, &.{ items, Values.natural(3, 2) });
    try std.testing.expectEqualSlices(u8, &.{ 2, 1, 'a', 0 }, try v.bytes(&prefix));
    const front = try evaluate(&v, .sequence_pop, 6, &.{items});
    try std.testing.expectEqualSlices(u8, &.{ 1, 1, 'a', 2, 0, 2, 'b', 'c' }, try v.bytes(&front));
    const back = try evaluate(&v, .sequence_pop_last, 7, &.{items});
    try std.testing.expectEqualSlices(u8, &.{ 2, 1, 'a', 0, 1, 2, 'b', 'c' }, try v.bytes(&back));
}
