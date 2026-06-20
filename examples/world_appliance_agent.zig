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
    var core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.AgentAppliance.memoryPlan(),
        capacity,
    );
    defer core.reset();

    var boot_output = try common.submitAndDecodeWithCapacity(&core, allocator, manifest, capacity, common.bootCommand(manifest));
    defer boot_output.deinit(allocator);
    if (boot_output.status != .needs_host) return error.ExpectedModelRequest;
    if (boot_output.host_requests.len != 1) return error.ExpectedModelRequest;

    const pending_reply = common.hostReplyWithStatusFor(boot_output.host_requests[0], .pending);
    const pending_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = boot_output.turn_receipt.receipt_fingerprint,
        .host_replies = &.{pending_reply},
    });
    var pending_output = try common.submitAndDecodeWithCapacity(&core, allocator, manifest, capacity, pending_command);
    defer pending_output.deinit(allocator);
    if (pending_output.status != .needs_host) return error.ExpectedSecondModelRequest;
    if (pending_output.host_requests.len != 1) return error.ExpectedSecondModelRequest;

    const final_reply = common.hostReplyFor(pending_output.host_requests[0], 0xA6E7_0001);
    const final_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .previous_turn_receipt_fingerprint = pending_output.turn_receipt.receipt_fingerprint,
        .host_replies = &.{final_reply},
    });
    var final_output = try common.submitAndDecodeWithCapacity(&core, allocator, manifest, capacity, final_command);
    defer final_output.deinit(allocator);
    if (final_output.status != .completed) return error.ExpectedCompletedAgent;

    var archive = try world.Archive.Memory.open(allocator, .{});
    defer archive.deinit();
    var plan = try world.Appliance.ArchivePlan.initForTurnOutput(
        allocator,
        archive.image.latestCursor(),
        pending_output,
        capacity,
    );
    defer plan.deinit();
    _ = try archive.appendBatch(plan.append_batch);

    try stdout.print("agent_appliance=core-protocol\n", .{});
    try stdout.print("external_model_requests={d}\n", .{boot_output.host_requests.len + pending_output.host_requests.len});
    try stdout.print("internal_tool_provider_targets={d}\n", .{manifest.provider_target_ref_fingerprints.len});
    try stdout.print("fabric_plans={d}\n", .{manifest.fabric_plan_fingerprints.len});
    try stdout.print("finalized_actuation_receipts={d}\n", .{final_output.finalized_actuation_receipt_fingerprints.len});
    try stdout.print("archive_objects={d}\n", .{plan.objects.len});
    try stdout.print("final_result={}\n", .{final_output.root_result_fingerprint != null});
    try stdout.flush();
}
