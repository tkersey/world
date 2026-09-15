//! New post-freeze consumer: yield, then return two unsigned values in sorted order.
const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");

pub fn main(init: std.process.Init) !void {
    var b = boundary.computation.Builder.init(init.gpa);
    defer b.deinit();
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const unit = try b.scalar(void);
    const pair = try b.schema(.{ .product = &.{ integer, integer } });
    const entry = try b.declare(&.{ integer, integer }, pair, &.{}, &.{});
    const left = try b.reference(b.parameter(entry, 0));
    const right = try b.reference(b.parameter(entry, 1));
    const ordered = try b.primitive(boolean, .less, &.{ left, right }, 0);
    const forward = try b.pure(try b.primitive(pair, .product, &.{ left, right }, 0));
    const backward = try b.pure(try b.primitive(pair, .product, &.{ right, left }, 0));
    const branch = try b.term(.{ .conditional = .{ .condition = ordered, .when_true = forward, .when_false = backward } });
    try b.define(entry, try b.term(.{ .yield_then = branch }));
    const module = b.module(entry, unit);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (options.source) {
        try std.json.Stringify.value(module, .{ .emit_strings_as_arrays = true }, &output.interface);
    } else {
        var compiled = try boundary.program.compile(init.gpa, module);
        defer compiled.deinit();
        const data = boundary.data_v2;
        const length = if (options.compact)
            try data.compact_image.encodedLength(init.gpa, compiled.program)
        else
            try data.image.encodedLength(compiled.program);
        const bytes = try init.gpa.alloc(u8, length);
        defer init.gpa.free(bytes);
        if (options.compact) {
            _ = try data.compact_image.encode(init.gpa, compiled.program, bytes);
        } else _ = try compiled.encode(init.gpa, bytes);
        try output.interface.writeAll(bytes);
    }
    try output.interface.flush();
}
