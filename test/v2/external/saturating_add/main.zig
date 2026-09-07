const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");
const source = boundary.computation;

fn program(b: *source.Builder) !source.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const pair = try b.schema(.{ .product = &.{ integer, integer } });
    const operation = try b.effect(.{
        .identity = "arithmetic/saturating-add",
        .payload = pair,
        .result = integer,
        .external = false,
    });
    const capability = try b.schema(.{ .internal = .{ .capability = operation } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{
        .effect = operation,
        .input = integer,
        .answer = pair,
        .capture_bound = &.{ unit, boolean, integer, pair, capability },
        .handled = &.{operation},
        .mode = .deep,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{pair}, pair, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 0))));
    const clause = try b.declare(&.{ pair, token }, pair, &.{}, &.{});
    const payload = try b.reference(b.parameter(clause, 0));
    const resumption = try b.reference(b.parameter(clause, 1));
    try b.define(clause, try addition(b, integer, boolean, payload, resumption));
    const handler = try b.handler(.{
        .mode = .deep,
        .input = pair,
        .answer = pair,
        .return_function = returns,
        .clauses = &.{.{ .effect = operation, .function = clause, .resumption = token }},
    });
    return application(b, integer, pair, operation, capability, handler);
}

fn addition(
    b: *source.Builder,
    integer: u64,
    boolean: u64,
    payload: u64,
    token: u64,
) !u64 {
    const left = try b.primitive(integer, .field, &.{payload}, 0);
    const right = try b.primitive(integer, .field, &.{payload}, 1);
    const maximum = try b.constant(u64, std.math.maxInt(u64));
    const headroom = try arithmetic(b, integer, .integer_sub, maximum, left);
    const overflow = try b.primitive(boolean, .less, &.{ headroom, right }, 0);
    const sum = try arithmetic(b, integer, .integer_add, left, right);
    return b.term(.{ .conditional = .{
        .condition = overflow,
        .when_true = try b.term(.{ .resume_value = .{
            .resumption = token,
            .argument = maximum,
        } }),
        .when_false = try b.term(.{ .resume_value = .{
            .resumption = token,
            .argument = sum,
        } }),
    } });
}

fn arithmetic(
    b: *source.Builder,
    integer: u64,
    opcode: boundary.data_v2.program.Opcode,
    left: u64,
    right: u64,
) !u64 {
    const fault = try b.failureLiteral(try b.constant(void, {}));
    return b.value(.{ .schema = integer, .expression = .{ .primitive = .{
        .opcode = opcode,
        .operands = &.{ left, right },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = fault }},
    } } });
}

fn application(
    b: *source.Builder,
    integer: u64,
    pair: u64,
    operation: u64,
    capability: u64,
    handler: u64,
) !source.Module {
    const parameters: []const u64 = &.{ capability, integer, integer, integer };
    const body = try b.declare(parameters, pair, &.{operation}, &.{});
    const first = try b.variable(integer);
    const second = try b.variable(integer);
    const request = try b.term(.{ .perform = .{
        .effect = operation,
        .capability = try b.reference(b.parameter(body, 0)),
        .payload = try b.primitive(pair, .product, &.{
            try b.reference(b.parameter(body, 1)),
            try b.reference(b.parameter(body, 2)),
        }, 0),
    } });
    const next = try b.term(.{ .perform = .{
        .effect = operation,
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
        .parameters = parameters,
        .result = pair,
        .effects = &.{operation},
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
        const length = try boundary.image_v2.encodedLength(compiled.program);
        const bytes = try allocator.alloc(u8, length);
        defer allocator.free(bytes);
        _ = try compiled.encode(allocator, bytes);
        try output.interface.writeAll(bytes);
    }
    try output.interface.flush();
}
