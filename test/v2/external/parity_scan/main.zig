const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");
const source = boundary.computation;

fn program(b: *source.Builder) !source.Module {
    const unit = try b.scalar(void);
    const boolean = try b.scalar(bool);
    const values = try b.schema(.{ .product = &.{ boolean, boolean, boolean, boolean } });
    const operation = try b.effect(.{
        .identity = "logic/prefix-parity",
        .payload = boolean,
        .result = boolean,
        .external = false,
    });
    const capability = try b.schema(.{ .internal = .{ .capability = operation } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{
        .effect = operation,
        .input = boolean,
        .answer = values,
        .effects = &.{operation},
        .capture_bound = &.{ unit, boolean, values, capability },
        .handled = &.{operation},
        .mode = .shallow,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{ boolean, values }, values, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 1))));
    const clause = try b.declare(&.{ boolean, boolean, token }, values, &.{}, &.{});
    const handler = try b.handler(.{
        .mode = .shallow,
        .input = values,
        .answer = values,
        .return_function = returns,
        .state = &.{boolean},
        .clauses = &.{.{ .effect = operation, .function = clause, .resumption = token }},
    });
    const previous = try b.reference(b.parameter(clause, 0));
    const incoming = try b.reference(b.parameter(clause, 1));
    const resumption = try b.reference(b.parameter(clause, 2));
    try b.define(clause, try b.term(.{ .conditional = .{
        .condition = try b.primitive(boolean, .equal, &.{ previous, incoming }, 0),
        .when_true = try update(b, handler, resumption, false),
        .when_false = try update(b, handler, resumption, true),
    } }));
    return application(b, boolean, values, operation, capability, handler);
}

fn update(b: *source.Builder, handler: u64, token: u64, odd: bool) !u64 {
    const parity = try b.constant(bool, odd);
    return b.term(.{ .resume_with = .{
        .resumption = token,
        .argument = parity,
        .handler = handler,
        .state = &.{parity},
    } });
}

fn application(
    b: *source.Builder,
    boolean: u64,
    values: u64,
    operation: u64,
    capability: u64,
    handler: u64,
) !source.Module {
    const parameters: []const u64 = &.{ capability, boolean, boolean, boolean, boolean };
    const body = try b.declare(parameters, values, &.{operation}, &.{});
    const cap = try b.reference(b.parameter(body, 0));
    var variables: [4]u64 = undefined;
    var references: [4]u64 = undefined;
    for (&variables, &references) |*variable, *reference| {
        variable.* = try b.variable(boolean);
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
    const args: []const u64 = &.{ boolean, boolean, boolean, boolean };
    const installed = try b.declare(args, values, &.{}, &.{});
    var arguments: [4]u64 = undefined;
    for (&arguments, 0..) |*argument, position| {
        argument.* = try b.reference(b.parameter(installed, position));
    }
    try b.define(installed, try b.term(.{ .handle = .{
        .handler = handler,
        .body = try b.lambda(body, body_type),
        .arguments = &arguments,
        .state = &.{try b.constant(bool, false)},
    } }));
    return reverseAnswer(b, boolean, values, installed, args);
}

fn reverseAnswer(
    b: *source.Builder,
    boolean: u64,
    values: u64,
    body: u64,
    args: []const u64,
) !source.Module {
    const returns = try b.declare(&.{values}, values, &.{}, &.{});
    const answer = try b.reference(b.parameter(returns, 0));
    var fields: [4]u64 = undefined;
    for (&fields, 0..) |*field, index| {
        field.* = try b.primitive(boolean, .field, &.{answer}, 3 - index);
    }
    try b.define(returns, try b.pure(try b.primitive(values, .product, &fields, 0)));
    const outer = try b.handler(.{
        .mode = .deep,
        .input = values,
        .answer = values,
        .return_function = returns,
        .clauses = &.{},
    });
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = args,
        .result = values,
    } } });
    const entry = try b.declare(args, values, &.{}, &.{});
    var arguments: [4]u64 = undefined;
    for (&arguments, 0..) |*argument, index| {
        argument.* = try b.reference(b.parameter(entry, index));
    }
    try b.define(entry, try b.term(.{ .handle = .{
        .handler = outer,
        .body = try b.lambda(body, body_type),
        .arguments = &arguments,
    } }));
    return b.module(entry, try b.scalar(void));
}

pub fn main(init: std.process.Init) !void {
    var b = source.Builder.init(init.gpa);
    defer b.deinit();
    const module = try program(&b);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (options.source) {
        const json_options: std.json.Stringify.Options = .{ .emit_strings_as_arrays = true };
        try std.json.Stringify.value(module, json_options, &output.interface);
        try output.interface.writeByte('\n');
    } else {
        var compiled = try boundary.program.compile(init.gpa, module);
        defer compiled.deinit();
        const bytes = try init.gpa.alloc(u8, try boundary.image_v2.encodedLength(compiled.program));
        defer init.gpa.free(bytes);
        _ = try compiled.encode(init.gpa, bytes);
        try output.interface.writeAll(bytes);
    }
    try output.interface.flush();
}
