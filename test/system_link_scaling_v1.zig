const boundary = @import("boundary");
const std = @import("std");
const world = @import("world");

const wide_tag_count = 128;

fn WideFailure(comptime prefix: []const u8) type {
    @setEvalBranchQuota(100_000);
    var names: [wide_tag_count][:0]const u8 = undefined;
    var values: [wide_tag_count]u32 = undefined;
    for (0..wide_tag_count) |index| {
        names[index] = std.fmt.comptimePrint("{s}{d}", .{ prefix, index });
        values[index] = @intCast(index);
    }
    return @Enum(u32, .exhaustive, &names, &values);
}

const WideProviderFailure = WideFailure("p");
const WideRootFailure = WideFailure("r");
const wide_failure_type: boundary.ir.ValueType = .{ .schema = 0 };
const wide_targets = blk: {
    var result: [wide_tag_count]WideRootFailure = undefined;
    for (0..wide_tag_count) |index| result[index] = @enumFromInt(index);
    break :blk result;
};
const WideMap = world.failureMorphism(
    WideProviderFailure,
    WideRootFailure,
    wide_targets,
);
const resume_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};
const WideSiteA = boundary.effect.site(
    0,
    "world.scaling.wide-map-a.v1",
    WideProviderFailure,
    WideProviderFailure,
);
const WideSiteB = boundary.effect.site(
    1,
    "world.scaling.wide-map-b.v1",
    WideProviderFailure,
    WideProviderFailure,
);
const wide_root_blocks = [_]boundary.ir.Block{
    .{ .id = 0, .parameters = &.{0}, .terminator = .{ .@"suspend" = .{
        .kind = .effect,
        .site_id = 0,
        .request_values = &.{0},
        .continuation = .{ .target = 1, .arguments = &resume_arguments },
        .resume_type = wide_failure_type,
    } } },
    .{ .id = 1, .parameters = &.{1}, .terminator = .{ .@"suspend" = .{
        .kind = .effect,
        .site_id = 1,
        .request_values = &.{1},
        .continuation = .{ .target = 2, .arguments = &resume_arguments },
        .resume_type = wide_failure_type,
    } } },
    .{ .id = 2, .parameters = &.{2}, .terminator = .{ .return_value = 2 } },
};
const WideRootBody = struct {
    pub const InitialArgs = WideProviderFailure;
    pub const Result = WideProviderFailure;
    pub const Failure = WideRootFailure;
    pub const effect_sites = .{ WideSiteA, WideSiteB };
    pub const schema_types = .{WideProviderFailure};
    pub const control_ir: boundary.ir.Program = .{
        .label = "world-scaling-wide-root",
        .value_types = &.{ wide_failure_type, wide_failure_type, wide_failure_type },
        .blocks = &wide_root_blocks,
        .entry = 0,
        .result_type = wide_failure_type,
    };
};
const WideRoot = boundary.program("world-scaling-wide-root", WideRootBody);
const WideProviderABody = struct {
    pub const InitialArgs = WideProviderFailure;
    pub const Result = WideProviderFailure;
    pub const Failure = WideProviderFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{WideProviderFailure};
    pub const control_ir: boundary.ir.Program = .{
        .label = "world-scaling-wide-provider-a",
        .value_types = &.{wide_failure_type},
        .blocks = &.{.{
            .id = 0,
            .parameters = &.{0},
            .terminator = .{ .fail_value = 0 },
        }},
        .entry = 0,
        .result_type = wide_failure_type,
    };
};
const WideProviderA = boundary.program(
    "world-scaling-wide-provider-a",
    WideProviderABody,
);
const WideProviderBBody = struct {
    const instructions = [_]boundary.ir.Instruction{.{
        .kind = .copy,
        .result = 1,
        .operands = &.{0},
        .operation = .copy,
    }};
    pub const InitialArgs = WideProviderFailure;
    pub const Result = WideProviderFailure;
    pub const Failure = WideProviderFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{WideProviderFailure};
    pub const control_ir: boundary.ir.Program = .{
        .label = "world-scaling-wide-provider-b",
        .value_types = &.{ wide_failure_type, wide_failure_type },
        .blocks = &.{.{
            .id = 0,
            .parameters = &.{0},
            .instructions = &instructions,
            .terminator = .{ .fail_value = 1 },
        }},
        .entry = 0,
        .result_type = wide_failure_type,
    };
};
const WideProviderB = boundary.program(
    "world-scaling-wide-provider-b",
    WideProviderBBody,
);
const WideMapSystem = world.system(.{
    .name = "world-scaling-wide-map-system",
    .root = WideRoot,
    .handlers = .{
        world.systemHandle(.{
            .consumer = WideRoot,
            .site = WideSiteA,
            .provider = WideProviderA,
            .failure_morphism = WideMap,
        }),
        world.systemHandle(.{
            .consumer = WideRoot,
            .site = WideSiteB,
            .provider = WideProviderB,
            .failure_morphism = WideMap,
        }),
    },
    .morphisms = .{},
    .external = .{},
});

