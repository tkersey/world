const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");

pub fn main(init: std.process.Init) !void {
    var b = boundary.source.Builder.init(init.gpa);
    defer b.deinit();
    const bytes_type = try b.schema(.bytes);
    const integer = try b.scalar(u64);
    const unit = try b.scalar(void);
    const entry = try b.declare(&.{bytes_type}, integer, &.{}, &.{});
    const value = try b.reference(b.parameter(entry, 0));
    const length = try b.primitive(integer, .blob_length, &.{value}, 0);
    try b.define(entry, try b.term(.{ .yield_then = try b.pure(length) }));
    const module = b.module(entry, unit);
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
