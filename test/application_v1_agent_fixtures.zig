// zlinter-disable declaration_naming no_inferred_error_unions require_doc_comment
const std = @import("std");
const boundary = @import("boundary");
const world = @import("world");

const application_limits: world.v1.Limits = .{
    .maximum_initial_args_bytes = 64 * 1024,
    .maximum_state_bytes = 256 * 1024,
    .maximum_payload_bytes = 64 * 1024,
    .maximum_result_bytes = 64 * 1024,
    .maximum_host_claim_bytes = 8 * 1024,
    .maximum_host_metadata_bytes = 8 * 1024,
    .maximum_failure_bytes = 8 * 1024,
};

fn skeletonRootPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const goal = boundary.ir.builder.local(root, 0);
    const first_decision = boundary.ir.builder.local(root, 1);
    const tool_result = boundary.ir.builder.local(root, 2);
    const final_decision = boundary.ir.builder.local(root, 3);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, first_decision, boundary.ir.builder.op(root, 0), goal) catch unreachable,
        boundary.ir.builder.callOp(root, tool_result, boundary.ir.builder.op(root, 1), first_decision) catch unreachable,
        boundary.ir.builder.callOp(root, final_decision, boundary.ir.builder.op(root, 0), tool_result) catch unreachable,
        boundary.ir.builder.returnValue(root, final_decision) catch unreachable,
    };
    return stringProgramPlan(
        "world-v1-skeleton-agent",
        0x5101,
        1,
        &.{
            .{ .label = "agent", .first_op = 0, .op_count = 1 },
            .{ .label = "toolbox", .first_op = 1, .op_count = 1 },
        },
        &.{
            stringTransformOp(0, "decide"),
            stringTransformOp(1, "call"),
        },
        4,
        &instructions,
    );
}

fn fixtureRootPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const goal = boundary.ir.builder.local(root, 0);
    const first_decision = boundary.ir.builder.local(root, 1);
    const read_result = boundary.ir.builder.local(root, 2);
    const second_decision = boundary.ir.builder.local(root, 3);
    const write_result = boundary.ir.builder.local(root, 4);
    const final_decision = boundary.ir.builder.local(root, 5);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, first_decision, boundary.ir.builder.op(root, 0), goal) catch unreachable,
        boundary.ir.builder.callOp(root, read_result, boundary.ir.builder.op(root, 1), first_decision) catch unreachable,
        boundary.ir.builder.callOp(root, second_decision, boundary.ir.builder.op(root, 0), read_result) catch unreachable,
        boundary.ir.builder.callOp(root, write_result, boundary.ir.builder.op(root, 2), second_decision) catch unreachable,
        boundary.ir.builder.callOp(root, final_decision, boundary.ir.builder.op(root, 0), write_result) catch unreachable,
        boundary.ir.builder.returnValue(root, final_decision) catch unreachable,
    };
    return stringProgramPlan(
        "world-v1-fixture-agent",
        0x5102,
        1,
        &.{
            .{ .label = "agent", .first_op = 0, .op_count = 1 },
            .{ .label = "toolbox", .first_op = 1, .op_count = 2 },
        },
        &.{
            stringTransformOp(0, "decide"),
            stringTransformOp(1, "read"),
            stringTransformOp(1, "write"),
        },
        6,
        &instructions,
    );
}

fn pureToolboxPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const result = boundary.ir.builder.local(root, 1);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_string, .dst = result.index, .string_literal = "actuate" },
        boundary.ir.builder.returnValue(root, result) catch unreachable,
    };
    return stringProgramPlan("world-v1-skeleton-toolbox", 0x5201, 1, &.{}, &.{}, 2, &instructions);
}

fn fileProviderPlan(comptime label: []const u8, comptime ir_hash: u64, comptime requirement: []const u8, comptime operation: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const result = boundary.ir.builder.local(root, 1);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, result, boundary.ir.builder.op(root, 0), payload) catch unreachable,
        boundary.ir.builder.returnValue(root, result) catch unreachable,
    };
    return stringProgramPlan(
        label,
        ir_hash,
        1,
        &.{.{ .label = requirement, .first_op = 0, .op_count = 1 }},
        &.{stringTransformOp(0, operation)},
        2,
        &instructions,
    );
}

