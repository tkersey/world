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
const Machine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ DecidePort, ToolPort },
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
    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replayed = try Machine.run(&replay_runtime, args, .{
        .allocator = allocator,
        .mode = world.Mode.replay,
        .transcript_image = &image,
    });
    defer replayed.deinit(allocator);

    try stdout.print("transcript_image_fingerprint={x}\n", .{image.transcript_image_fingerprint});
    try stdout.print("event_count={d}\n", .{image.events.len});
    try stdout.print("tool_call_count={d}\n", .{fresh_ctx.tool_calls});
    try stdout.print("replay_verified={}\n", .{std.mem.eql(u8, fresh.value, replayed.value)});
    try stdout.print("final_result={s}\n", .{replayed.value});
    try stdout.flush();
}
