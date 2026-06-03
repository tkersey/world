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
const Args = struct { usize, []const u8 };

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{ .allocator = allocator, .scenario = .skeleton };
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();

    _ = try runspace.installMachineRun(fixtures.Agent.Target, Env, &runtime, Args{ 3, fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    var model_pending: usize = 0;
    var tool_pending: usize = 0;
    while (runspace.report().completed_count == 0) {
        _ = try runspace.tick();
        const pending_ports = try runspace.mailbox.listPending(allocator);
        defer allocator.free(pending_ports);
        for (pending_ports) |pending| {
            if (pending.world_port_id == DecidePort.world_port_id) {
                model_pending += 1;
                const value: fixtures.Agent.Action = if (model_pending == 1)
                    .{ .tool = "actuate" }
                else
                    .{ .final = "final=actuate skeleton complete" };
                _ = try runspace.respondValue(pending.mailbox_id, value);
            } else if (pending.world_port_id == ToolPort.world_port_id) {
                tool_pending += 1;
                _ = try runspace.respondValue(pending.mailbox_id, @as([]const u8, "actuate"));
            }
        }
    }

    try stdout.print("model_pending_count={d}\n", .{model_pending});
    try stdout.print("tool_pending_count={d}\n", .{tool_pending});
    try stdout.print("event_count={d}\n", .{runspace.report().event_count});
    try stdout.print("final_result=final=actuate skeleton complete\n", .{});
    try stdout.flush();
}