fn stringTransformOp(requirement_index: u32, comptime name: []const u8) boundary.ir.plan.Op {
    return .{
        .requirement_index = requirement_index,
        .op_name = name,
        .mode = .transform,
        .payload_codec = .string,
        .resume_codec = .string,
    };
}

fn stringProgramPlan(
    comptime label: []const u8,
    ir_hash: u64,
    parameter_count: u32,
    requirements: []const boundary.ir.plan.Requirement,
    ops: []const boundary.ir.plan.Op,
    local_count: u32,
    instructions: []const boundary.ir.plan.Instruction,
) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .string,
        .result_codec = .string,
        .parameter_count = parameter_count,
        .first_requirement = 0,
        .requirement_count = @intCast(requirements.len),
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = local_count,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    const locals = [_]boundary.ir.plan.Local{.{ .codec = .string }} ** 8;
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = ir_hash,
        .entry = root,
        .functions = &functions,
        .requirements = requirements,
        .ops = ops,
        .outputs = &.{},
        .locals = locals[0..local_count],
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = instructions,
    }) catch unreachable;
}

const SkeletonRootBody = struct {
    pub const compiled_plan = skeletonRootPlan();
};
const SkeletonRootProgram = boundary.program("world-v1-skeleton-agent", struct {}, SkeletonRootBody);
pub const SkeletonRootMachine = boundary.staticMachine(SkeletonRootProgram, .{ .maximum_state_bytes = application_limits.maximum_state_bytes });
pub const SkeletonModelSite0 = SkeletonRootMachine.EffectRow.operationSite("agent", "decide", 0);
pub const SkeletonModelSite1 = SkeletonRootMachine.EffectRow.operationSite("agent", "decide", 1);
pub const SkeletonToolboxSite = SkeletonRootMachine.EffectRow.operationSite("toolbox", "call", 0);

const PureToolboxBody = struct {
    pub const compiled_plan = pureToolboxPlan();
};
const PureToolboxProgram = boundary.program("world-v1-skeleton-toolbox", struct {}, PureToolboxBody);
pub const PureToolboxMachine = boundary.staticMachine(PureToolboxProgram, .{ .maximum_state_bytes = application_limits.maximum_state_bytes });

pub const SkeletonApp = world.application(.{
    .name = "skeleton-agent",
    .version = "1.0.0",
    .root = SkeletonRootMachine,
    .handlers = .{world.v1.handle(SkeletonToolboxSite, PureToolboxMachine)},
    .external = .{
        world.v1.external(SkeletonModelSite0, .{
            .interface = "agent.model.decide.v1",
            .authority = world.v1.Authority.model,
        }),
        world.v1.external(SkeletonModelSite1, .{
            .interface = "agent.model.decide.v1",
            .authority = world.v1.Authority.model,
        }),
    },
    .limits = application_limits,
});

const FixtureRootBody = struct {
    pub const compiled_plan = fixtureRootPlan();
};
const FixtureRootProgram = boundary.program("world-v1-fixture-agent", struct {}, FixtureRootBody);
pub const FixtureRootMachine = boundary.staticMachine(FixtureRootProgram, .{ .maximum_state_bytes = application_limits.maximum_state_bytes });
pub const FixtureModelSite0 = FixtureRootMachine.EffectRow.operationSite("agent", "decide", 0);
pub const FixtureModelSite1 = FixtureRootMachine.EffectRow.operationSite("agent", "decide", 1);
pub const FixtureModelSite2 = FixtureRootMachine.EffectRow.operationSite("agent", "decide", 2);
pub const FixtureReadSite = FixtureRootMachine.EffectRow.operationSite("toolbox", "read", 0);
pub const FixtureWriteSite = FixtureRootMachine.EffectRow.operationSite("toolbox", "write", 0);

