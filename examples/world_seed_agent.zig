const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

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
    defer core.reset();

    var boot = try common.submitAndDecodeWithCapacity(&core, allocator, manifest, capacity, common.bootCommand(manifest));
    defer boot.deinit(allocator);
    if (boot.status != .needs_host or boot.host_requests.len != 1) return error.WorldSeedAgentRequestMissing;

    const pending_reply = common.hostReplyWithStatusFor(boot.host_requests[0], .pending);
    const pending_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = boot.turn_receipt.receipt_fingerprint,
        .host_replies = &.{pending_reply},
    });
    var pending = try common.submitAndDecodeWithCapacity(&core, allocator, manifest, capacity, pending_command);
    defer pending.deinit(allocator);
    if (pending.status != .needs_host or pending.host_requests.len != 1) return error.WorldSeedAgentPendingMissing;

    const final_reply = common.hostReplyFor(pending.host_requests[0], 0x5100_0002);
    const final_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .previous_turn_receipt_fingerprint = pending.turn_receipt.receipt_fingerprint,
        .host_replies = &.{final_reply},
    });
    var done = try common.submitAndDecodeWithCapacity(&core, allocator, manifest, capacity, final_command);
    defer done.deinit(allocator);
    if (done.status != .completed) return error.WorldSeedAgentNotCompleted;

    try stdout.print("world_seed=agent\n", .{});
    try stdout.print("provider_modules={d}\n", .{manifest.provider_target_ref_fingerprints.len});
    try stdout.print("fabric_plans={d}\n", .{manifest.fabric_plan_fingerprints.len});
    try stdout.print("external_requests={d}\n", .{boot.host_requests.len + pending.host_requests.len});
    try stdout.print("completed={}\n", .{done.status == .completed});
    try stdout.flush();
}
