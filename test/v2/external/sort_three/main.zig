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
    const operation = try b.effect(.{
        .identity = "ordering/compare-pair-descending",
        .payload = pair,
        .result = pair,
        .external = false,
    });
    const capability = try b.schema(.{ .internal = .{ .capability = operation } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{
        .effect = operation,
        .input = pair,
        .answer = triple,
        .capture_bound = &.{ unit, boolean, integer, pair, triple, capability },
        .handled = &.{operation},
        .mode = .deep,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{triple}, triple, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 0))));
    const clause = try b.declare(&.{ pair, token }, triple, &.{}, &.{});
    const payload = try b.reference(b.parameter(clause, 0));
    const resumption = try b.reference(b.parameter(clause, 1));
    try b.define(clause, try comparePair(b, integer, boolean, pair, payload, resumption));
    const handler = try b.handler(.{
        .mode = .deep,
        .input = triple,
        .answer = triple,
        .return_function = returns,
        .clauses = &.{.{ .effect = operation, .function = clause, .resumption = token }},
    });
    return application(b, integer, pair, triple, operation, capability, handler);
}

fn comparePair(
    b: *source.Builder,
    integer: u64,
    boolean: u64,
    pair: u64,
    payload: u64,
    token: u64,
) !u64 {
    const left = try b.primitive(integer, .field, &.{payload}, 0);
    const right = try b.primitive(integer, .field, &.{payload}, 1);
    const swap = try b.primitive(boolean, .less, &.{ left, right }, 0);
    return b.term(.{ .conditional = .{
        .condition = swap,
        .when_true = try b.term(.{ .resume_value = .{
            .resumption = token,
            .argument = try b.primitive(pair, .product, &.{ right, left }, 0),
        } }),
        .when_false = try b.term(.{ .resume_value = .{
            .resumption = token,
            .argument = payload,
        } }),
    } });
}

fn comparison(b: *source.Builder, operation: u64, cap: u64, pair: u64, a: u64, c: u64) !u64 {
    return b.term(.{ .perform = .{
        .effect = operation,
        .capability = cap,
        .payload = try b.primitive(pair, .product, &.{ a, c }, 0),
    } });
}

fn application(
    b: *source.Builder,
    integer: u64,
    pair: u64,
    triple: u64,
    operation: u64,
    capability: u64,
    handler: u64,
) !source.Module {
    const parameters: []const u64 = &.{ capability, integer, integer, integer };
    const body = try b.declare(parameters, triple, &.{operation}, &.{});
    const cap = try b.reference(b.parameter(body, 0));
    const first = try b.variable(pair);
    const second = try b.variable(pair);
    const third = try b.variable(pair);
    const first_value = try b.reference(first);
    const second_value = try b.reference(second);
    const third_value = try b.reference(third);
    const first_request = try comparison(b, operation, cap, pair, try b.reference(b.parameter(body, 1)), try b.reference(b.parameter(body, 2)));
    const second_request = try comparison(b, operation, cap, pair, try b.primitive(integer, .field, &.{first_value}, 1), try b.reference(b.parameter(body, 3)));
    const third_request = try comparison(b, operation, cap, pair, try b.primitive(integer, .field, &.{first_value}, 0), try b.primitive(integer, .field, &.{second_value}, 0));
    const result = try b.pure(try b.primitive(triple, .product, &.{
        try b.primitive(integer, .field, &.{third_value}, 0),
        try b.primitive(integer, .field, &.{third_value}, 1),
        try b.primitive(integer, .field, &.{second_value}, 1),
    }, 0));
    const after_yield = try b.bind(third, third_request, result);
    const before_yield = try b.bind(second, second_request, try b.term(.{ .yield_then = after_yield }));
    try b.define(body, try b.bind(first, first_request, before_yield));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = parameters,
        .result = triple,
        .effects = &.{operation},
    } } });
    const entry = try b.declare(&.{ integer, integer, integer }, triple, &.{}, &.{});
    try b.define(entry, try b.term(.{ .handle = .{
        .handler = handler,
        .body = try b.lambda(body, body_type),
        .arguments = &.{
            try b.reference(b.parameter(entry, 0)),
            try b.reference(b.parameter(entry, 1)),
            try b.reference(b.parameter(entry, 2)),
        },
    } }));
    return b.module(entry, try b.scalar(void));
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
        const bytes = try allocator.alloc(u8, try boundary.image_v2.encodedLength(compiled.program));
        defer allocator.free(bytes);
        _ = try compiled.encode(allocator, bytes);
        try output.interface.writeAll(bytes);
    }
    try output.interface.flush();
}
