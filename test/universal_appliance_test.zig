const std = @import("std");
const universal = @import("universal_appliance_impl");
const world = @import("world");
const fixtures = @import("world_fixtures");

test "Universal Appliance ABI v2 loads canonical executable image bytes" {
    try std.testing.expectEqual(@as(u32, 2), universal.world_appliance_abi_version());
    try std.testing.expect(universal.world_appliance_runtime_manifest_len() > 0);
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_read_manifest(0, 0));

    var image = try buildExecutableImage(std.testing.allocator, "universal.test.image", "universal.test.binding");
    defer image.deinit(std.testing.allocator);
    const image_bytes = try image.encode(std.testing.allocator);
    defer std.testing.allocator.free(image_bytes);
    const image_ptr = try writeGuest(image_bytes);

    const malformed_image = "world.Executable.TextEnvelope.v1\nfingerprint=8cdcc3dc851ba11b\npayload=test-a";
    const malformed_image_ptr = try writeGuest(malformed_image);
    try std.testing.expectEqual(@as(u32, 7), universal.world_appliance_load_executable(malformed_image_ptr, malformed_image.len));
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);

    try std.testing.expectEqual(@as(u32, 12), universal.world_appliance_load_executable(image_ptr, 1024 * 1024));
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);

    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_load_executable(image_ptr, image_bytes.len));
    const manifest_len = universal.world_appliance_manifest_len();
    try std.testing.expect(manifest_len > 0);
    const manifest_ptr = universal.world_appliance_alloc(manifest_len);
    try std.testing.expect(manifest_ptr != 0);
    try std.testing.expectEqual(manifest_len, universal.world_appliance_read_manifest(manifest_ptr, manifest_len));
    var manifest = try world.Appliance.Manifest.decode(std.testing.allocator, guestSlice(manifest_ptr, manifest_len));
    defer manifest.deinit(std.testing.allocator);

    const command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .metadata = "native-universal-test",
    });
    const command_bytes = try command.encode(std.testing.allocator);
    defer std.testing.allocator.free(command_bytes);
    const command_ptr = try writeGuest(command_bytes);
    try std.testing.expectEqual(@as(u32, 2), universal.world_appliance_submit_command(command_ptr, command_bytes.len));
    const output_len = universal.world_appliance_output_len();
    try std.testing.expect(output_len > 0);
    const output_ptr = universal.world_appliance_alloc(output_len);
    try std.testing.expect(output_ptr != 0);
    try std.testing.expectEqual(output_len, universal.world_appliance_read_output(output_ptr, output_len));
    var output = try world.Appliance.TurnOutput.decode(std.testing.allocator, guestSlice(output_ptr, output_len), manifest.manifest_fingerprint, world.Appliance.Capacity.archive_decode);
    defer output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.needs_host, output.status);
    try std.testing.expectEqual(@as(usize, 1), output.host_requests.len);

    const reply = try hostReplyFor(std.testing.allocator, output.host_requests[0], 0x700D_0001);
    defer if (reply.outcome.response_bytes.len != 0) std.testing.allocator.free(reply.outcome.response_bytes);
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = output.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = output.turn_receipt.receipt_fingerprint,
        .host_replies = &.{reply},
        .metadata = "native-universal-test.reply",
    });
    const continue_command_bytes = try continue_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(continue_command_bytes);
    const continue_command_ptr = try writeGuest(continue_command_bytes);
    try std.testing.expectEqual(@as(u32, 3), universal.world_appliance_submit_command(continue_command_ptr, continue_command_bytes.len));
    const completed_output_len = universal.world_appliance_output_len();
    try std.testing.expect(completed_output_len > 0);
    const completed_output_ptr = universal.world_appliance_alloc(completed_output_len);
    try std.testing.expect(completed_output_ptr != 0);
    try std.testing.expectEqual(completed_output_len, universal.world_appliance_read_output(completed_output_ptr, completed_output_len));
    var completed_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        guestSlice(completed_output_ptr, completed_output_len),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.wasm_small,
    );
    defer completed_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.completed, completed_output.status);
    try std.testing.expect(completed_output.root_result_fingerprint != null);
    try std.testing.expect(completed_output.root_result_value_image_bytes.len > 0);
    try std.testing.expect(completed_output.archive_append_batch_fingerprint != null);
    try std.testing.expect(completed_output.archive_append_batch_bytes.len > 0);

    try std.testing.expectEqual(@as(u32, 8), universal.world_appliance_submit_command(continue_command_ptr, continue_command_bytes.len));
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);

    try std.testing.expectEqual(@as(u32, 12), universal.world_appliance_submit_command(command_ptr, 0));
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);

    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_reset());
    try std.testing.expectEqual(manifest_len, universal.world_appliance_manifest_len());

    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_unload_executable());
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_output_len());
}