const ReadProviderBody = struct {
    pub const compiled_plan = fileProviderPlan("world-v1-file-read-provider", 0x5202, "file", "read");
};
const ReadProviderProgram = boundary.program("world-v1-file-read-provider", struct {}, ReadProviderBody);
pub const ReadProviderMachine = boundary.staticMachine(ReadProviderProgram, .{ .maximum_state_bytes = application_limits.maximum_state_bytes });
pub const FileReadSite = ReadProviderMachine.EffectRow.operationSite("file", "read", 0);

const WriteProviderBody = struct {
    pub const compiled_plan = fileProviderPlan("world-v1-file-write-provider", 0x5203, "file", "write");
};
const WriteProviderProgram = boundary.program("world-v1-file-write-provider", struct {}, WriteProviderBody);
pub const WriteProviderMachine = boundary.staticMachine(WriteProviderProgram, .{ .maximum_state_bytes = application_limits.maximum_state_bytes });
pub const FileWriteSite = WriteProviderMachine.EffectRow.operationSite("file", "write", 0);

pub const FixtureApp = world.application(.{
    .name = "fixture-agent",
    .version = "1.0.0",
    .root = FixtureRootMachine,
    .handlers = .{
        world.v1.handle(FixtureReadSite, ReadProviderMachine),
        world.v1.handle(FixtureWriteSite, WriteProviderMachine),
    },
    .external = .{
        world.v1.external(FixtureModelSite0, .{
            .interface = "agent.model.decide.v1",
            .authority = world.v1.Authority.model,
        }),
        world.v1.external(FixtureModelSite1, .{
            .interface = "agent.model.decide.v1",
            .authority = world.v1.Authority.model,
        }),
        world.v1.external(FixtureModelSite2, .{
            .interface = "agent.model.decide.v1",
            .authority = world.v1.Authority.model,
        }),
        world.v1.external(FileReadSite, .{
            .interface = "host.file.read.v1",
            .authority = world.v1.Authority.file_read,
        }),
        world.v1.external(FileWriteSite, .{
            .interface = "host.file.write.v1",
            .authority = world.v1.Authority.file_write,
        }),
    },
    .limits = application_limits,
});

pub const WasmOptions: world.v1.WasmOptions = .{
    .input_capacity = 2 * 1024 * 1024,
    .output_capacity = 2 * 1024 * 1024,
    .scratch_capacity = 8 * 1024 * 1024,
};

fn continueWithString(
    comptime App: type,
    comptime Site: type,
    arena: *std.heap.ArenaAllocator,
    parent: world.v1.Frame,
    value: []const u8,
) !world.v1.Frame {
    const allocator = arena.allocator();
    const result_bytes = try App.encodeExternalResult(allocator, Site, value);
    var result: world.v1.EffectResult = .{
        .request_id = parent.pending_effect.?.request_id,
        .status = .ok,
        .result_schema_id = parent.pending_effect.?.result_schema_id,
        .result_bytes = result_bytes,
        .attempt = 1,
    };
    try result.seal(allocator, App.Limits);
    const parent_bytes = try App.encodeFrame(allocator, parent);
    return App.step(arena, .{
        .application_id = App.Manifest.application_id,
        .expected_parent_frame_id = parent.frame_id,
        .prior_frame_bytes = parent_bytes,
        .effect_result = result,
        .fuel = 100,
    });
}

fn expectStringPayload(allocator: std.mem.Allocator, frame: world.v1.Frame, expected: []const u8) !void {
    const encoded = try world.v1.encodeValue(allocator, expected);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, encoded, frame.pending_effect.?.payload_bytes);
}

