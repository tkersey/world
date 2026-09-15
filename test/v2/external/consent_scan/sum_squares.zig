const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");
const source = boundary.computation;

fn arithmetic(b: *source.Builder, opcode: boundary.data_v2.program.Opcode, left: u64, right: u64, fault: u64) !u64 {
    return b.value(.{ .schema = try b.scalar(u64), .expression = .{ .primitive = .{
        .opcode = opcode,
        .operands = &.{ left, right },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = fault }},
    } } });
}

fn program(b: *source.Builder) !source.Module {
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const unit = try b.scalar(void);
    const fault = try b.failureLiteral(try b.constant(void, {}));
    const entry = try b.declare(&.{integer}, integer, &.{}, &.{});
    const loop = try b.declare(&.{ integer, integer }, integer, &.{}, &.{});
    const n = try b.reference(b.parameter(loop, 0));
    const sum = try b.reference(b.parameter(loop, 1));
    const zero = try b.constant(u64, 0);
    const condition = try b.primitive(boolean, .equal, &.{ n, zero }, 0);
    const square = try arithmetic(b, .integer_mul, n, n, fault);
    const added = try arithmetic(b, .integer_add, sum, square, fault);
    const previous = try arithmetic(b, .integer_sub, n, try b.constant(u64, 1), fault);
    const recurse = try b.term(.{ .call = .{ .function = loop, .arguments = &.{ previous, added } } });
    try b.define(loop, try b.term(.{ .conditional = .{
        .condition = condition,
        .when_true = try b.pure(sum),
        .when_false = recurse,
    } }));
    const call = try b.term(.{ .call = .{ .function = loop, .arguments = &.{ try b.reference(b.parameter(entry, 0)), zero } } });
    try b.define(entry, try b.term(.{ .yield_then = call }));
    return b.module(entry, unit);
}

pub fn main(init: std.process.Init) !void {
    var b = source.Builder.init(init.gpa);
    defer b.deinit();
    const module = try program(&b);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (options.source) {
        try std.json.Stringify.value(module, .{ .emit_strings_as_arrays = true }, &output.interface);
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
