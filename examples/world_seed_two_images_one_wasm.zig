const std = @import("std");
const world = @import("world");
const fixtures = @import("world_fixtures");
const universal = @import("world_universal_appliance_wasm.zig");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const image_a = try buildExecutableImage(allocator, "two-images.a", "two-images.a");
    const image_a_bytes = try image_a.encode(allocator);
    const command_a = try commandForImage(allocator, image_a, "two-images.a");
    const image_b = try buildExecutableImage(allocator, "two-images.b", "two-images.b");
    const image_b_bytes = try image_b.encode(allocator);
    const command_b = try commandForImage(allocator, image_b, "two-images.b");

    _ = universal.world_appliance_unload_executable();
    const image_a_status = try loadAndSubmit(image_a_bytes, command_a);
    const image_a_manifest_len = universal.world_appliance_manifest_len();

    if (universal.world_appliance_unload_executable() != 0) return error.UnloadImageA;
    const image_b_status = try loadAndSubmit(image_b_bytes, command_b);
    const image_b_manifest_len = universal.world_appliance_manifest_len();

    try stdout.print("world_seed=two_images_one_wasm\n", .{});
    try stdout.print("abi_version={d}\n", .{universal.world_appliance_abi_version()});
    try stdout.print("images=2\n", .{});
    try stdout.print("images_loaded={}\n", .{image_a_status.load == 0 and image_b_status.load == 0});
    try stdout.print("manifests_present={}\n", .{image_a_manifest_len > 0 and image_b_manifest_len > 0});
    try stdout.print("turn_outputs_ready={}\n", .{image_a_status.submit == 2 and image_b_status.submit == 2});
    try stdout.flush();
}

fn loadAndSubmit(image_bytes: []const u8, command_bytes: []const u8) !struct { load: u32, submit: u32 } {
    const image_ptr = try writeGuest(image_bytes);
    const load = universal.world_appliance_load_executable(image_ptr, image_bytes.len);
    const submit = if (load == 0) blk: {
        const command_ptr = try writeGuest(command_bytes);
        break :blk universal.world_appliance_submit_command(command_ptr, command_bytes.len);
    } else 0;
    return .{ .load = load, .submit = submit };
}

fn commandForImage(allocator: std.mem.Allocator, image: world.Executable.Image, metadata: []const u8) ![]const u8 {
    var core = try world.Appliance.Core.initExecutable(allocator, image, .{
        .profile = .wasm_small,
        .metadata = "world-universal-appliance",
    });
    defer core.deinit();
    const command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = core.readManifest().manifest_fingerprint,
        .turn_sequence_number = 0,
        .metadata = metadata,
    });
    return command.encode(allocator);
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
