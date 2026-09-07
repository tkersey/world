const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");
const source = boundary.computation;

fn program(b: *source.Builder) !source.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const pair = try b.schema(.{ .product = &.{ integer, integer } });
    const triple = try b.schema(.{ .product = &.{ integer, integer, integer } });
    const clamp = try b.effect(.{
        .identity = "range/clamp",
        .payload = triple,
        .result = integer,
        .external = false,
    });
    const capability = try b.schema(.{ .internal = .{ .capability = clamp } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{
        .effect = clamp,
        .input = integer,
        .answer = pair,
        .capture_bound = &.{ unit, boolean, integer, pair, triple, capability },
        .handled = &.{clamp},
        .mode = .deep,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{pair}, pair, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 0))));
    const clause = try b.declare(&.{ triple, token }, pair, &.{}, &.{});
    const payload = try b.reference(b.parameter(clause, 0));
    try b.define(clause, try b.term(.{ .resume_value = .{
        .resumption = try b.reference(b.parameter(clause, 1)),
        .argument = try clampValue(b, integer, boolean, payload),
    } }));
    const handler = try b.handler(.{
        .mode = .deep,
        .input = pair,
        .answer = pair,
        .return_function = returns,
        .clauses = &.{.{ .effect = clamp, .function = clause, .resumption = token }},
    });
    return application(b, unit, integer, pair, triple, clamp, capability, handler);
}

fn clampValue(b: *source.Builder, integer: u64, boolean: u64, payload: u64) !u64 {
    const value = try b.primitive(integer, .field, &.{payload}, 0);
    const first = try b.primitive(integer, .field, &.{payload}, 1);
    const second = try b.primitive(integer, .field, &.{payload}, 2);
    const ordered = try b.primitive(boolean, .less, &.{ first, second }, 0);
    const lower = try b.primitive(integer, .select, &.{ ordered, first, second }, 0);
    const upper = try b.primitive(integer, .select, &.{ ordered, second, first }, 0);
    const below = try b.primitive(boolean, .less, &.{ value, lower }, 0);
    const above = try b.primitive(boolean, .less, &.{ upper, value }, 0);
    const bounded_above = try b.primitive(integer, .select, &.{ above, upper, value }, 0);
    return b.primitive(integer, .select, &.{ below, lower, bounded_above }, 0);
}

fn application(
    b: *source.Builder,
    unit: u64,
    integer: u64,
    pair: u64,
    triple: u64,
    clamp: u64,
    capability: u64,
    handler: u64,
) !source.Module {
    const parameters: []const u64 = &.{ capability, integer, integer, integer, integer, integer };
    const body = try b.declare(parameters, pair, &.{clamp}, &.{});
    const first = try b.variable(integer);
    const second = try b.variable(integer);
    const request = try b.term(.{ .perform = .{
        .effect = clamp,
        .capability = try b.reference(b.parameter(body, 0)),
        .payload = try b.primitive(triple, .product, &.{
            try b.reference(b.parameter(body, 1)),
            try b.reference(b.parameter(body, 2)),
            try b.reference(b.parameter(body, 3)),
        }, 0),
    } });
    const next = try b.term(.{ .perform = .{
        .effect = clamp,
        .capability = try b.reference(b.parameter(body, 0)),
        .payload = try b.primitive(triple, .product, &.{
            try b.reference(first),
            try b.reference(b.parameter(body, 4)),
            try b.reference(b.parameter(body, 5)),
        }, 0),
    } });
    const result = try b.pure(try b.primitive(pair, .product, &.{
        try b.reference(first), try b.reference(second),
    }, 0));
    const after_yield = try b.bind(second, next, result);
    try b.define(body, try b.bind(first, request, try b.term(.{ .yield_then = after_yield })));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = parameters,
        .result = pair,
        .effects = &.{clamp},
    } } });
    const entry = try b.declare(&.{ integer, integer, integer, integer, integer }, pair, &.{}, &.{});
    try b.define(entry, try b.term(.{ .handle = .{
        .handler = handler,
        .body = try b.lambda(body, body_type),
        .arguments = &.{
            try b.reference(b.parameter(entry, 0)),
            try b.reference(b.parameter(entry, 1)),
            try b.reference(b.parameter(entry, 2)),
            try b.reference(b.parameter(entry, 3)),
            try b.reference(b.parameter(entry, 4)),
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