test "skeleton application closes toolbox and completes through two model effects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try std.testing.expectEqual(@as(usize, 1), SkeletonApp.internal_handler_ids.len);
    try std.testing.expectEqual(@as(usize, 2), SkeletonApp.residual_effect_row.len);
    for (SkeletonApp.residual_effect_row) |effect| {
        try std.testing.expect(effect.site_id != SkeletonToolboxSite.canonical_fingerprint);
    }
    const args = try SkeletonApp.encodeInitialArgs(allocator, .{@as([]const u8, "goal=invoke")});

    const first = try SkeletonApp.initialFrame(&arena, args, 100);
    try std.testing.expectEqual(SkeletonModelSite0.canonical_fingerprint, first.pending_effect.?.site_id);
    try expectStringPayload(allocator, first, "goal=invoke");

    const second = try continueWithString(SkeletonApp, SkeletonModelSite0, &arena, first, "actuate");
    try std.testing.expectEqual(SkeletonModelSite1.canonical_fingerprint, second.pending_effect.?.site_id);
    try expectStringPayload(allocator, second, "actuate");
    try std.testing.expectEqual(@as(u64, 1), second.resource_counters.internal_handler_calls);

    const completed = try continueWithString(SkeletonApp, SkeletonModelSite1, &arena, second, "final=actuate skeleton complete");
    try std.testing.expectEqual(world.v1.FrameStatus.completed, completed.status);
    var result = try SkeletonApp.decodeFinalResult(allocator, completed);
    defer result.deinit();
    try std.testing.expectEqualStrings("final=actuate skeleton complete", result.value);
}

test "fixture application exposes model read write model sequence through static providers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try std.testing.expectEqual(@as(usize, 2), FixtureApp.internal_handler_ids.len);
    try std.testing.expectEqual(@as(usize, 5), FixtureApp.residual_effect_row.len);
    for (FixtureApp.residual_effect_row) |effect| {
        try std.testing.expect(effect.site_id != FixtureReadSite.canonical_fingerprint);
        try std.testing.expect(effect.site_id != FixtureWriteSite.canonical_fingerprint);
    }
    const args = try FixtureApp.encodeInitialArgs(allocator, .{@as([]const u8, "goal=fixture")});

    const frame0 = try FixtureApp.initialFrame(&arena, args, 100);
    try std.testing.expectEqual(FixtureModelSite0.canonical_fingerprint, frame0.pending_effect.?.site_id);

    const frame1 = try continueWithString(FixtureApp, FixtureModelSite0, &arena, frame0, "fixture-input.txt");
    try std.testing.expectEqual(FileReadSite.canonical_fingerprint, frame1.pending_effect.?.site_id);
    try expectStringPayload(allocator, frame1, "fixture-input.txt");

    const frame2 = try continueWithString(FixtureApp, FileReadSite, &arena, frame1, "rewrite this file through the agent loop\n");
    try std.testing.expectEqual(FixtureModelSite1.canonical_fingerprint, frame2.pending_effect.?.site_id);
    try expectStringPayload(allocator, frame2, "rewrite this file through the agent loop\n");

    const frame3 = try continueWithString(FixtureApp, FixtureModelSite1, &arena, frame2, "fixture-output.txt\nactuate updated the fixture");
    try std.testing.expectEqual(FileWriteSite.canonical_fingerprint, frame3.pending_effect.?.site_id);
    try expectStringPayload(allocator, frame3, "fixture-output.txt\nactuate updated the fixture");

    const frame4 = try continueWithString(FixtureApp, FileWriteSite, &arena, frame3, "write=ok");
    try std.testing.expectEqual(FixtureModelSite2.canonical_fingerprint, frame4.pending_effect.?.site_id);
    try expectStringPayload(allocator, frame4, "write=ok");

    const completed = try continueWithString(FixtureApp, FixtureModelSite2, &arena, frame4, "final=fixture updated");
    try std.testing.expectEqual(world.v1.FrameStatus.completed, completed.status);
    var result = try FixtureApp.decodeFinalResult(allocator, completed);
    defer result.deinit();
    try std.testing.expectEqualStrings("final=fixture updated", result.value);
    try std.testing.expectEqual(@as(u64, 2), completed.resource_counters.internal_handler_calls);
}
