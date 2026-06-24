const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");
const fixtures = @import("world_fixtures");

const ApplianceCtx = struct {};

fn applianceDecide(_: *ApplianceCtx, _: []const u8) !fixtures.Agent.Action {
    return .{ .final = "final=actuate skeleton complete" };
}

fn applianceTool(_: *ApplianceCtx, _: []const u8) ![]const u8 {
    return "tool";
}

const ApplianceAgentDecideDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, applianceDecide);
const ApplianceAgentToolDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, applianceTool);
const ApplianceActuator = world.actuator(.{
    .kind = .fixture,
    .class = .deterministic_fixture,
    .label = "appliance.batch",
    .supported_response_statuses = world.Actuation.ResponseStatusSet.all,
    .value_policy = world.ValuePolicy.portable,
});
const BatchAppliance = world.Appliance.Define(fixtures.Agent.Target, .{
    .profile = world.Appliance.Profile.wasm_agent,
    .capacity = world.Appliance.Capacity.wasm_agent,
    .actuation_bindings = .{
        world.bindActuator(ApplianceAgentDecideDecl, ApplianceActuator),
        world.bindActuator(ApplianceAgentToolDecl, ApplianceActuator),
    },
});

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const manifest = BatchAppliance.manifest();
    const capacity = world.Appliance.Capacity.wasm_agent;
    var core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        BatchAppliance.memoryPlan(),
        capacity,
    );
    defer core.reset();

    const boot_command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_image = "agent:prompt",
    });
    var boot_output = try common.submitAndDecodeWithCapacity(&core, allocator, manifest, capacity, boot_command);
    defer boot_output.deinit(allocator);
    if (boot_output.status != .needs_host) return error.ExpectedHostRequests;
    if (boot_output.host_requests.len != 2) return error.ExpectedBatchedRequests;

    const first = boot_output.host_requests[0];
    const second = boot_output.host_requests[1];
    const duplicate_replies = [_]world.Appliance.HostReply{
        common.hostReplyFor(first, 0xB471_0001),
        common.hostReplyFor(first, 0xB471_0002),
    };
    const duplicate_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = boot_output.turn_receipt.receipt_fingerprint,
        .host_replies = &duplicate_replies,
    });
    if (duplicate_command.validate(manifest.manifest_fingerprint, capacity) != error.DuplicateReply) {
        return error.ExpectedDuplicateReplyReject;
    }

    const partial_reply = common.hostReplyFor(first, 0xB471_0003);
    const restore_command = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = boot_output.checkpoint.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = boot_output.checkpoint.previous_turn_receipt_fingerprint,
        .host_replies = &.{partial_reply},
        .restore_checkpoint = boot_output.checkpoint,
    });
    var restored = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        BatchAppliance.memoryPlan(),
        capacity,
    );
    defer restored.reset();
    var partial_output = try common.submitAndDecodeWithCapacity(&restored, allocator, manifest, capacity, restore_command);
    defer partial_output.deinit(allocator);
    const partial_batch_preserved =
        partial_output.status == .needs_host and
        partial_output.host_requests.len == 1 and
        partial_output.host_requests[0].request_fingerprint == second.request_fingerprint;
    if (!partial_batch_preserved) return error.ExpectedPartialBatchPreserved;

    const reverse_replies = [_]world.Appliance.HostReply{
        common.hostReplyFor(second, 0xB471_0004),
        common.hostReplyFor(first, 0xB471_0005),
    };
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = boot_output.turn_receipt.receipt_fingerprint,
        .host_replies = &reverse_replies,
    });
    var final_output = try common.submitAndDecodeWithCapacity(&core, allocator, manifest, capacity, continue_command);
    defer final_output.deinit(allocator);
    const reverse_replies_accepted =
        final_output.status == .completed and
        final_output.finalized_actuation_receipt_fingerprints.len == 2 and
        final_output.root_result_value_image_bytes.len != 0;
    if (!reverse_replies_accepted) return error.ExpectedReverseRepliesAccepted;

    try stdout.print("initial_requests={d}\n", .{boot_output.host_requests.len});
    try stdout.print("reverse_replies_accepted={}\n", .{reverse_replies_accepted});
    try stdout.print("partial_batch_preserved={}\n", .{partial_batch_preserved});
    try stdout.print("completed={}\n", .{final_output.status == .completed});
    try stdout.flush();
}
