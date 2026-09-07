const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");
const source = boundary.computation;

fn program(b: *source.Builder) !source.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const pair = try b.schema(.{ .product = &.{ integer, integer } });
    const toggle = try b.effect(.{
        .identity = "bitmask/toggle",
        .payload = pair,
        .result = integer,
        .external = false,
    });
    const capability = try b.schema(.{ .internal = .{ .capability = toggle } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{
        .effect = toggle,
        .input = integer,
        .answer = pair,
        .capture_bound = &.{ unit, integer, pair, capability },
        .handled = &.{toggle},
        .mode = .deep,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{pair}, pair, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 0))));
    const clause = try b.declare(&.{ pair, token }, pair, &.{}, &.{});
    const payload = try b.reference(b.parameter(clause, 0));
    const toggled = try b.primitive(integer, .integer_bit_xor, &.{
        try b.primitive(integer, .field, &.{payload}, 0),
        try b.primitive(integer, .field, &.{payload}, 1),
    }, 0);
    try b.define(clause, try b.term(.{ .resume_value = .{
        .resumption = try b.reference(b.parameter(clause, 1)),
        .argument = toggled,
    } }));
    const handler = try b.handler(.{
        .mode = .deep,
        .input = pair,
        .answer = pair,
        .return_function = returns,
        .clauses = &.{.{ .effect = toggle, .function = clause, .resumption = token }},
    });
    return application(b, unit, integer, pair, toggle, capability, handler);
}

fn application(
    b: *source.Builder,
    unit: u64,
    integer: u64,
    pair: u64,
    toggle: u64,
    capability: u64,
    handler: u64,
) !source.Module {
    const body = try b.declare(&.{ capability, integer, integer, integer }, pair, &.{toggle}, &.{});
    const first = try b.variable(integer);
    const second = try b.variable(integer);
    const request = try b.term(.{ .perform = .{
        .effect = toggle,
        .capability = try b.reference(b.parameter(body, 0)),
        .payload = try b.primitive(pair, .product, &.{
            try b.reference(b.parameter(body, 1)),
            try b.reference(b.parameter(body, 2)),
        }, 0),
    } });
    const next = try b.term(.{ .perform = .{
        .effect = toggle,
        .capability = try b.reference(b.parameter(body, 0)),
        .payload = try b.primitive(pair, .product, &.{
            try b.reference(first), try b.reference(b.parameter(body, 3)),
        }, 0),
    } });
    const result = try b.pure(try b.primitive(pair, .product, &.{
        try b.reference(first), try b.reference(second),
    }, 0));
    const after_yield = try b.bind(second, next, result);
    try b.define(body, try b.bind(first, request, try b.term(.{ .yield_then = after_yield })));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{ capability, integer, integer, integer },
        .result = pair,
        .effects = &.{toggle},
    } } });
    const entry = try b.declare(&.{ integer, integer, integer }, pair, &.{}, &.{});
    try b.define(entry, try b.term(.{ .handle = .{
        .handler = handler,
        .body = try b.lambda(body, body_type),
        .arguments = &.{
            try b.reference(b.parameter(entry, 0)),
            try b.reference(b.parameter(entry, 1)),
            try b.reference(b.parameter(entry, 2)),
        },
    } }));
    return b.module(entry, unit);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var b = source.Builder.init(allocator);
    defer b.deinit();
    const module = try program(&b);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (options.source) {
        const json_options: std.json.Stringify.Options = .{ .emit_strings_as_arrays = true };
        try std.json.Stringify.value(module, json_options, &output.interface);
        try output.interface.writeByte('\n');
    } else {
        var compiled = try boundary.program.compile(allocator, module);
        defer compiled.deinit();
        const length = try boundary.image_v2.encodedLength(compiled.program);
        const bytes = try allocator.alloc(u8, length);
        defer allocator.free(bytes);
        _ = try compiled.encode(allocator, bytes);
        try output.interface.writeAll(bytes);
    }
    try output.interface.flush();
}
