const std = @import("std");
const universal = @import("world_universal_appliance_wasm.zig");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    _ = universal.world_appliance_unload_executable();
    const malformed = "bad";
    const malformed_ptr = try writeGuest(malformed);
    const oversized_status = universal.world_appliance_load_executable(malformed_ptr, 1024 * 1024);
    const manifest_after_reject = universal.world_appliance_manifest_len();
    const submit_without_image = universal.world_appliance_submit_command(malformed_ptr, malformed.len);

    try stdout.print("world_seed=reject\n", .{});
    try stdout.print("oversized_rejected={}\n", .{oversized_status == 12});
    try stdout.print("manifest_after_reject={d}\n", .{manifest_after_reject});
    try stdout.print("submit_without_image_rejected={}\n", .{submit_without_image == 7});
    try stdout.flush();
}

fn writeGuest(bytes: []const u8) !usize {
    const ptr = universal.world_appliance_alloc(bytes.len);
    if (ptr == 0) return error.OutOfMemory;
    const many: [*]u8 = @ptrFromInt(ptr);
    @memcpy(many[0..bytes.len], bytes);
    return ptr;
}
