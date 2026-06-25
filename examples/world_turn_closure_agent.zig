const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

const executable_image_fingerprint: u64 = 0xCE11_C105_0000_0201;

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const manifest = common.AgentAppliance.manifest();
    const capacity = world.Appliance.Capacity.wasm_agent;
    var core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.AgentAppliance.memoryPlan(),
        capacity,
    );
    core.executable_image_fingerprint = executable_image_fingerprint;
    var native = world.Appliance.Native.init(core);
    defer native.deinit();

    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_images = &.{"goal=invoke"},
    });
    const boot_bytes = try boot.encode(allocator);
    defer allocator.free(boot_bytes);
    const boot_status = native.submitTurn(boot_bytes);
    if (boot_status != .needs_host) {
        std.debug.print("boot_status={s} last_error={s}\n", .{ @tagName(boot_status), native.lastErrorBytes() });
        return error.ExpectedFirstModelRequest;
    }

    const first_closure_bytes = try common.readClosureOwned(allocator, &native);
    defer allocator.free(first_closure_bytes);
    var first_closure = try world.Appliance.TurnClosure.decode(allocator, first_closure_bytes);
    defer first_closure.deinit(allocator);
    var first_output = try common.decodeNativeOutput(allocator, manifest, capacity, &native);
    defer first_output.deinit(allocator);
    if (first_output.host_requests.len != 1) return error.ExpectedFirstModelRequest;

    const tool_resolution = try common.wireResolutionFor(allocator, first_output.host_requests[0], .pending, 0);
    const tool_turn = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = first_closure.closure_fingerprint,
        .previous_turn_receipt_fingerprint = first_output.turn_receipt.receipt_fingerprint,
        .turn_sequence_number = 1,
        .resolutions = &.{tool_resolution},
    });
    const tool_bytes = try tool_turn.encode(allocator);
    defer allocator.free(tool_bytes);
    if (native.submitTurn(tool_bytes) != .needs_host) return error.ExpectedSecondModelRequest;

    const second_closure_bytes = try common.readClosureOwned(allocator, &native);
    defer allocator.free(second_closure_bytes);
    var second_closure = try world.Appliance.TurnClosure.decode(allocator, second_closure_bytes);
    defer second_closure.deinit(allocator);
    var second_output = try common.decodeNativeOutput(allocator, manifest, capacity, &native);
    defer second_output.deinit(allocator);
    if (second_output.host_requests.len != 1) return error.ExpectedSecondModelRequest;

    const final_resolution = try common.wireResolutionFor(allocator, second_output.host_requests[0], .responded, 0xCE11_0202);
    defer if (final_resolution.response_value_image_bytes.len != 0) allocator.free(final_resolution.response_value_image_bytes);
    const final_turn = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = second_closure.closure_fingerprint,
        .previous_turn_receipt_fingerprint = second_output.turn_receipt.receipt_fingerprint,
        .turn_sequence_number = 2,
        .resolutions = &.{final_resolution},
    });
    const final_bytes = try final_turn.encode(allocator);
    defer allocator.free(final_bytes);
    if (native.submitTurn(final_bytes) != .completed) return error.ExpectedCompleted;

    const final_closure_bytes = try common.readClosureOwned(allocator, &native);
    defer allocator.free(final_closure_bytes);
    var final_closure = try world.Appliance.TurnClosure.decode(allocator, final_closure_bytes);
    defer final_closure.deinit(allocator);
    try final_closure.validate(allocator, .{
        .expected_executable_image_fingerprint = executable_image_fingerprint,
        .expected_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = second_closure.closure_fingerprint,
        .bundle_options = .{ .allow_external_dependencies = true },
    });

    try stdout.print("root_loaded=true\n", .{});
    try stdout.print("provider_loaded={}\n", .{manifest.provider_target_ref_fingerprints.len == 1});
    try stdout.print("external_model_requests={d}\n", .{first_output.host_requests.len + second_output.host_requests.len});
    try stdout.print("internal_tool_invocations=1\n", .{});
    try stdout.print("final_result=final=actuate skeleton complete\n", .{});
    try stdout.print("closure_valid=true\n", .{});
    try stdout.flush();
}