fn buildExecutableImage(allocator: std.mem.Allocator, image_metadata: []const u8, binding_label: []const u8) !world.Executable.Image {
    const root_bytes = try fixtures.Ports.Target.Module.fullImage(allocator);
    defer allocator.free(root_bytes);

    var builder = world.Executable.Builder.init(allocator, .{ .metadata = image_metadata });
    defer builder.deinit();
    try builder.addRootModule(root_bytes);

    const root_module = builder.modules.items[0];
    const root_import = root_module.imports[0];
    const actuator_ref = world.Actuation.Ref.init(.{
        .kind = .fixture,
        .class = .deterministic_fixture,
        .label = binding_label,
        .supported_modes = .all,
        .supported_response_statuses = .all,
        .value_policy_fingerprint = world.Actuation.valuePolicyFingerprint(.portable),
    });
    const descriptor = world.Actuation.Descriptor.init(.{
        .actuator_ref = actuator_ref,
        .world_surface_fingerprint = root_module.target_ref.world_surface_fingerprint,
        .target_ref_fingerprint = root_module.target_ref.target_ref_fingerprint,
        .world_port_id = root_import.world_port_id,
        .world_port_ref_fingerprint = root_import.world_port_ref_fingerprint,
        .source_effect_shape_ref_fingerprint = root_import.source_effect_shape_ref_fingerprint,
        .payload_value_table_id = root_import.payload_value_table_id,
        .response_value_table_id = root_import.response_value_table_id,
        .label = binding_label,
    });
    try builder.addExternalBinding(world.Executable.ExternalBinding.init(.{
        .parent_module_fingerprint = root_module.module_ref.boundary_module_fingerprint,
        .world_port_id = root_import.world_port_id,
        .world_port_ref_fingerprint = root_import.world_port_ref_fingerprint,
        .payload_value_table_id = root_import.payload_value_table_id,
        .payload_value_ref_fingerprint = root_import.payload_value_ref_fingerprint,
        .response_value_table_id = root_import.response_value_table_id,
        .response_value_ref_fingerprint = root_import.response_value_ref_fingerprint,
        .actuator_ref = actuator_ref,
        .descriptor = descriptor,
        .label = binding_label,
    }));

    var prepared = try builder.prepare();
    defer prepared.deinit();
    return try prepared.seal();
}

fn hostReplyFor(
    allocator: std.mem.Allocator,
    request: world.Appliance.HostRequest,
    response_fingerprint: u64,
) !world.Appliance.HostReply {
    var response_bytes: []const u8 = "";
    var response_value_fingerprint = response_fingerprint;
    if (request.expected_response_value_ref_fingerprint != null or request.expected_response_schema_ref_fingerprint != null) {
        var image = try world.Frame.ValueImage.fromCanonicalBytes(
            allocator,
            null,
            request.expected_response_value_ref_fingerprint,
            request.expected_response_schema_ref_fingerprint,
            std.mem.asBytes(&response_fingerprint),
            false,
        );
        defer image.deinit(allocator);
        response_bytes = try image.encode(allocator);
        response_value_fingerprint = image.value_image_fingerprint;
    }
    const outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = response_value_fingerprint,
        .response_kind = .frame_value_image,
        .response_bytes = response_bytes,
        .host_evidence_fingerprint = request.request_fingerprint ^ 0xE11D,
        .host_evidence_bytes = "host-claim:fixture",
        .attempt_number = 1,
        .metadata = "fixture-response",
    });
    return world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .outcome = outcome,
        .metadata = "fixture-reply",
    });
}

fn writeGuest(bytes: []const u8) !usize {
    const ptr = universal.world_appliance_alloc(bytes.len);
    try std.testing.expect(ptr != 0);
    const out = guestSlice(ptr, bytes.len);
    @memcpy(out, bytes);
    return ptr;
}

fn guestSlice(ptr: usize, len: usize) []u8 {
    const many: [*]u8 = @ptrFromInt(ptr);
    return many[0..len];
}
