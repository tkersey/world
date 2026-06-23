const std = @import("std");
const universal = @import("universal_appliance_impl");
const world = @import("world");
const fixtures = @import("world_fixtures");

test "Universal Appliance ABI v2 loads canonical executable image bytes" {
    try std.testing.expectEqual(@as(u32, 2), universal.world_appliance_abi_version());
    try std.testing.expect(universal.world_appliance_runtime_manifest_len() > 0);
    try std.testing.expect(!universal.executable_runtime_profile.supports_internal_providers);
    const runtime_manifest_len = universal.world_appliance_runtime_manifest_len();
    const runtime_manifest_ptr = universal.world_appliance_alloc(runtime_manifest_len);
    try std.testing.expect(runtime_manifest_ptr != 0);
    try std.testing.expectEqual(runtime_manifest_len, universal.world_appliance_read_runtime_manifest(runtime_manifest_ptr, runtime_manifest_len));
    const runtime_manifest = guestSlice(runtime_manifest_ptr, runtime_manifest_len);
    var runtime_profile_fingerprint_line_buf: [64]u8 = undefined;
    const runtime_profile_fingerprint_line = try std.fmt.bufPrint(
        &runtime_profile_fingerprint_line_buf,
        "runtime_profile_fingerprint={x}\n",
        .{universal.executable_runtime_profile.profile_fingerprint},
    );
    try expectManifestLine(runtime_manifest, runtime_profile_fingerprint_line);
    try expectManifestLine(runtime_manifest, "supports_loaded_execution=true\n");
    try expectManifestLine(runtime_manifest, "supports_internal_providers=false\n");
    try expectManifestLine(runtime_manifest, "supports_external_actuation=true\n");
    try expectManifestLine(runtime_manifest, "max_modules=8\n");
    try expectManifestLine(runtime_manifest, "max_provider_depth=8\n");
    try expectManifestLine(runtime_manifest, "max_external_bindings=16\n");
    try expectManifestLine(runtime_manifest, "max_module_bytes=131072\n");
    try expectManifestLine(runtime_manifest, "max_image_bytes=131072\n");
    try expectManifestLine(runtime_manifest, "max_command_bytes=65536\n");
    try expectManifestLine(runtime_manifest, "max_output_bytes=131072\n");
    try expectManifestLine(runtime_manifest, "max_linear_memory_pages=2048\n");
    try expectManifestLine(runtime_manifest, "runtime_profile_metadata=\n");
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_read_manifest(0, 0));

    var oversized_contract_image = try buildExecutableImageWithProfile(
        std.testing.allocator,
        world.Executable.RuntimeProfile.universal_v1,
        "universal.test.oversized-contract",
        "universal.test.oversized-contract",
    );
    defer oversized_contract_image.deinit(std.testing.allocator);
    const oversized_contract_bytes = try oversized_contract_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(oversized_contract_bytes);
    const oversized_contract_ptr = try writeGuest(oversized_contract_bytes);
    try std.testing.expectEqual(@as(u32, 12), universal.world_appliance_load_executable(oversized_contract_ptr, oversized_contract_bytes.len));
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);

    var loaded_route_image = try buildLoadedRouteImage(std.testing.allocator);
    defer loaded_route_image.deinit(std.testing.allocator);
    const loaded_route_bytes = try loaded_route_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(loaded_route_bytes);
    try std.testing.expect(loaded_route_bytes.len <= 128 * 1024);
    const loaded_route_ptr = try writeGuest(loaded_route_bytes);
    try std.testing.expectEqual(@as(u32, 12), universal.world_appliance_load_executable(loaded_route_ptr, loaded_route_bytes.len));
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);

    var no_host_image = try buildNoHostExecutableImage(std.testing.allocator, "universal.test.no-host");
    defer no_host_image.deinit(std.testing.allocator);
    const no_host_bytes = try no_host_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(no_host_bytes);
    const no_host_ptr = try writeGuest(no_host_bytes);
    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_load_executable(no_host_ptr, no_host_bytes.len));
    const no_host_manifest_len = universal.world_appliance_manifest_len();
    try std.testing.expect(no_host_manifest_len > 0);
    const no_host_manifest_ptr = universal.world_appliance_alloc(no_host_manifest_len);
    try std.testing.expect(no_host_manifest_ptr != 0);
    try std.testing.expectEqual(no_host_manifest_len, universal.world_appliance_read_manifest(no_host_manifest_ptr, no_host_manifest_len));
    var no_host_manifest = try world.Appliance.Manifest.decode(std.testing.allocator, guestSlice(no_host_manifest_ptr, no_host_manifest_len));
    defer no_host_manifest.deinit(std.testing.allocator);
    const no_host_command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = no_host_manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .metadata = "native-universal-test.no-host",
    });
    const no_host_command_bytes = try no_host_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(no_host_command_bytes);
    const no_host_command_ptr = try writeGuest(no_host_command_bytes);
    try std.testing.expectEqual(@as(u32, 3), universal.world_appliance_submit_command(no_host_command_ptr, no_host_command_bytes.len));
    const no_host_output_len = universal.world_appliance_output_len();
    try std.testing.expect(no_host_output_len > 0);
    const no_host_output_ptr = universal.world_appliance_alloc(no_host_output_len);
    try std.testing.expect(no_host_output_ptr != 0);
    try std.testing.expectEqual(no_host_output_len, universal.world_appliance_read_output(no_host_output_ptr, no_host_output_len));
    var no_host_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        guestSlice(no_host_output_ptr, no_host_output_len),
        no_host_manifest.manifest_fingerprint,
        universal.abi_capacity,
    );
    defer no_host_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.completed, no_host_output.status);
    try std.testing.expectEqual(@as(usize, 0), no_host_output.host_requests.len);
    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_unload_executable());

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
    try std.testing.expectEqual(manifest_len, universal.world_appliance_read_manifest(manifest_ptr, 1));
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);
    try std.testing.expectEqual(manifest_len, universal.world_appliance_read_manifest(manifest_ptr, manifest_len));
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_last_error_len());
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
    try std.testing.expectEqual(output_len, universal.world_appliance_read_output(output_ptr, 1));
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);
    try std.testing.expectEqual(output_len, universal.world_appliance_read_output(output_ptr, output_len));
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_last_error_len());
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
        universal.abi_capacity,
    );
    defer completed_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.completed, completed_output.status);
    try std.testing.expect(completed_output.root_result_fingerprint != null);
    try std.testing.expect(completed_output.root_result_value_image_bytes.len > 0);
    try std.testing.expect(completed_output.archive_append_batch_fingerprint != null);
    try std.testing.expect(completed_output.archive_append_batch_bytes.len > 0);

    try std.testing.expectEqual(@as(u32, 8), universal.world_appliance_submit_command(continue_command_ptr, continue_command_bytes.len));
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_output_len());

    try std.testing.expectEqual(@as(u32, 12), universal.world_appliance_submit_command(command_ptr, 0));
    try std.testing.expect(universal.world_appliance_last_error_len() > 0);
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_output_len());

    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_reset());
    try std.testing.expectEqual(manifest_len, universal.world_appliance_manifest_len());

    try std.testing.expectEqual(@as(u32, 0), universal.world_appliance_unload_executable());
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_manifest_len());
    try std.testing.expectEqual(@as(usize, 0), universal.world_appliance_output_len());
}

