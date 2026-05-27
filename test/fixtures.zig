// zlinter-disable declaration_naming field_ordering require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

pub const Strict = struct {
    const semantic = boundary.ir.builder.semantic;

    const compiled = semantic.finish(.{
        .label = "world-strict-residual",
        .ir_hash = 0x7773_7472_6963_7402,
        .entry = "run",
        .functions = .{.{
            .symbol_name = "run",
            .params = .{},
            .locals = .{semantic.local("decision", i32)},
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{semantic.constI32("decision", 1)},
                .terminator = semantic.returnValue("decision"),
            }},
        }},
    }) catch |err| @compileError("invalid strict fixture: " ++ @errorName(err));

    pub const Program = boundary.program("world-strict-residual", struct {}, struct {
        pub const compiled_plan = compiled.plan;
    });

    const Closure = Program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    const program_ref = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Program.Evidence.refFor(Program.Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    };
    const closure_graph = Closure.Graph.init("world-strict-graph", &.{}, &.{}, &.{});
    const closure_report = Closure.Report.init(.{
        .graph_fingerprint = closure_graph.fingerprint,
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
            .label = "world-strict-target",
            .input = elaboration_input,
            .residual_program = Program,
            .policy = Elaboration.Target.Policy.auditOnly(),
        });
    };
};

pub const Ports = struct {
    pub const Handlers = struct {};
    const semantic = boundary.ir.builder.semantic;
    const ApprovalProtocol = boundary.ir.schema.Protocol(.{
        .label = "approval",
        .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
    });
    const Rows = ApprovalProtocol.Rows(Handlers, .{ .requirement_index = 0, .first_op = 0 });
    const RequestOp = Rows.op("request");

    const compiled = semantic.finish(.{
        .label = "world-ports-residual",
        .ir_hash = 0x7773_706f_7274_0001,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{ semantic.local("payload", []const u8), semantic.local("decision", i32) },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    semantic.constString("payload", "deploy-prod"),
                    semantic.call(RequestOp, .{ .dst = "decision", .payload = "payload", .label = "approval.request.world" }),
                },
                .terminator = semantic.returnValue("decision"),
            }},
        }},
    }) catch |err| @compileError("invalid ports fixture: " ++ @errorName(err));

    pub const Program = boundary.program("world-ports-residual", Handlers, struct {
        pub const site_metadata = compiled.site_metadata;
        pub const compiled_plan = compiled.plan;
    });
    pub const ApprovalRequest = Program.protocol.operationSite("approval", "request", 0);

    const Closure = Program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    const program_ref = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Program.Evidence.refFor(Program.Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    };
    pub const source_shape = Closure.EffectShape.init(.{
        .program_label = Program.contract.label,
        .plan_hash = Program.compiled_plan.hash(),
        .kind = .operation,
        .site_index = ApprovalRequest.index,
        .protocol_label = "approval",
        .protocol_op_fingerprint = ApprovalRequest.fingerprint,
    });
    const intrinsic_ref = Program.Evidence.refFor(Program.Evidence.domains.host_intrinsic, 0x7773_9001, .{ .label = "human-approval-host" });
    const static_plan = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Closure.StaticTreatyPlan.init(.{
            .label = "approval.request.world",
            .source_shape = source_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = intrinsic_ref,
            .host_intrinsic = true,
        });
    };
    const port = Closure.WorldPort.init(.{
        .label = "human-approval-port",
        .kind = .host_human,
        .effect_shape_ref = source_shape.evidenceRef(),
        .exposed_intrinsic_ref = intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{ApprovalRequest.index},
        .supported_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
    });
    const closure_graph = Closure.Graph.init("world-ports-graph", &.{}, &.{}, &.{});
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
            .label = "world-ports-target",
            .input = elaboration_input,
            .residual_program = Program,
            .policy = Elaboration.Target.Policy.auditOnly(),
        });
    };
};

