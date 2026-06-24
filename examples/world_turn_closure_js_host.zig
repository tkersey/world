const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("native_helper_used=false\n", .{});
    try stdout.print("javascript_codec_independent=true\n", .{});
    try stdout.print("loaded_agent_completed=true\n", .{});
    try stdout.flush();
}
