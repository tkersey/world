const boundary = @import("boundary");
const std = @import("std");
const world = @import("world");

const SystemFailure = enum {
    arithmetic_overflow,
};

pub const InternalPolicy = boundary.effect.site(
    0,
    "generic.internal-policy.v1",
    u32,
    u32,
);
pub const Observe = boundary.effect.site(
    1,
    "generic.observe.v1",
    u32,
    u32,
);
pub const ProviderObserve = boundary.effect.site(
    0,
    "generic.provider-observe.v1",
    u32,
    u32,
);

const SharedSchema = struct {
    value: u32,
};

const u32_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const resume_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};

fn expectResidualSite(
    comptime Actual: type,
    comptime Expected: type,
    expected_ordinal: u32,
) !void {
    try std.testing.expectEqual(expected_ordinal, Actual.id);
    try std.testing.expectEqual(expected_ordinal, Actual.site_id);
    try std.testing.expectEqualStrings(
        Expected.semantic_identity,
        Actual.semantic_identity,
    );
    try std.testing.expect(Actual.Payload == Expected.Payload);
    try std.testing.expect(Actual.Resume == Expected.Resume);
}
const root_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 1,
            .request_values = &.{1},
            .continuation = .{
                .target = 2,
                .arguments = &resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 2,
        .role = .terminal_handoff,
        .parameters = &.{2},
        .terminator = .{ .return_value = 2 },
    },
};

const RootBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{ InternalPolicy, Observe };
    pub const schema_types = .{SharedSchema};
    pub const control_ir: boundary.ir.Program = .{
        .label = "generic-root",
        .value_types = &.{ u32_type, u32_type, u32_type },
        .blocks = &root_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const provider_instructions = [_]boundary.ir.Instruction{
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
const provider_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .instructions = &provider_instructions,
        .terminator = .{ .return_value = 3 },
    },
};

const ProviderBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const constants = .{@as(u32, 1)};
    pub const effect_sites = .{ProviderObserve};
    pub const schema_types = .{SharedSchema};
    pub const control_ir: boundary.ir.Program = .{
        .label = "generic-provider",
        .value_types = &.{ u32_type, u32_type, u32_type, u32_type },
        .blocks = &provider_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

pub const RootProgram = boundary.program("generic-root", RootBody);
pub const ProviderProgram = boundary.program("generic-provider", ProviderBody);
pub const GenericSpec = .{
    .name = "generic-system",
    .root = RootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = RootProgram,
        .site = InternalPolicy,
        .provider = ProviderProgram,
    })},
    .morphisms = .{},
    .external = .{ Observe, ProviderObserve },
};
pub const System = world.system(GenericSpec);

const Machine = System.Program.compile(.{
    .maximum_frames = 8,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 64,
});

test "world.system links one internal Program handler into one BPI1" {
    try std.testing.expect(!@hasDecl(System, "Root"));
    try std.testing.expectEqual(@as(usize, 2), System.component_count);
    try std.testing.expectEqual(@as(usize, 1), System.internal_handler_count);
    try std.testing.expectEqual(@as(usize, 2), System.schema_count);
    try std.testing.expectEqual(@as(usize, 2), System.residual_effects.count);
    try expectResidualSite(System.residual_effects.items[0], Observe, 0);
    try expectResidualSite(System.residual_effects.items[1], ProviderObserve, 1);
    try std.testing.expect(System.Program.image().bytes.len > 0);
    try std.testing.expectEqual(@as(usize, 2), Machine.EffectRow.operation_site_count);
    try std.testing.expectEqualStrings(
        Observe.semantic_identity,
        Machine.EffectRow.site(0).semantic_identity,
    );
    try std.testing.expectEqualStrings(
        ProviderObserve.semantic_identity,
        Machine.EffectRow.site(1).semantic_identity,
    );

    const state = try Machine.initialState(std.testing.allocator, 41);
    defer Machine.deinitState(state);
    var fuel: u64 = 32;
    const request = switch (try Machine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    switch (request.value) {
        .s1 => |payload| try std.testing.expectEqual(@as(u32, 41), payload),
        else => return error.TestUnexpectedRequest,
    }
    {
        const prepared = try Machine.prepareResume(state, request);
        defer Machine.deinitPreparedResume(prepared);
        try Machine.@"resume"(prepared, @as(u32, 50));
    }
    const second_request = switch (try Machine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    switch (second_request.value) {
        .s0 => |payload| try std.testing.expectEqual(@as(u32, 51), payload),
        else => return error.TestUnexpectedRequest,
    }
    {
        const prepared = try Machine.prepareResume(state, second_request);
        defer Machine.deinitPreparedResume(prepared);
        try Machine.@"resume"(prepared, @as(u32, 99));
    }
    const completed = switch (try Machine.step(state, &fuel)) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer completed.deinit();
    try std.testing.expectEqual(@as(u32, 99), completed.value().*);
}

test "world.system BPI1 runs through one-reduction Process semantics" {
    const Image = System.Program.image();
    const Storage = boundary.process_v1.CapacityStorage(.{
        .input = 128 * 1024,
        .output = 128 * 1024,
        .state = 128 * 1024,
        .value = 64 * 1024,
        .request = 64 * 1024,
        .environment = 64 * 1024,
        .scratch = 512 * 1024,
    });
    const first_storage = try std.testing.allocator.create(Storage);
    defer std.testing.allocator.destroy(first_storage);
    first_storage.* = .{};
    const second_storage = try std.testing.allocator.create(Storage);
    defer std.testing.allocator.destroy(second_storage);
    second_storage.* = .{};
    var first_workspace: boundary.image.ValidationWorkspace = .{};
    var second_workspace: boundary.image.ValidationWorkspace = .{};
    var initial_args: [4]u8 = undefined;
    std.mem.writeInt(u32, &initial_args, 41, .little);

    const first = try first_storage.advance(
        &Image.bytes,
        .{ .initial_args = &initial_args },
        null,
        &first_workspace,
    );
    const progressed = switch (first) {
        .progressed => |state| state,
        else => return error.TestUnexpectedResult,
    };
    const second = try second_storage.advance(
        &Image.bytes,
        .{ .process_state = progressed },
        null,
        &second_workspace,
    );
    const request_bytes = switch (second) {
        .requested => |requested| requested.request,
        else => return error.TestUnexpectedResult,
    };
    const request = try boundary.process_v1.effect.validateRequest(
        request_bytes,
        Image.program_transition_digest,
    );
    try std.testing.expectEqualStrings(
        ProviderObserve.semantic_identity,
        request.effect_semantic_identity,
    );
    try std.testing.expectEqual(@as(usize, 4), request.payload.len);
    try std.testing.expectEqual(
        @as(u32, 41),
        std.mem.readInt(u32, request.payload[0..4], .little),
    );
}

const MappedInstructionPolicy = boundary.effect.site(
    0,
    "generic.mapped-instruction-policy.v1",
    u8,
    u8,
);
const MappedInstructionRootFailure = enum { mapped };
const MappedInstructionProviderFailure = enum { arithmetic_overflow };
const mapped_instruction_root_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{ .target = 1, .arguments = &resume_arguments },
            .resume_type = .{ .scalar = .u8 },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};
const MappedInstructionRootBody = struct {
    pub const InitialArgs = u8;
    pub const Result = u8;
    pub const Failure = MappedInstructionRootFailure;
    pub const effect_sites = .{MappedInstructionPolicy};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "mapped-instruction-root",
        .value_types = &.{ .{ .scalar = .u8 }, .{ .scalar = .u8 } },
        .blocks = &mapped_instruction_root_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u8 },
    };
};
const mapped_instruction_provider_blocks = [_]boundary.ir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .instructions = &.{
        .{
            .kind = .constant,
            .result = 1,
            .operation = .{ .constant = 0 },
        },
        .{
            .kind = .pure,
            .result = 2,
            .operands = &.{ 0, 1 },
            .operation = .integer_add,
        },
    },
    .terminator = .{ .return_value = 2 },
}};
const MappedInstructionProviderBody = struct {
    pub const InitialArgs = u8;
    pub const Result = u8;
    pub const Failure = MappedInstructionProviderFailure;
    pub const constants = .{@as(u8, 1)};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "mapped-instruction-provider",
        .value_types = &.{
            .{ .scalar = .u8 },
            .{ .scalar = .u8 },
            .{ .scalar = .u8 },
        },
        .blocks = &mapped_instruction_provider_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u8 },
    };
};
const MappedInstructionRoot = boundary.program(
    "mapped-instruction-root",
    MappedInstructionRootBody,
);
const MappedInstructionProvider = boundary.program(
    "mapped-instruction-provider",
    MappedInstructionProviderBody,
);
pub const MappedInstructionSpec = .{
    .name = "mapped-instruction-system",
    .root = MappedInstructionRoot,
    .handlers = .{world.systemHandle(.{
        .consumer = MappedInstructionRoot,
        .site = MappedInstructionPolicy,
        .provider = MappedInstructionProvider,
        .failure_morphism = world.failureMorphism(
            MappedInstructionProviderFailure,
            MappedInstructionRootFailure,
            .{MappedInstructionRootFailure.mapped},
        ),
    })},
    .morphisms = .{},
    .external = .{},
};
pub const MappedInstructionSystem = world.system(MappedInstructionSpec);

