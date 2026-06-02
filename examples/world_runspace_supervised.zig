const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {
    allocator: std.mem.Allocator,
    model_calls: usize = 0,
    tool_calls: usize = 0,
};

fn decide(ctx: *Ctx, observation: []const u8) !fixtures.Agent.Action {
    ctx.model_calls += 1;
    return fixtures.Agent.decideAction(.skeleton, observation);
}

fn callTool(ctx: *Ctx, command: []const u8) ![]const u8 {
    ctx.tool_calls += 1;
    return fixtures.Agent.callTool(ctx.allocator, .skeleton, command);
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
const Args = struct { usize, []const u8 };

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const permit = world.Supervision.issue(fixtures.Agent.Target, Env, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.agent_fixture,
        .budget = world.Budget.init(.{ .max_fresh_calls = 1 }),
    });
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{ .allocator = allocator };
    var runspace = world.Runspace.init(allocator, .{ .auto_dispatch = true, .require_supervision = true });
    defer runspace.deinit();

    _ = try runspace.installMachineRun(fixtures.Agent.Target, Env, &runtime, Args{ 3, fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    var budget_exceeded = false;
    while (runspace.report().completed_count == 0 and runspace.report().failed_count == 0) {
        _ = runspace.tick() catch |err| {
            budget_exceeded = err == error.BudgetExceeded;
            break;
        };
    }
    const event_fingerprint = if (runspace.events.items.len != 0) runspace.events.items[runspace.events.items.len - 1].event_fingerprint else 0;

    try stdout.print("run_permit={x}\n", .{permit.permit_fingerprint});
    try stdout.print("budget_exceeded={}\n", .{budget_exceeded});
    try stdout.print("event_fingerprint={x}\n", .{event_fingerprint});
    try stdout.flush();
}
