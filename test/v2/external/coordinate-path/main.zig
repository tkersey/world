const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");
const source = boundary.computation;

fn program(b: *source.Builder) !source.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(i64);
    const point = try b.schema(.{ .product = &.{ integer, integer } });
    const answer = try b.schema(.{ .product = &.{ point, point } });
    const move = try b.effect(.{
        .identity = "coordinate-path/move",
        .payload = point,
        .result = point,
        .external = false,
    });
    const capability = try b.schema(.{ .internal = .{ .capability = move } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{
        .effect = move,
        .input = point,
        .answer = answer,
        .capture_bound = &.{ unit, integer, point, answer, capability },
        .handled = &.{move},
        .effects = &.{move},
        .mode = .shallow,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{ point, answer }, answer, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 1))));
    const clause = try b.declare(&.{ point, point, token }, answer, &.{}, &.{});
    const handler = try b.handler(.{
        .mode = .shallow,
        .input = answer,
        .answer = answer,
        .state = &.{point},
        .return_function = returns,
        .clauses = &.{.{ .effect = move, .function = clause, .resumption = token }},
    });
    const previous = try b.reference(b.parameter(clause, 0));
    const delta = try b.reference(b.parameter(clause, 1));
    var coordinates: [2]u64 = undefined;
    for (&coordinates, 0..) |*coordinate, index| {
        coordinate.* = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{
            .opcode = .integer_add,
            .operands = &.{
                try b.primitive(integer, .field, &.{previous}, index),
                try b.primitive(integer, .field, &.{delta}, index),
            },
            .failures = &.{.{
                .kind = .arithmetic_overflow,
                .value = try b.failureLiteral(try b.constant(void, {})),
            }},
        } } });
    }
    const next = try b.primitive(point, .product, &coordinates, 0);
    try b.define(clause, try b.term(.{ .resume_with = .{
        .resumption = try b.reference(b.parameter(clause, 2)),
        .argument = next,
        .handler = handler,
        .state = &.{next},
    } }));
    return application(b, unit, point, answer, move, capability, handler);
}

fn application(
    b: *source.Builder,
    unit: u64,
    point: u64,
    answer: u64,
    move: u64,
    capability: u64,
    handler: u64,
) !source.Module {
    const body = try b.declare(&.{ capability, point, point }, answer, &.{move}, &.{});
    const first = try b.variable(point);
    const second = try b.variable(point);
    var requests: [2]u64 = undefined;
    for (&requests, 0..) |*request, index| request.* = try b.term(.{ .perform = .{
        .effect = move,
        .capability = try b.reference(b.parameter(body, 0)),
        .payload = try b.reference(b.parameter(body, index + 1)),
    } });
    const result = try b.pure(try b.primitive(answer, .product, &.{
        try b.reference(first), try b.reference(second),
    }, 0));
    const after_yield = try b.bind(second, requests[1], result);
    try b.define(body, try b.bind(first, requests[0], try b.term(.{ .yield_then = after_yield })));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{ capability, point, point },
        .result = answer,
        .effects = &.{move},
    } } });
    const entry = try b.declare(&.{ point, point, point }, answer, &.{}, &.{});
    try b.define(entry, try b.term(.{ .handle = .{
        .handler = handler,
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
