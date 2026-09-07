const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");
const source = boundary.computation;

fn program(b: *source.Builder) !source.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(i64);
    const boolean = try b.scalar(bool);
    const pair = try b.schema(.{ .product = &.{ integer, integer } });
    const answer = try b.schema(.{ .product = &.{ boolean, boolean } });
    const precedes = try b.effect(.{
        .identity = "ordering/precedes",
        .payload = pair,
        .result = boolean,
        .external = false,
    });
    const capability = try b.schema(.{ .internal = .{ .capability = precedes } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{
        .effect = precedes,
        .input = boolean,
        .answer = answer,
        .capture_bound = &.{ unit, integer, boolean, pair, answer, capability },
        .handled = &.{precedes},
        .mode = .deep,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{answer}, answer, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 0))));
    const clause = try b.declare(&.{ pair, token }, answer, &.{}, &.{});
    const payload = try b.reference(b.parameter(clause, 0));
    const comparison = try b.primitive(boolean, .less, &.{
        try b.primitive(integer, .field, &.{payload}, 0),
        try b.primitive(integer, .field, &.{payload}, 1),
    }, 0);
    try b.define(clause, try b.term(.{ .resume_value = .{
        .resumption = try b.reference(b.parameter(clause, 1)),
        .argument = comparison,
    } }));
    const handler = try b.handler(.{
        .mode = .deep,
        .input = answer,
        .answer = answer,
        .return_function = returns,
        .clauses = &.{.{ .effect = precedes, .function = clause, .resumption = token }},
    });
    return application(b, unit, boolean, pair, answer, precedes, capability, handler);
}

fn application(
    b: *source.Builder,
    unit: u64,
    boolean: u64,
    pair: u64,
    answer: u64,
    precedes: u64,
    capability: u64,
    handler: u64,
) !source.Module {
    const body = try b.declare(&.{ capability, pair, pair }, answer, &.{precedes}, &.{});
    const first = try b.variable(boolean);
    const second = try b.variable(boolean);
    var requests: [2]u64 = undefined;
    for (&requests, 0..) |*request, index| request.* = try b.term(.{ .perform = .{
        .effect = precedes,
        .capability = try b.reference(b.parameter(body, 0)),
        .payload = try b.reference(b.parameter(body, index + 1)),
    } });
    const result = try b.pure(try b.primitive(answer, .product, &.{
        try b.reference(first), try b.reference(second),
    }, 0));
    const after_yield = try b.bind(second, requests[1], result);
    try b.define(body, try b.bind(first, requests[0], try b.term(.{ .yield_then = after_yield })));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{ capability, pair, pair },
        .result = answer,
        .effects = &.{precedes},
    } } });
    const entry = try b.declare(&.{ pair, pair }, answer, &.{}, &.{});
    try b.define(entry, try b.term(.{ .handle = .{
        .handler = handler,
        .body = try b.lambda(body, body_type),
        .arguments = &.{
            try b.reference(b.parameter(entry, 0)),
            try b.reference(b.parameter(entry, 1)),
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
