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

    if (universal.world_appliance_load_executable(image_a_ptr, image_a.len) != 0) return error.LoadImageA;
    if (universal.world_appliance_submit_command(command_ptr, command.len) != 3) return error.RunImageA;
    const output_a = try readOutputFingerprint();

    if (universal.world_appliance_unload_executable() != 0) return error.UnloadImageA;
    if (universal.world_appliance_load_executable(image_b_ptr, image_b.len) != 0) return error.LoadImageB;
    if (universal.world_appliance_submit_command(command_ptr, command.len) != 3) return error.RunImageB;
    const output_b = try readOutputFingerprint();

    try stdout.print("world_seed=two_images_one_wasm\n", .{});
    try stdout.print("abi_version={d}\n", .{universal.world_appliance_abi_version()});
    try stdout.print("images=2\n", .{});
    try stdout.print("outputs_distinct={}\n", .{output_a != output_b});
    try stdout.flush();
}

fn writeGuest(bytes: []const u8) !usize {
    const ptr = universal.world_appliance_alloc(bytes.len);
    if (ptr == 0) return error.OutOfMemory;
    const out = guestSlice(ptr, bytes.len);
    @memcpy(out, bytes);
    return ptr;
}

fn readOutputFingerprint() !u64 {
    const len = universal.world_appliance_output_len();
    if (len == 0) return error.MissingOutput;
    const ptr = universal.world_appliance_alloc(len);
    if (ptr == 0) return error.OutOfMemory;
    if (universal.world_appliance_read_output(ptr, len) != len) return error.OutputReadFailed;
    return std.hash.Wyhash.hash(0, guestSlice(ptr, len));
}

fn guestSlice(ptr: usize, len: usize) []u8 {
    const many: [*]u8 = @ptrFromInt(ptr);
    return many[0..len];
}
