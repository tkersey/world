const std = @import("std");
const data = @import("boundary_data");
const fixtures = @import("frame_fixture");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.Mode;
    const count = if (args.next()) |text| try std.fmt.parseInt(usize, text, 10) else 4;
    if (args.next() != null) return error.Arguments;
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (std.mem.eql(u8, mode, "sizes")) {
        try std.json.Stringify.value(.{ .valueBytes = @sizeOf(data.graph.Value), .stackArgumentBytes = 8 * @sizeOf(data.graph.Value) }, .{}, &output.interface);
        try output.interface.flush();
        return;
    }
    const compatible = std.mem.eql(u8, mode, "compatible");
    if (!compatible and !std.mem.eql(u8, mode, "fallback")) return error.Mode;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try fixtures.wideFixture(a, count, compatible);
    const image = try a.alloc(u8, try data.program_image.encodedLength(program));
    _ = try data.program_image.encode(a, program, image);
    try output.interface.writeAll(image);
    try output.interface.flush();
}
