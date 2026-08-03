// zlinter-disable declaration_naming no_inferred_error_unions require_doc_comment
const std = @import("std");
const boundary = @import("boundary");
const world = @import("world");

const u32_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const continuation_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};

fn EffectSite(comptime identity: []const u8) type {
    return struct {
        pub const id: u32 = 0;
        pub const semantic_identity = identity;
        pub const Payload = u32;
        pub const Resume = u32;
    };
}

const RootEffect = EffectSite("world.test.root.v2");
const ProviderEffect = EffectSite("world.test.provider.v2");

fn EffectBody(comptime label: []const u8, comptime Site: type) type {
    return struct {
        const blocks = [_]boundary.ir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .terminator = .{ .@"suspend" = .{
                    .kind = .effect,
                    .site_id = 0,
                    .request_values = &.{0},
                    .continuation = .{
                        .target = 1,
                        .arguments = &continuation_arguments,
                    },
                    .resume_type = u32_type,
                } },
            },
            .{
                .id = 1,
                .parameters = &.{1},
                .terminator = .{ .return_value = 1 },
            },
        };

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{Site};
        pub const schema_types = .{};
        pub const control_ir: boundary.ir.Program = .{
            .label = label,
            .value_types = &.{ u32_type, u32_type },
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
}

const IncrementingEffectBody = struct {
    const increment_instructions = [_]boundary.ir.Instruction{
        .{
            .kind = .constant,
            .result = 2,
            .operation = .{ .constant = 0 },
        },
        .{
            .kind = .pure,
            .result = 3,
            .operands = &.{ 1, 2 },
            .operation = .integer_add,
        },
    };
    const blocks = [_]boundary.ir.Block{
        .{
            .id = 0,
            .parameters = &.{0},
            .terminator = .{ .@"suspend" = .{
                .kind = .effect,
                .site_id = 0,
                .request_values = &.{0},
                .continuation = .{
                    .target = 1,
                    .arguments = &continuation_arguments,
                },
                .resume_type = u32_type,
            } },
        },
        .{
            .id = 1,
            .parameters = &.{1},
            .instructions = &increment_instructions,
            .terminator = .{ .return_value = 3 },
        },
    };

    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected, arithmetic_overflow };
    pub const constants = .{@as(u32, 1)};
    pub const effect_sites = .{RootEffect};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "world-v2-root-duplicate",
        .value_types = &.{ u32_type, u32_type, u32_type, u32_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const machine_options: boundary.MachineOptions = .{
    .maximum_frames = 8,
    .maximum_state_bytes = 16 * 1024,
    .maximum_machine_fuel = 1024,
};

pub const RootMachine = boundary.program(
    "world-v2-root",
    EffectBody("world-v2-root", RootEffect),
).compile(machine_options);
pub const RootSite = RootMachine.EffectRow.site(0);

const DuplicateRootMachine = boundary.program(
    "world-v2-root-duplicate",
    IncrementingEffectBody,
).compile(machine_options);

pub const ProviderMachine = boundary.program(
    "world-v2-provider",
    EffectBody("world-v2-provider", ProviderEffect),
).compile(machine_options);
pub const ProviderSite = ProviderMachine.EffectRow.site(0);

const application_limits = .{
    .maximum_initial_args_bytes = 64 * 1024,
    .maximum_state_bytes = 64 * 1024,
    .maximum_payload_bytes = 64 * 1024,
    .maximum_result_bytes = 64 * 1024,
    .maximum_host_claim_bytes = 8 * 1024,
    .maximum_host_metadata_bytes = 8 * 1024,
    .maximum_failure_bytes = 8 * 1024,
};

pub const OneEffectApp = world.v1.application(.{
    .name = "one-effect",
    .version = "2.0.0",
    .root = RootMachine,
    .limits = application_limits,
    .external = .{world.v1.external(RootMachine, 0, .{
        .site_identity = "world.test.root.v2",
        .interface = "test.one-effect.v1",
        .authority = world.v1.Authority.model,
    })},
});

pub const ProviderApp = world.v1.application(.{
    .name = "provider-parked",
    .version = "2.0.0",
    .root = RootMachine,
    .limits = application_limits,
    .handlers = .{world.v1.handle(
        RootMachine,
        0,
        "world.test.root.v2",
        ProviderMachine,
    )},
    .external = .{world.v1.external(ProviderMachine, 0, .{
        .site_identity = "world.test.provider.v2",
        .interface = "test.provider-external.v1",
        .authority_requirements = @as(u64, 1) << @intFromEnum(world.v1.Authority.file_read),
    })},
});

pub const DeferredApp = world.v1.application(.{
    .name = "deferred-effect",
    .version = "2.0.0",
    .root = RootMachine,
    .limits = application_limits,
    .external = .{world.v1.external(RootMachine, 0, .{
        .site_identity = "world.test.root.v2",
        .interface = "test.deferred-effect.v1",
        .allowed_statuses = world.v1.AllowedStatuses{ .deferred = true },
    })},
});

pub const TightResultApp = world.v1.application(.{
    .name = "tight-result",
    .version = "2.0.0",
    .root = RootMachine,
    .limits = application_limits,
    .external = .{world.v1.external(RootMachine, 0, .{
        .site_identity = "world.test.root.v2",
        .interface = "test.tight-result.v1",
        .maximum_result_bytes = 3,
    })},
});

const SumTagA = enum(u8) { left = 0, right = 1 };
const SumA = union(SumTagA) { left: i32, right: bool };
const SumTagB = enum(u8) { left = 1, right = 2 };
const SumB = union(SumTagB) { left: i32, right: bool };

fn okResult(
    comptime App: type,
    comptime Machine: type,
    comptime site_ordinal: usize,
    allocator: std.mem.Allocator,
    request: world.v1.EffectRequest,
    value: anytype,
) !world.v1.EffectResult {
    const bytes = try App.encodeExternalResult(allocator, Machine, site_ordinal, value);
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

test "site ids bind the owning Machine occurrence" {
    try std.testing.expectEqualSlices(
        u8,
        &RootMachine.EffectRow.site(0).contract_digest,
        &DuplicateRootMachine.EffectRow.site(0).contract_digest,
    );
    try std.testing.expect(
        world.v1.siteId(RootMachine, 0) !=
            world.v1.siteId(DuplicateRootMachine, 0),
    );
}

test "World closes one Boundary Machine ABI v2 residual effect" {
    try std.testing.expectEqual(@as(u16, 2), RootMachine.abi_version);
    try std.testing.expectEqual(@as(usize, 0), OneEffectApp.internal_handler_ids.len);
    try std.testing.expectEqual(@as(usize, 1), OneEffectApp.residual_effect_row.len);
    try std.testing.expectEqual(world.v1.siteId(RootMachine, 0), OneEffectApp.residual_effect_row[0].site_id);
    try std.testing.expectEqual(
        @as(u64, 1) << @intFromEnum(world.v1.Authority.model),
        OneEffectApp.Manifest.required_host_capabilities,
    );
    try std.testing.expectEqualStrings("1.0.0-rc.1", OneEffectApp.Manifest.boundary_package_version);
    try std.testing.expectEqualStrings("2.0.0", OneEffectApp.Manifest.world_package_version);
    try OneEffectApp.Manifest.validate();
    try std.testing.expect(ProviderApp.maximum_encoded_runtime_state_bytes <= ProviderApp.Limits.maximum_state_bytes);
}

test "World delegates portable schema identity to Boundary" {
    try std.testing.expectEqualSlices(
        u8,
        &boundary.schema.schemaDigest(SumA),
        &world.v1.valueSchemaId(SumA),
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        &world.v1.valueSchemaId(SumA),
        &world.v1.valueSchemaId(SumB),
    ));
}

test "World external value encoder enforces its binding result limit" {
    try std.testing.expectError(
        error.LimitExceeded,
        TightResultApp.encodeExternalResult(std.testing.allocator, RootMachine, 0, @as(u32, 41)),
    );
}

test "World deferred result preserves the exact outstanding request and Frame" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try DeferredApp.encodeInitialArgs(allocator, @as(u32, 7));
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
    try std.testing.expectEqualSlices(u8, &parent.pending_effect.?.request_id, &parked.pending_effect.?.request_id);
    try std.testing.expectEqualSlices(u8, &parent.pending_effect.?.idempotency_key, &parked.pending_effect.?.idempotency_key);
}

