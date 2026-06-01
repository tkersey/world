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
const Machine = world.Machine(fixtures.Agent.Target, .{ .environment = Env, .strict_handler_coverage = true });
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
    var fresh = try Machine.run(&fresh_runtime, args, .{ .allocator = allocator, .mode = world.Mode.fresh, .ctx = &fresh_ctx, .transcript = &transcript });
    defer fresh.deinit(allocator);
    var image = try transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(allocator);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Agent.Target);
    const target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Agent.Target, image, .completed_run).withModuleRef(module_ref, null);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = run_image,
        .requested_mode = .replay_only,
    });
    const entry = world.Admission.TargetRegistry.register(fixtures.Agent.Target);
    const permit = world.Supervision.issue(fixtures.Agent.Target, Env, .{
        .mode = .replay,
        .transcript_image_available = true,
        .policy = world.SupervisionPolicy.agent_fixture,
        .budget = world.Budget.init(.{ .max_port_requests = 4, .max_total_cost_units = 20 }),
    });
    const admitter = world.Admission.Admitter.init(.{ .registry = world.Admission.TargetRegistry.init(&.{entry}), .policy = world.Admission.AdmissionPolicy.test_fixture });
    const admission = admitter.admitForTarget(fixtures.Agent.Target, Env, package, .{ .mode = .replay_only, .permit = permit });
    image.resetReplay();
    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replayed = try Machine.run(&replay_runtime, args, .{ .allocator = allocator, .mode = world.Mode.replay, .transcript_image = &image, .permit = permit });
    defer replayed.deinit(allocator);

    try stdout.print("module_ref_fingerprint={x}\n", .{module_ref.module_ref_fingerprint});
    try stdout.print("model_port_id={d}\n", .{DecidePort.world_port_id});
    try stdout.print("tool_port_id={d}\n", .{ToolPort.world_port_id});
    try stdout.print("admission_receipt={x}\n", .{admission.receipt.?.receipt_fingerprint});
    try stdout.print("final_result={s}\n", .{replayed.value});
    try stdout.flush();
}
