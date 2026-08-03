// zlinter-disable declaration_naming no_inferred_error_unions require_doc_comment
const std = @import("std");
const boundary = @import("boundary");
const world = @import("world");

pub const TextValue = boundary.Text(2048);
const text_type: boundary.ir.ValueType = .{ .schema = 0 };
const continuation_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};

const application_limits: world.v1.Limits = .{
    .maximum_initial_args_bytes = 64 * 1024,
    .maximum_state_bytes = 256 * 1024,
    .maximum_payload_bytes = 64 * 1024,
    .maximum_result_bytes = 64 * 1024,
    .maximum_host_claim_bytes = 8 * 1024,
    .maximum_host_metadata_bytes = 8 * 1024,
    .maximum_failure_bytes = 8 * 1024,
};

const machine_options: boundary.MachineOptions = .{
    .maximum_frames = 16,
    .maximum_state_bytes = 64 * 1024,
    .maximum_machine_fuel = 4096,
};

fn TextEffect(
    comptime source_id: u32,
    comptime identity: []const u8,
) type {
    return struct {
        pub const id = source_id;
        pub const semantic_identity = identity;
        pub const Payload = TextValue;
        pub const Resume = TextValue;
    };
}

const SkeletonModel0 = TextEffect(0, "agent.model.decide.v1");
const SkeletonToolbox = TextEffect(1, "agent.toolbox.call.v1");
const SkeletonModel1 = TextEffect(2, "agent.model.decide.v1");

const skeleton_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{ .target = 1, .arguments = &continuation_arguments },
            .resume_type = text_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 1,
            .request_values = &.{1},
            .continuation = .{ .target = 2, .arguments = &continuation_arguments },
            .resume_type = text_type,
        } },
    },
    .{
        .id = 2,
        .parameters = &.{2},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 2,
            .request_values = &.{2},
            .continuation = .{ .target = 3, .arguments = &continuation_arguments },
            .resume_type = text_type,
        } },
    },
    .{
        .id = 3,
        .parameters = &.{3},
        .terminator = .{ .return_value = 3 },
    },
};

const SkeletonBody = struct {
    pub const InitialArgs = TextValue;
    pub const Result = TextValue;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{ SkeletonModel0, SkeletonToolbox, SkeletonModel1 };
    pub const schema_types = .{TextValue};
    pub const control_ir: boundary.ir.Program = .{
        .label = "world-v2-skeleton-agent",
        .value_types = &.{ text_type, text_type, text_type, text_type },
        .blocks = &skeleton_blocks,
        .entry = 0,
        .result_type = text_type,
    };
};

const IdentityBody = struct {
    const blocks = [_]boundary.ir.Block{.{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .return_value = 0 },
    }};

    pub const InitialArgs = TextValue;
    pub const Result = TextValue;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{TextValue};
    pub const control_ir: boundary.ir.Program = .{
        .label = "world-v2-identity-provider",
        .value_types = &.{text_type},
        .blocks = &blocks,
        .entry = 0,
        .result_type = text_type,
    };
};

pub const SkeletonRootMachine = boundary.program(
    "world-v2-skeleton-agent",
    SkeletonBody,
).compile(machine_options);
pub const SkeletonModelSite0 = SkeletonRootMachine.EffectRow.site(0);
pub const SkeletonToolboxSite = SkeletonRootMachine.EffectRow.site(1);
pub const SkeletonModelSite1 = SkeletonRootMachine.EffectRow.site(2);

pub const PureToolboxMachine = boundary.program(
    "world-v2-skeleton-toolbox",
    IdentityBody,
).compile(machine_options);

pub const SkeletonApp = world.application(.{
    .name = "skeleton-agent",
    .version = "2.0.0",
    .root = SkeletonRootMachine,
    .handlers = .{world.v1.handle(
        SkeletonRootMachine,
        1,
        "agent.toolbox.call.v1",
        PureToolboxMachine,
    )},
    .external = .{
        world.v1.external(SkeletonRootMachine, 0, .{
            .site_identity = "agent.model.decide.v1",
            .interface = "agent.model.decide.v1",
            .authority = world.v1.Authority.model,
        }),
        world.v1.external(SkeletonRootMachine, 2, .{
            .site_identity = "agent.model.decide.v1",
            .interface = "agent.model.decide.v1",
            .authority = world.v1.Authority.model,
        }),
    },
    .limits = application_limits,
});

const FixtureModel0 = TextEffect(0, "agent.model.decide.v1");
const FixtureRead = TextEffect(1, "agent.toolbox.read.v1");
const FixtureModel1 = TextEffect(2, "agent.model.decide.v1");
const FixtureWrite = TextEffect(3, "agent.toolbox.write.v1");
const FixtureModel2 = TextEffect(4, "agent.model.decide.v1");