test "World application executes one external effect deterministically" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try OneEffectApp.encodeInitialArgs(allocator, @as(u32, 7));
    const parent = try OneEffectApp.initialFrame(&arena, args, 100);
    try std.testing.expectEqual(world.v1.FrameStatus.needs_effect, parent.status);
    const request = parent.pending_effect.?;
    const expected_payload = try boundary.schema.encodedSize(u32, 7);
    try std.testing.expectEqual(expected_payload, request.payload_bytes.len);
    try std.testing.expectEqual(@as(u32, 7), try boundary.schema.decodeExact(u32, request.payload_bytes));

    const result = try okResult(OneEffectApp, RootMachine, 0, allocator, request, @as(u32, 41));
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
    try std.testing.expectEqual(@as(u32, 41), decoded.value);

    const first_bytes = try OneEffectApp.encodeFrame(allocator, first);
    const second_bytes = try OneEffectApp.encodeFrame(allocator, second);
    try std.testing.expectEqualSlices(u8, first_bytes, second_bytes);
}

test "World provider parks externally and resumes its exact parent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try std.testing.expectEqual(@as(usize, 1), ProviderApp.internal_handler_ids.len);
    try std.testing.expectEqual(@as(usize, 1), ProviderApp.residual_effect_row.len);
    try std.testing.expectEqual(world.v1.siteId(ProviderMachine, 0), ProviderApp.residual_effect_row[0].site_id);

    const args = try ProviderApp.encodeInitialArgs(allocator, @as(u32, 9));
    const parent = try ProviderApp.initialFrame(&arena, args, 100);
    try std.testing.expectEqual(world.v1.FrameStatus.needs_effect, parent.status);
    try std.testing.expectEqual(world.v1.siteId(ProviderMachine, 0), parent.pending_effect.?.site_id);
    try std.testing.expectEqual(@as(u64, 1), parent.resource_counters.internal_handler_calls);
    try std.testing.expectEqual(@as(u32, 9), try boundary.schema.decodeExact(u32, parent.pending_effect.?.payload_bytes));

    const result = try okResult(ProviderApp, ProviderMachine, 0, allocator, parent.pending_effect.?, @as(u32, 52));
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
    try std.testing.expectEqual(@as(u32, 52), decoded.value);
    try std.testing.expectEqual(@as(u64, 2), completed.resource_counters.continuation_operations);
}
