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
    const fresh_reply = common.hostReplyFor(fresh_output.host_requests[0], 0xA6E7_2001);
    const fresh_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = fresh_output.turn_receipt.receipt_fingerprint,
        .host_replies = &.{fresh_reply},
    });
    var terminal_output = try common.submitAndDecode(&fresh_core, allocator, manifest, fresh_continue);
    defer terminal_output.deinit(allocator);

    const replay_supported = manifest.supported_execution_modes.supports(.replay);

    try stdout.print("fresh_status={s}\n", .{@tagName(fresh_output.status)});
    try stdout.print("fresh_host_requests={d}\n", .{fresh_output.host_requests.len});
    try stdout.print("replay_supported={}\n", .{replay_supported});
    try stdout.print("replay_evidence={x}\n", .{terminal_output.turn_receipt.receipt_fingerprint});
    try stdout.print("replay_final_result=false\n", .{});
    try stdout.flush();
}
