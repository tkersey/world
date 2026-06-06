const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {
    model_calls: usize = 0,
    native_tool_calls: usize = 0,
};

fn decide(ctx: *Ctx, observation: []const u8) !fixtures.Agent.Action {
    ctx.model_calls += 1;
    if (std.mem.eql(u8, observation, "goal=invoke")) return .{ .tool = "actuate" };
    return .{ .final = "final=actuate skeleton complete" };
}

fn unexpectedTool(ctx: *Ctx, _: []const u8) ![]const u8 {
    ctx.native_tool_calls += 1;
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

fn providerImage(allocator: std.mem.Allocator) !struct {
    image: world.RunImage,
    value_image: world.Frame.ValueImage,
} {
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    var value_image = try world.Frame.ValueImage.fromValue(
        allocator,
        4,
        0x5150_1a02,
        null,
        @as([]const u8, "actuate"),
        world.ValuePolicy.portable,
    );
    errdefer value_image.deinit(allocator);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .final_response_fingerprint = 0x5150_1a02,
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

    const root_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const decide_import = world.ImportRequirement.fromTargetPort(fixtures.Agent.Target, 0);
    const tool_import = world.ImportRequirement.fromTargetPort(fixtures.Agent.Target, 1);
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    const tool_export = world.Linker.ExportDescriptor.init(.{
        .target_ref = provider_ref,
        .result_ref = .{ .value_table_id = tool_import.response_value_table_id, .schema_fingerprint = tool_import.response_value_ref_fingerprint },
        .label = "tool-provider-main",
    });
    const entries = [_]world.Linker.Catalog.Entry{
        world.Linker.Catalog.Entry.generatedTarget(.{
            .target_ref = provider_ref,
            .export_descriptor = tool_export,
            .import_set = world.ImportSet.fromTarget(fixtures.Strict.Target),
            .label = "tool-provider",
        }),
    };
    const hint = world.Linker.Hint.init(.{
        .parent_target_ref_fingerprint = root_ref.target_ref_fingerprint,
        .parent_world_port_id = tool_import.world_port_id,
        .provider_target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .provider_export_fingerprint = tool_export.export_fingerprint,
        .route_kind = .target_export,
        .label = "tool-provider",
    });
    var linked = try world.Linker.link(allocator, .{
        .root_target_ref = root_ref,
        .root_import_set = world.ImportSet.fromTarget(fixtures.Agent.Target),
        .root_imports = &.{ decide_import, tool_import },
        .catalog = world.Linker.Catalog.init(&entries),
        .hints = &.{hint},
        .policy = .allow_external_ports,
    });
    defer linked.deinit();

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{};
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();
    try linked.assembly.installIntoRunspace(&runspace);
    const parent_handle = try runspace.installMachineRun(fixtures.Agent.Target, Env, &runtime, Args{ 3, fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    var provider = try providerImage(allocator);
    defer provider.value_image.deinit(allocator);
    const provider_handle = try runspace.installRunImage(provider.image);

    var model_responses: usize = 0;
    while ((try runspace.getSlotSummary(parent_handle)).status != .completed) {
        _ = try runspace.tick();
        const pending_ports = try runspace.mailbox.listPending(allocator);
        defer allocator.free(pending_ports);
        for (pending_ports) |pending| {
            if (pending.world_port_id == DecidePort.world_port_id) {
                model_responses += 1;
                const action: fixtures.Agent.Action = if (model_responses == 1)
                    .{ .tool = "actuate" }
                else
                    .{ .final = "final=actuate skeleton complete" };
                _ = try runspace.respondValue(pending.mailbox_id, action);
            } else if (pending.world_port_id == ToolPort.world_port_id) {
                const invocation = try runspace.routePendingToProviderRun(pending.mailbox_id, linked.plan.fabric_plans[0], provider_handle);
                _ = try runspace.respondFromFabric(invocation);
            }
        }
    }

    try stdout.print("resolved_import_count={d}\n", .{linked.report.resolved_import_count});
    try stdout.print("residual_import_count={d}\n", .{linked.assembly.residualImportSet().required_count});
    try stdout.print("tool_provider_target_ref={x}\n", .{provider_ref.target_ref_fingerprint});
    try stdout.print("native_tool_calls={d}\n", .{ctx.native_tool_calls});
    try stdout.print("final_result=final=actuate skeleton complete\n", .{});
    try stdout.flush();
}
