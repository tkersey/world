const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct { model_calls: usize = 0 };

fn decide(ctx: *Ctx, _: []const u8) !fixtures.Agent.Action {
    ctx.model_calls += 1;
    return if (ctx.model_calls == 1)
        fixtures.Agent.Action{ .tool = "first" }
    else
        fixtures.Agent.Action{ .tool = "second" };
}

fn unexpectedTool(_: *Ctx, _: []const u8) ![]const u8 {
    return error.UnexpectedNativeTool;
}

const DecidePort = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decide);
const ToolPort = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, unexpectedTool);
const Env = world.Environment(fixtures.Agent.Target, .{
    .bindings = .{
        world.bind(DecidePort, world.NativeAdapter(decide)),
        world.bind(ToolPort, world.NativeAdapter(unexpectedTool)),
    },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const Args = struct { usize, []const u8 };

fn providerImage(allocator: std.mem.Allocator, seed: u64, value: []const u8) !struct {
    image: world.RunImage,
    value_image: world.Frame.ValueImage,
} {
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    var value_image = try world.Frame.ValueImage.fromValue(allocator, 4, seed, null, value, world.ValuePolicy.portable);
    errdefer value_image.deinit(allocator);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .final_response_fingerprint = seed,
        .final_value_image_fingerprint = value_image.value_image_fingerprint,
        .status = .completed,
    });
    return .{
        .image = world.RunImage.init(.{
            .kind = .completed_run,
            .target_ref = provider_ref,
            .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
            .current_state = state,
            .final_result_image = value_image,
        }),
        .value_image = value_image,
    };
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const permit = world.Supervision.issue(fixtures.Agent.Target, Env, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_fabric_invocations = 1, .max_provider_runs = 2 }),
    });
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{};
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();
    _ = try runspace.installMachineRun(fixtures.Agent.Target, Env, &runtime, Args{ 3, fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });

    var first = try providerImage(allocator, 0x5150_fab4, "one");
    defer first.value_image.deinit(allocator);
    const first_handle = try runspace.installRunImage(first.image);
    var second = try providerImage(allocator, 0x5150_fab5, "two");
    defer second.value_image.deinit(allocator);
    const second_handle = try runspace.installRunImage(second.image);
    const parent_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    const mapping = world.Fabric.ValueMapping.init(.{
        .kind = .provider_result_to_parent_response,
        .provider_result_value_table_id = 4,
        .parent_response_value_table_id = 4,
    });
    const route = world.Fabric.Route.init(.{
        .route_id = 0xfab4,
        .kind = .target_export,
        .parent_world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .parent_target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .parent_world_port_id = ToolPort.world_port_id,
        .provider_target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .provider_world_surface_fingerprint = provider_ref.world_surface_fingerprint,
        .provider_target_certificate_fingerprint = provider_ref.target_certificate_fingerprint,
        .value_mapping_fingerprint = mapping.mapping_fingerprint,
    });
    const plan = world.Fabric.Plan.init(.{
        .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
        .module_fingerprint = parent_ref.boundary_module_fingerprint,
        .world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .routes = &.{route},
        .value_mappings = &.{mapping},
        .max_depth = 2,
        .max_provider_runs = 2,
    });
    try runspace.installFabricPlan(parent_ref, plan);
    var budget_exceeded = false;
    var model_responses: usize = 0;

    while (!budget_exceeded) {
        _ = try runspace.tick();
        const pending_ports = try runspace.mailbox.listPending(allocator);
        defer allocator.free(pending_ports);
        for (pending_ports) |pending| {
            if (pending.world_port_id == DecidePort.world_port_id) {
                model_responses += 1;
                const action: fixtures.Agent.Action = if (model_responses == 1)
                    .{ .tool = "first" }
                else
                    .{ .tool = "second" };
                _ = try runspace.respondValue(pending.mailbox_id, action);
            } else if (pending.world_port_id == ToolPort.world_port_id) {
                const handle = if (runspace.report().fabric_invocation_count == 0) first_handle else second_handle;
                const invocation = runspace.routePendingToProviderRun(pending.mailbox_id, plan, handle) catch |err| {
                    budget_exceeded = err == error.BudgetExceeded;
                    break;
                };
                _ = try runspace.respondFromFabric(invocation);
            }
        }
    }

    const receipt_fingerprint = if (runspace.fabric_receipts.items.len == 0) 0 else runspace.fabric_receipts.items[0].receipt_fingerprint;
    try stdout.print("fabric_invocation_count={d}\n", .{runspace.report().fabric_invocation_count});
    try stdout.print("budget_exceeded={}\n", .{budget_exceeded});
    try stdout.print("run_receipt_fingerprint={x}\n", .{receipt_fingerprint});
    try stdout.flush();
}
