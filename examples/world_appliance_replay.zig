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
    const replay_bytes = try replay_command.encode(allocator);
    defer allocator.free(replay_bytes);
    const replay_rejected = rejected: {
        fresh_core.submit(replay_bytes) catch |err| {
            if (err != error.InvalidCommand) return err;
            break :rejected true;
        };
        break :rejected false;
    };
    if (!replay_rejected) return error.ExpectedReplayRejected;

    const replay_supported = manifest.supported_execution_modes.supports(.replay);

    try stdout.print("fresh_host_requests={d}\n", .{boot_output.host_requests.len});
    try stdout.print("replay_supported={}\n", .{replay_supported});
    try stdout.print("actuated_replay_rejected={}\n", .{replay_rejected});
    try stdout.flush();
}
