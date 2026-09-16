//! Explicit compiler-dependent fixture builder and independent native byte peer.
const std = @import("std");
const boundary = @import("boundary");
const runtime = @import("stable_runtime");

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    _ = arguments.next();
    const mode = arguments.next() orelse return error.MissingMode;
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    if (std.mem.eql(u8, mode, "invoke")) {
        var buffer: [4096]u8 = undefined;
        var input = std.Io.File.stdin().reader(init.io, &buffer);
        const bytes = try input.interface.allocRemaining(init.gpa, .unlimited);
        defer init.gpa.free(bytes);
        const result = try runtime.invocation.invokeBytes(init.gpa, bytes);
        defer init.gpa.free(result);
        try output.interface.writeAll(result);
    } else if (std.mem.eql(u8, mode, "image")) {
        const name = arguments.next() orelse return error.MissingName;
        var builder = boundary.source.Builder.init(init.gpa);
        defer builder.deinit();
        const module = blk: {
            if (std.mem.eql(u8, name, "install")) break :blk try boundary.source.examples.installations(&builder, 64);
            if (std.mem.eql(u8, name, "resource")) break :blk try boundary.source.examples.resourceScalar(&builder);
            if (std.mem.eql(u8, name, "custody")) break :blk try boundary.source.examples.custodyOrder(&builder, 0);
            inline for (.{ "deep", "recursive", "reentrant", "generator", "shallow", "scalarContracts" }) |candidate| {
                if (std.mem.eql(u8, name, candidate)) break :blk try @field(boundary.source.examples, candidate)(&builder);
            }
            return error.InvalidName;
        };
        var compiled = try boundary.source.construct(init.gpa, module);
        defer compiled.deinit();
        const bytes = try init.gpa.alloc(u8, try boundary.data_v2.program_image.encodedLength(compiled.program));
        defer init.gpa.free(bytes);
        _ = try compiled.encode(init.gpa, bytes);
        try output.interface.writeAll(bytes);
    } else return error.InvalidMode;
    try output.interface.flush();
}
