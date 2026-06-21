const std = @import("std");
const universal = @import("world_universal_appliance_wasm.zig");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const image_a = "world.Executable.Image.v1\nfingerprint=af63fc4c860222ec\npayload=A";
    const image_b = "world.Executable.Image.v1\nfingerprint=af63ff4c86022805\npayload=B";
    const command = "boot";
    _ = universal.world_appliance_unload_executable();
    const image_a_ptr = try writeGuest(image_a);
    const image_b_ptr = try writeGuest(image_b);
    const command_ptr = try writeGuest(command);

    const image_a_status = universal.world_appliance_load_executable(image_a_ptr, image_a.len);
    const image_a_manifest_len = universal.world_appliance_manifest_len();
    const image_a_submit_status = universal.world_appliance_submit_command(command_ptr, command.len);

    if (universal.world_appliance_unload_executable() != 0) return error.UnloadImageA;
    const image_b_status = universal.world_appliance_load_executable(image_b_ptr, image_b.len);
    const image_b_manifest_len = universal.world_appliance_manifest_len();
    const image_b_submit_status = universal.world_appliance_submit_command(command_ptr, command.len);

    try stdout.print("world_seed=two_images_one_wasm\n", .{});
    try stdout.print("abi_version={d}\n", .{universal.world_appliance_abi_version()});
    try stdout.print("images=2\n", .{});
    try stdout.print("images_loaded={}\n", .{image_a_status == 0 and image_b_status == 0});
    try stdout.print("manifests_present={}\n", .{image_a_manifest_len == image_a.len and image_b_manifest_len == image_b.len});
    try stdout.print("commands_completed={}\n", .{image_a_submit_status == 3 and image_b_submit_status == 3});
    try stdout.flush();
}

fn writeGuest(bytes: []const u8) !usize {
    const ptr = universal.world_appliance_alloc(bytes.len);
    if (ptr == 0) return error.OutOfMemory;
    const out = guestSlice(ptr, bytes.len);
    @memcpy(out, bytes);
    return ptr;
}

fn guestSlice(ptr: usize, len: usize) []u8 {
    const many: [*]u8 = @ptrFromInt(ptr);
    return many[0..len];
}
