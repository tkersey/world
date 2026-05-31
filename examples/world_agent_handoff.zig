const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {
    allocator: std.mem.Allocator,
    scenario: fixtures.Agent.Scenario,
    model_calls: usize = 0,
    tool_calls: usize = 0,
};

fn decide(ctx: *Ctx, observation: []const u8) !fixtures.Agent.Action {
    ctx.model_calls += 1;
    return fixtures.Agent.decideAction(ctx.scenario, observation);
}

fn callTool(ctx: *Ctx, command: []const u8) ![]const u8 {
    ctx.tool_calls += 1;
    return fixtures.Agent.callTool(ctx.allocator, ctx.scenario, command);
}

const DecidePort = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decide);
const ToolPort = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, callTool);
const Env = world.Environment(fixtures.Agent.Target, .{
    .bindings = .{
        world.bind(DecidePort, world.NativeAdapter(decide)),
        world.bind(ToolPort, world.NativeAdapter(callTool)),
    },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const Machine = world.Machine(fixtures.Agent.Target, .{
    .environment = Env,
    .strict_handler_coverage = true,
});
const Args = struct { usize, []const u8 };

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;
    const args: Args = .{ 3, fixtures.Agent.initialObservation(.skeleton) };

    var transcript = world.Transcript.init(allocator);
    defer transcript.deinit();
    var fresh_runtime = boundary.Runtime.init(allocator);
    defer fresh_runtime.deinit();
    var fresh_ctx: Ctx = .{ .allocator = allocator, .scenario = .skeleton };
    var fresh = try Machine.run(&fresh_runtime, args, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
    });
    defer fresh.deinit(allocator);
    var image = try transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(allocator);
    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = fixtures.Agent.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Agent.Target.Certificate.certificate_fingerprint,
        .event_index = 2,
        .turn_index = image.events[1].turn_index orelse 0,
        .current_request_fingerprint = image.events[1].request_fingerprint,
        .transcript_prefix_fingerprint = image.events[1].event_fingerprint,
        .branch_id = 1,
        .status = .parked_on_port,
    });
    const target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const branch = world.Timeline.Branch{
        .branch_id = 1,
        .parent_branch_id = null,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .branch_label = "agent-handoff",
        .start_event_index = checkpoint.event_index,
        .final_event_index = image.events.len,
        .final_status = .completed,
        .event_count = image.events.len - checkpoint.event_index,
        .response_count = image.response_count,
    };
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .branch_id = 1,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .status = .completed,
    });
    const run_image = world.RunImage.init(.{
        .kind = .branched_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .transcript_image = image,
        .current_state = state,
        .checkpoints = &.{checkpoint},
        .branches = @constCast(&[_]world.Timeline.Branch{branch}),
    });
    const encoded = try run_image.encode(allocator);
    defer allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(allocator, encoded);
    defer handoff.deinit();

    handoff.run_image.transcript_image.?.resetReplay();
    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replayed = try Machine.run(&replay_runtime, args, .{
        .allocator = allocator,
        .mode = world.Mode.replay,
        .transcript_image = &handoff.run_image.transcript_image.?,
    });
    defer replayed.deinit(allocator);

    try stdout.print("run_image_fingerprint={x}\n", .{run_image.run_image_fingerprint});
    try stdout.print("checkpoint_fingerprint={x}\n", .{checkpoint.checkpoint_fingerprint});
    try stdout.print("branch_id={d}\n", .{state.branch_id});
    try stdout.print("model_port_id={d}\n", .{DecidePort.world_port_id});
    try stdout.print("tool_port_id={d}\n", .{ToolPort.world_port_id});
    try stdout.print("final_result={s}\n", .{replayed.value});
    try stdout.flush();
}
