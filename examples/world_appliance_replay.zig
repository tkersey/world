const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const manifest = common.PortsAppliance.manifest();

    var fresh_core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer fresh_core.reset();
    try common.submit(&fresh_core, allocator, common.bootCommand(manifest));
    var fresh_output = try world.Appliance.TurnOutput.decode(
        allocator,
        fresh_core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer fresh_output.deinit(allocator);

    var replay_core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer replay_core.reset();
    const replay_evidence = [_]u64{fresh_output.turn_receipt.receipt_fingerprint};
    const replay_command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .execution_mode = .replay,
        .receiver_evidence_fingerprints = &replay_evidence,
    });
    try common.submit(&replay_core, allocator, replay_command);
    var replay_output = try world.Appliance.TurnOutput.decode(
        allocator,
        replay_core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer replay_output.deinit(allocator);

    try stdout.print("fresh_status={s}\n", .{@tagName(fresh_output.status)});
    try stdout.print("fresh_host_requests={d}\n", .{fresh_output.host_requests.len});
    try stdout.print("replay_status={s}\n", .{@tagName(replay_output.status)});
    try stdout.print("replay_host_requests={d}\n", .{replay_output.host_requests.len});
    try stdout.print("replay_evidence={x}\n", .{replay_evidence[0]});
    try stdout.print("replay_final_result={}\n", .{replay_output.root_result_fingerprint != null});
    try stdout.flush();
}