test "world.system maps provider instruction failures inside ordinary BPI1" {
    const Image = MappedInstructionSystem.Program.image();
    try std.testing.expectEqual(
        boundary.image.evaluator_semantics_v2,
        Image.evaluator_semantics_version,
    );
    const Storage = boundary.process_v1.CapacityStorage(.{
        .input = 4096,
        .output = 4096,
        .state = 4096,
        .value = 4096,
        .request = 4096,
        .environment = 4096,
        .scratch = 64 * 1024,
    });
    var first_storage: Storage = .{};
    var second_storage: Storage = .{};
    var first_workspace: boundary.image.ValidationWorkspace = .{};
    var second_workspace: boundary.image.ValidationWorkspace = .{};
    const first = try first_storage.advance(
        &Image.bytes,
        .{ .initial_args = &.{std.math.maxInt(u8)} },
        null,
        &first_workspace,
    );
    const state = first.progressed;
    const second = try second_storage.advance(
        &Image.bytes,
        .{ .process_state = state },
        null,
        &second_workspace,
    );
    try std.testing.expectEqual(
        @as(u32, @intFromEnum(MappedInstructionRootFailure.mapped)),
        std.mem.readInt(u32, second.authored_failure[0..4], .little),
    );
}

const AuthoredInstructionProviderFailure = enum { custom };
const authored_instruction_provider_blocks = [_]boundary.ir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .instructions = &.{
        .{
            .kind = .constant,
            .result = 1,
            .operation = .{ .constant = 0 },
        },
        .{
            .kind = .constant,
            .result = 2,
            .operation = .{ .constant = 1 },
        },
        .{
            .kind = .pure,
            .result = 3,
            .operands = &.{ 0, 1, 2 },
            .operation = .integer_add,
        },
    },
    .terminator = .{ .return_value = 3 },
}};
const AuthoredInstructionProviderBody = struct {
    pub const InitialArgs = u8;
    pub const Result = u8;
    pub const Failure = AuthoredInstructionProviderFailure;
    pub const constants = .{
        @as(u8, 1),
        AuthoredInstructionProviderFailure.custom,
    };
    pub const effect_sites = .{};
    pub const schema_types = .{AuthoredInstructionProviderFailure};
    pub const control_ir: boundary.ir.Program = .{
        .label = "authored-instruction-provider",
        .value_types = &.{
            .{ .scalar = .u8 },
            .{ .scalar = .u8 },
            .{ .schema = 0 },
            .{ .scalar = .u8 },
        },
        .blocks = &authored_instruction_provider_blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u8 },
    };
};
const AuthoredInstructionProvider = boundary.program(
    "authored-instruction-provider",
    AuthoredInstructionProviderBody,
);
pub const AuthoredInstructionSpec = .{
    .name = "authored-instruction-system",
    .root = MappedInstructionRoot,
    .handlers = .{world.systemHandle(.{
        .consumer = MappedInstructionRoot,
        .site = MappedInstructionPolicy,
        .provider = AuthoredInstructionProvider,
        .failure_morphism = world.failureMorphism(
            AuthoredInstructionProviderFailure,
            MappedInstructionRootFailure,
            .{MappedInstructionRootFailure.mapped},
        ),
    })},
    .morphisms = .{},
    .external = .{},
};
pub const AuthoredInstructionSystem = world.system(AuthoredInstructionSpec);

test "world.system translates authored evaluator-v2 provider failures exactly once" {
    const Image = AuthoredInstructionSystem.Program.image();
    try std.testing.expectEqual(
        boundary.image.evaluator_semantics_v2,
        Image.evaluator_semantics_version,
    );
    const Storage = boundary.process_v1.CapacityStorage(.{
        .input = 4096,
        .output = 4096,
        .state = 4096,
        .value = 4096,
        .request = 4096,
        .environment = 4096,
        .scratch = 64 * 1024,
    });
    var first_storage: Storage = .{};
    var second_storage: Storage = .{};
    var first_workspace: boundary.image.ValidationWorkspace = .{};
    var second_workspace: boundary.image.ValidationWorkspace = .{};
    const first = try first_storage.advance(
        &Image.bytes,
        .{ .initial_args = &.{std.math.maxInt(u8)} },
        null,
        &first_workspace,
    );
    const second = try second_storage.advance(
        &Image.bytes,
        .{ .process_state = first.progressed },
        null,
        &second_workspace,
    );
    try std.testing.expectEqual(
        @as(u32, @intFromEnum(MappedInstructionRootFailure.mapped)),
        std.mem.readInt(u32, second.authored_failure[0..4], .little),
    );
}

const SameFailureV2Body = struct {
    pub const InitialArgs = void;
    pub const Result = u8;
    pub const Failure = AuthoredInstructionProviderFailure;
    pub const constants = .{
        @as(u8, std.math.maxInt(u8)),
        @as(u8, 1),
        AuthoredInstructionProviderFailure.custom,
    };
    pub const effect_sites = .{};
    pub const schema_types = .{AuthoredInstructionProviderFailure};
    pub const control_ir: boundary.ir.Program = .{
        .label = "same-failure-v2-root",
        .value_types = &.{
            .{ .scalar = .u8 },
            .{ .scalar = .u8 },
            .{ .schema = 0 },
            .{ .scalar = .u8 },
        },
        .blocks = &.{.{
            .id = 0,
            .instructions = &.{
                .{
                    .kind = .constant,
                    .result = 0,
                    .operation = .{ .constant = 0 },
                },
                .{
                    .kind = .constant,
                    .result = 1,
                    .operation = .{ .constant = 1 },
                },
                .{
                    .kind = .constant,
                    .result = 2,
                    .operation = .{ .constant = 2 },
                },
                .{
                    .kind = .pure,
                    .result = 3,
                    .operands = &.{ 0, 1, 2 },
                    .operation = .integer_add,
                },
            },
            .terminator = .{ .return_value = 3 },
        }},
        .entry = 0,
        .result_type = .{ .scalar = .u8 },
    };
};
const SameFailureV2Program = boundary.program(
    "same-failure-v2-root",
    SameFailureV2Body,
);
const SameFailureV2System = world.system(.{
    .name = "same-failure-v2-root",
    .root = SameFailureV2Program,
    .handlers = .{},
    .morphisms = .{},
    .external = .{},
});

test "world.system preserves authored evaluator-v2 failures without a morphism" {
    const Image = SameFailureV2System.Program.image();
    try std.testing.expectEqual(
        boundary.image.evaluator_semantics_v2,
        Image.evaluator_semantics_version,
    );
}

