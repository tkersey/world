const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");
const source = boundary.computation;

fn program(b: *source.Builder) !source.Module {
    const unit = try b.scalar(void);
    const temperature = try b.scalar(i64);
    const boolean = try b.scalar(bool);
    const answer = try b.schema(.{ .product = &.{ boolean, boolean } });
    const demand = try b.effect(.{
        .identity = "thermostat/below-setpoint",
        .payload = temperature,
        .result = boolean,
        .external = false,
    });
    const capability = try b.schema(.{ .internal = .{ .capability = demand } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{
        .effect = demand,
        .input = boolean,
        .answer = answer,
        .capture_bound = &.{ unit, temperature, boolean, answer, capability },
        .handled = &.{demand},
        .mode = .deep,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{ temperature, answer }, answer, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 1))));
    const clause = try b.declare(&.{ temperature, temperature, token }, answer, &.{}, &.{});
    const heat = try b.primitive(boolean, .less, &.{
        try b.reference(b.parameter(clause, 1)),
        try b.reference(b.parameter(clause, 0)),
    }, 0);
    try b.define(clause, try b.term(.{ .resume_value = .{
        .resumption = try b.reference(b.parameter(clause, 2)),
        .argument = heat,
    } }));
    const thermostat = try b.handler(.{
        .mode = .deep,
        .input = answer,
        .answer = answer,
        .state = &.{temperature},
        .return_function = returns,
        .clauses = &.{.{ .effect = demand, .function = clause, .resumption = token }},
    });
    const body = try b.declare(&.{ capability, temperature, temperature }, answer, &.{demand}, &.{});
    const first = try b.variable(boolean);
    const second = try b.variable(boolean);
    var requests: [2]u64 = undefined;
    for (&requests, 0..) |*request, index| request.* = try b.term(.{ .perform = .{
        .effect = demand,
        .capability = try b.reference(b.parameter(body, 0)),
        .payload = try b.reference(b.parameter(body, index + 1)),
    } });
    const result = try b.pure(try b.primitive(answer, .product, &.{
        try b.reference(first), try b.reference(second),
    }, 0));
    const after_yield = try b.bind(second, requests[1], result);
    try b.define(body, try b.bind(first, requests[0], try b.term(.{ .yield_then = after_yield })));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{ capability, temperature, temperature },
        .result = answer,
        .effects = &.{demand},
    } } });
    return install(b, temperature, answer, unit, thermostat, body, body_type);
}

fn install(b: *source.Builder, temperature: u64, answer: u64, unit: u64, thermostat: u64, body: u64, body_type: u64) !source.Module {
    const entry = try b.declare(&.{ temperature, temperature, temperature }, answer, &.{}, &.{});
    try b.define(entry, try b.term(.{ .handle = .{
        .handler = thermostat,
        .body = try b.lambda(body, body_type),
        .arguments = &.{
            try b.reference(b.parameter(entry, 1)),
            try b.reference(b.parameter(entry, 2)),
        },
        .state = &.{try b.reference(b.parameter(entry, 0))},
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
        try std.json.Stringify.value(module, .{ .emit_strings_as_arrays = true }, &output.interface);
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
