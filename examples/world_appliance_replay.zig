const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const manifest = common.AgentAppliance.manifest();
    const capacity = world.Appliance.Capacity.wasm_agent;

    var fresh_core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.AgentAppliance.memoryPlan(),
        capacity,
    );
    defer fresh_core.reset();

    var boot_output = try common.submitAndDecodeWithCapacity(&fresh_core, allocator, manifest, capacity, common.bootCommand(manifest));
    defer boot_output.deinit(allocator);
    if (boot_output.status != .needs_host or boot_output.host_requests.len != 1) return error.ExpectedModelRequest;

    const replay_evidence = [_]u64{
        boot_output.turn_receipt.receipt_fingerprint,
        manifest.actuation_binding_fingerprints[0],
    };
    const replay_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = boot_output.turn_receipt.receipt_fingerprint,
        .execution_mode = .replay,
        .receiver_evidence_fingerprints = &replay_evidence,
    });
    var replay_output = try common.submitAndDecodeWithCapacity(&fresh_core, allocator, manifest, capacity, replay_command);
    defer replay_output.deinit(allocator);
    if (replay_output.status != .completed) return error.ExpectedReplayCompleted;
    if (replay_output.host_requests.len != 0) return error.ExpectedNoReplayHostRequests;
    if (replay_output.finalized_actuation_receipt_fingerprints.len != 0) return error.ExpectedNoReplayReceipt;

    const replay_supported = manifest.supported_execution_modes.supports(.replay);
    const replay_fresh_called = replay_output.turn_receipt.applied_host_reply_fingerprints.len != 0;
    const replay_final_result = replay_output.root_result_fingerprint != null and replay_output.root_result_value_image_bytes.len != 0;

    try stdout.print("fresh_host_requests={d}\n", .{boot_output.host_requests.len});
    try stdout.print("replay_supported={}\n", .{replay_supported});
    try stdout.print("replay_host_requests={d}\n", .{replay_output.host_requests.len});
    try stdout.print("replay_fresh_called={}\n", .{replay_fresh_called});
    try stdout.print("replay_final_result={}\n", .{replay_final_result});
    try stdout.flush();
}