pub const MorphSource = boundary.effect.site(
    0,
    "generic.morph-source.v1",
    u32,
    u32,
);
pub const MorphTarget = boundary.effect.site(
    0,
    "generic.morph-target.v1",
    u32,
    u32,
);
const morph_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
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
const MorphBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{MorphSource};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "morph-root",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &morph_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
pub const MorphProgram = boundary.program("morph-root", MorphBody);
const MorphedSystem = world.system(.{
    .name = "morphed-system",
    .root = MorphProgram,
    .handlers = .{},
    .morphisms = .{world.systemMorphism(.{
        .consumer = MorphProgram,
        .site = MorphSource,
        .target = MorphTarget,
    })},
    .external = .{MorphTarget},
});

test "world.system calculates the residual effect after one morphism" {
    const MorphedMachine = MorphedSystem.Program.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 16,
    });
    try std.testing.expectEqual(@as(usize, 1), MorphedSystem.residual_effects.count);
    try expectResidualSite(MorphedSystem.residual_effects.items[0], MorphTarget, 0);
    try std.testing.expectEqualStrings(
        MorphTarget.semantic_identity,
        MorphedMachine.EffectRow.site(0).semantic_identity,
    );
}

const MappedFailure = enum {
    policy_denied,
};
const ProviderFailure = enum {
    denied,
};
pub const FailureSite = boundary.effect.site(
    0,
    "generic.failure-policy.v1",
    u32,
    u32,
);
const failure_root_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
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
const FailureRootBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = MappedFailure;
    pub const effect_sites = .{FailureSite};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "failure-root",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &failure_root_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const failure_provider_blocks = [_]boundary.ir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .terminator = .{ .fail = 0 },
}};
const FailureProviderBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = ProviderFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const block_costs = [_]u64{11};
    pub const control_ir: boundary.ir.Program = .{
        .label = "failure-provider",
        .value_types = &.{u32_type},
        .blocks = &failure_provider_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
pub const FailureRootProgram = boundary.program("failure-root", FailureRootBody);
pub const FailureProviderProgram = boundary.program(
    "failure-provider",
    FailureProviderBody,
);
const FailureMap = world.failureMorphism(
    ProviderFailure,
    MappedFailure,
    .{MappedFailure.policy_denied},
);
const FailureSystem = world.system(.{
    .name = "failure-system",
    .root = FailureRootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = FailureRootProgram,
        .site = FailureSite,
        .provider = FailureProviderProgram,
        .failure_morphism = FailureMap,
    })},
    .morphisms = .{},
    .external = .{},
});

test "world.system applies one explicit pure total Failure morphism" {
    const FailureMachine = FailureSystem.Program.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const state = try FailureMachine.initialState(std.testing.allocator, 7);
    defer FailureMachine.deinitState(state);
    var fuel: u64 = 64;
    const failure = switch (try FailureMachine.step(state, &fuel)) {
        .failed => |value| value,
        else => return error.TestUnexpectedResult,
    };
    switch (failure) {
        .authored => |value| try std.testing.expectEqual(
            MappedFailure.policy_denied,
            value,
        ),
        else => return error.TestUnexpectedFailure,
    }
}

test "world.system preserves authored failure-block cost before its adapter" {
    const Linked = FailureSystem.Program.component();
    try std.testing.expectEqual(@as(u64, 11), Linked.block_costs[2]);
    try std.testing.expectEqual(@as(usize, 0), Linked.control_ir.blocks[2].instructions.len);
    try std.testing.expect(Linked.control_ir.blocks[2].terminator == .jump);
    try std.testing.expectEqual(@as(u64, 2), Linked.block_costs[3]);
    try std.testing.expectEqual(@as(usize, 1), Linked.control_ir.blocks[3].instructions.len);
}

const WrongProviderBody = struct {
    pub const InitialArgs = bool;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "wrong-provider",
        .value_types = &.{.{ .scalar = .boolean }},
        .blocks = &.{.{
            .id = 0,
            .parameters = &.{0},
            .terminator = .{ .fail = 0 },
        }},
        .entry = 0,
        .result_type = u32_type,
    };
};
pub const WrongProviderProgram = boundary.program(
    "wrong-provider",
    WrongProviderBody,
);

pub const CycleASite = boundary.effect.site(
    0,
    "generic.cycle-a.v1",
    u32,
    u32,
);
pub const CycleBSite = boundary.effect.site(
    0,
    "generic.cycle-b.v1",
    u32,
    u32,
);
const cycle_a_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
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
const CycleABody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{CycleASite};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "cycle-a",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &cycle_a_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const CycleBBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{CycleBSite};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "cycle-b",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &cycle_a_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
pub const CycleAProgram = boundary.program("cycle-a", CycleABody);
pub const CycleBProgram = boundary.program("cycle-b", CycleBBody);

pub const DynamicProviderFailure = enum(u8) {
    denied = 3,
    retry = 9,
};
pub const DynamicSystemFailure = enum(u32) {
    policy_denied = 70_000,
    policy_retry = 90_000,
};
pub const DynamicFailureSite = boundary.effect.site(
    0,
    "generic.dynamic-failure.v1",
    DynamicProviderFailure,
    u32,
);
const dynamic_failure_type: boundary.ir.ValueType = .{ .schema = 0 };
const dynamic_root_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
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
const DynamicRootBody = struct {
    pub const InitialArgs = DynamicProviderFailure;
    pub const Result = u32;
    pub const Failure = DynamicSystemFailure;
    pub const effect_sites = .{DynamicFailureSite};
    pub const schema_types = .{DynamicProviderFailure};
    pub const control_ir: boundary.ir.Program = .{
        .label = "dynamic-failure-root",
        .value_types = &.{ dynamic_failure_type, u32_type },
        .blocks = &dynamic_root_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const dynamic_provider_blocks = [_]boundary.ir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .terminator = .{ .fail_value = 0 },
}};
const DynamicProviderBody = struct {
    pub const InitialArgs = DynamicProviderFailure;
    pub const Result = u32;
    pub const Failure = DynamicProviderFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{DynamicProviderFailure};
    pub const control_ir: boundary.ir.Program = .{
        .label = "dynamic-failure-provider",
        .value_types = &.{dynamic_failure_type},
        .blocks = &dynamic_provider_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
pub const DynamicRootProgram = boundary.program(
    "dynamic-failure-root",
    DynamicRootBody,
);
pub const DynamicProviderProgram = boundary.program(
    "dynamic-failure-provider",
    DynamicProviderBody,
);
const DynamicFailureMap = world.failureMorphism(
    DynamicProviderFailure,
    DynamicSystemFailure,
    .{
        DynamicSystemFailure.policy_retry,
        DynamicSystemFailure.policy_denied,
    },
);
const DynamicFailureSystem = world.system(.{
    .name = "dynamic-failure-system",
    .root = DynamicRootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = DynamicRootProgram,
        .site = DynamicFailureSite,
        .provider = DynamicProviderProgram,
        .failure_morphism = DynamicFailureMap,
    })},
    .morphisms = .{},
    .external = .{},
});

test "world.system lowers dynamic fail_value through the total Failure morphism" {
    const DynamicMachine = DynamicFailureSystem.Program.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    inline for (.{
        .{ DynamicProviderFailure.denied, DynamicSystemFailure.policy_retry },
        .{ DynamicProviderFailure.retry, DynamicSystemFailure.policy_denied },
    }) |case| {
        const state = try DynamicMachine.initialState(std.testing.allocator, case[0]);
        defer DynamicMachine.deinitState(state);
        var fuel: u64 = 16;
        const failure = switch (try DynamicMachine.step(state, &fuel)) {
            .failed => |value| value,
            else => return error.TestUnexpectedResult,
        };
        switch (failure) {
            .authored => |value| try std.testing.expectEqual(case[1], value),
            else => return error.TestUnexpectedFailure,
        }
    }
}

