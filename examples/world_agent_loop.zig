const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {
    allocator: std.mem.Allocator,
    scenario: fixtures.Agent.Scenario,
    model_calls: usize = 0,
    tool_calls: usize = 0,
    event_count: usize = 2,
};

fn decide(ctx: *Ctx, observation: []const u8) !fixtures.Agent.Action {
    ctx.model_calls += 1;
    const action = fixtures.Agent.decideAction(ctx.scenario, observation);
    if (action == .tool) ctx.event_count += 2;
    return action;
}

fn callTool(ctx: *Ctx, command: []const u8) ![]const u8 {
    ctx.tool_calls += 1;
    ctx.event_count += 2;
    return fixtures.Agent.callTool(ctx.allocator, ctx.scenario, command);
}

const DecidePort = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decide);
const ToolPort = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, callTool);
const Machine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ DecidePort, ToolPort },
    .strict_handler_coverage = true,
});
const Args = struct { usize, []const u8 };
const Options = struct {
    allocator: std.mem.Allocator,
    mode: world.Mode,
    ctx: *Ctx,
    transcript: *world.Transcript,
};

fn runScenario(
    allocator: std.mem.Allocator,
    scenario: fixtures.Agent.Scenario,
) !struct {
    final_text: []const u8,
    event_count: usize,
    tool_calls: usize,
    recorded_responses: usize,
    replay_handler_calls: usize,
} {
    if (scenario == .fixture) try fixtures.Agent.prepareFixtureWorkspace();

    var transcript = world.Transcript.init(allocator);
    defer transcript.deinit();

    const args: Args = .{ 3, fixtures.Agent.initialObservation(scenario) };

    var fresh_runtime = boundary.Runtime.init(allocator);
    defer fresh_runtime.deinit();
    var fresh_ctx: Ctx = .{ .allocator = allocator, .scenario = scenario };
    var fresh = try Machine.run(&fresh_runtime, args, Options{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
    });
    defer fresh.deinit(allocator);

    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replay_ctx: Ctx = .{ .allocator = allocator, .scenario = scenario };
    var replayed = try Machine.run(&replay_runtime, args, Options{
        .allocator = allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript = &transcript,
    });
    defer replayed.deinit(allocator);

    if (!std.mem.eql(u8, fresh.value, replayed.value)) return error.ReplayFinalMismatch;
    if (!std.mem.eql(u8, fresh.value, fixtures.Agent.expectedFinalText(scenario))) return error.UnexpectedFinalText;

    return .{
        .final_text = fixtures.Agent.expectedFinalText(scenario),
        .event_count = fresh_ctx.event_count,
        .tool_calls = fresh_ctx.tool_calls,
        .recorded_responses = transcript.summary().port_responded,
        .replay_handler_calls = replay_ctx.model_calls + replay_ctx.tool_calls,
    };
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const skeleton = try runScenario(std.heap.page_allocator, .skeleton);
    try stdout.print("skeleton final={s} events={d} tool_calls={d} responses={d}\n", .{
        skeleton.final_text,
        skeleton.event_count,
        skeleton.tool_calls,
        skeleton.recorded_responses,
    });

    const fixture = try runScenario(std.heap.page_allocator, .fixture);
    const io = std.Io.Threaded.global_single_threaded.io();
    var output_buffer: [1024]u8 = undefined;
    const bytes = try std.Io.Dir.cwd().readFile(io, fixtures.Agent.fixture_output_path, &output_buffer);
    try stdout.print("fixture final={s} events={d} tool_calls={d} responses={d}\n", .{
        fixture.final_text,
        fixture.event_count,
        fixture.tool_calls,
        fixture.recorded_responses,
    });
    try stdout.print("fixture output={s}\n", .{bytes});
    try stdout.print("replay fresh_handler_calls={d}\n", .{skeleton.replay_handler_calls + fixture.replay_handler_calls});
    try stdout.flush();
}
