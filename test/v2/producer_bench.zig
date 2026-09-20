//! Source-only installation producer for cold/warm native build comparisons.
//! Usage: producer-bench COUNT > IMAGE; emits BPI3 or predecessor compact BPC1.
const std = @import("std");
const boundary = @import("boundary");
const data = @import("boundary_data");
const current = @hasDecl(data, "program_image");
pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const count = try std.fmt.parseInt(usize, args.next() orelse return error.ExpectedCount, 10);
    if (count == 0 or count > 256 or args.next() != null) return error.InvalidCount;
    var b = boundary.source.Builder.init(init.gpa);
    defer b.deinit();
    var compiled = try boundary.source.lower(init.gpa, try boundary.source.examples.installations(&b, count));
    defer compiled.deinit();
    const length = if (current) try data.program_image.encodedLength(compiled.program) else try data.compact_image.encodedLength(init.gpa, compiled.program);
    const image = try init.gpa.alloc(u8, length);
    defer init.gpa.free(image);
    if (current) {
        _ = try compiled.encode(init.gpa, image);
    } else {
        _ = try data.compact_image.encode(init.gpa, compiled.program, image);
    }
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try out.interface.writeAll(image);
    try out.interface.flush();
}