const WideProviderFailure = enum(u32) {
    p00,
    p01,
    p02,
    p03,
    p04,
    p05,
    p06,
    p07,
    p08,
    p09,
    p10,
    p11,
    p12,
    p13,
    p14,
    p15,
    p16,
    p17,
    p18,
    p19,
    p20,
    p21,
    p22,
    p23,
    p24,
    p25,
    p26,
    p27,
    p28,
    p29,
    p30,
    p31,
    p32,
    p33,
    p34,
    p35,
    p36,
    p37,
    p38,
    p39,
    p40,
    p41,
    p42,
    p43,
    p44,
    p45,
    p46,
    p47,
    p48,
    p49,
    p50,
    p51,
    p52,
    p53,
    p54,
    p55,
    p56,
    p57,
    p58,
    p59,
    p60,
    p61,
    p62,
    p63,
};
const WideSystemFailure = enum(u32) {
    s00,
    s01,
    s02,
    s03,
    s04,
    s05,
    s06,
    s07,
    s08,
    s09,
    s10,
    s11,
    s12,
    s13,
    s14,
    s15,
    s16,
    s17,
    s18,
    s19,
    s20,
    s21,
    s22,
    s23,
    s24,
    s25,
    s26,
    s27,
    s28,
    s29,
    s30,
    s31,
    s32,
    s33,
    s34,
    s35,
    s36,
    s37,
    s38,
    s39,
    s40,
    s41,
    s42,
    s43,
    s44,
    s45,
    s46,
    s47,
    s48,
    s49,
    s50,
    s51,
    s52,
    s53,
    s54,
    s55,
    s56,
    s57,
    s58,
    s59,
    s60,
    s61,
    s62,
    s63,
};
const wide_provider_failure_type: boundary.ir.ValueType = .{ .schema = 0 };
const wide_provider_arguments = [_]boundary.ir.EdgeArgument{.{ .value = 0 }};
const wide_provider_instructions = [_]boundary.ir.Instruction{
    .{
        .kind = .pure,
        .result = 1,
        .operands = &.{0},
        .operation = .enum_to_u32,
    },
    .{
        .kind = .constant,
        .result = 2,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 3,
        .operands = &.{ 1, 2 },
        .operation = .integer_equal,
    },
};
const wide_provider_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &wide_provider_instructions,
        .terminator = .{ .branch = .{
            .condition = 3,
            .then_edge = .{ .target = 1, .arguments = &wide_provider_arguments },
            .else_edge = .{ .target = 2, .arguments = &wide_provider_arguments },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{4},
        .terminator = .{ .fail_value = 4 },
    },
    .{
        .id = 2,
        .parameters = &.{5},
        .terminator = .{ .fail_value = 5 },
    },
};
const WideFailureSite = boundary.effect.site(
    0,
    "generic.wide-failure.v1",
    WideProviderFailure,
    u32,
);
const wide_root_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
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
const WideRootBody = struct {
    pub const InitialArgs = WideProviderFailure;
    pub const Result = u32;
    pub const Failure = WideSystemFailure;
    pub const effect_sites = .{WideFailureSite};
    pub const schema_types = .{ WideProviderFailure, WideSystemFailure };
    pub const control_ir: boundary.ir.Program = .{
        .label = "wide-failure-root",
        .value_types = &.{ wide_provider_failure_type, u32_type },
        .blocks = &wide_root_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const WideProviderBody = struct {
    pub const InitialArgs = WideProviderFailure;
    pub const Result = u32;
    pub const Failure = WideProviderFailure;
    pub const constants = .{@as(u32, 0)};
    pub const effect_sites = .{};
    pub const schema_types = .{WideProviderFailure};
    pub const control_ir: boundary.ir.Program = .{
        .label = "wide-failure-provider",
        .value_types = &.{
            wide_provider_failure_type,
            u32_type,
            u32_type,
            .{ .scalar = .boolean },
            wide_provider_failure_type,
            wide_provider_failure_type,
        },
        .blocks = &wide_provider_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
pub const WideRootProgram = boundary.program("wide-failure-root", WideRootBody);
pub const WideProviderProgram = boundary.program(
    "wide-failure-provider",
    WideProviderBody,
);
const WideFailureMap = world.failureMorphism(
    WideProviderFailure,
    WideSystemFailure,
    [_]WideSystemFailure{
        .s63, .s62, .s61, .s60, .s59, .s58, .s57, .s56,
        .s55, .s54, .s53, .s52, .s51, .s50, .s49, .s48,
        .s47, .s46, .s45, .s44, .s43, .s42, .s41, .s40,
        .s39, .s38, .s37, .s36, .s35, .s34, .s33, .s32,
        .s31, .s30, .s29, .s28, .s27, .s26, .s25, .s24,
        .s23, .s22, .s21, .s20, .s19, .s18, .s17, .s16,
        .s15, .s14, .s13, .s12, .s11, .s10, .s09, .s08,
        .s07, .s06, .s05, .s04, .s03, .s02, .s01, .s00,
    },
);
pub const WideFailureSpec = .{
    .name = "wide-failure-system",
    .root = WideRootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = WideRootProgram,
        .site = WideFailureSite,
        .provider = WideProviderProgram,
        .failure_morphism = WideFailureMap,
    })},
    .morphisms = .{},
    .external = .{},
};
pub const WideFailureSystem = world.system(WideFailureSpec);

test "world.system shares one wide Failure mapper across dynamic fail sites" {
    const Linked = WideFailureSystem.Program.component();
    try std.testing.expectEqual(@as(usize, 8), Linked.control_ir.blocks.len);
    try std.testing.expectEqual(@as(usize, 3), Linked.control_ir.functions.len);
    const WideMachine = WideFailureSystem.Program.compile(.{
        .maximum_frames = 8,
        .maximum_state_bytes = 16_384,
        .maximum_machine_fuel = 1024,
    });
    inline for (.{
        .{ WideProviderFailure.p00, WideSystemFailure.s63 },
        .{ WideProviderFailure.p31, WideSystemFailure.s32 },
        .{ WideProviderFailure.p63, WideSystemFailure.s00 },
    }) |case| {
        const state = try WideMachine.initialState(std.testing.allocator, case[0]);
        defer WideMachine.deinitState(state);
        var fuel: u64 = 1024;
        const failure = switch (try WideMachine.step(state, &fuel)) {
            .failed => |value| value,
            else => return error.TestUnexpectedResult,
        };
        switch (failure) {
            .authored => |value| try std.testing.expectEqual(case[1], value),
            else => return error.TestUnexpectedFailure,
        }
    }
}

const ConstantWideFailureMap = world.failureMorphism(
    WideProviderFailure,
    WideSystemFailure,
    [_]WideSystemFailure{.s00} ** 64,
);
pub const ConstantWideFailureSpec = .{
    .name = "constant-wide-failure-system",
    .root = WideRootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = WideRootProgram,
        .site = WideFailureSite,
        .provider = WideProviderProgram,
        .failure_morphism = ConstantWideFailureMap,
    })},
    .morphisms = .{},
    .external = .{},
};
pub const ConstantWideFailureSystem = world.system(ConstantWideFailureSpec);

const alternating_targets = blk: {
    var result: [64]WideSystemFailure = undefined;
    for (0..64) |index| result[index] = if (index % 2 == 0) .s00 else .s01;
    break :blk result;
};
const AlternatingWideFailureMap = world.failureMorphism(
    WideProviderFailure,
    WideSystemFailure,
    alternating_targets,
);
pub const AlternatingWideFailureSpec = .{
    .name = "alternating-wide-failure-system",
    .root = WideRootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = WideRootProgram,
        .site = WideFailureSite,
        .provider = WideProviderProgram,
        .failure_morphism = AlternatingWideFailureMap,
    })},
    .morphisms = .{},
    .external = .{},
};
pub const AlternatingWideFailureSystem = world.system(AlternatingWideFailureSpec);

test "world.system quotients constant and repeated Failure targets" {
    try std.testing.expectEqual(
        @as(usize, 6),
        ConstantWideFailureSystem.Program.component().control_ir.blocks.len,
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        AlternatingWideFailureSystem.Program.component().control_ir.blocks.len,
    );
    try std.testing.expect(
        AlternatingWideFailureSystem.Program.component().control_ir.value_types.len <
            WideFailureSystem.Program.component().control_ir.value_types.len,
    );
}

