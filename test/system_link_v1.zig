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
const System = world.system(.{
    .name = "generic-system",
    .root = RootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = RootProgram,
        .site = InternalPolicy,
        .provider = ProviderProgram,
    })},
    .morphisms = .{},
    .external = .{ Observe, ProviderObserve },
});

const Machine = System.Program.compile(.{
    .maximum_frames = 8,
    .maximum_state_bytes = 4096,
    .maximum_machine_fuel = 64,
});

test "world.system links one internal Program handler into one BPI1" {
    try std.testing.expectEqual(@as(usize, 2), System.component_count);
    try std.testing.expectEqual(@as(usize, 1), System.internal_handler_count);
    try std.testing.expectEqual(@as(usize, 1), System.schema_count);
    try std.testing.expectEqual(@as(usize, 2), System.residual_effects.count);
    try std.testing.expect(System.residual_effects.items[0] == Observe);
    try std.testing.expect(System.residual_effects.items[1] == ProviderObserve);
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
    try std.testing.expect(MorphedSystem.residual_effects.items[0] == MorphTarget);
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
        .maximum_machine_fuel = 16,
    });
    const state = try FailureMachine.initialState(std.testing.allocator, 7);
    defer FailureMachine.deinitState(state);
    var fuel: u64 = 8;
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

const DynamicProviderFailure = enum(u8) {
    denied = 3,
    retry = 9,
};
const DynamicSystemFailure = enum {
    policy_denied,
    policy_retry,
};
const DynamicFailureSite = boundary.effect.site(
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
const DynamicRootProgram = boundary.program(
    "dynamic-failure-root",
    DynamicRootBody,
);
const DynamicProviderProgram = boundary.program(
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

const VoidSite = boundary.effect.site(
    0,
    "generic.void-policy.v1",
    u32,
    void,
);
const unit_type: boundary.ir.ValueType = .{ .scalar = .unit };
const void_root_blocks = [_]boundary.ir.Block{
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
    pub const InitialArgs = u32;
    pub const Result = void;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{VoidSite};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "void-root",
        .value_types = &.{ u32_type, unit_type },
        .blocks = &void_root_blocks,
        .entry = 0,
        .result_type = unit_type,
    };
};
const void_provider_blocks = [_]boundary.ir.Block{.{
    .id = 0,
    .parameters = &.{0},
    .terminator = .{ .return_value = null },
}};
const VoidProviderBody = struct {
    pub const InitialArgs = u32;
    pub const Result = void;
    pub const Failure = SystemFailure;
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "void-provider",
        .value_types = &.{u32_type},
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
        .maximum_machine_fuel = 16,
    });
    try std.testing.expectEqual(@as(usize, 0), VoidMachine.EffectRow.operation_site_count);
    const state = try VoidMachine.initialState(std.testing.allocator, 7);
    defer VoidMachine.deinitState(state);
    var fuel: u64 = 8;
    const completed = switch (try VoidMachine.step(state, &fuel)) {
        .done => |value| value,
        else => return error.TestUnexpectedResult,
    };
    defer completed.deinit();
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
