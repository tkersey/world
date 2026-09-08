const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");
const source = boundary.computation;

fn program(b: *source.Builder) !source.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const values = try b.schema(.{ .product = &.{ integer, integer, integer, integer } });
    const operation = try b.effect(.{
        .identity = "scan/running-maximum",
        .payload = integer,
        .result = integer,
        .external = false,
    });
    const capability = try b.schema(.{ .internal = .{ .capability = operation } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{
        .effect = operation,
        .input = integer,
        .answer = values,
        .effects = &.{operation},
        .capture_bound = &.{ unit, boolean, integer, values, capability },
        .handled = &.{operation},
        .mode = .shallow,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{ integer, values }, values, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 1))));
    const clause = try b.declare(&.{ integer, integer, token }, values, &.{}, &.{});
    const handler = try b.handler(.{
        .mode = .shallow,
        .input = values,
        .answer = values,
        .return_function = returns,
        .state = &.{integer},
        .clauses = &.{.{ .effect = operation, .function = clause, .resumption = token }},
    });
    const previous = try b.reference(b.parameter(clause, 0));
    const incoming = try b.reference(b.parameter(clause, 1));
    const resumption = try b.reference(b.parameter(clause, 2));
    try b.define(clause, try b.term(.{ .conditional = .{
        .condition = try b.primitive(boolean, .less, &.{ previous, incoming }, 0),
        .when_true = try update(b, handler, resumption, incoming),
        .when_false = try update(b, handler, resumption, previous),
    } }));
    return application(b, integer, values, operation, capability, handler);
}

fn update(b: *source.Builder, handler: u64, resumption: u64, value: u64) !u64 {
    return b.term(.{ .resume_with = .{
        .resumption = resumption,
        .argument = value,
        .handler = handler,
        .state = &.{value},
    } });
}

fn application(
    b: *source.Builder,
    integer: u64,
    values: u64,
    operation: u64,
    capability: u64,
    handler: u64,
) !source.Module {
    const parameters: []const u64 = &.{ capability, integer, integer, integer, integer };
    const body = try b.declare(parameters, values, &.{operation}, &.{});
    const cap = try b.reference(b.parameter(body, 0));
    var variables: [4]u64 = undefined;
    var references: [4]u64 = undefined;
    for (&variables, &references) |*variable, *reference| {
        variable.* = try b.variable(integer);
        reference.* = try b.reference(variable.*);
    }
    var next = try b.pure(try b.primitive(values, .product, &references, 0));
    var index: usize = 4;
    while (index != 0) {
        index -= 1;
        const request = try b.term(.{ .perform = .{
            .effect = operation,
            .capability = cap,
            .payload = try b.reference(b.parameter(body, index + 1)),
        } });
        next = try b.bind(variables[index], request, next);
        if (index == 2) next = try b.term(.{ .yield_then = next });
    }
    try b.define(body, next);
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = parameters,
        .result = values,
        .effects = &.{operation},
    } } });
    const entry = try b.declare(&.{ integer, integer, integer, integer }, values, &.{}, &.{});
    var arguments: [4]u64 = undefined;
    for (&arguments, 0..) |*argument, position| {
        argument.* = try b.reference(b.parameter(entry, position));
    }
    try b.define(entry, try b.term(.{ .handle = .{
        .handler = handler,
        .body = try b.lambda(body, body_type),
        .arguments = &arguments,
        .state = &.{arguments[0]},
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