const fixture_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{ .target = 1, .arguments = &continuation_arguments },
            .resume_type = text_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 1,
            .request_values = &.{1},
            .continuation = .{ .target = 2, .arguments = &continuation_arguments },
            .resume_type = text_type,
        } },
    },
    .{
        .id = 2,
        .parameters = &.{2},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 2,
            .request_values = &.{2},
            .continuation = .{ .target = 3, .arguments = &continuation_arguments },
            .resume_type = text_type,
        } },
    },
    .{
        .id = 3,
        .parameters = &.{3},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 3,
            .request_values = &.{3},
            .continuation = .{ .target = 4, .arguments = &continuation_arguments },
            .resume_type = text_type,
        } },
    },
    .{
        .id = 4,
        .parameters = &.{4},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 4,
            .request_values = &.{4},
            .continuation = .{ .target = 5, .arguments = &continuation_arguments },
            .resume_type = text_type,
        } },
    },
    .{
        .id = 5,
        .parameters = &.{5},
        .terminator = .{ .return_value = 5 },
    },
};

const FixtureBody = struct {
    pub const InitialArgs = TextValue;
    pub const Result = TextValue;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{ FixtureModel0, FixtureRead, FixtureModel1, FixtureWrite, FixtureModel2 };
    pub const schema_types = .{TextValue};
    pub const control_ir: boundary.ir.Program = .{
        .label = "world-v2-fixture-agent",
        .value_types = &.{ text_type, text_type, text_type, text_type, text_type, text_type },
        .blocks = &fixture_blocks,
        .entry = 0,
        .result_type = text_type,
    };
};

fn ExternalTextProviderBody(
    comptime label: []const u8,
    comptime Site: type,
) type {
    return struct {
        const blocks = [_]boundary.ir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .terminator = .{ .@"suspend" = .{
                    .kind = .effect,
                    .site_id = 0,
                    .request_values = &.{0},
                    .continuation = .{ .target = 1, .arguments = &continuation_arguments },
                    .resume_type = text_type,
                } },
            },
            .{
                .id = 1,
                .parameters = &.{1},
                .terminator = .{ .return_value = 1 },
            },
        };

        pub const InitialArgs = TextValue;
        pub const Result = TextValue;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{Site};
        pub const schema_types = .{TextValue};
        pub const control_ir: boundary.ir.Program = .{
            .label = label,
            .value_types = &.{ text_type, text_type },
            .blocks = &blocks,
            .entry = 0,
            .result_type = text_type,
        };
    };
}

const FileRead = TextEffect(0, "host.file.read.v1");
const FileWrite = TextEffect(0, "host.file.write.v1");

pub const FixtureRootMachine = boundary.program(
    "world-v2-fixture-agent",
    FixtureBody,
).compile(machine_options);
pub const FixtureModelSite0 = FixtureRootMachine.EffectRow.site(0);
pub const FixtureReadSite = FixtureRootMachine.EffectRow.site(1);
pub const FixtureModelSite1 = FixtureRootMachine.EffectRow.site(2);
pub const FixtureWriteSite = FixtureRootMachine.EffectRow.site(3);
pub const FixtureModelSite2 = FixtureRootMachine.EffectRow.site(4);

pub const ReadProviderMachine = boundary.program(
    "world-v2-file-read-provider",
    ExternalTextProviderBody("world-v2-file-read-provider", FileRead),
).compile(machine_options);
pub const FileReadSite = ReadProviderMachine.EffectRow.site(0);

pub const WriteProviderMachine = boundary.program(
    "world-v2-file-write-provider",
    ExternalTextProviderBody("world-v2-file-write-provider", FileWrite),
).compile(machine_options);
pub const FileWriteSite = WriteProviderMachine.EffectRow.site(0);

