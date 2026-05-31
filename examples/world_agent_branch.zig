const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {
    allocator: std.mem.Allocator,
    alternate: bool = false,
};

fn decide(ctx: *Ctx, observation: []const u8) !fixtures.Agent.Action {
    if (ctx.alternate) return .{ .final = "final=branch alternate" };
    return fixtures.Agent.decideAction(.skeleton, observation);
}

fn callTool(ctx: *Ctx, command: []const u8) ![]const u8 {
    return fixtures.Agent.callTool(ctx.allocator, .skeleton, command);
}

const DecidePort = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decide);
const ToolPort = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, callTool);
const Machine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ DecidePort, ToolPort },
    .strict_handler_coverage = true,
});
const Args = struct { usize, []const u8 };

fn runTranscript(allocator: std.mem.Allocator, alternate: bool) !struct {
    value: []const u8,
    transcript: world.Transcript,
    image: world.TranscriptImage,
} {
    var transcript = world.Transcript.init(allocator);
    errdefer transcript.deinit();
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{ .allocator = allocator, .alternate = alternate };
    var result = try Machine.run(&runtime, Args{ 3, fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(allocator);
    const value = try allocator.dupe(u8, result.value);
    errdefer allocator.free(value);
    var image = try transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    errdefer image.deinit(allocator);
    return .{ .value = value, .transcript = transcript, .image = image };
}

fn forkTranscriptFromCheckpoint(
    allocator: std.mem.Allocator,
    baseline: *const world.Transcript,
    branch: *const world.Transcript,
    checkpoint_event_index: usize,
) !world.Transcript {
    if (checkpoint_event_index > baseline.events.items.len or checkpoint_event_index > branch.events.items.len) return error.InvalidFrameEncoding;
    var forked = world.Transcript.init(allocator);
    errdefer forked.deinit();
    for (baseline.events.items[0..checkpoint_event_index]) |event| {
        try forked.append(event);
    }
    for (branch.events.items[checkpoint_event_index..]) |event| {
        try forked.append(event);
    }
    return forked;
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var baseline = try runTranscript(allocator, false);
    defer {
        allocator.free(baseline.value);
        baseline.image.deinit(allocator);
        baseline.transcript.deinit();
    }
    var branch_run = try runTranscript(allocator, true);
    defer {
        allocator.free(branch_run.value);
        branch_run.image.deinit(allocator);
        branch_run.transcript.deinit();
    }

    const checkpoint_event_index = 2;
    const checkpoint_event = baseline.image.events[checkpoint_event_index - 1];
    if (branch_run.image.events[checkpoint_event_index - 1].request_fingerprint != checkpoint_event.request_fingerprint) return error.InvalidFrameEncoding;
    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = fixtures.Agent.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Agent.Target.Certificate.certificate_fingerprint,
        .event_index = checkpoint_event_index,
        .turn_index = checkpoint_event.turn_index orelse 0,
        .current_request_fingerprint = checkpoint_event.request_fingerprint,
        .transcript_prefix_fingerprint = checkpoint_event.event_fingerprint,
        .branch_id = 1,
        .status = .parked_on_port,
    });
    var branch_transcript = try forkTranscriptFromCheckpoint(allocator, &baseline.transcript, &branch_run.transcript, checkpoint.event_index);
    defer branch_transcript.deinit();
    var branch_image = try branch_transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer branch_image.deinit(allocator);

    try stdout.print("checkpoint_fingerprint={x}\n", .{checkpoint.checkpoint_fingerprint});
    try stdout.print("baseline_transcript_fingerprint={x}\n", .{baseline.image.transcript_image_fingerprint});
    try stdout.print("branch_transcript_fingerprint={x}\n", .{branch_image.transcript_image_fingerprint});
    try stdout.print("baseline_final_result={s}\n", .{baseline.value});
    try stdout.print("branch_final_result={s}\n", .{branch_run.value});
    try stdout.flush();
}
