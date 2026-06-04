const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const StringProvider = struct {
    pub const Handlers = struct {};
    const semantic = boundary.ir.builder.semantic;
    const ProviderProtocol = boundary.ir.schema.Protocol(.{
        .label = "fabric_provider",
        .ops = .{boundary.ir.schema.transform("provide", []const u8, []const u8)},
    });
    const Rows = ProviderProtocol.Rows(Handlers, .{ .requirement_index = 0, .first_op = 0 });
    const ProvideOp = Rows.op("provide");

    const compiled = semantic.finish(.{
        .label = "world-fabric-nested-provider",
        .ir_hash = 0x7773_fab3_0001,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{ semantic.local("payload", []const u8), semantic.local("result", []const u8) },
            .result = []const u8,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    semantic.constString("payload", "actuate"),
                    semantic.call(ProvideOp, .{ .dst = "result", .payload = "payload", .label = "fabric.provider.provide" }),
                },
                .terminator = semantic.returnValue("result"),
            }},
        }},
    }) catch |err| @compileError("invalid fabric nested provider fixture: " ++ @errorName(err));

    pub const Program = boundary.program("world-fabric-nested-provider", Handlers, struct {
        pub const site_metadata = compiled.site_metadata;
        pub const compiled_plan = compiled.plan;
    });
    pub const Provide = Program.protocol.operationSite("fabric_provider", "provide", 0);

    const Closure = Program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    const program_ref = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Program.Evidence.refFor(Program.Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    };
    const source_shape = Closure.EffectShape.init(.{
        .program_label = Program.contract.label,
        .plan_hash = Program.compiled_plan.hash(),
        .kind = .operation,
        .site_index = Provide.index,
        .protocol_label = "fabric_provider",
        .protocol_op_fingerprint = Provide.fingerprint,
    });
    const intrinsic_ref = Program.Evidence.refFor(Program.Evidence.domains.host_intrinsic, 0x7773_fab3, .{ .label = "fabric-provider-host" });
    const static_plan = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Closure.StaticTreatyPlan.init(.{
            .label = "fabric.provider.provide",
            .source_shape = source_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = intrinsic_ref,
            .host_intrinsic = true,
        });
    };
    const port = Closure.WorldPort.init(.{
        .label = "fabric.provider",
        .kind = .host_tool,
        .effect_shape_ref = source_shape.evidenceRef(),
        .exposed_intrinsic_ref = intrinsic_ref,
        .supported_protocol_labels = &.{"fabric_provider"},
        .supported_site_indexes = &.{Provide.index},
        .supported_protocol_op_fingerprints = &.{Provide.fingerprint},
    });
    const closure_graph = Closure.Graph.init("world-fabric-nested-provider-graph", &.{}, &.{}, &.{});
    const closure_report = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Closure.Report.init(.{
            .graph_fingerprint = closure_graph.fingerprint,
            .root_program_refs = &.{program_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{port.evidenceRef()},
            .open_world_port_count = 1,
        });
    };
    const closure_policy = Closure.Policy.auditOnly();
    pub const closure_certificate = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Closure.Certificate.init(closure_report, closure_graph, closure_policy, &.{static_plan.evidenceRef()});
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
        .static_treaty_plans = &.{static_plan},
        .source_program_ref = program_ref,
        .world_ports = &.{port},
        .policy = elaboration_policy,
    };
    pub const Target = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Elaboration.Target.compileComptime(.{
            .label = "world-fabric-nested-provider-target",
            .input = elaboration_input,
            .residual_program = Program,
            .policy = Elaboration.Target.Policy.auditOnly(),
        });
    };
};

const Ctx = struct {};

fn decide(_: *Ctx, _: []const u8) !fixtures.Agent.Action {
    return error.ManualOnly;
}

fn tool(_: *Ctx, _: []const u8) ![]const u8 {
    return error.ManualOnly;
}

fn provide(_: *Ctx, _: []const u8) ![]const u8 {
    return error.ManualOnly;
}

