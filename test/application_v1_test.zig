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
pub const RootMachine = boundary.staticMachine(RootProgram, .{
    .maximum_state_bytes = 64 * 1024,
});
pub const RootSite = RootMachine.EffectRow.operationSite("root", "decide", 0);

const ProviderBody = struct {
    pub const compiled_plan = providerEffectPlan("world-v1-provider");
};
const ProviderProgram = boundary.program("world-v1-provider", struct {}, ProviderBody);
pub const ProviderMachine = boundary.staticMachine(ProviderProgram, .{
    .maximum_state_bytes = 64 * 1024,
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
    try result.seal(allocator);
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
}

test "World comptime application executes one external effect deterministically" {
    const allocator = std.testing.allocator;
    const args = try OneEffectApp.encodeInitialArgs(allocator, .{});
    defer allocator.free(args);
    var parent = try OneEffectApp.initialFrame(allocator, args, 100);
    defer parent.deinit(allocator);
    try std.testing.expectEqual(world.v1.FrameStatus.needs_effect, parent.status);
    const request = parent.pending_effect.?;
    const expected_payload = try world.v1.encodeValue(allocator, @as([]const u8, "payload"));
    defer allocator.free(expected_payload);
    try std.testing.expectEqualSlices(u8, expected_payload, request.payload_bytes);

    var result = try okResult(OneEffectApp, RootSite, allocator, request, @as(i32, 41));
    defer result.deinit(allocator);
    const parent_bytes = try OneEffectApp.encodeFrame(allocator, parent);
    defer allocator.free(parent_bytes);
    const input: world.v1.StepInput = .{
        .application_id = OneEffectApp.Manifest.application_id,
        .expected_parent_frame_id = parent.frame_id,
        .prior_frame_bytes = parent_bytes,
        .effect_result = result,
        .fuel = 100,
    };
    var first = try OneEffectApp.step(allocator, input);
    defer first.deinit(allocator);
    var second = try OneEffectApp.step(allocator, input);
    defer second.deinit(allocator);
    try std.testing.expectEqual(world.v1.FrameStatus.completed, first.status);
    var decoded = try OneEffectApp.decodeFinalResult(allocator, first);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(i32, 41), decoded.value);

    const first_bytes = try OneEffectApp.encodeFrame(allocator, first);
    defer allocator.free(first_bytes);
    const second_bytes = try OneEffectApp.encodeFrame(allocator, second);
    defer allocator.free(second_bytes);
    try std.testing.expectEqualSlices(u8, first_bytes, second_bytes);
}

test "World comptime provider parks externally and resumes its exact parent" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(@as(usize, 1), ProviderApp.internal_handler_ids.len);
    try std.testing.expectEqual(@as(usize, 1), ProviderApp.residual_effect_row.len);
    try std.testing.expectEqual(ProviderSite.canonical_fingerprint, ProviderApp.residual_effect_row[0].site_id);

    const args = try ProviderApp.encodeInitialArgs(allocator, .{});
    defer allocator.free(args);
    var parent = try ProviderApp.initialFrame(allocator, args, 100);
    defer parent.deinit(allocator);
    try std.testing.expectEqual(world.v1.FrameStatus.needs_effect, parent.status);
    try std.testing.expectEqual(ProviderSite.canonical_fingerprint, parent.pending_effect.?.site_id);
    try std.testing.expectEqual(@as(u64, 1), parent.resource_counters.internal_handler_calls);

    var result = try okResult(ProviderApp, ProviderSite, allocator, parent.pending_effect.?, @as(i32, 52));
    defer result.deinit(allocator);
    const parent_bytes = try ProviderApp.encodeFrame(allocator, parent);
    defer allocator.free(parent_bytes);
    var completed = try ProviderApp.step(allocator, .{
        .application_id = ProviderApp.Manifest.application_id,
        .expected_parent_frame_id = parent.frame_id,
        .prior_frame_bytes = parent_bytes,
        .effect_result = result,
        .fuel = 100,
    });
    defer completed.deinit(allocator);
    try std.testing.expectEqual(world.v1.FrameStatus.completed, completed.status);
    var decoded = try ProviderApp.decodeFinalResult(allocator, completed);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(i32, 52), decoded.value);
    try std.testing.expectEqual(@as(u64, 2), completed.resource_counters.continuation_operations);
}