const inert_component_blocks = [_]boundary.ir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .terminator = .{ .return_value = 0 },
}};
const EmptyBindingBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{};
    pub const effect_handlers = .{};
    pub const effect_morphisms = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "empty-binding-root",
        .value_types = &.{u32_type},
        .blocks = &inert_component_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const EmptyBindingProgram = boundary.program(
    "empty-binding-root",
    EmptyBindingBody,
);
const EmptyBindingSystem = world.system(.{
    .name = "empty-binding-system",
    .root = EmptyBindingProgram,
    .handlers = .{},
    .morphisms = .{},
    .external = .{},
});

test "world.system accepts explicit empty component bindings" {
    try std.testing.expectEqual(@as(usize, 1), EmptyBindingSystem.component_count);
    try std.testing.expectEqual(@as(usize, 0), EmptyBindingSystem.internal_handler_count);
    try std.testing.expectEqual(@as(usize, 0), EmptyBindingSystem.residual_effects.count);
    try std.testing.expect(EmptyBindingSystem.Program.image().bytes.len > 0);
}

const InertHandlerSite = boundary.effect.site(
    0,
    "generic.inert-handler.v1",
    u32,
    u32,
);
const InertHandlerRootBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{InertHandlerSite};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "inert-handler-root",
        .value_types = &.{u32_type},
        .blocks = &inert_component_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const InertHandlerProviderBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "inert-handler-provider",
        .value_types = &.{u32_type},
        .blocks = &inert_component_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
pub const InertHandlerRoot = boundary.program(
    "inert-handler-root",
    InertHandlerRootBody,
);
pub const InertHandlerProvider = boundary.program(
    "inert-handler-provider",
    InertHandlerProviderBody,
);
pub const InertHandlerSpec = .{
    .name = "inert-handler-system",
    .root = InertHandlerRoot,
    .handlers = .{world.systemHandle(.{
        .consumer = InertHandlerRoot,
        .site = InertHandlerSite,
        .provider = InertHandlerProvider,
    })},
    .morphisms = .{},
    .external = .{},
};
pub const InertHandlerSystem = world.system(InertHandlerSpec);

test "world.system excludes handlers behind unreachable source sites" {
    try std.testing.expectEqual(@as(usize, 1), InertHandlerSystem.component_count);
    try std.testing.expectEqual(@as(usize, 0), InertHandlerSystem.internal_handler_count);
    try std.testing.expectEqual(@as(usize, 0), InertHandlerSystem.residual_effects.count);
    try std.testing.expectEqual(
        @as(usize, 0),
        boundary.componentAdmission(InertHandlerSystem.Program)
            .residual_effects.residual_count,
    );
}

const InertMorphismTarget = boundary.effect.site(
    1,
    "generic.inert-morphism-target.v1",
    u32,
    u32,
);
pub const InertMorphismSpec = .{
    .name = "inert-morphism-system",
    .root = InertHandlerRoot,
    .handlers = .{},
    .morphisms = .{world.systemMorphism(.{
        .consumer = InertHandlerRoot,
        .site = InertHandlerSite,
        .target = InertMorphismTarget,
    })},
    .external = .{},
};
pub const InertMorphismSystem = world.system(InertMorphismSpec);

test "world.system excludes morphisms behind unreachable source sites" {
    const Linked = InertMorphismSystem.Program.component();
    try std.testing.expectEqual(@as(usize, 1), InertMorphismSystem.component_count);
    try std.testing.expectEqual(@as(usize, 0), InertMorphismSystem.residual_effects.count);
    try std.testing.expectEqual(@as(usize, 0), InertMorphismSystem.residual_effects.items.len);
    try std.testing.expectEqual(@as(usize, 0), Linked.effect_morphisms.len);
}

const VoidSite = boundary.effect.site(
    0,
    "generic.void-policy.v1",
    void,
    void,
);
const unit_type: boundary.ir.ValueType = .{ .scalar = .unit };
const void_root_instructions = [_]boundary.ir.Instruction{.{
    .kind = .constant,
    .result = 0,
    .operation = .{ .constant = 0 },
}};
const void_root_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .instructions = &void_root_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
            },
            .resume_type = unit_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = null },
    },
};
const VoidRootBody = struct {
    pub const InitialArgs = void;
    pub const Result = void;
    pub const Failure = SystemFailure;
    pub const constants = .{@as(void, {})};
    pub const effect_sites = .{VoidSite};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "void-root",
        .value_types = &.{ unit_type, unit_type },
        .blocks = &void_root_blocks,
        .entry = 0,
        .result_type = unit_type,
    };
};
const void_provider_blocks = [_]boundary.ir.Block{.{
    .id = 0,
    .terminator = .{ .return_value = null },
}};
const VoidProviderBody = struct {
    pub const InitialArgs = void;
    pub const Result = void;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const block_costs = [_]u64{13};
    pub const control_ir: boundary.ir.Program = .{
        .label = "void-provider",
        .value_types = &.{},
        .blocks = &void_provider_blocks,
        .entry = 0,
        .result_type = unit_type,
    };
};
const VoidRootProgram = boundary.program("void-root", VoidRootBody);
const VoidProviderProgram = boundary.program("void-provider", VoidProviderBody);
const VoidSystem = world.system(.{
    .name = "void-system",
    .root = VoidRootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = VoidRootProgram,
        .site = VoidSite,
        .provider = VoidProviderProgram,
    })},
    .morphisms = .{},
    .external = .{},
});

test "world.system internal handlers preserve void Resume and Result" {
    const VoidMachine = VoidSystem.Program.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    try std.testing.expectEqual(@as(usize, 0), VoidMachine.EffectRow.operation_site_count);
    const state = try VoidMachine.initialState(std.testing.allocator, {});
    defer VoidMachine.deinitState(state);
    var fuel: u64 = 64;
    const completed = switch (try VoidMachine.step(state, &fuel)) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer completed.deinit();
}

test "world.system preserves authored void-return cost before its adapter" {
    const Linked = VoidSystem.Program.component();
    try std.testing.expectEqual(@as(u64, 13), Linked.block_costs[2]);
    try std.testing.expectEqual(@as(usize, 0), Linked.control_ir.blocks[2].instructions.len);
    try std.testing.expect(Linked.control_ir.blocks[2].terminator == .jump);
    try std.testing.expectEqual(@as(u64, 2), Linked.block_costs[3]);
    try std.testing.expectEqual(@as(usize, 1), Linked.control_ir.blocks[3].instructions.len);
}

const nonroot_entry_instructions = [_]boundary.ir.Instruction{.{
    .kind = .constant,
    .result = 0,
    .operation = .{ .constant = 0 },
}};
const nonroot_entry_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .instructions = &nonroot_entry_instructions,
        .terminator = .{ .return_value = 0 },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};
const NonrootEntryBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const constants = .{@as(u32, 42)};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "nonroot-entry",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &nonroot_entry_blocks,
        .entry = 1,
        .result_type = u32_type,
    };
};
const NonrootEntryProgram = boundary.program("nonroot-entry", NonrootEntryBody);
const NonrootEntrySystem = world.system(.{
    .name = "nonroot-entry-system",
    .root = NonrootEntryProgram,
    .handlers = .{},
    .morphisms = .{},
    .external = .{},
});

test "world.system preserves a root component entry other than block zero" {
    const EntryMachine = NonrootEntrySystem.Program.compile(.{
        .maximum_frames = 2,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 8,
    });
    const state = try EntryMachine.initialState(std.testing.allocator, 7);
    defer EntryMachine.deinitState(state);
    var fuel: u64 = 4;
    const completed = switch (try EntryMachine.step(state, &fuel)) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer completed.deinit();
    try std.testing.expectEqual(@as(u32, 7), completed.value().*);
}

const CostBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const block_costs = [_]u64{10};
    pub const control_ir: boundary.ir.Program = .{
        .label = "cost-root",
        .value_types = &.{u32_type},
        .blocks = &.{.{
            .id = 0,
            .parameters = &.{0},
            .terminator = .{ .return_value = 0 },
        }},
        .entry = 0,
        .result_type = u32_type,
    };
};
const CostProgram = boundary.program("cost-root", CostBody);
const CostSystem = world.system(.{
    .name = "cost-system",
    .root = CostProgram,
    .handlers = .{},
    .morphisms = .{},
    .external = .{},
});

