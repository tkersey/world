//! Authored after the BPC1 kernel freeze: yield, ask for a salt, XOR it with byte length.
const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");

pub fn main(init: std.process.Init) !void {
    var b = boundary.computation.Builder.init(init.gpa);
    defer b.deinit();
    const blob = try b.schema(.bytes);
    const integer = try b.scalar(u64);
    const unit = try b.scalar(void);
    const ask = try b.effect(.{ .identity = "external/request-xor-salt", .payload = integer, .result = integer });
    const entry = try b.declare(&.{blob}, integer, &.{ask}, &.{});
    const length = try b.primitive(integer, .blob_length, &.{try b.reference(b.parameter(entry, 0))}, 0);
    const salt = try b.variable(integer);
    const requested = try b.term(.{ .perform = .{ .effect = ask, .payload = length } });
    const value = try b.primitive(integer, .integer_bit_xor, &.{ length, try b.reference(salt) }, 0);
    try b.define(entry, try b.term(.{ .yield_then = try b.bind(salt, requested, try b.pure(value)) }));
    const module = b.module(entry, unit);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (options.source) {
        try std.json.Stringify.value(module, .{ .emit_strings_as_arrays = true }, &output.interface);
    } else {
        var compiled = try boundary.program.compile(init.gpa, module);
        defer compiled.deinit();
        const data = boundary.data_v2;
        const length_bytes = if (options.compact)
            try data.compact_image.encodedLength(init.gpa, compiled.program)
        else
            try data.image.encodedLength(compiled.program);
        const bytes = try init.gpa.alloc(u8, length_bytes);
        defer init.gpa.free(bytes);
        if (options.compact) {
            _ = try data.compact_image.encode(init.gpa, compiled.program, bytes);
        } else _ = try compiled.encode(init.gpa, bytes);
        try output.interface.writeAll(bytes);
    }
    try output.interface.flush();
}
