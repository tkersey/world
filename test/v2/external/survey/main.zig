//! Authored after the recorded kernel freeze. Only Boundary's public API is used.
const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");
const Id = boundary.data_v2.program.Id;
const Builder = boundary.computation.Builder;

fn add(b: *Builder, integer: Id, left: Id, right: Id, failure: Id) !Id {
    return b.value(.{ .schema = integer, .expression = .{ .primitive = .{
        .opcode = .integer_add,
        .operands = &.{ left, right },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = failure }},
    } } });
}

fn emit(b: *Builder) !boundary.computation.Module {
    const integer = try b.scalar(i64);
    const unit = try b.scalar(void);
    const point = try b.schema(.{ .product = &.{ integer, integer } });
    const effect = try b.effect(.{ .identity = "survey/translate-point", .payload = point, .result = point, .external = false });
    const capability = try b.schema(.{ .internal = .{ .capability = effect } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{
        .effect = effect,
        .input = point,
        .answer = point,
        .capture_bound = &.{ point, capability },
        .handled = &.{effect},
        .mode = .deep,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{ point, point }, point, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 1))));
    const clause = try b.declare(&.{ point, point, token }, point, &.{}, &.{});
    const offset = try b.reference(b.parameter(clause, 0));
    const input = try b.reference(b.parameter(clause, 1));
    const failure = try b.failureLiteral(try b.constant(void, {}));
    var coordinates: [2]Id = undefined;
    for (&coordinates, 0..) |*coordinate, index| coordinate.* = try add(b, integer, try b.primitive(integer, .field, &.{input}, index), try b.primitive(integer, .field, &.{offset}, index), failure);
    try b.define(clause, try b.term(.{ .resume_value = .{
        .resumption = try b.reference(b.parameter(clause, 2)),
        .argument = try b.primitive(point, .product, &coordinates, 0),
    } }));
    const handler = try b.handler(.{ .mode = .deep, .input = point, .answer = point, .state = &.{point}, .return_function = returns, .clauses = &.{.{ .effect = effect, .function = clause, .resumption = token }} });
    const entry = try b.declare(&.{point}, point, &.{}, &.{});
    const body = try b.declare(&.{capability}, point, &.{effect}, &.{});
    const cap = try b.reference(b.parameter(body, 0));
    const first = try b.variable(point);
    const first_call = try b.term(.{ .perform = .{ .effect = effect, .capability = cap, .payload = try b.reference(b.parameter(entry, 0)) } });
    const second_call = try b.term(.{ .perform = .{ .effect = effect, .capability = cap, .payload = try b.reference(first) } });
    try b.define(body, try b.bind(first, first_call, try b.term(.{ .yield_then = second_call })));
    const computation = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{capability},
        .result = point,
        .effects = &.{effect},
        .capture_bound = &.{point},
    } } });
    const translation = try b.primitive(point, .product, &.{ try b.constant(i64, 10), try b.constant(i64, -3) }, 0);
    try b.define(entry, try b.term(.{ .handle = .{ .handler = handler, .body = try b.lambda(body, computation), .state = &.{translation} } }));
    return b.module(entry, unit);
}

pub fn main(init: std.process.Init) !void {
    var builder = Builder.init(init.gpa);
    defer builder.deinit();
    const module = try emit(&builder);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (options.source) {
        try std.json.Stringify.value(module, .{ .emit_strings_as_arrays = true }, &output.interface);
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