fn buildExecutableImage(allocator: std.mem.Allocator, image_metadata: []const u8, binding_label: []const u8) !world.Executable.Image {
    return buildExecutableImageWithProfile(allocator, universal.executable_runtime_profile, image_metadata, binding_label);
}

fn expectManifestLine(manifest: []const u8, line: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, manifest, line) != null);
}

fn buildNoHostExecutableImage(allocator: std.mem.Allocator, image_metadata: []const u8) !world.Executable.Image {
    const root_bytes = try fixtures.Strict.Target.Module.fullImage(allocator);
    defer allocator.free(root_bytes);

    var builder = world.Executable.Builder.init(allocator, .{
        .runtime_profile = universal.executable_runtime_profile,
        .metadata = image_metadata,
    });
    defer builder.deinit();
    try builder.addRootModule(root_bytes);
    var prepared = try builder.prepare();
    defer prepared.deinit();
    return try prepared.seal();
}

fn buildExecutableImageWithProfile(
    allocator: std.mem.Allocator,
    runtime_profile: world.Executable.RuntimeProfile,
    image_metadata: []const u8,
    binding_label: []const u8,
) !world.Executable.Image {
    const root_bytes = try fixtures.Ports.Target.Module.fullImage(allocator);
    defer allocator.free(root_bytes);

    var builder = world.Executable.Builder.init(allocator, .{
        .runtime_profile = runtime_profile,
        .metadata = image_metadata,
    });
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

fn buildLoadedRouteImage(allocator: std.mem.Allocator) !world.Executable.Image {
    const root_bytes = try fixtures.Ports.Target.Module.fullImage(allocator);
    defer allocator.free(root_bytes);
    const provider_bytes = try fixtures.Strict.Target.Module.fullImage(allocator);
    defer allocator.free(provider_bytes);
    const provider_runtime_profile = world.Executable.RuntimeProfile.init(.{
        .supports_internal_providers = true,
        .max_modules = universal.executable_runtime_profile.max_modules,
        .max_external_bindings = universal.executable_runtime_profile.max_external_bindings,
        .max_module_bytes = universal.executable_runtime_profile.max_module_bytes,
        .max_image_bytes = universal.executable_runtime_profile.max_image_bytes,
        .max_command_bytes = universal.executable_runtime_profile.max_command_bytes,
        .max_output_bytes = universal.executable_runtime_profile.max_output_bytes,
        .max_linear_memory_pages = universal.executable_runtime_profile.max_linear_memory_pages,
    });

    var builder = world.Executable.Builder.init(allocator, .{
        .runtime_profile = provider_runtime_profile,
        .linker_policy = .strict_closed,
        .metadata = "universal.test.loaded-route",
    });
    defer builder.deinit();
    try builder.addRootModule(root_bytes);
    try builder.addProviderModule(provider_bytes);
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
