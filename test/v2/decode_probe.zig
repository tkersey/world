//! Decoder lifecycle and memory through the existing bounded Workspace allocator.
const std = @import("std");
const data = @import("boundary_data_v2");
const Workspace = @import("world").process_v2.Workspace;

pub fn main(init: std.process.Init) !void {
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().reader(init.io, &input_buffer);
    const bytes = try input.interface.allocRemaining(init.gpa, .limited(64 << 20));
    defer init.gpa.free(bytes);
    const buffer = try init.gpa.alloc(u8, 1 << 20);
    defer init.gpa.free(buffer);
    const Row = struct { decode_ns: i96, retained: usize, peak: usize, demand: u64 };
    var rows: [21]Row = undefined;
    for (0..26) |index| {
        var workspace = Workspace.init(buffer);
        const start = std.Io.Clock.awake.now(init.io);
        var decoded = try data.image.decode(workspace.allocator(), bytes);
        const elapsed = start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds;
        const row: Row = .{ .decode_ns = elapsed, .retained = workspace.live_payload, .peak = workspace.peak_payload, .demand = workspace.required };
        if (!std.mem.eql(u8, bytes, decoded.bytes)) return error.ChangedImage;
        if (index == 0) {
            const output = try init.gpa.alloc(u8, bytes.len);
            defer init.gpa.free(output);
            const encoded = try data.image.encode(init.gpa, decoded.program, output);
            if (!std.mem.eql(u8, bytes, encoded)) return error.ChangedProgram;
        }
        decoded.deinit();
        if (workspace.live_payload != 0) return error.LeakedOwner;
        if (index >= 5) rows[index - 5] = row;
    }
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try std.json.Stringify.value(.{ .image_bytes = bytes.len, .image_sha256 = std.fmt.bytesToHex(data.wire.digest(bytes), .lower), .workspace_bytes = buffer.len, .warmups = 5, .rows = rows }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
