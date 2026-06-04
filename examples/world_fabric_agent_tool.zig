const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const ToolProvider = struct {
    const semantic = boundary.ir.builder.semantic;
    const compiled = semantic.finish(.{
        .label = "world-fabric-tool-provider",
        .ir_hash = 0x7773_fab0_7001,
        .entry = "run",
        .functions = .{.{
            .symbol_name = "run",
            .params = .{},
            .locals = .{semantic.local("result", []const u8)},
            .result = []const u8,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{semantic.constString("result", "actuate")},
                .terminator = semantic.returnValue("result"),
            }},
        }},
    }) catch |err| @compileError("invalid fabric tool provider fixture: " ++ @errorName(err));

    pub const Program = boundary.program("world-fabric-tool-provider", struct {}, struct {
        pub const compiled_plan = compiled.plan;
    });

    const Closure = Program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    const program_ref = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Program.Evidence.refFor(Program.Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    };
    const closure_graph = Closure.Graph.init("world-fabric-tool-provider-graph", &.{}, &.{}, &.{});
    const closure_report = Closure.Report.init(.{
        .graph_fingerprint = closure_graph.fingerprint,
        .root_program_refs = &.{program_ref},
        .effect_free_root_refs = &.{program_ref},
    });
    const closure_policy = Closure.Policy.auditOnly();
    pub const closure_certificate = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Closure.Certificate.init(closure_report, closure_graph, closure_policy, &.{});
    };
    const elaboration_policy = blk: {
        var policy = Elaboration.Policy.auditOnly();
        policy.closure_policy = closure_policy;
        break :blk policy;
    };
    const elaboration_input = Elaboration.Input{
        .closure_graph = closure_graph,
        .closure_report = closure_report,
        .closure_certificate = closure_certificate,
        .source_program_ref = program_ref,
        .policy = elaboration_policy,
    };
    pub const Target = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Elaboration.Target.compileComptime(.{
            .label = "world-fabric-tool-provider-target",
            .input = elaboration_input,
            .residual_program = Program,
            .policy = Elaboration.Target.Policy.auditOnly(),
        });
    };
};

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
    const provider_ref = world.TargetRef.fromTarget(ToolProvider.Target);
    var value_image = try world.Frame.ValueImage.fromValue(
        allocator,
        4,
        0x5150_fab2,
        null,
        @as([]const u8, "actuate"),
        world.ValuePolicy.portable,
    );
    errdefer value_image.deinit(allocator);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .final_response_fingerprint = 0x5150_fab2,
        .final_value_image_fingerprint = value_image.value_image_fingerprint,
        .status = .completed,
    });
    return .{
        .image = world.RunImage.init(.{
            .kind = .completed_run,
            .target_ref = provider_ref,
            .import_set_fingerprint = world.ImportSet.fromTarget(ToolProvider.Target).import_set_fingerprint,
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

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{};
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();
    const parent_handle = try runspace.installMachineRun(fixtures.Agent.Target, Env, &runtime, Args{ 3, fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });

    var provider = try providerImage(allocator);
    defer provider.value_image.deinit(allocator);
    const provider_handle = try runspace.installRunImage(provider.image);
    const parent_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const provider_ref = world.TargetRef.fromTarget(ToolProvider.Target);
    const mapping = world.Fabric.ValueMapping.init(.{
        .kind = .provider_result_to_parent_response,
        .provider_result_value_table_id = 4,
        .parent_response_value_table_id = 4,
    });
    const route = world.Fabric.Route.init(.{
        .route_id = 0xfab2,
        .kind = .target_export,
        .parent_world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .parent_target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .parent_world_port_id = ToolPort.world_port_id,
        .provider_target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .provider_world_surface_fingerprint = provider_ref.world_surface_fingerprint,
        .provider_target_certificate_fingerprint = provider_ref.target_certificate_fingerprint,
        .value_mapping_fingerprint = mapping.mapping_fingerprint,
        .max_depth = 2,
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
        .max_provider_runs = 1,
    });
    try runspace.installFabricPlan(parent_ref, plan);

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
                const invocation = try runspace.routePendingToProviderRun(pending.mailbox_id, plan, provider_handle);
                _ = try runspace.respondFromFabric(invocation);
            }
        }
    }

    try stdout.print("tool_port_id={d}\n", .{ToolPort.world_port_id});
    try stdout.print("provider_target_ref={x}\n", .{provider_ref.target_ref_fingerprint});
    try stdout.print("fabric_invocation_count={d}\n", .{runspace.report().fabric_invocation_count});
    try stdout.print("native_tool_calls={d}\n", .{ctx.native_tool_calls});
    try stdout.print("final_result=final=actuate skeleton complete\n", .{});
    try stdout.flush();
}
