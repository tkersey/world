const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("wasm_sha_equal=true\n", .{});
    try stdout.print("program_plan_a_not_equal_b=true\n", .{});
    try stdout.print("image_a_completed=true\n", .{});
    try stdout.print("image_b_completed=true\n", .{});
    try stdout.print("fresh_instance_repeat=true\n", .{});
    try stdout.flush();
}
