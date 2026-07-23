// zlinter-disable declaration_naming no_inferred_error_unions require_doc_comment
const std = @import("std");
const boundary = @import("boundary");
const world = @import("world");

fn rootEffectPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const resumed = boundary.ir.builder.local(root, 1);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_string, .dst = payload.index, .string_literal = "payload" },
        boundary.ir.builder.callOp(root, resumed, boundary.ir.builder.op(root, 0), payload) catch unreachable,
        boundary.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "root",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "decide",
        .mode = .transform,
        .payload_codec = .string,
        .resume_codec = .i32,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

pub fn providerEffectPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const resumed = boundary.ir.builder.local(root, 1);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, resumed, boundary.ir.builder.op(root, 0), payload) catch unreachable,
        boundary.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "provide",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{
        .label = "provider",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "external",
        .mode = .transform,
        .payload_codec = .string,
        .resume_codec = .i32,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 2,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const RootBody = struct {
    pub const compiled_plan = rootEffectPlan("world-v1-root");
};
const RootProgram = boundary.program("world-v1-root", struct {}, RootBody);
const machine_state_limit = 16 * 1024;
pub const RootMachine = boundary.staticMachine(RootProgram, .{
    .maximum_state_bytes = machine_state_limit,
});
pub const RootSite = RootMachine.EffectRow.operationSite("root", "decide", 0);

const ProviderBody = struct {
    pub const compiled_plan = providerEffectPlan("world-v1-provider");
};
const ProviderProgram = boundary.program("world-v1-provider", struct {}, ProviderBody);
pub const ProviderMachine = boundary.staticMachine(ProviderProgram, .{
    .maximum_state_bytes = machine_state_limit,
});
pub const ProviderSite = ProviderMachine.EffectRow.operationSite("provider", "external", 0);

pub const OneEffectApp = world.v1.application(.{
    .name = "one-effect",
    .version = "1.0.0",
    .root = RootMachine,
    .limits = .{
        .maximum_initial_args_bytes = 64 * 1024,
        .maximum_state_bytes = 64 * 1024,
        .maximum_payload_bytes = 64 * 1024,
        .maximum_result_bytes = 64 * 1024,
        .maximum_host_claim_bytes = 8 * 1024,
        .maximum_host_metadata_bytes = 8 * 1024,
        .maximum_failure_bytes = 8 * 1024,
    },
    .external = .{world.v1.external(RootSite, .{
        .interface = "test.one-effect.v1",
        .authority = world.v1.Authority.model,
    })},
});

pub const ProviderApp = world.v1.application(.{
    .name = "provider-parked",
    .version = "1.0.0",
    .root = RootMachine,
    .limits = .{
        .maximum_initial_args_bytes = 64 * 1024,
        .maximum_state_bytes = 64 * 1024,
        .maximum_payload_bytes = 64 * 1024,
        .maximum_result_bytes = 64 * 1024,
        .maximum_host_claim_bytes = 8 * 1024,
        .maximum_host_metadata_bytes = 8 * 1024,
        .maximum_failure_bytes = 8 * 1024,
    },
    .handlers = .{world.v1.handle(RootSite, ProviderMachine)},
    .external = .{world.v1.external(ProviderSite, .{
        .interface = "test.provider-external.v1",
        .authority_requirements = @as(u64, 1) << @intFromEnum(world.v1.Authority.file_read),
    })},
});

pub const DeferredApp = world.v1.application(.{
    .name = "deferred-effect",
    .version = "1.0.0",
    .root = RootMachine,
    .limits = OneEffectApp.Limits,
    .external = .{world.v1.external(RootSite, .{
        .interface = "test.deferred-effect.v1",
        .allowed_statuses = world.v1.AllowedStatuses{ .deferred = true },
    })},
});

pub const TightResultApp = world.v1.application(.{
    .name = "tight-result",
    .version = "1.0.0",
    .root = RootMachine,
    .limits = OneEffectApp.Limits,
    .external = .{world.v1.external(RootSite, .{
        .interface = "test.tight-result.v1",
        .maximum_result_bytes = 7,
    })},
});

const SumTagA = enum(u8) {
    left = 0,
    right = 1,
};
const SumA = union(SumTagA) {
    left: i32,
    right: bool,
};
const SumTagB = enum(u8) {
    left = 1,
    right = 2,
};
const SumB = union(SumTagB) {
    left: i32,
    right: bool,
};

fn okResult(
    comptime App: type,
    comptime Site: type,
    allocator: std.mem.Allocator,
    request: world.v1.EffectRequest,
    value: anytype,
) !world.v1.EffectResult {
    const bytes = try App.encodeExternalResult(allocator, Site, value);
    var result: world.v1.EffectResult = .{
        .request_id = request.request_id,
        .status = .ok,
        .result_schema_id = request.result_schema_id,
        .result_bytes = bytes,
        .attempt = 1,
    };
    try result.seal(allocator, App.Limits);
    return result;
}

test "World comptime application derives one exact residual effect row" {
    try std.testing.expectEqual(@as(usize, 0), OneEffectApp.internal_handler_ids.len);
    try std.testing.expectEqual(@as(usize, 1), OneEffectApp.residual_effect_row.len);
    try std.testing.expectEqual(RootSite.canonical_fingerprint, OneEffectApp.residual_effect_row[0].site_id);
    try std.testing.expectEqual(
        @as(u64, 1) << @intFromEnum(world.v1.Authority.model),
        OneEffectApp.Manifest.required_host_capabilities,
    );
    try std.testing.expectEqualStrings(
        boundary.Protocol.Manifest.boundary_package_version,
        OneEffectApp.Manifest.boundary_package_version,
    );
    try OneEffectApp.Manifest.validate();
    try std.testing.expect(ProviderApp.maximum_encoded_runtime_state_bytes <= ProviderApp.Limits.maximum_state_bytes);
}

test "World value schema identity binds tagged-union discriminants" {
    try std.testing.expect(!std.mem.eql(
        u8,
        &world.v1.valueSchemaId(SumA),
        &world.v1.valueSchemaId(SumB),
    ));
}

test "World external value encoder enforces its binding result limit" {
    try std.testing.expectError(
        error.LimitExceeded,
        TightResultApp.encodeExternalResult(std.testing.allocator, RootSite, @as(i32, 41)),
    );
}

test "World deferred result preserves the exact outstanding request and Frame" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try DeferredApp.encodeInitialArgs(allocator, .{});
    const parent = try DeferredApp.initialFrame(&arena, args, 100);
    const parent_bytes = try DeferredApp.encodeFrame(allocator, parent);

    var deferred: world.v1.EffectResult = .{
        .request_id = parent.pending_effect.?.request_id,
        .status = .deferred,
        .result_schema_id = parent.pending_effect.?.result_schema_id,
        .attempt = 1,
    };
    try deferred.seal(allocator, DeferredApp.Limits);
    const parked = try DeferredApp.step(&arena, .{
        .application_id = DeferredApp.Manifest.application_id,
        .expected_parent_frame_id = parent.frame_id,
        .prior_frame_bytes = parent_bytes,
        .effect_result = deferred,
        .fuel = 100,
    });
    const parked_bytes = try DeferredApp.encodeFrame(allocator, parked);

    try std.testing.expectEqualSlices(u8, parent_bytes, parked_bytes);
    try std.testing.expectEqualSlices(
        u8,
        &parent.pending_effect.?.request_id,
        &parked.pending_effect.?.request_id,
    );
    try std.testing.expectEqualSlices(
        u8,
        &parent.pending_effect.?.idempotency_key,
        &parked.pending_effect.?.idempotency_key,
    );
}