pub const Agent = struct {
    pub const Action = union(enum) {
        final: []const u8,
        tool: []const u8,
    };

    pub const Scenario = enum {
        fixture,
        skeleton,
    };

    pub const RunRecord = struct {
        event_count: usize = 0,
        tool_calls: usize = 0,
    };

    pub const fixture_dir = "zig-cache/world-agent-loop-fixtures";
    pub const fixture_input_path = fixture_dir ++ "/input.txt";
    pub const fixture_output_path = fixture_dir ++ "/output.txt";
    pub const fixture_input_contents = "rewrite this file through the agent loop\n";
    pub const fixture_observation = "rewrite this file through the agent loop";
    pub const fixture_write_contents = "actuate updated the fixture";
    pub const fixture_read_command = "read:" ++ fixture_input_path;
    pub const fixture_write_command = "write:" ++ fixture_output_path ++ "=" ++ fixture_write_contents;

    pub const Handlers = struct {};
    const semantic = boundary.ir.builder.semantic;
    const Schemas = boundary.ir.schema.Registry(.{Action});
    const AgentProtocol = boundary.ir.schema.Protocol(.{
        .label = "agent",
        .ops = .{boundary.ir.schema.transform("decide", []const u8, Action)},
    });
    const ToolProtocol = boundary.ir.schema.Protocol(.{
        .label = "tool",
        .ops = .{boundary.ir.schema.transform("call", []const u8, []const u8)},
    });
    const AgentRows = AgentProtocol.Rows(Handlers, .{
        .requirement_index = 0,
        .first_op = 0,
        .schema_refs = Schemas.schema_refs,
    });
    const ToolRows = ToolProtocol.Rows(Handlers, .{
        .requirement_index = 1,
        .first_op = AgentRows.op_count,
        .schema_refs = Schemas.schema_refs,
    });
    const requirements = [_]boundary.ir.plan.Requirement{ AgentRows.requirement, ToolRows.requirement };
    const ops = AgentRows.ops ++ ToolRows.ops;
    const DecideOp = AgentRows.op("decide");
    const ToolOp = ToolRows.op("call");

    const compiled = semantic.finish(.{
        .label = "world-agent-residual",
        .ir_hash = 0x7770_6167_656e_7401,
        .entry = "agent",
        .schemas = Schemas,
        .requirements = &requirements,
        .ops = &ops,
        .functions = .{.{
            .symbol_name = "agent",
            .requirements = semantic.span(0, requirements.len),
            .params = .{
                semantic.param("remaining", usize),
                semantic.param("observation", []const u8),
            },
            .locals = .{
                semantic.local("budget_empty", bool),
                semantic.local("action", Action),
                semantic.local("is_final", bool),
                semantic.local("answer", []const u8),
                semantic.local("tool_name", []const u8),
            },
            .result = []const u8,
            .blocks = .{
                .{
                    .name = "entry",
                    .instructions = .{semantic.compareEqZero("budget_empty", "remaining")},
                    .terminator = semantic.branchIf("budget_empty", .{ .then = "exhausted", .@"else" = "decide" }),
                },
                .{
                    .name = "decide",
                    .instructions = .{
                        semantic.call(DecideOp, .{ .dst = "action", .payload = "observation", .label = "agent.decide" }),
                        semantic.sumVariantIs("is_final", "action", 0),
                    },
                    .terminator = semantic.branchIf("is_final", .{ .then = "final", .@"else" = "tool" }),
                },
                .{
                    .name = "final",
                    .instructions = .{semantic.sumExtractPayload("answer", "action", 0)},
                    .terminator = semantic.returnValue("answer"),
                },
                .{
                    .name = "tool",
                    .instructions = .{
                        semantic.sumExtractPayload("tool_name", "action", 1),
                        semantic.call(ToolOp, .{ .dst = "observation", .payload = "tool_name", .label = "agent.tool" }),
                        semantic.subOne("remaining", "remaining"),
                    },
                    .terminator = semantic.jump("entry"),
                },
                .{
                    .name = "exhausted",
                    .instructions = .{semantic.constString("answer", "budget exhausted")},
                    .terminator = semantic.returnValue("answer"),
                },
            },
        }},
    }) catch |err| @compileError("invalid agent fixture: " ++ @errorName(err));

    pub const Program = boundary.program("world-agent-residual", Handlers, struct {
        pub const value_schema_types = Schemas.value_schema_types;
        pub const site_metadata = compiled.site_metadata;
        pub const compiled_plan = compiled.plan;
    });
    pub const Decide = Program.protocol.operationSite("agent", "decide", 0);
    pub const Tool = Program.protocol.operationSite("tool", "call", 0);

    const Closure = Program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    const program_ref = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Program.Evidence.refFor(Program.Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    };
    const plan_hash = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Program.compiled_plan.hash();
    };
    const decide_shape = Closure.EffectShape.init(.{
        .program_label = Program.contract.label,
        .plan_hash = plan_hash,
        .kind = .operation,
        .site_index = Decide.index,
        .protocol_label = "agent",
        .protocol_op_fingerprint = Decide.fingerprint,
    });
    const tool_shape = Closure.EffectShape.init(.{
        .program_label = Program.contract.label,
        .plan_hash = plan_hash,
        .kind = .operation,
        .site_index = Tool.index,
        .protocol_label = "tool",
        .protocol_op_fingerprint = Tool.fingerprint,
    });
    const model_intrinsic_ref = Program.Evidence.refFor(Program.Evidence.domains.host_intrinsic, 0x7773_a001, .{ .label = "model-decide-host" });
    const tool_intrinsic_ref = Program.Evidence.refFor(Program.Evidence.domains.host_intrinsic, 0x7773_a002, .{ .label = "tool-call-host" });
    const decide_plan = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Closure.StaticTreatyPlan.init(.{
            .label = "agent.decide.world",
            .source_shape = decide_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = model_intrinsic_ref,
            .host_intrinsic = true,
        });
    };
    const tool_plan = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Closure.StaticTreatyPlan.init(.{
            .label = "tool.call.world",
            .source_shape = tool_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = tool_intrinsic_ref,
            .host_intrinsic = true,
        });
    };
    const decide_port = Closure.WorldPort.init(.{
        .label = "model.decide",
        .kind = .host_model,
        .effect_shape_ref = decide_shape.evidenceRef(),
        .exposed_intrinsic_ref = model_intrinsic_ref,
        .supported_protocol_labels = &.{"agent"},
        .supported_site_indexes = &.{Decide.index},
        .supported_protocol_op_fingerprints = &.{Decide.fingerprint},
    });
    const tool_port = Closure.WorldPort.init(.{
        .label = "tool.call",
        .kind = .host_tool,
        .effect_shape_ref = tool_shape.evidenceRef(),
        .exposed_intrinsic_ref = tool_intrinsic_ref,
        .supported_protocol_labels = &.{"tool"},
        .supported_site_indexes = &.{Tool.index},
        .supported_protocol_op_fingerprints = &.{Tool.fingerprint},
    });
    const closure_graph = Closure.Graph.init("world-agent-graph", &.{}, &.{}, &.{});
    const closure_report = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Closure.Report.init(.{
            .graph_fingerprint = closure_graph.fingerprint,
            .root_program_refs = &.{program_ref},
            .effect_shape_count = 2,
            .world_port_refs = &.{ decide_port.evidenceRef(), tool_port.evidenceRef() },
            .open_world_port_count = 2,
        });
    };
    const closure_policy = Closure.Policy.auditOnly();
    pub const closure_certificate = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Closure.Certificate.init(closure_report, closure_graph, closure_policy, &.{ decide_plan.evidenceRef(), tool_plan.evidenceRef() });
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
        .static_treaty_plans = &.{ decide_plan, tool_plan },
        .source_program_ref = program_ref,
        .world_ports = &.{ decide_port, tool_port },
        .policy = elaboration_policy,
    };
    pub const Target = blk: {
        @setEvalBranchQuota(2_000_000);
        break :blk Elaboration.Target.compileComptime(.{
            .label = "world-agent-target",
            .input = elaboration_input,
            .residual_program = Program,
            .policy = Elaboration.Target.Policy.auditOnly(),
        });
    };

    pub fn initialObservation(scenario: Scenario) []const u8 {
        return switch (scenario) {
            .skeleton => "goal=invoke",
            .fixture => "goal=fixture",
        };
    }

    pub fn expectedFinalText(scenario: Scenario) []const u8 {
        return switch (scenario) {
            .skeleton => "final=actuate skeleton complete",
            .fixture => "final=fixture updated",
        };
    }

    pub fn expectedResponseCount(scenario: Scenario) usize {
        return switch (scenario) {
            .skeleton => 3,
            .fixture => 5,
        };
    }

    pub fn decideAction(scenario: Scenario, observation: []const u8) Action {
        return switch (scenario) {
            .skeleton => if (std.mem.eql(u8, observation, "goal=invoke"))
                .{ .tool = "actuate" }
            else if (std.mem.eql(u8, observation, "actuate"))
                .{ .final = "final=actuate skeleton complete" }
            else
                .{ .final = "final=unexpected-tool-output" },
            .fixture => if (std.mem.eql(u8, observation, "goal=fixture"))
                .{ .tool = fixture_read_command }
            else if (std.mem.eql(u8, observation, fixture_observation))
                .{ .tool = fixture_write_command }
            else if (std.mem.eql(u8, observation, "write=ok"))
                .{ .final = "final=fixture updated" }
            else
                .{ .final = "final=fixture update failed" },
        };
    }

    pub fn prepareFixtureWorkspace() !void {
        const io = std.Io.Threaded.global_single_threaded.io();
        try std.Io.Dir.cwd().createDirPath(io, fixture_dir);
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = fixture_input_path,
            .data = fixture_input_contents,
        });
        std.Io.Dir.cwd().deleteFile(io, fixture_output_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }

    pub fn callTool(allocator: std.mem.Allocator, scenario: Scenario, command: []const u8) ![]const u8 {
        switch (scenario) {
            .skeleton => return if (std.mem.eql(u8, command, "actuate")) "actuate" else "tool=unsupported",
            .fixture => {
                const io = std.Io.Threaded.global_single_threaded.io();
                if (std.mem.startsWith(u8, command, "read:")) {
                    const path = command["read:".len..];
                    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024));
                    defer allocator.free(bytes);
                    const trimmed = std.mem.trim(u8, bytes, "\r\n");
                    if (!std.mem.eql(u8, trimmed, fixture_observation)) return error.UnexpectedFixtureInput;
                    return fixture_observation;
                }
                if (std.mem.startsWith(u8, command, "write:")) {
                    const payload = command["write:".len..];
                    const split = std.mem.findScalar(u8, payload, '=') orelse return "write=invalid";
                    try std.Io.Dir.cwd().writeFile(io, .{
                        .sub_path = payload[0..split],
                        .data = payload[split + 1 ..],
                    });
                    return "write=ok";
                }
                return "tool=unsupported";
            },
        }
    }
};