test "world.system preserves component-authored Machine-v2 block costs" {
    try std.testing.expectEqualSlices(
        u8,
        &CostProgram.machine_v2_semantic_digest,
        &CostSystem.Program.machine_v2_semantic_digest,
    );
}

const DuplicateMorphA = boundary.effect.site(
    0,
    "generic.duplicate-source-a.v1",
    u32,
    u32,
);
const DuplicateMorphB = boundary.effect.site(
    1,
    "generic.duplicate-source-b.v1",
    u32,
    u32,
);
const DuplicateTarget = boundary.effect.site(
    0,
    "generic.duplicate-target.v1",
    u32,
    u32,
);
const DuplicateTargetB = boundary.effect.site(
    0,
    "generic.duplicate-target-b.v1",
    u32,
    u32,
);
const duplicate_morph_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 1,
            .request_values = &.{1},
            .continuation = .{
                .target = 2,
                .arguments = &resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 2,
        .parameters = &.{2},
        .terminator = .{ .return_value = 2 },
    },
};
const DuplicateMorphBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{ DuplicateMorphA, DuplicateMorphB };
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "duplicate-morph-root",
        .value_types = &.{ u32_type, u32_type, u32_type },
        .blocks = &duplicate_morph_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const DuplicateMorphProgram = boundary.program(
    "duplicate-morph-root",
    DuplicateMorphBody,
);
const DuplicateMorphSystem = world.system(.{
    .name = "duplicate-morph-system",
    .root = DuplicateMorphProgram,
    .handlers = .{},
    .morphisms = .{
        world.systemMorphism(.{
            .consumer = DuplicateMorphProgram,
            .site = DuplicateMorphA,
            .target = DuplicateTarget,
        }),
        world.systemMorphism(.{
            .consumer = DuplicateMorphProgram,
            .site = DuplicateMorphB,
            .target = DuplicateTargetB,
        }),
    },
    .external = .{ DuplicateTarget, DuplicateTargetB },
});

test "world.system retains every reachable residual source-site occurrence" {
    const DuplicateMachine = DuplicateMorphSystem.Program.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 16,
    });
    try std.testing.expectEqual(@as(usize, 2), DuplicateMorphSystem.residual_effects.count);
    try expectResidualSite(
        DuplicateMorphSystem.residual_effects.items[0],
        DuplicateTarget,
        0,
    );
    try expectResidualSite(
        DuplicateMorphSystem.residual_effects.items[1],
        DuplicateTargetB,
        1,
    );
    try std.testing.expectEqual(@as(usize, 2), DuplicateMachine.EffectRow.operation_site_count);
}

const CollidingExternalSite = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "generic.colliding-external-site.v1";
    pub const Payload = u32;
    pub const Resume = u32;
    pub const binding_kind = enum { external }.external;
};
const colliding_external_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{ .target = 1, .arguments = &resume_arguments },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};
const CollidingExternalBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{CollidingExternalSite};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "colliding-external-site",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &colliding_external_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const CollidingExternalProgram = boundary.program(
    "colliding-external-site",
    CollidingExternalBody,
);
const CollidingExternalSystem = world.system(.{
    .name = "colliding-external-site",
    .root = CollidingExternalProgram,
    .handlers = .{},
    .morphisms = .{},
    .external = .{CollidingExternalSite},
});

test "world.system bare Site shorthand ignores unrelated binding_kind declarations" {
    try std.testing.expectEqual(
        @as(usize, 1),
        CollidingExternalSystem.residual_effects.count,
    );
    _ = CollidingExternalSystem.Program.image();
}

const OrderPolicyA = boundary.effect.site(
    0,
    "generic.order-policy-a.v1",
    u32,
    u32,
);
const OrderPolicyB = boundary.effect.site(
    1,
    "generic.order-policy-b.v1",
    u32,
    u32,
);
const order_root_blocks = duplicate_morph_blocks;
const OrderRootBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{ OrderPolicyA, OrderPolicyB };
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "order-root",
        .value_types = &.{ u32_type, u32_type, u32_type },
        .blocks = &order_root_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

fn PureProvider(comptime label: []const u8, comptime delta: u32) type {
    const GeneratedBody = struct {
        const instructions = [_]boundary.ir.Instruction{
            .{
                .kind = .constant,
                .result = 1,
                .operation = .{ .constant = 0 },
            },
            .{
                .kind = .pure,
                .result = 2,
                .operands = &.{ 0, 1 },
                .operation = .integer_add,
            },
        };
        const blocks = [_]boundary.ir.Block{.{
            .id = 0,
            .parameters = &.{0},
            .instructions = &instructions,
            .terminator = .{ .return_value = 2 },
        }};
        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = SystemFailure;
        pub const constants = .{delta};
        pub const effect_sites = .{};
        pub const schema_types = .{};
        pub const control_ir: boundary.ir.Program = .{
            .label = label,
            .value_types = &.{ u32_type, u32_type, u32_type },
            .blocks = &blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
    return boundary.program(label, GeneratedBody);
}

const OrderRootProgram = boundary.program("order-root", OrderRootBody);
const OrderProviderA = PureProvider("order-provider-a", 1);
const OrderProviderB = PureProvider("order-provider-b", 2);
const OrderHandlerA = world.systemHandle(.{
    .consumer = OrderRootProgram,
    .site = OrderPolicyA,
    .provider = OrderProviderA,
});
const OrderHandlerB = world.systemHandle(.{
    .consumer = OrderRootProgram,
    .site = OrderPolicyB,
    .provider = OrderProviderB,
});
const OrderSystemAB = world.system(.{
    .name = "order-system",
    .root = OrderRootProgram,
    .handlers = .{ OrderHandlerA, OrderHandlerB },
    .morphisms = .{},
    .external = .{},
});
const OrderSystemBA = world.system(.{
    .name = "order-system",
    .root = OrderRootProgram,
    .handlers = .{ OrderHandlerB, OrderHandlerA },
    .morphisms = .{},
    .external = .{},
});

test "world.system canonical identity ignores handler tuple ordering" {
    try std.testing.expectEqualSlices(
        u8,
        &OrderSystemAB.Program.image().bytes,
        &OrderSystemBA.Program.image().bytes,
    );
}

const SharedOccurrence = struct {
    pub const Payload = u32;
    pub const Resume = u32;
    pub const semantic_identity = "generic.shared-occurrence.v1";
};

const shared_occurrence_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
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

fn SharedOccurrenceProgram(comptime label: []const u8) type {
    const Body = struct {
        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = SystemFailure;
        pub const effect_sites = .{SharedOccurrence};
        pub const schema_types = .{};
        pub const control_ir: boundary.ir.Program = .{
            .label = label,
            .value_types = &.{ u32_type, u32_type },
            .blocks = &shared_occurrence_blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
    return boundary.program(label, Body);
}

const SharedOccurrenceRoot = SharedOccurrenceProgram("shared-occurrence-root");
const SharedOccurrenceProvider = SharedOccurrenceProgram("shared-occurrence-provider");
const SharedOccurrenceSystem = world.system(.{
    .name = "shared-occurrence-system",
    .root = SharedOccurrenceRoot,
    .handlers = .{world.systemHandle(.{
        .consumer = SharedOccurrenceRoot,
        .site = SharedOccurrence,
        .provider = SharedOccurrenceProvider,
    })},
    .morphisms = .{},
    .external = .{world.systemExternal(.{
        .consumer = SharedOccurrenceProvider,
        .site = SharedOccurrence,
    })},
});

test "world.system dispositions belong to component-site occurrences" {
    const SharedMachine = SharedOccurrenceSystem.Program.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 16,
    });
    try std.testing.expectEqual(@as(usize, 1), SharedOccurrenceSystem.residual_effects.count);
    const state = try SharedMachine.initialState(std.testing.allocator, 7);
    defer SharedMachine.deinitState(state);
    var fuel: u64 = 8;
    const request = switch (try SharedMachine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u32, 7), request.value.s0);
}

const void_backedge_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .terminator = .{ .jump = .{ .target = 1 } },
    },
    .{
        .id = 1,
        .terminator = .{ .jump = .{ .target = 0 } },
    },
};
const VoidBackedgeBody = struct {
    pub const InitialArgs = void;
    pub const Result = void;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "void-backedge-provider",
        .value_types = &.{},
        .blocks = &void_backedge_blocks,
        .entry = 0,
        .result_type = unit_type,
    };
};
const VoidBackedgeProvider = boundary.program(
    "void-backedge-provider",
    VoidBackedgeBody,
);
const VoidBackedgeSystem = world.system(.{
    .name = "void-backedge-system",
    .root = VoidRootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = VoidRootProgram,
        .site = VoidSite,
        .provider = VoidBackedgeProvider,
    })},
    .morphisms = .{},
    .external = .{},
});