pub const FixtureApp = world.application(.{
    .name = "fixture-agent",
    .version = "2.0.0",
    .root = FixtureRootMachine,
    .handlers = .{
        world.v1.handle(
            FixtureRootMachine,
            1,
            "agent.toolbox.read.v1",
            ReadProviderMachine,
        ),
        world.v1.handle(
            FixtureRootMachine,
            3,
            "agent.toolbox.write.v1",
            WriteProviderMachine,
        ),
    },
    .external = .{
        world.v1.external(FixtureRootMachine, 0, .{
            .site_identity = "agent.model.decide.v1",
            .interface = "agent.model.decide.v1",
            .authority = world.v1.Authority.model,
        }),
        world.v1.external(FixtureRootMachine, 2, .{
            .site_identity = "agent.model.decide.v1",
            .interface = "agent.model.decide.v1",
            .authority = world.v1.Authority.model,
        }),
        world.v1.external(FixtureRootMachine, 4, .{
            .site_identity = "agent.model.decide.v1",
            .interface = "agent.model.decide.v1",
            .authority = world.v1.Authority.model,
        }),
        world.v1.external(ReadProviderMachine, 0, .{
            .site_identity = "host.file.read.v1",
            .interface = "host.file.read.v1",
            .authority = world.v1.Authority.file_read,
        }),
        world.v1.external(WriteProviderMachine, 0, .{
            .site_identity = "host.file.write.v1",
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

fn continueWithText(
    comptime App: type,
    comptime Machine: type,
    comptime site_ordinal: usize,
    arena: *std.heap.ArenaAllocator,
    parent: world.v1.Frame,
    value: TextValue,
) !world.v1.Frame {
    const allocator = arena.allocator();
    const result_bytes = try App.encodeExternalResult(allocator, Machine, site_ordinal, value);
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

fn expectTextPayload(frame: world.v1.Frame, expected: []const u8) !void {
    const decoded = try boundary.schema.decodeExact(TextValue, frame.pending_effect.?.payload_bytes);
    try std.testing.expectEqualStrings(expected, try decoded.slice());
}

test "skeleton application closes toolbox and completes through two model effects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try std.testing.expectEqual(@as(usize, 1), SkeletonApp.internal_handler_ids.len);
    try std.testing.expectEqual(@as(usize, 2), SkeletonApp.residual_effect_row.len);
    for (SkeletonApp.residual_effect_row) |effect| {
        try std.testing.expect(effect.site_id != world.v1.siteId(SkeletonRootMachine, 1));
    }
    const args = try SkeletonApp.encodeInitialArgs(allocator, try TextValue.fromSlice("goal=invoke"));

    const first = try SkeletonApp.initialFrame(&arena, args, 100);
    try std.testing.expectEqual(world.v1.siteId(SkeletonRootMachine, 0), first.pending_effect.?.site_id);
    try expectTextPayload(first, "goal=invoke");

    const second = try continueWithText(SkeletonApp, SkeletonRootMachine, 0, &arena, first, try TextValue.fromSlice("actuate"));
    try std.testing.expectEqual(world.v1.siteId(SkeletonRootMachine, 2), second.pending_effect.?.site_id);
    try expectTextPayload(second, "actuate");
    try std.testing.expectEqual(@as(u64, 1), second.resource_counters.internal_handler_calls);

    const completed = try continueWithText(SkeletonApp, SkeletonRootMachine, 2, &arena, second, try TextValue.fromSlice("final=actuate skeleton complete"));
    try std.testing.expectEqual(world.v1.FrameStatus.completed, completed.status);
    var result = try SkeletonApp.decodeFinalResult(allocator, completed);
    defer result.deinit();
    try std.testing.expectEqualStrings("final=actuate skeleton complete", try result.value.slice());
}

test "fixture application exposes model read write model sequence through compiled providers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try std.testing.expectEqual(@as(usize, 2), FixtureApp.internal_handler_ids.len);
    try std.testing.expectEqual(@as(usize, 5), FixtureApp.residual_effect_row.len);
    for (FixtureApp.residual_effect_row) |effect| {
        try std.testing.expect(effect.site_id != world.v1.siteId(FixtureRootMachine, 1));
        try std.testing.expect(effect.site_id != world.v1.siteId(FixtureRootMachine, 3));
    }
    const args = try FixtureApp.encodeInitialArgs(allocator, try TextValue.fromSlice("goal=fixture"));

    const frame0 = try FixtureApp.initialFrame(&arena, args, 100);
    try std.testing.expectEqual(world.v1.siteId(FixtureRootMachine, 0), frame0.pending_effect.?.site_id);

    const frame1 = try continueWithText(FixtureApp, FixtureRootMachine, 0, &arena, frame0, try TextValue.fromSlice("fixture-input.txt"));
    try std.testing.expectEqual(world.v1.siteId(ReadProviderMachine, 0), frame1.pending_effect.?.site_id);
    try expectTextPayload(frame1, "fixture-input.txt");

    const frame2 = try continueWithText(FixtureApp, ReadProviderMachine, 0, &arena, frame1, try TextValue.fromSlice("rewrite this file through the agent loop\n"));
    try std.testing.expectEqual(world.v1.siteId(FixtureRootMachine, 2), frame2.pending_effect.?.site_id);
    try expectTextPayload(frame2, "rewrite this file through the agent loop\n");

    const frame3 = try continueWithText(FixtureApp, FixtureRootMachine, 2, &arena, frame2, try TextValue.fromSlice("fixture-output.txt\nactuate updated the fixture"));
    try std.testing.expectEqual(world.v1.siteId(WriteProviderMachine, 0), frame3.pending_effect.?.site_id);
    try expectTextPayload(frame3, "fixture-output.txt\nactuate updated the fixture");

    const frame4 = try continueWithText(FixtureApp, WriteProviderMachine, 0, &arena, frame3, try TextValue.fromSlice("write=ok"));
    try std.testing.expectEqual(world.v1.siteId(FixtureRootMachine, 4), frame4.pending_effect.?.site_id);
    try expectTextPayload(frame4, "write=ok");

    const completed = try continueWithText(FixtureApp, FixtureRootMachine, 4, &arena, frame4, try TextValue.fromSlice("final=fixture updated"));
    try std.testing.expectEqual(world.v1.FrameStatus.completed, completed.status);
    var result = try FixtureApp.decodeFinalResult(allocator, completed);
    defer result.deinit();
    try std.testing.expectEqualStrings("final=fixture updated", try result.value.slice());
    try std.testing.expectEqual(@as(u64, 2), completed.resource_counters.internal_handler_calls);
}
