const std = @import("std");
const universal = @import("universal_appliance_impl");

test "Universal Appliance ABI v2 lifecycle keeps image and output boundaries deterministic" {
    try std.testing.expectEqual(@as(u32, 2), universal.world_appliance_abi_version());
    try std.testing.expect(universal.world_appliance_runtime_manifest_len() > 0);
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_read_manifest(0, 0));

    const malformed_image = "world.Executable.Image:test-a";
    const marker_only_image = "world.Executable.TextEnvelope.v1\nfingerprint=8cdcc3dc851ba11b\npayload=";
    const image = "world.Executable.TextEnvelope.v1\nfingerprint=8cdcc3dc851ba11b\npayload=test-a";
    const command = "boot:canonical-args";
    const malformed_image_ptr = try writeGuest(malformed_image);
    const image_ptr = try writeGuest(image);
    const command_ptr = try writeGuest(command);
    const manifest_ptr = universal.world_appliance_alloc(128);
    try std.testing.expect(manifest_ptr != 0);

    try std.testing.expectEqual(@as(u32, 12), universal.world_appliance_load_executable(image_ptr, 1024 * 1024));
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);
    try std.testing.expectEqual(@as(u32, 7), universal.world_appliance_load_executable(malformed_image_ptr, malformed_image.len));
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    const marker_only_image_ptr = try writeGuest(marker_only_image);
    try std.testing.expectEqual(@as(u32, 7), universal.world_appliance_load_executable(marker_only_image_ptr, marker_only_image.len));
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());

    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_load_executable(image_ptr, image.len));
    try std.testing.expectEqual(image.len, universal.world_appliance_manifest_len());
    try std.testing.expectEqual(image.len, universal.world_appliance_read_manifest(manifest_ptr, 128));
    try std.testing.expectEqual(@as(u32, 3), universal.world_appliance_submit_command(command_ptr, command.len));
    try std.testing.expect(universal.world_appliance_output_len() > 0);
    const expected_output =
        "world.universal_appliance.output.v2\n" ++
        "image=8cdcc3dc851ba11b\n" ++
        "command=e792718f2026b62d\n" ++
        "payload=test-a\n";
    const output_ptr = universal.world_appliance_alloc(expected_output.len);
    try std.testing.expect(output_ptr != 0);
    try std.testing.expectEqual(expected_output.len, universal.world_appliance_read_output(output_ptr, expected_output.len));
    try std.testing.expectEqualStrings(expected_output, guestSlice(output_ptr, expected_output.len));

    try std.testing.expectEqual(@as(u32, 12), universal.world_appliance_submit_command(command_ptr, 0));
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_output_len());
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);

    const oversized_payload_image = try oversizedPayloadImage();
    defer std.testing.allocator.free(oversized_payload_image);
    const oversized_payload_image_ptr = try writeGuest(oversized_payload_image);
    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_load_executable(oversized_payload_image_ptr, oversized_payload_image.len));
    try std.testing.expectEqual(@as(u32, 12), universal.world_appliance_submit_command(command_ptr, command.len));
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_output_len());
    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_load_executable(image_ptr, image.len));

    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_reset());
    try std.testing.expectEqual(image.len, universal.world_appliance_manifest_len());
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_output_len());

    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_unload_executable());
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_output_len());
}

fn writeGuest(bytes: []const u8) !usize {
    const ptr = universal.world_appliance_alloc(bytes.len);
    try std.testing.expect(ptr != 0);
    const out = guestSlice(ptr, bytes.len);
    @memcpy(out, bytes);
    return ptr;
}

fn oversizedPayloadImage() ![]u8 {
    const payload = try std.testing.allocator.alloc(u8, 128 * 1024);
    defer std.testing.allocator.free(payload);
    @memset(payload, 'x');
    const fixed_output_len =
        "world.universal_appliance.output.v2\n".len +
        "image=".len + 16 +
        "\ncommand=".len + 16 +
        "\npayload=".len +
        "\n".len;
    const payload_len = 128 * 1024 - fixed_output_len + 1;
    return std.fmt.allocPrint(
        std.testing.allocator,
        "world.Executable.TextEnvelope.v1\nfingerprint={x:0>16}\npayload={s}",
        .{ fingerprintBytes(payload[0..payload_len]), payload[0..payload_len] },
    );
}

fn fingerprintBytes(bytes: []const u8) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (bytes) |byte| {
        hash ^= byte;
        hash *%= 0x100000001b3;
    }
    return hash;
}

fn guestSlice(ptr: usize, len: usize) []u8 {
    const many: [*]u8 = @ptrFromInt(ptr);
    return many[0..len];
}
