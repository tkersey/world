const std = @import("std");
const world = @import("world");
const fixtures = @import("world_fixtures");
const universal = @import("world_universal_appliance_wasm.zig");

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    if (args.next()) |first_arg| {
        if (std.mem.eql(u8, first_arg, "--reply")) {
            const output_path = args.next() orelse return error.InvalidArguments;
            const command_path = args.next() orelse return error.InvalidArguments;
            const metadata = args.next() orelse return error.InvalidArguments;
            if (args.next() != null) return error.InvalidArguments;
            const output_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, output_path, allocator, .limited(1024 * 1024));
            var output = try world.Appliance.TurnOutput.decodeArchivePayload(allocator, output_bytes);
            defer output.deinit(allocator);
            if (output.status != .needs_host or output.host_requests.len != 1) return error.InvalidFrameEncoding;
            const command = try replyCommandBytesForOutput(allocator, output, metadata);
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = command_path, .data = command });
            return;
        }
        args = std.process.Args.Iterator.init(init.minimal.args);
        _ = args.next();
    }
    const image_a_path = args.next() orelse return error.InvalidArguments;
    const command_a_path = args.next() orelse return error.InvalidArguments;
    const image_b_path = args.next() orelse return error.InvalidArguments;
    const command_b_path = args.next() orelse return error.InvalidArguments;
    if (args.next() != null) return error.InvalidArguments;

    const image_a = try buildExecutableImage(allocator, "universal.fixture.a", "universal.fixture.a");
    const image_a_bytes = try image_a.encode(allocator);
    const manifest_a_fingerprint = try manifestFingerprintForImage(allocator, image_a);
    const command_a = try bootCommandBytes(allocator, manifest_a_fingerprint, "universal.fixture.a");

    const image_b = try buildExecutableImage(allocator, "universal.fixture.b", "universal.fixture.b");
    const image_b_bytes = try image_b.encode(allocator);
    const manifest_b_fingerprint = try manifestFingerprintForImage(allocator, image_b);
    const command_b = try bootCommandBytes(allocator, manifest_b_fingerprint, "universal.fixture.b");

    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = image_a_path, .data = image_a_bytes });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = command_a_path, .data = command_a });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = image_b_path, .data = image_b_bytes });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = command_b_path, .data = command_b });
}

fn buildExecutableImage(allocator: std.mem.Allocator, image_metadata: []const u8, binding_label: []const u8) !world.Executable.Image {
    const root_bytes = try fixtures.Ports.Target.Module.fullImage(allocator);
    defer allocator.free(root_bytes);

    var builder = world.Executable.Builder.init(allocator, .{
        .runtime_profile = universal.executable_runtime_profile,
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

fn manifestFingerprintForImage(allocator: std.mem.Allocator, image: world.Executable.Image) !u64 {
    var core = try world.Appliance.Core.initExecutable(allocator, image, .{
        .profile = .wasm_small,
        .capacity = universal.abi_capacity,
        .supported_runtime_profile = universal.executable_runtime_profile,
        .metadata = "world-universal-appliance",
    });
    defer core.deinit();
    return core.readManifest().manifest_fingerprint;
}

fn bootCommandBytes(allocator: std.mem.Allocator, manifest_fingerprint: u64, metadata: []const u8) ![]const u8 {
    const command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 0,
        .metadata = metadata,
    });
    return command.encode(allocator);
}

fn replyCommandBytesForBoot(
    allocator: std.mem.Allocator,
    image: world.Executable.Image,
    boot_command_bytes: []const u8,
    metadata: []const u8,
) ![]const u8 {
    var core = try world.Appliance.Core.initExecutable(allocator, image, .{
        .profile = .wasm_small,
        .capacity = universal.abi_capacity,
        .supported_runtime_profile = universal.executable_runtime_profile,
        .metadata = "world-universal-appliance",
    });
    defer core.deinit();

    try core.submit(boot_command_bytes);
    try core.executeTurn();
    const output_bytes = core.readOutput();
    var output = try world.Appliance.TurnOutput.decode(
        allocator,
        output_bytes,
        core.readManifest().manifest_fingerprint,
        universal.abi_capacity,
    );
    defer output.deinit(allocator);
    if (output.status != .needs_host or output.host_requests.len != 1) return error.InvalidFrameEncoding;

    const reply = try hostReplyFor(allocator, output.host_requests[0], 0x600D_0001);
    defer if (reply.outcome.response_bytes.len != 0) allocator.free(reply.outcome.response_bytes);
    const command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = output.manifest_fingerprint,
        .turn_sequence_number = output.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = output.turn_receipt.receipt_fingerprint,
        .host_replies = &.{reply},
        .metadata = metadata,
    });
    return command.encode(allocator);
}

fn replyCommandBytesForOutput(
    allocator: std.mem.Allocator,
    output: world.Appliance.TurnOutput,
    metadata: []const u8,
) ![]const u8 {
    const reply = try hostReplyFor(allocator, output.host_requests[0], 0x600D_0001);
    defer if (reply.outcome.response_bytes.len != 0) allocator.free(reply.outcome.response_bytes);
    try reply.validateWithAllocator(allocator, output.host_requests, universal.abi_capacity);
    const command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = output.manifest_fingerprint,
        .turn_sequence_number = output.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = output.turn_receipt.receipt_fingerprint,
        .host_replies = &.{reply},
        .metadata = metadata,
    });
    try command.validateWithAllocator(allocator, output.manifest_fingerprint, universal.abi_capacity);
    return command.encode(allocator);
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