test "world.system shares one wide Failure selector by mapping identity" {
    const Linked = WideMapSystem.Program.component();
    try std.testing.expectEqual(@as(usize, 519), Linked.control_ir.value_types.len);
    try std.testing.expectEqual(@as(usize, 8), Linked.control_ir.blocks.len);
    try std.testing.expectEqual(@as(usize, 4), Linked.control_ir.functions.len);
    const provider_a_call = Linked.control_ir.blocks[3].terminator.@"suspend";
    const provider_b_call = Linked.control_ir.blocks[4].terminator.@"suspend";
    try std.testing.expectEqual(
        provider_a_call.callee_function,
        provider_b_call.callee_function,
    );
    try std.testing.expectEqual(
        provider_a_call.callee.?.target,
        provider_b_call.callee.?.target,
    );
    try std.testing.expect(WideMapSystem.Program.image().bytes.len > 0);
}

const quota_handler_count = 8;
const QuotaProviderFailure = enum(u8) { denied = 3, retry = 9 };
const QuotaRootFailure = enum(u32) { mapped_denied = 70_000, mapped_retry = 90_000 };
const quota_failure_type: boundary.ir.ValueType = .{ .schema = 0 };
const QuotaMap = world.failureMorphism(
    QuotaProviderFailure,
    QuotaRootFailure,
    .{ QuotaRootFailure.mapped_denied, QuotaRootFailure.mapped_retry },
);
const quota_sites = blk: {
    var result: [quota_handler_count]type = undefined;
    for (0..quota_handler_count) |index| {
        result[index] = boundary.effect.site(
            @intCast(index),
            std.fmt.comptimePrint("world.scaling.quota-site-{d}.v1", .{index}),
            QuotaProviderFailure,
            QuotaProviderFailure,
        );
    }
    break :blk result;
};
const quota_root_blocks = blk: {
    var result: [quota_handler_count + 1]boundary.ir.Block = undefined;
    for (0..quota_handler_count) |index| {
        result[index] = .{
            .id = @intCast(index),
            .parameters = &.{@as(boundary.ir.ValueId, @intCast(index))},
            .terminator = .{ .@"suspend" = .{
                .kind = .effect,
                .site_id = @intCast(index),
                .request_values = &.{@as(boundary.ir.ValueId, @intCast(index))},
                .continuation = .{
                    .target = @intCast(index + 1),
                    .arguments = &resume_arguments,
                },
                .resume_type = quota_failure_type,
            } },
        };
    }
    result[quota_handler_count] = .{
        .id = quota_handler_count,
        .parameters = &.{quota_handler_count},
        .terminator = .{ .return_value = quota_handler_count },
    };
    break :blk result;
};
const QuotaRootBody = struct {
    pub const InitialArgs = QuotaProviderFailure;
    pub const Result = QuotaProviderFailure;
    pub const Failure = QuotaRootFailure;
    pub const effect_sites = quota_sites;
    pub const schema_types = .{QuotaProviderFailure};
    pub const control_ir: boundary.ir.Program = .{
        .label = "world-scaling-quota-root",
        .value_types = &([_]boundary.ir.ValueType{quota_failure_type} **
            (quota_handler_count + 1)),
        .blocks = &quota_root_blocks,
        .entry = 0,
        .result_type = quota_failure_type,
    };
};
const QuotaRoot = boundary.program("world-scaling-quota-root", QuotaRootBody);