test "world.system preserves void provider backedges behind a wrapper" {
    const Linked = VoidBackedgeSystem.Program.component();
    const provider_backedge = Linked.control_ir.blocks[3].terminator.jump;
    try std.testing.expectEqual(@as(boundary.ir.BlockId, 2), provider_backedge.target);
    try std.testing.expectEqual(@as(usize, 0), provider_backedge.arguments.len);
}

const DiamondLeaf = struct {
    pub const Payload = u32;
    pub const Resume = u32;
    pub const semantic_identity = "generic.diamond-leaf.v1";
};

fn DiamondBranch(comptime label: []const u8) type {
    const Body = struct {
        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = SystemFailure;
        pub const effect_sites = .{DiamondLeaf};
        pub const schema_types = .{};
        pub const control_ir: boundary.ir.Program = .{
            .label = label,
            .value_types = &.{ u32_type, u32_type },
            .blocks = &shared_occurrence_blocks,
            .entry = 0,
            .result_type = u32_type,
        };
    };
    return boundary.program(label, Body);
}

const DiamondBranchA = DiamondBranch("diamond-branch-a");
const DiamondBranchB = DiamondBranch("diamond-branch-b");
const DiamondProvider = PureProvider("diamond-provider", 1);
const DiamondSystem = world.system(.{
    .name = "diamond-system",
    .root = OrderRootProgram,
    .handlers = .{
        world.systemHandle(.{
            .consumer = OrderRootProgram,
            .site = OrderPolicyA,
            .provider = DiamondBranchA,
        }),
        world.systemHandle(.{
            .consumer = OrderRootProgram,
            .site = OrderPolicyB,
            .provider = DiamondBranchB,
        }),
        world.systemHandle(.{
            .consumer = DiamondBranchA,
            .site = DiamondLeaf,
            .provider = DiamondProvider,
        }),
        world.systemHandle(.{
            .consumer = DiamondBranchB,
            .site = DiamondLeaf,
            .provider = DiamondProvider,
        }),
    },
    .morphisms = .{},
    .external = .{},
});

test "world.system validates a shared-provider DAG once per component" {
    try std.testing.expectEqual(@as(usize, 4), DiamondSystem.component_count);
    try std.testing.expectEqual(@as(usize, 0), DiamondSystem.residual_effects.count);
    try std.testing.expect(DiamondSystem.Program.image().bytes.len > 0);
}

const void_dead_provider_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .terminator = .{ .return_value = null },
    },
    .{
        .id = 1,
        .terminator = .{ .jump = .{ .target = 0 } },
    },
    .{
        .id = 2,
        .terminator = .{ .return_value = null },
    },
};
const VoidDeadProviderBody = struct {
    pub const InitialArgs = void;
    pub const Result = void;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "void-dead-provider",
        .value_types = &.{},
        .blocks = &void_dead_provider_blocks,
        .entry = 0,
        .result_type = unit_type,
    };
};
const VoidDeadProvider = boundary.program(
    "void-dead-provider",
    VoidDeadProviderBody,
);
pub const VoidDeadSpec = .{
    .name = "void-dead-system",
    .root = VoidRootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = VoidRootProgram,
        .site = VoidSite,
        .provider = VoidDeadProvider,
    })},
    .morphisms = .{},
    .external = .{},
};
pub const VoidDeadSystem = world.system(VoidDeadSpec);

test "world.system preserves unreachable void-entry predecessors behind a wrapper" {
    const Linked = VoidDeadSystem.Program.component();
    const dead_edge = Linked.control_ir.blocks[3].terminator.jump;
    try std.testing.expectEqual(@as(boundary.ir.BlockId, 2), dead_edge.target);
    try std.testing.expectEqual(@as(usize, 0), dead_edge.arguments.len);
    try std.testing.expectEqual(@as(usize, 3), Linked.control_ir.functions.len);
    const dead_return = Linked.control_ir.blocks[4].terminator.jump;
    try std.testing.expectEqual(@as(boundary.ir.BlockId, 4), dead_return.target);
    try std.testing.expectEqual(@as(usize, 0), dead_return.arguments.len);

    const DeadMachine = VoidDeadSystem.Program.compile(.{
        .maximum_frames = 8,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    const state = try DeadMachine.initialState(std.testing.allocator, {});
    defer DeadMachine.deinitState(state);
    var fuel: u64 = 64;
    const completed = switch (try DeadMachine.step(state, &fuel)) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer completed.deinit();
}

const shared_void_exit_instructions = [_]boundary.ir.Instruction{.{
    .kind = .constant,
    .result = 0,
    .operation = .{ .constant = 0 },
}};
const shared_void_exit_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .instructions = &shared_void_exit_instructions,
        .terminator = .{ .branch = .{
            .condition = 0,
            .then_edge = .{ .target = 1 },
            .else_edge = .{ .target = 2 },
        } },
    },
    .{ .id = 1, .terminator = .{ .return_value = null } },
    .{ .id = 2, .terminator = .{ .return_value = null } },
};
const SharedVoidExitBody = struct {
    pub const InitialArgs = void;
    pub const Result = void;
    pub const Failure = SystemFailure;
    pub const constants = .{@as(bool, true)};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "shared-void-exit-provider",
        .value_types = &.{.{ .scalar = .boolean }},
        .blocks = &shared_void_exit_blocks,
        .entry = 0,
        .result_type = unit_type,
    };
};
pub const SharedVoidExitProvider = boundary.program(
    "shared-void-exit-provider",
    SharedVoidExitBody,
);
pub const SharedVoidExitSpec = .{
    .name = "shared-void-exit-system",
    .root = VoidRootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = VoidRootProgram,
        .site = VoidSite,
        .provider = SharedVoidExitProvider,
    })},
    .morphisms = .{},
    .external = .{},
};
pub const SharedVoidExitSystem = world.system(SharedVoidExitSpec);

test "world.system shares one unit adapter across void exits" {
    const Linked = SharedVoidExitSystem.Program.component();
    try std.testing.expectEqual(
        @as(usize, 8),
        Linked.control_ir.blocks.len,
    );
    try std.testing.expectEqual(
        Linked.control_ir.blocks[3].terminator.jump.target,
        Linked.control_ir.blocks[4].terminator.jump.target,
    );
    try std.testing.expectEqual(
        @as(boundary.ir.BlockId, 5),
        Linked.control_ir.blocks[3].terminator.jump.target,
    );
    try std.testing.expectEqual(
        boundary.ir.BlockRole.terminal_handoff,
        Linked.control_ir.blocks[5].role,
    );
    try std.testing.expectEqual(
        boundary.ir.BlockRole.segment,
        Linked.control_ir.blocks[6].role,
    );
    try std.testing.expectEqual(
        boundary.ir.BlockRole.terminal_handoff,
        Linked.control_ir.blocks[7].role,
    );
}

const RoleSource = boundary.effect.site(
    0,
    "generic.role-source.v1",
    u32,
    u32,
);
const RoleTarget = boundary.effect.site(
    1,
    "generic.role-target.v1",
    u32,
    u32,
);
const external_role_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 1,
            .request_values = &.{1},
            .continuation = .{
                .target = 2,
                .arguments = &resume_arguments,
            },
            .resume_type = u32_type,
        } },
    },
    .{
        .id = 2,
        .parameters = &.{2},
        .terminator = .{ .return_value = 2 },
    },
};
const ExternalRoleBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{ RoleSource, RoleTarget };
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "external-role-root",
        .value_types = &.{ u32_type, u32_type, u32_type },
        .blocks = &external_role_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const ExternalRoleRoot = boundary.program("external-role-root", ExternalRoleBody);
