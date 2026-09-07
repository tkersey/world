//! Handwritten target-level fixture, separate from source/lowering conformance.
const std = @import("std");
const data = @import("boundary_data_v2");
const fixtures = @import("world_test_fixtures");

pub fn main(init: std.process.Init) !void {
    const records = switch (@import("fixture_options").fixture_index) {
        0 => fixtures.suspended,
        1 => fixtures.loop,
        2 => fixtures.deep,
        3 => fixtures.choice,
        4 => fixtures.local_regions,
        5 => fixtures.shared_regions,
        6 => fixtures.shallow,
        7 => fixtures.reentrant,
        8 => fixtures.cleanup,
        9 => fixtures.bounded,
        10 => fixtures.compact,
        else => @compileError("unknown target fixture"),
    };
    var normalized = try data.canonical.normalize(init.gpa, records);
    defer normalized.deinit();
    const program = normalized.program;
    const buffer = try init.gpa.alloc(u8, try data.image.encodedLength(program));
    defer init.gpa.free(buffer);
    const encoded = try data.image.encode(init.gpa, program, buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try output.interface.writeAll(encoded);
    try output.interface.flush();
}