fn QuotaProvider(comptime ordinal: usize) type {
    const Body = struct {
        const instructions = blk: {
            var result: [ordinal]boundary.ir.Instruction = undefined;
            for (0..ordinal) |index| {
                result[index] = .{
                    .kind = .copy,
                    .result = @intCast(index + 1),
                    .operands = &.{@as(boundary.ir.ValueId, @intCast(index))},
                    .operation = .copy,
                };
            }
            break :blk result;
        };
        const blocks = [_]boundary.ir.Block{.{
            .id = 0,
            .parameters = &.{0},
            .instructions = &instructions,
            .terminator = .{ .fail_value = ordinal },
        }};
        pub const InitialArgs = QuotaProviderFailure;
        pub const Result = QuotaProviderFailure;
        pub const Failure = QuotaProviderFailure;
        pub const effect_sites = .{};
        pub const schema_types = .{QuotaProviderFailure};
        pub const control_ir: boundary.ir.Program = .{
            .label = std.fmt.comptimePrint(
                "world-scaling-quota-provider-{d}",
                .{ordinal},
            ),
            .value_types = &([_]boundary.ir.ValueType{quota_failure_type} **
                (ordinal + 1)),
            .blocks = &blocks,
            .entry = 0,
            .result_type = quota_failure_type,
        };
    };
    return boundary.program(
        std.fmt.comptimePrint("world-scaling-quota-provider-{d}", .{ordinal}),
        Body,
    );
}

const quota_handlers = blk: {
    var result: [quota_handler_count]type = undefined;
    for (0..quota_handler_count) |index| {
        result[index] = world.systemHandle(.{
            .consumer = QuotaRoot,
            .site = quota_sites[index],
            .provider = QuotaProvider(index),
            .failure_morphism = QuotaMap,
        });
    }
    break :blk result;
};
const QuotaSystem = world.system(.{
    .name = "world-scaling-quota-system",
    .root = QuotaRoot,
    .handlers = quota_handlers,
    .morphisms = .{},
    .external = .{},
});

test "world.system applies its branch quota in lazy lowering scopes" {
    const Linked = QuotaSystem.Program.component();
    try std.testing.expectEqual(@as(usize, 60), Linked.control_ir.value_types.len);
    try std.testing.expect(QuotaSystem.Program.image().bytes.len > 0);
}