const ExternalRoleProvider = PureProvider("external-role-provider", 1);
pub const ExternalRoleSpec = .{
    .name = "external-role-system",
    .root = ExternalRoleRoot,
    .handlers = .{world.systemHandle(.{
        .consumer = ExternalRoleRoot,
        .site = RoleTarget,
        .provider = ExternalRoleProvider,
    })},
    .morphisms = .{world.systemMorphism(.{
        .consumer = ExternalRoleRoot,
        .site = RoleSource,
        .target = RoleTarget,
    })},
    .external = .{RoleTarget},
};
pub const ExternalRoleSystem = world.system(ExternalRoleSpec);

test "world.system separates morphism targets from source dispositions" {
    const RoleMachine = ExternalRoleSystem.Program.compile(.{
        .maximum_frames = 8,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 64,
    });
    try std.testing.expectEqual(@as(usize, 1), ExternalRoleSystem.residual_effects.count);
    try expectResidualSite(
        ExternalRoleSystem.residual_effects.items[0],
        RoleTarget,
        0,
    );
    try std.testing.expectEqual(@as(u32, 1), RoleTarget.id);
    try std.testing.expectEqualStrings(
        RoleTarget.semantic_identity,
        RoleMachine.EffectRow.site(0).semantic_identity,
    );
    const state = try RoleMachine.initialState(std.testing.allocator, 4);
    defer RoleMachine.deinitState(state);
    var fuel: u64 = 64;
    const request = switch (try RoleMachine.step(state, &fuel)) {
        .request => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u32, 4), request.value.s0);
    {
        const prepared = try RoleMachine.prepareResume(state, request);
        defer RoleMachine.deinitPreparedResume(prepared);
        try RoleMachine.@"resume"(prepared, @as(u32, 5));
    }
    const completed = switch (try RoleMachine.step(state, &fuel)) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer completed.deinit();
    try std.testing.expectEqual(@as(u32, 6), completed.value().*);
}

const EmptyProviderFailure = enum {};
const EmptyFailureSite = boundary.effect.site(
    0,
    "generic.empty-failure.v1",
    u32,
    u32,
);
const empty_failure_type: boundary.ir.ValueType = .{ .schema = 0 };
const empty_failure_root_blocks = failure_root_blocks;
const EmptyFailureRootBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{EmptyFailureSite};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "empty-failure-root",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &empty_failure_root_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const empty_failure_provider_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .return_value = 0 },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .fail_value = 1 },
    },
};
const EmptyFailureProviderBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = EmptyProviderFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{EmptyProviderFailure};
    pub const control_ir: boundary.ir.Program = .{
        .label = "empty-failure-provider",
        .value_types = &.{ u32_type, empty_failure_type },
        .blocks = &empty_failure_provider_blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};
const EmptyFailureRoot = boundary.program("empty-failure-root", EmptyFailureRootBody);
const EmptyFailureProvider = boundary.program(
    "empty-failure-provider",
    EmptyFailureProviderBody,
);
const EmptyFailureMap = world.failureMorphism(
    EmptyProviderFailure,
    SystemFailure,
    .{},
);
pub const EmptyFailureSpec = .{
    .name = "empty-failure-system",
    .root = EmptyFailureRoot,
    .handlers = .{world.systemHandle(.{
        .consumer = EmptyFailureRoot,
        .site = EmptyFailureSite,
        .provider = EmptyFailureProvider,
        .failure_morphism = EmptyFailureMap,
    })},
    .morphisms = .{},
    .external = .{},
};
pub const EmptyFailureSystem = world.system(EmptyFailureSpec);

test "world.system closes zero-cardinality Failure layout" {
    const Linked = EmptyFailureSystem.Program.component();
    try std.testing.expectEqual(@as(usize, 4), Linked.control_ir.blocks.len);
    const dead_edge = Linked.control_ir.blocks[3].terminator.jump;
    try std.testing.expectEqual(@as(boundary.ir.BlockId, 3), dead_edge.target);

    const EmptyMachine = EmptyFailureSystem.Program.compile(.{
        .maximum_frames = 4,
        .maximum_state_bytes = 4096,
        .maximum_machine_fuel = 32,
    });
    const state = try EmptyMachine.initialState(std.testing.allocator, 9);
    defer EmptyMachine.deinitState(state);
    var fuel: u64 = 32;
    const completed = switch (try EmptyMachine.step(state, &fuel)) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer completed.deinit();
    try std.testing.expectEqual(@as(u32, 9), completed.value().*);
}

const UnusedDeclared = boundary.effect.site(
    0,
    "generic.unused-declared.v1",
    u32,
    u32,
);
const UnusedDeclaredBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{UnusedDeclared};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "unused-declared",
        .value_types = &.{u32_type},
        .blocks = &.{.{
            .id = 0,
            .parameters = &.{0},
            .terminator = .{ .return_value = 0 },
        }},
        .entry = 0,
        .result_type = u32_type,
    };
};
const UnusedDeclaredProgram = boundary.program(
    "unused-declared",
    UnusedDeclaredBody,
);
pub const UnusedDeclaredSpec = .{
    .name = "unused-declared-system",
    .root = UnusedDeclaredProgram,
    .handlers = .{},
    .morphisms = .{},
    .external = .{},
};
pub const UnusedDeclaredSystem = world.system(UnusedDeclaredSpec);

test "world.system ignores unreachable effect declarations" {
    try std.testing.expectEqual(@as(usize, 0), UnusedDeclaredSystem.residual_effects.count);
    try std.testing.expect(UnusedDeclaredSystem.Program.image().bytes.len > 0);
}

const helper_instructions = [_]boundary.ir.Instruction{.{
    .kind = .constant,
    .result = 1,
    .operation = .{ .constant = 0 },
}};
const helper_return_instructions = [_]boundary.ir.Instruction{.{
    .kind = .copy,
    .result = 2,
    .operands = &.{1},
    .operation = .copy,
}};
const unreachable_helper_blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .return_value = 0 },
    },
    .{
        .id = 1,
        .function_id = 1,
        .instructions = &helper_instructions,
        .terminator = .{ .jump = .{ .target = 2 } },
    },
    .{
        .id = 2,
        .function_id = 1,
        .instructions = &helper_return_instructions,
        .terminator = .{ .return_to_caller = 2 },
    },
};
const unreachable_helper_functions = [_]boundary.ir.Function{
    .{ .id = 0, .entry = 0, .result_type = u32_type },
    .{ .id = 1, .entry = 1, .result_type = u32_type },
};
const UnreachableHelperBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = SystemFailure;
    pub const constants = .{@as(u32, 7)};
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "unreachable-helper",
        .value_types = &.{ u32_type, u32_type, u32_type },
        .blocks = &unreachable_helper_blocks,
        .entry = 0,
        .result_type = u32_type,
        .functions = &unreachable_helper_functions,
    };
};
const UnreachableHelperProgram = boundary.program(
    "unreachable-helper",
    UnreachableHelperBody,
);
pub const UnreachableHelperSpec = .{
    .name = "unreachable-helper-system",
    .root = UnreachableHelperProgram,
    .handlers = .{},
    .morphisms = .{},
    .external = .{},
};
pub const UnreachableHelperSystem = world.system(UnreachableHelperSpec);

test "world.system preserves unreachable helper SSA topology" {
    const Linked = UnreachableHelperSystem.Program.component();
    try std.testing.expectEqual(
        @as(boundary.ir.BlockId, 2),
        Linked.control_ir.blocks[1].terminator.jump.target,
    );
    try std.testing.expectEqual(
        @as(boundary.ir.ValueId, 1),
        Linked.control_ir.blocks[2].instructions[0].operands[0],
    );
    try std.testing.expect(UnreachableHelperSystem.Program.image().bytes.len > 0);
}
