const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

const executable_image_fingerprint: u64 = 0xCE11_C105_0000_0101;

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    var core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.PortsAppliance.memoryPlan(),
        capacity,
    );
    core.executable_image_fingerprint = executable_image_fingerprint;
    var native = world.Appliance.Native.init(core);
    defer native.deinit();

    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    defer allocator.free(boot_bytes);
    const boot_status = native.submitTurn(boot_bytes);
    if (boot_status != .needs_host) {
        std.debug.print("boot_status={s} last_error={s}\n", .{ @tagName(boot_status), native.lastErrorBytes() });
        return error.ExpectedNeedsHost;
    }

    const boot_closure_bytes = try common.readClosureOwned(allocator, &native);
    defer allocator.free(boot_closure_bytes);
    var boot_closure = try world.Appliance.TurnClosure.decode(allocator, boot_closure_bytes);
    defer boot_closure.deinit(allocator);
    try boot_closure.validate(allocator, .{
        .expected_executable_image_fingerprint = executable_image_fingerprint,
        .expected_manifest_fingerprint = manifest.manifest_fingerprint,
        .bundle_options = .{ .allow_external_dependencies = true },
    });

    var boot_output = try common.decodeNativeOutput(allocator, manifest, capacity, &native);
    defer boot_output.deinit(allocator);
    if (boot_output.status != .needs_host or boot_output.host_requests.len != 1) return error.ExpectedOneHostRequest;

    const resolution = try common.wireResolutionFor(allocator, boot_output.host_requests[0], .responded, 0xCE11_0102);
    defer if (resolution.response_value_image_bytes.len != 0) allocator.free(resolution.response_value_image_bytes);
    const continue_turn = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .previous_turn_receipt_fingerprint = boot_output.turn_receipt.receipt_fingerprint,
        .turn_sequence_number = 1,
        .resolutions = &.{resolution},
    });
    const continue_bytes = try continue_turn.encode(allocator);
    defer allocator.free(continue_bytes);
    if (native.submitTurn(continue_bytes) != .completed) return error.ExpectedCompleted;

    const completed_closure_bytes = try common.readClosureOwned(allocator, &native);
    defer allocator.free(completed_closure_bytes);
    var completed_closure = try world.Appliance.TurnClosure.decode(allocator, completed_closure_bytes);
    defer completed_closure.deinit(allocator);
    try completed_closure.validate(allocator, .{
        .expected_executable_image_fingerprint = executable_image_fingerprint,
        .expected_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = boot_closure.closure_fingerprint,
        .bundle_options = .{ .allow_external_dependencies = true },
    });

    try stdout.print("closure_valid=true\n", .{});
    try stdout.print("host_requests={d}\n", .{boot_output.host_requests.len});
    try stdout.print("result_bytes_present={}\n", .{completed_closure.root_result_bytes.len != 0});
    try stdout.print("archive_append_present={}\n", .{completed_closure.archive_append_batch_bytes.len != 0});
    try stdout.flush();
}
