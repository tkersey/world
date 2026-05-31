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
const DecideBinding = world.bind(DecidePort, world.NativeAdapter(decide));
const ToolBinding = world.bind(ToolPort, world.NativeAdapter(callTool));
const Env = world.Environment(fixtures.Agent.Target, .{ .bindings = .{ DecideBinding, ToolBinding }, .policy = world.EnvironmentPolicy.fresh_and_replay });
const Machine = world.Machine(fixtures.Agent.Target, .{ .environment = Env });
const Args = struct { usize, []const u8 };

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const permit = world.Supervision.issue(fixtures.Agent.Target, Env, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.agent_fixture,
        .budget = world.Budget.init(.{ .max_port_requests = 4, .max_fresh_calls = 4, .max_total_cost_units = 20 }),
    });
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{ .allocator = allocator };
    var result = try Machine.run(&runtime, Args{ 3, fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    defer result.deinit(allocator);

    try stdout.print("model_port_calls={d}\n", .{ctx.model_calls});
    try stdout.print("tool_port_calls={d}\n", .{ctx.tool_calls});
    try stdout.print("total_cost_units={d}\n", .{result.receipt.?.total_cost_units});
    try stdout.print("final_result={s}\n", .{result.value});
    try stdout.flush();
}