const DecidePort = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decide);
const ToolPort = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, tool);
const ProviderPort = world.port(StringProvider.Target, StringProvider.Provide, provide);
const Env = world.Environment(fixtures.Agent.Target, .{
    .bindings = .{
        world.bind(DecidePort, world.NativeAdapter(decide)),
        world.bind(ToolPort, world.NativeAdapter(tool)),
    },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const ProviderEnv = world.Environment(StringProvider.Target, .{
    .bindings = .{world.bind(ProviderPort, world.NativeAdapter(provide))},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const Args = struct { usize, []const u8 };

fn completedProviderImage(allocator: std.mem.Allocator, value: []const u8) !struct {
    image: world.RunImage,
    value_image: world.Frame.ValueImage,
} {
    const provider_ref = world.TargetRef.fromTarget(StringProvider.Target);
    var value_image = try world.Frame.ValueImage.fromValue(allocator, 1, 0x5150_fab3, null, value, world.ValuePolicy.portable);
    errdefer value_image.deinit(allocator);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .final_response_fingerprint = 0x5150_fab3,
        .final_value_image_fingerprint = value_image.value_image_fingerprint,
        .status = .completed,
    });
    return .{
        .image = world.RunImage.init(.{
            .kind = .completed_run,
            .target_ref = provider_ref,
            .import_set_fingerprint = world.ImportSet.fromTarget(StringProvider.Target).import_set_fingerprint,
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
    var provider_transcript = world.Transcript.init(allocator);
    defer provider_transcript.deinit();
    const parent_handle = try runspace.installMachineRun(fixtures.Agent.Target, Env, &runtime, Args{ 3, fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    const provider_handle = try runspace.installMachineRun(StringProvider.Target, ProviderEnv, &runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &provider_transcript,
    });
    const parent_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const mapping = world.Fabric.ValueMapping.init(.{
        .kind = .provider_result_to_parent_response,
        .provider_result_value_table_id = 1,
        .parent_response_value_table_id = 1,
    });
    const route = world.Fabric.Route.init(.{
        .route_id = 0xfab3,
        .kind = .target_export,
        .parent_world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .parent_target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .parent_world_port_id = ToolPort.world_port_id,
        .provider_target_ref_fingerprint = world.TargetRef.fromTarget(StringProvider.Target).target_ref_fingerprint,
        .provider_world_surface_fingerprint = world.TargetRef.fromTarget(StringProvider.Target).world_surface_fingerprint,
        .provider_target_certificate_fingerprint = world.TargetRef.fromTarget(StringProvider.Target).target_certificate_fingerprint,
        .value_mapping_fingerprint = mapping.mapping_fingerprint,
        .max_depth = 2,
        .metadata = "nested agent provider",
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
    var saved_invocation: ?world.Fabric.Invocation = null;

    var parent_decisions: usize = 0;
    var provider_result: []const u8 = "";
    var routed_to_provider = false;
    while ((try runspace.getSlotSummary(parent_handle)).status != .completed) {
        _ = try runspace.tick();
        const pending_ports = try runspace.mailbox.listPending(allocator);
        defer allocator.free(pending_ports);
        for (pending_ports) |pending| {
            if (pending.handle.handle_fingerprint == provider_handle.handle_fingerprint and pending.world_port_id == ProviderPort.world_port_id) {
                if (routed_to_provider) {
                    _ = try runspace.respondValue(pending.mailbox_id, @as([]const u8, "actuate"));
                    provider_result = "actuate";
                }
            } else if (pending.world_port_id == DecidePort.world_port_id) {
                parent_decisions += 1;
                const action: fixtures.Agent.Action = if (parent_decisions == 1)
                    .{ .tool = "actuate" }
                else
                    .{ .final = "final=actuate skeleton complete" };
                _ = try runspace.respondValue(pending.mailbox_id, action);
            } else if (pending.world_port_id == ToolPort.world_port_id and saved_invocation == null) {
                const invocation = try runspace.routePendingToProviderRun(pending.mailbox_id, plan, provider_handle);
                saved_invocation = invocation;
                routed_to_provider = true;
            }
        }
        if (saved_invocation) |invocation| {
            if ((try runspace.getSlotSummary(provider_handle)).status == .completed and runspace.report().pending_port_count == 1) {
                var completed_provider = try completedProviderImage(allocator, provider_result);
                defer completed_provider.value_image.deinit(allocator);
                const completed_provider_handle = try runspace.installRunImage(completed_provider.image);
                const completed_invocation = world.Fabric.Invocation.init(.{
                    .plan_fingerprint = invocation.plan_fingerprint,
                    .route_fingerprint = invocation.route_fingerprint,
                    .parent_run_handle_fingerprint = invocation.parent_run_handle_fingerprint,
                    .parent_pending_port_fingerprint = invocation.parent_pending_port_fingerprint,
                    .parent_mailbox_id = invocation.parent_mailbox_id,
                    .request_frame_fingerprint = invocation.request_frame_fingerprint,
                    .provider_run_handle_fingerprint = completed_provider_handle.handle_fingerprint,
                    .run_permit_fingerprint = invocation.run_permit_fingerprint,
                    .depth = invocation.depth,
                    .sequence = invocation.sequence,
                    .status = .provider_completed,
                });
                _ = try runspace.respondFromFabric(completed_invocation);
                saved_invocation = null;
            }
        }
    }

    try stdout.print("fabric_depth={d}\n", .{runspace.fabric_invocations.items[0].depth});
    try stdout.print("parent_result=final=actuate skeleton complete\n", .{});
    try stdout.print("provider_result={s}\n", .{provider_result});
    try stdout.flush();
}