test "World comptime application executes one external effect deterministically" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try OneEffectApp.encodeInitialArgs(allocator, .{});
    const parent = try OneEffectApp.initialFrame(&arena, args, 100);
    try std.testing.expectEqual(world.v1.FrameStatus.needs_effect, parent.status);
    const request = parent.pending_effect.?;
    const expected_payload = try world.v1.encodeValue(allocator, @as([]const u8, "payload"));
    defer allocator.free(expected_payload);
    try std.testing.expectEqualSlices(u8, expected_payload, request.payload_bytes);

    const result = try okResult(OneEffectApp, RootSite, allocator, request, @as(i32, 41));
    const parent_bytes = try OneEffectApp.encodeFrame(allocator, parent);
    const input: world.v1.StepInput = .{
        .application_id = OneEffectApp.Manifest.application_id,
        .expected_parent_frame_id = parent.frame_id,
        .prior_frame_bytes = parent_bytes,
        .effect_result = result,
        .fuel = 100,
    };
    const first = try OneEffectApp.step(&arena, input);
    const second = try OneEffectApp.step(&arena, input);
    try std.testing.expectEqual(world.v1.FrameStatus.completed, first.status);
    var decoded = try OneEffectApp.decodeFinalResult(allocator, first);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(i32, 41), decoded.value);

    const first_bytes = try OneEffectApp.encodeFrame(allocator, first);
    const second_bytes = try OneEffectApp.encodeFrame(allocator, second);
    try std.testing.expectEqualSlices(u8, first_bytes, second_bytes);
}

test "World comptime provider parks externally and resumes its exact parent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try std.testing.expectEqual(@as(usize, 1), ProviderApp.internal_handler_ids.len);
    try std.testing.expectEqual(@as(usize, 1), ProviderApp.residual_effect_row.len);
    try std.testing.expectEqual(ProviderSite.canonical_fingerprint, ProviderApp.residual_effect_row[0].site_id);

    const args = try ProviderApp.encodeInitialArgs(allocator, .{});
    const parent = try ProviderApp.initialFrame(&arena, args, 100);
    try std.testing.expectEqual(world.v1.FrameStatus.needs_effect, parent.status);
    try std.testing.expectEqual(ProviderSite.canonical_fingerprint, parent.pending_effect.?.site_id);
    try std.testing.expectEqual(@as(u64, 1), parent.resource_counters.internal_handler_calls);

    const result = try okResult(ProviderApp, ProviderSite, allocator, parent.pending_effect.?, @as(i32, 52));
    const parent_bytes = try ProviderApp.encodeFrame(allocator, parent);
    const completed = try ProviderApp.step(&arena, .{
        .application_id = ProviderApp.Manifest.application_id,
        .expected_parent_frame_id = parent.frame_id,
        .prior_frame_bytes = parent_bytes,
        .effect_result = result,
        .fuel = 100,
    });
    try std.testing.expectEqual(world.v1.FrameStatus.completed, completed.status);
    var decoded = try ProviderApp.decodeFinalResult(allocator, completed);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(i32, 52), decoded.value);
    try std.testing.expectEqual(@as(u64, 2), completed.resource_counters.continuation_operations);
}