const QuotaMapSwapped = world.failureMorphism(
    QuotaProviderFailure,
    QuotaRootFailure,
    .{ QuotaRootFailure.mapped_retry, QuotaRootFailure.mapped_denied },
);
const distinct_map_root_blocks = [_]boundary.ir.Block{
    .{ .id = 0, .parameters = &.{0}, .terminator = .{ .@"suspend" = .{
        .kind = .effect,
        .site_id = 0,
        .request_values = &.{0},
        .continuation = .{ .target = 1, .arguments = &resume_arguments },
        .resume_type = quota_failure_type,
    } } },
    .{ .id = 1, .parameters = &.{1}, .terminator = .{ .@"suspend" = .{
        .kind = .effect,
        .site_id = 1,
        .request_values = &.{1},
        .continuation = .{ .target = 2, .arguments = &resume_arguments },
        .resume_type = quota_failure_type,
    } } },
    .{ .id = 2, .parameters = &.{2}, .terminator = .{ .return_value = 2 } },
};
const DistinctMapRootBody = struct {
    pub const InitialArgs = QuotaProviderFailure;
    pub const Result = QuotaProviderFailure;
    pub const Failure = QuotaRootFailure;
    pub const effect_sites = .{ quota_sites[0], quota_sites[1] };
    pub const schema_types = .{QuotaProviderFailure};
    pub const control_ir: boundary.ir.Program = .{
        .label = "world-scaling-distinct-map-root",
        .value_types = &.{ quota_failure_type, quota_failure_type, quota_failure_type },
        .blocks = &distinct_map_root_blocks,
        .entry = 0,
        .result_type = quota_failure_type,
    };
};
const DistinctMapRoot = boundary.program(
    "world-scaling-distinct-map-root",
    DistinctMapRootBody,
);
const DistinctMapSystem = world.system(.{
    .name = "world-scaling-distinct-map-system",
    .root = DistinctMapRoot,
    .handlers = .{
        world.systemHandle(.{
            .consumer = DistinctMapRoot,
            .site = quota_sites[0],
            .provider = QuotaProvider(0),
            .failure_morphism = QuotaMap,
        }),
        world.systemHandle(.{
            .consumer = DistinctMapRoot,
            .site = quota_sites[1],
            .provider = QuotaProvider(1),
            .failure_morphism = QuotaMapSwapped,
        }),
    },
    .morphisms = .{},
    .external = .{},
});

test "world.system does not share distinct Failure mappings" {
    const Linked = DistinctMapSystem.Program.component();
    try std.testing.expectEqual(@as(usize, 22), Linked.control_ir.value_types.len);
    try std.testing.expectEqual(@as(usize, 9), Linked.control_ir.blocks.len);
    try std.testing.expectEqual(@as(usize, 5), Linked.control_ir.functions.len);
    const provider_a_call = Linked.control_ir.blocks[3].terminator.@"suspend";
    const provider_b_call = Linked.control_ir.blocks[4].terminator.@"suspend";
    try std.testing.expect(provider_a_call.callee_function != provider_b_call.callee_function);
    try std.testing.expect(provider_a_call.callee.?.target != provider_b_call.callee.?.target);
    try std.testing.expect(DistinctMapSystem.Program.image().bytes.len > 0);
}

const RepeatedProviderDistinctMapSystem = world.system(.{
    .name = "world-scaling-repeated-provider-distinct-map-system",
    .root = DistinctMapRoot,
    .handlers = .{
        world.systemHandle(.{
            .consumer = DistinctMapRoot,
            .site = quota_sites[0],
            .provider = QuotaProvider(0),
            .failure_morphism = QuotaMap,
        }),
        world.systemHandle(.{
            .consumer = DistinctMapRoot,
            .site = quota_sites[1],
            .provider = QuotaProvider(0),
            .failure_morphism = QuotaMapSwapped,
        }),
    },
    .morphisms = .{},
    .external = .{},
});

test "world.system preserves distinct Failure maps for repeated provider Programs" {
    const Linked = RepeatedProviderDistinctMapSystem.Program.component();
    try std.testing.expectEqual(
        @as(usize, 3),
        RepeatedProviderDistinctMapSystem.component_count,
    );
    try std.testing.expectEqual(@as(usize, 21), Linked.control_ir.value_types.len);
    try std.testing.expectEqual(@as(usize, 9), Linked.control_ir.blocks.len);
    try std.testing.expectEqual(@as(usize, 5), Linked.control_ir.functions.len);
    const provider_a_call = Linked.control_ir.blocks[3].terminator.@"suspend";
    const provider_b_call = Linked.control_ir.blocks[4].terminator.@"suspend";
    try std.testing.expect(provider_a_call.callee_function != provider_b_call.callee_function);
    try std.testing.expect(provider_a_call.callee.?.target != provider_b_call.callee.?.target);
    try std.testing.expect(
        RepeatedProviderDistinctMapSystem.Program.image().bytes.len > 0,
    );
}
