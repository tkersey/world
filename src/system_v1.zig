const boundary = @import("boundary");
const std = @import("std");

const cir = boundary.ir;
const system_eval_branch_quota = 500_000_000;

const BindingKind = enum {
    handler,
    morphism,
};

const SiteDisposition = enum {
    inactive,
    handler,
    morphism,
    external,
};

pub fn handle(comptime config: anytype) type {
    inline for (.{ "consumer", "site", "provider" }) |field| {
        if (!@hasField(@TypeOf(config), field)) {
            @compileError("world.systemHandle requires " ++ field);
        }
    }
    return struct {
        pub const binding_kind = BindingKind.handler;
        pub const Consumer = config.consumer;
        pub const Site = config.site;
        pub const site_ordinal = resolveSiteOrdinal(config.consumer, config);
        pub const Provider = config.provider;
        pub const FailureMorphism = if (@hasField(
            @TypeOf(config),
            "failure_morphism",
        )) config.failure_morphism else void;
    };
}

pub fn morphism(comptime config: anytype) type {
    inline for (.{ "consumer", "site", "target" }) |field| {
        if (!@hasField(@TypeOf(config), field)) {
            @compileError("world.systemMorphism requires " ++ field);
        }
    }
    return struct {
        pub const binding_kind = BindingKind.morphism;
        pub const Consumer = config.consumer;
        pub const Site = config.site;
        pub const site_ordinal = resolveSiteOrdinal(config.consumer, config);
        pub const Target = config.target;
    };
}

pub fn external(comptime config: anytype) type {
    inline for (.{ "consumer", "site" }) |field| {
        if (!@hasField(@TypeOf(config), field)) {
            @compileError("world.systemExternal requires " ++ field);
        }
    }
    return struct {
        pub const Consumer = config.consumer;
        pub const Site = config.site;
        pub const site_ordinal = resolveSiteOrdinal(config.consumer, config);
    };
}

pub fn failureMorphism(
    comptime Source: type,
    comptime Target: type,
    comptime target_values: anytype,
) type {
    requireFailureEnum(Source, "failure morphism Source");
    requireFailureEnum(Target, "failure morphism Target");
    const source_fields = @typeInfo(Source).@"enum".fields;
    if (target_values.len != source_fields.len) {
        @compileError("World failure morphism must map every provider Failure tag");
    }
    const mapping = comptime blk: {
        var source_tags: [target_values.len]u32 = undefined;
        var mapped_targets: [target_values.len]Target = undefined;
        for (target_values, 0..) |target, index| {
            if (@TypeOf(target) != Target) {
                @compileError("World failure morphism targets must use system Failure");
            }
            source_tags[index] = @intCast(source_fields[index].value);
            mapped_targets[index] = target;
        }
        break :blk .{ source_tags, mapped_targets };
    };
    return struct {
        pub const SourceFailure = Source;
        pub const TargetFailure = Target;
        pub const source_tags = mapping[0];
        pub const targets = mapping[1];
    };
}

pub fn system(comptime spec: anytype) type {
    @setEvalBranchQuota(system_eval_branch_quota);
    if (!@hasField(@TypeOf(spec), "name") or
        !@hasField(@TypeOf(spec), "root"))
    {
        @compileError("world.system requires name and root");
    }
    const name: []const u8 = spec.name;
    if (name.len == 0) @compileError("world.system name must be non-empty");
    const handlers = if (@hasField(@TypeOf(spec), "handlers"))
        spec.handlers
    else
        .{};
    const morphisms = if (@hasField(@TypeOf(spec), "morphisms"))
        spec.morphisms
    else
        .{};
    const externals = if (@hasField(@TypeOf(spec), "external"))
        spec.external
    else
        .{};
    const components = comptime componentsFor(spec.root, handlers, morphisms);
    const Plan = PlanFor(
        spec.root,
        components,
        handlers,
        morphisms,
        externals,
    );
    comptime validateSystem(Plan);
    const Linked = LinkedBody(name, Plan);
    const LinkedProgram = boundary.program(name, Linked.Body);
    return struct {
        pub const Program = LinkedProgram;
        pub const InitialArgs = Linked.Body.InitialArgs;
        pub const Result = Linked.Body.Result;
        pub const Failure = Linked.Body.Failure;
        pub const residual_effects = Linked.residual_effects;
        pub const schema_count = Linked.schema_count;
        pub const component_count = Plan.components.count;
        pub const internal_handler_count = activeHandlerCount(
            Plan.components,
            handlers,
        );
    };
}

fn ComponentSet(comptime capacity: usize) type {
    return struct {
        items: [capacity]type = undefined,
        failure_maps: [capacity]type = undefined,
        admissions: [capacity]type = undefined,
        count: usize = 0,

        fn contains(self: @This(), comptime Program: type) bool {
            inline for (0..self.count) |index| {
                if (self.items[index] == Program) return true;
            }
            return false;
        }

        fn containsInstance(
            self: @This(),
            comptime Program: type,
            comptime FailureMap: type,
        ) bool {
            inline for (0..self.count) |index| {
                if (self.items[index] == Program and
                    failureMapsEqual(self.failure_maps[index], FailureMap))
                {
                    return true;
                }
            }
            return false;
        }

        fn add(
            self: *@This(),
            comptime Program: type,
            comptime FailureMap: type,
        ) bool {
            if (self.containsInstance(Program, FailureMap)) return false;
            const Admission = boundary.componentAdmission(Program);
            self.items[self.count] = Program;
            self.failure_maps[self.count] = FailureMap;
            self.admissions[self.count] = Admission;
            self.count += 1;
            return true;
        }

        fn admissionAt(comptime self: @This(), comptime index: usize) type {
            return self.admissions[index];
        }

        fn failureMapAt(comptime self: @This(), comptime index: usize) type {
            return self.failure_maps[index];
        }

        fn indexOfInstance(
            comptime self: @This(),
            comptime Program: type,
            comptime FailureMap: type,
        ) usize {
            inline for (0..self.count) |index| {
                if (self.items[index] == Program and
                    failureMapsEqual(self.failure_maps[index], FailureMap))
                {
                    return index;
                }
            }
            unreachable;
        }
    };
}

fn componentsFor(
    comptime Root: type,
    comptime handlers: anytype,
    comptime morphisms: anytype,
) ComponentSet(1 + handlers.len * 2 + morphisms.len) {
    var result: ComponentSet(1 + handlers.len * 2 + morphisms.len) = .{};
    _ = result.add(Root, void);
    inline for (handlers) |Handler| {
        requireHandler(Handler);
    }
    inline for (morphisms) |Morphism| {
        requireMorphism(Morphism);
    }
    discoverComponents(&result, 0, handlers);
    return result;
}

fn PlanFor(
    comptime Root: type,
    comptime components_value: anytype,
    comptime handlers_value: anytype,
    comptime morphisms_value: anytype,
    comptime externals_value: anytype,
) type {
    const dispositions = comptime blk: {
        var result: [totalEffects(components_value)]SiteDisposition = undefined;
        for (0..components_value.count) |component_index| {
            const Program = components_value.items[component_index];
            for (body(Program).effect_sites, 0..) |Site, site_ordinal| {
                const linked_id = effectOffset(components_value, component_index) +
                    site_ordinal;
                if (!admittedSiteReachableAt(
                    components_value,
                    component_index,
                    site_ordinal,
                )) {
                    result[linked_id] = .inactive;
                    continue;
                }
                const internal_count = handlerCount(
                    handlers_value,
                    Program,
                    site_ordinal,
                );
                const morphism_count = morphismCount(
                    morphisms_value,
                    Program,
                    site_ordinal,
                );
                const external_count = externalSourceCountRaw(
                    components_value,
                    handlers_value,
                    morphisms_value,
                    externals_value,
                    Program,
                    site_ordinal,
                    Site,
                );
                const count = internal_count + morphism_count + external_count;
                if (count == 0) {
                    @compileError(
                        "World system has an uncovered non-external effect site",
                    );
                }
                if (count != 1) {
                    @compileError("World system effect site has ambiguous disposition");
                }
                result[linked_id] = if (internal_count == 1)
                    .handler
                else if (morphism_count == 1)
                    .morphism
                else
                    .external;
            }
        }
        break :blk result;
    };
    const failure_maps = comptime blk: {
        var result: [components_value.count]type = undefined;
        for (0..components_value.count) |component_index| {
            result[component_index] = components_value.failureMapAt(component_index);
        }
        break :blk result;
    };
    const failure_quotients = comptime blk: {
        var result: [components_value.count]type = undefined;
        for (0..components_value.count) |component_index| {
            result[component_index] = FailureQuotientProjection(
                failure_maps[component_index],
            );
        }
        break :blk result;
    };
    const dynamic_failure_components = comptime blk: {
        var result: [components_value.count]bool = undefined;
        for (0..components_value.count) |component_index| {
            result[component_index] = componentHasDynamicFailureForMap(
                components_value,
                component_index,
                failure_maps[component_index],
                failure_quotients[component_index],
            );
        }
        break :blk result;
    };
    const failure_selector_owners = comptime blk: {
        var result: [components_value.count]?usize = undefined;
        for (0..components_value.count) |component_index| {
            result[component_index] = null;
            if (!dynamic_failure_components[component_index]) continue;
            const Map = failure_maps[component_index];
            for (0..component_index + 1) |candidate_index| {
                if (!dynamic_failure_components[candidate_index]) continue;
                const CandidateMap = failure_maps[candidate_index];
                if (failureMapsEqual(Map, CandidateMap)) {
                    result[component_index] = candidate_index;
                    break;
                }
            }
        }
        break :blk result;
    };
    const failure_layouts = comptime blk: {
        var result: [totalBlocks(components_value)]FailureAdapterLayout = undefined;
        for (0..components_value.count) |component_index| {
            const Map = failure_maps[component_index];
            for (body(components_value.items[component_index]).control_ir.blocks) |block| {
                const linked_id = blockOffset(components_value, component_index) +
                    block.id;
                if (!components_value.admissionAt(component_index)
                    .reachability.contains(block.id))
                {
                    result[linked_id] = .{ .kind = .none };
                    continue;
                }
                var layout = failureAdapterLayout(
                    Map,
                    failure_quotients[component_index],
                    block.terminator,
                );
                if (layout.kind == .direct) {
                    const owner_block = directFailureOwnerBlockForMap(
                        components_value,
                        component_index,
                        block.id,
                        Map,
                        failure_quotients[component_index],
                    );
                    if (owner_block != block.id) {
                        layout = .{
                            .kind = .direct_alias,
                            .direct_owner_block = owner_block,
                        };
                    } else {
                        layout.direct_owner_block = owner_block;
                    }
                } else if (layout.kind == .dynamic) {
                    layout.selector_owner_component =
                        failure_selector_owners[component_index].?;
                }
                result[linked_id] = layout;
            }
        }
        break :blk result;
    };
    return struct {
        pub const RootProgram = Root;
        pub const components = components_value;
        pub const handlers = handlers_value;
        pub const morphisms = morphisms_value;
        pub const externals = externals_value;
        pub const site_dispositions = dispositions;
        pub const failure_map_types = failure_maps;
        pub const failure_quotient_projections = failure_quotients;
        pub const failure_selector_owner_components = failure_selector_owners;
        pub const failure_adapter_layouts = failure_layouts;
        pub fn blockReachable(
            comptime component_index: usize,
            comptime block_id: cir.BlockId,
        ) bool {
            return components.admissionAt(component_index)
                .reachability.contains(block_id);
        }

        pub fn siteDisposition(
            comptime component_index: usize,
            comptime site_ordinal: usize,
        ) SiteDisposition {
            return site_dispositions[
                effectOffset(components, component_index) + site_ordinal
            ];
        }

        pub fn failureLayout(
            comptime component_index: usize,
            comptime block_id: cir.BlockId,
        ) FailureAdapterLayout {
            return failure_adapter_layouts[
                blockOffset(components, component_index) + block_id
            ];
        }

        pub fn failureSelectorOwner(
            comptime component_index: usize,
        ) ?usize {
            return failure_selector_owner_components[component_index];
        }

        pub fn failureMap(comptime component_index: usize) type {
            return failure_map_types[component_index];
        }

        pub fn FailureQuotient(comptime component_index: usize) type {
            return failure_quotient_projections[component_index];
        }
    };
}

fn discoverComponents(
    result: anytype,
    comptime current_index: usize,
    comptime handlers: anytype,
) void {
    const Current = result.items[current_index];
    inline for (body(Current).effect_sites, 0..) |_, site_ordinal| {
        if (!admittedSiteReachableAt(result.*, current_index, site_ordinal)) continue;
        inline for (handlers) |Handler| {
            if (Handler.Consumer == Current and
                Handler.site_ordinal == site_ordinal)
            {
                const FailureMap = handlerFailureMap(
                    Handler,
                    body(result.items[0]).Failure,
                );
                if (result.add(Handler.Provider, FailureMap)) {
                    discoverComponents(
                        result,
                        result.indexOfInstance(
                            Handler.Provider,
                            FailureMap,
                        ),
                        handlers,
                    );
                }
            }
        }
    }
}

fn handlerFailureMap(
    comptime Handler: type,
    comptime RootFailure: type,
) type {
    return if (body(Handler.Provider).Failure == RootFailure)
        void
    else
        Handler.FailureMorphism;
}

fn body(comptime Program: type) type {
    @setEvalBranchQuota(system_eval_branch_quota);
    if (!@hasDecl(Program, "component")) {
        @compileError("world.system components must be Boundary Programs");
    }
    const Body = Program.component();
    inline for (.{
        "InitialArgs",
        "Result",
        "Failure",
        "effect_sites",
        "schema_types",
        "control_ir",
    }) |decl| {
        if (!@hasDecl(Body, decl)) {
            @compileError("Boundary Program component is missing " ++ decl);
        }
    }
    if ((@hasDecl(Body, "effect_handlers") and
        Body.effect_handlers.len != 0) or
        (@hasDecl(Body, "effect_morphisms") and
            Body.effect_morphisms.len != 0))
    {
        @compileError(
            "world.system components must leave handler and morphism selection to World",
        );
    }
    return Body;
}

fn resolveSiteOrdinal(comptime Program: type, comptime config: anytype) usize {
    const Body = body(Program);
    if (@hasField(@TypeOf(config), "site_ordinal")) {
        const ordinal: usize = config.site_ordinal;
        if (ordinal >= Body.effect_sites.len or Body.effect_sites[ordinal] != config.site) {
            @compileError("World system binding site_ordinal does not match its Site");
        }
        return ordinal;
    }
    var match: ?usize = null;
    inline for (Body.effect_sites, 0..) |Site, ordinal| {
        if (Site != config.site) continue;
        if (match != null) {
            @compileError(
                "World system binding must provide site_ordinal for an aliased Site type",
            );
        }
        match = ordinal;
    }
    return match orelse
        @compileError("World system binding Site does not occur in its component");
}

fn validateSystem(comptime Plan: type) void {
    const Root = Plan.RootProgram;
    const components = Plan.components;
    const handlers = Plan.handlers;
    const morphisms = Plan.morphisms;
    const externals = Plan.externals;
    const RootBody = body(Root);
    requireFailureEnum(RootBody.Failure, "root Failure");
    validateExternalDeclarations(components, externals);
    inline for (handlers) |Handler| {
        requireHandler(Handler);
        if (!handlerActive(components, Handler)) continue;
        validateHandler(Handler, RootBody.Failure);
        if (!components.contains(Handler.Provider)) {
            @compileError("World system contains a handler unreachable from root");
        }
    }
    inline for (morphisms) |Morphism| {
        requireMorphism(Morphism);
        if (!morphismActive(components, Morphism)) continue;
        validateMorphism(Morphism);
        if (externalTargetCount(externals, Morphism.Target) != 1) {
            @compileError(
                "World system morphism Target must be intentionally residual",
            );
        }
    }
    validateAcyclic(components, handlers);
    inline for (0..components.count) |component_index| {
        const Program = components.items[component_index];
        const Body = body(Program);
        inline for (Body.effect_sites, 0..) |_, site_ordinal| {
            _ = Plan.siteDisposition(component_index, site_ordinal);
        }
    }
    validateExternalUsage(Plan);
}

fn validateExternalUsage(comptime Plan: type) void {
    const components = Plan.components;
    const handlers = Plan.handlers;
    const morphisms = Plan.morphisms;
    const externals = Plan.externals;
    inline for (externals) |External| {
        var used = false;
        inline for (0..components.count) |component_index| {
            const Program = components.items[component_index];
            inline for (body(Program).effect_sites, 0..) |Site, site_ordinal| {
                if (!componentSiteReachable(Plan, component_index, site_ordinal)) {
                    continue;
                }
                if (!isExternalBinding(External) and
                    siteContractsEqual(External, Site) and
                    bareExternalSourceCount(Plan, Site) == 1 and
                    handlerCount(handlers, Program, site_ordinal) == 0 and
                    morphismCount(morphisms, Program, site_ordinal) == 0)
                {
                    used = true;
                }
                if (isExternalBinding(External) and
                    External.Consumer == Program and
                    External.site_ordinal == site_ordinal and
                    handlerCount(handlers, Program, site_ordinal) == 0 and
                    morphismCount(morphisms, Program, site_ordinal) == 0)
                {
                    used = true;
                }
            }
        }
        inline for (morphisms) |Morphism| {
            if (morphismActive(components, Morphism) and
                !isExternalBinding(External) and
                siteContractsEqual(Morphism.Target, External))
            {
                used = true;
            }
        }
        if (!used) {
            @compileError("World system has an unreachable external declaration");
        }
    }
}

fn failureMapsEqual(comptime Left: type, comptime Right: type) bool {
    if (Left == void or Right == void) return Left == Right;
    if (Left.SourceFailure != Right.SourceFailure or
        Left.TargetFailure != Right.TargetFailure or
        Left.targets.len != Right.targets.len)
    {
        return false;
    }
    inline for (
        Left.source_tags,
        Right.source_tags,
        Left.targets,
        Right.targets,
    ) |left_source, right_source, left_target, right_target| {
        if (left_source != right_source or
            @intFromEnum(left_target) != @intFromEnum(right_target))
        {
            return false;
        }
    }
    return true;
}

fn mappedFailureTarget(comptime Map: type, comptime source_tag: u32) Map.TargetFailure {
    inline for (Map.source_tags, Map.targets) |from, target| {
        if (from == source_tag) return target;
    }
    unreachable;
}

fn FailureTargetQuotient(comptime Map: type) type {
    return struct {
        targets: [Map.targets.len]Map.TargetFailure = undefined,
        source_to_target: [Map.targets.len]usize = undefined,
        count: usize = 0,
    };
}

fn failureTargetQuotient(comptime Map: type) FailureTargetQuotient(Map) {
    var result: FailureTargetQuotient(Map) = .{};
    inline for (Map.targets, 0..) |target, source_index| {
        var target_index: ?usize = null;
        inline for (0..result.count) |index| {
            if (@intFromEnum(result.targets[index]) == @intFromEnum(target)) {
                target_index = index;
            }
        }
        if (target_index == null) {
            target_index = result.count;
            result.targets[result.count] = target;
            result.count += 1;
        }
        result.source_to_target[source_index] = target_index.?;
    }
    return result;
}

fn FailureQuotientProjection(comptime Map: type) type {
    if (Map == void) return struct {};
    return struct {
        pub const value = blk: {
            @setEvalBranchQuota(system_eval_branch_quota);
            break :blk failureTargetQuotient(Map);
        };
    };
}

fn blockInstructionFailureCapacity(comptime block: cir.Block) usize {
    var result: usize = 0;
    inline for (block.instructions) |instruction| {
        result += cir.mappedFailureOperandCount(instruction.operation);
    }
    return result;
}

fn InstructionFailureTargets(
    comptime Failure: type,
    comptime capacity: usize,
) type {
    return struct {
        items: [capacity]Failure = undefined,
        count: usize = 0,

        fn add(self: *@This(), target: Failure) void {
            inline for (0..self.count) |index| {
                if (@intFromEnum(self.items[index]) == @intFromEnum(target)) {
                    return;
                }
            }
            self.items[self.count] = target;
            self.count += 1;
        }

        fn indexOf(self: @This(), target: Failure) usize {
            inline for (0..self.count) |index| {
                if (@intFromEnum(self.items[index]) == @intFromEnum(target)) {
                    return index;
                }
            }
            unreachable;
        }
    };
}

fn blockInstructionFailureTargets(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block: cir.Block,
) InstructionFailureTargets(
    body(Plan.components.items[0]).Failure,
    blockInstructionFailureCapacity(block),
) {
    const RootFailure = body(Plan.components.items[0]).Failure;
    var result: InstructionFailureTargets(
        RootFailure,
        blockInstructionFailureCapacity(block),
    ) = .{};
    const Map = Plan.failureMap(component_index);
    if (Map == void) return result;
    const Admission = Plan.components.admissionAt(component_index);
    inline for (block.instructions) |instruction| {
        const source_tags = Admission.instructionFailureProjection(
            instruction,
        ).failure_tags;
        inline for (source_tags) |source_tag| {
            result.add(mappedFailureTarget(Map, source_tag));
        }
    }
    return result;
}

fn componentInstructionFailureValues(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (body(Plan.components.items[component_index]).control_ir.blocks) |block| {
        result += blockInstructionFailureTargets(
            Plan,
            component_index,
            block,
        ).count;
    }
    return result;
}

const FailureAdapterKind = enum {
    none,
    impossible,
    direct,
    direct_alias,
    dynamic,
};

const FailureAdapterLayout = struct {
    kind: FailureAdapterKind,
    value_count: usize = 0,
    block_count: usize = 0,
    constant_count: usize = 0,
    direct_owner_block: ?cir.BlockId = null,
    selector_owner_component: ?usize = null,
};

fn failureAdapterLayout(
    comptime Map: type,
    comptime QuotientProjection: type,
    comptime terminator: cir.Terminator,
) FailureAdapterLayout {
    if (Map == void) return .{ .kind = .none };
    return switch (terminator) {
        .fail => .{
            .kind = .direct,
            .value_count = 1,
            .block_count = 1,
            .constant_count = 1,
        },
        .fail_value => if (Map.targets.len == 0)
            .{ .kind = .impossible }
        else if (QuotientProjection.value.count == 1)
            .{
                .kind = .direct,
                .value_count = 1,
                .block_count = 1,
                .constant_count = 1,
            }
        else
            .{
                .kind = .dynamic,
                .value_count = 1,
                .block_count = 1,
            },
        else => .{ .kind = .none },
    };
}

fn directFailureTarget(
    comptime Map: type,
    comptime QuotientProjection: type,
    comptime terminator: cir.Terminator,
) ?Map.TargetFailure {
    return switch (terminator) {
        .fail => |source_tag| mappedFailureTarget(Map, source_tag),
        .fail_value => if (QuotientProjection.value.count == 1)
            QuotientProjection.value.targets[0]
        else
            null,
        else => null,
    };
}

fn directFailureOwnerBlockForMap(
    comptime components: anytype,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
    comptime Map: type,
    comptime QuotientProjection: type,
) cir.BlockId {
    const Program = components.items[component_index];
    const Body = body(Program);
    const current = Body.control_ir.blocks[block_id];
    const target = directFailureTarget(
        Map,
        QuotientProjection,
        current.terminator,
    ) orelse unreachable;
    inline for (Body.control_ir.blocks) |candidate| {
        if (candidate.id > block_id) continue;
        if (!components.admissionAt(component_index).reachability.contains(candidate.id)) continue;
        if (candidate.function_id != current.function_id) continue;
        const candidate_target = directFailureTarget(
            Map,
            QuotientProjection,
            candidate.terminator,
        ) orelse continue;
        if (@intFromEnum(candidate_target) == @intFromEnum(target)) return candidate.id;
    }
    unreachable;
}

fn componentExtraValues(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (body(Plan.components.items[component_index]).control_ir.blocks) |block| {
        if (!Plan.blockReachable(component_index, block.id)) continue;
        result += Plan.failureLayout(component_index, block.id).value_count;
    }
    return result;
}

fn componentExtraBlocks(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (body(Plan.components.items[component_index]).control_ir.blocks) |block| {
        if (!Plan.blockReachable(component_index, block.id)) continue;
        result += Plan.failureLayout(component_index, block.id).block_count;
    }
    return result;
}

fn componentExtraConstants(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (body(Plan.components.items[component_index]).control_ir.blocks) |block| {
        if (!Plan.blockReachable(component_index, block.id)) continue;
        result += Plan.failureLayout(component_index, block.id).constant_count;
    }
    return result;
}

fn componentHasDynamicFailureForMap(
    comptime components: anytype,
    comptime component_index: usize,
    comptime Map: type,
    comptime QuotientProjection: type,
) bool {
    inline for (body(components.items[component_index]).control_ir.blocks) |block| {
        if (!components.admissionAt(component_index).reachability.contains(block.id)) {
            continue;
        }
        if (failureAdapterLayout(
            Map,
            QuotientProjection,
            block.terminator,
        ).kind == .dynamic) {
            return true;
        }
    }
    return false;
}

fn componentSharedFailureCount(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    const owner = Plan.failureSelectorOwner(component_index) orelse return 0;
    return @intFromBool(owner == component_index);
}

fn componentSharedFailureValues(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    if (componentSharedFailureCount(Plan, component_index) == 0) return 0;
    return 12;
}

fn componentSharedFailureBlocks(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    if (componentSharedFailureCount(Plan, component_index) == 0) return 0;
    return 3;
}

fn componentSharedFailureConstants(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    if (componentSharedFailureCount(Plan, component_index) == 0) return 0;
    return 5;
}

fn FailureSourceTags(comptime Map: type) type {
    return boundary.schema.Vector(u32, Map.targets.len);
}

fn FailureTargets(comptime Map: type) type {
    return boundary.schema.Vector(Map.TargetFailure, Map.targets.len);
}

fn componentVoidReturnCount(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    if (component_index == 0 or
        body(Plan.components.items[component_index]).Result != void)
    {
        return 0;
    }
    inline for (body(Plan.components.items[component_index]).control_ir.blocks) |block| {
        if (!Plan.blockReachable(component_index, block.id)) continue;
        if (block.function_id != 0) continue;
        switch (block.terminator) {
            .return_value => |value| if (value == null) {
                return 1;
            },
            else => {},
        }
    }
    return 0;
}

fn voidReturnOwnerBlock(
    comptime Plan: type,
    comptime component_index: usize,
) cir.BlockId {
    inline for (body(Plan.components.items[component_index]).control_ir.blocks) |block| {
        if (!Plan.blockReachable(component_index, block.id)) continue;
        if (block.function_id != 0) continue;
        switch (block.terminator) {
            .return_value => |value| if (value == null) return block.id,
            else => {},
        }
    }
    unreachable;
}

fn totalVoidReturns(comptime Plan: type) usize {
    var result: usize = 0;
    inline for (0..Plan.components.count) |index| {
        result += componentVoidReturnCount(Plan, index);
    }
    return result;
}

fn precedingVoidReturns(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentVoidReturnCount(Plan, index);
    }
    return result;
}

fn voidReturnOrdinal(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    inline for (body(Plan.components.items[component_index]).control_ir.blocks) |block| {
        if (block.id == block_id) return 0;
        if (!Plan.blockReachable(component_index, block.id)) continue;
        if (block.function_id != 0) continue;
    }
    unreachable;
}

fn componentVoidWrapperCount(
    comptime components: anytype,
    comptime component_index: usize,
) usize {
    if (component_index == 0) return 0;
    const Body = body(components.items[component_index]);
    return @intFromBool(
        Body.InitialArgs == void and
            Body.control_ir.blocks[Body.control_ir.entry].parameters.len == 0,
    );
}

fn totalVoidWrappers(comptime components: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += componentVoidWrapperCount(components, index);
    }
    return result;
}

fn precedingVoidWrappers(
    comptime components: anytype,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentVoidWrapperCount(components, index);
    }
    return result;
}

fn requireHandler(comptime Handler: type) void {
    if (!@hasDecl(Handler, "binding_kind") or
        @TypeOf(Handler.binding_kind) != BindingKind or
        Handler.binding_kind != .handler)
    {
        @compileError("world.system handlers contains a non-handler binding");
    }
}

fn requireMorphism(comptime Morphism: type) void {
    if (!@hasDecl(Morphism, "binding_kind") or
        @TypeOf(Morphism.binding_kind) != BindingKind or
        Morphism.binding_kind != .morphism)
    {
        @compileError("world.system morphisms contains a non-morphism binding");
    }
}

fn handlerActive(comptime components: anytype, comptime Handler: type) bool {
    inline for (0..components.count) |component_index| {
        if (components.items[component_index] == Handler.Consumer and
            admittedSiteReachableAt(
                components,
                component_index,
                Handler.site_ordinal,
            )) return true;
    }
    return false;
}

fn activeHandlerCount(comptime components: anytype, comptime handlers: anytype) usize {
    var count: usize = 0;
    inline for (0..components.count) |component_index| {
        inline for (handlers) |Handler| {
            if (components.items[component_index] == Handler.Consumer and
                admittedSiteReachableAt(
                    components,
                    component_index,
                    Handler.site_ordinal,
                )) count += 1;
        }
    }
    return count;
}

fn morphismActive(comptime components: anytype, comptime Morphism: type) bool {
    inline for (0..components.count) |component_index| {
        if (components.items[component_index] == Morphism.Consumer and
            admittedSiteReachableAt(
                components,
                component_index,
                Morphism.site_ordinal,
            )) return true;
    }
    return false;
}

fn activeMorphismCount(comptime components: anytype, comptime morphisms: anytype) usize {
    var count: usize = 0;
    inline for (0..components.count) |component_index| {
        inline for (morphisms) |Morphism| {
            if (components.items[component_index] == Morphism.Consumer and
                admittedSiteReachableAt(
                    components,
                    component_index,
                    Morphism.site_ordinal,
                )) count += 1;
        }
    }
    return count;
}

fn validateHandler(
    comptime Handler: type,
    comptime SystemFailure: type,
) void {
    requireHandler(Handler);
    const ConsumerBody = body(Handler.Consumer);
    const ProviderBody = body(Handler.Provider);
    requireComponentSite(ConsumerBody, Handler.Site, Handler.site_ordinal);
    if (Handler.Site.Payload != ProviderBody.InitialArgs) {
        @compileError("World system provider InitialArgs must match effect Payload");
    }
    if (Handler.Site.Resume != ProviderBody.Result) {
        @compileError("World system provider Result must match effect Resume");
    }
    if (ProviderBody.Failure == SystemFailure) {
        if (Handler.FailureMorphism != void) {
            @compileError("World system identical Failure types need no morphism");
        }
        return;
    }
    if (Handler.FailureMorphism == void) {
        @compileError(
            "World system provider Failure requires an explicit pure total morphism",
        );
    }
    const Map = Handler.FailureMorphism;
    validateFailureMap(Map, ProviderBody.Failure, SystemFailure);
}

fn validateFailureMap(
    comptime Map: type,
    comptime SourceFailure: type,
    comptime TargetFailure: type,
) void {
    inline for (.{ "SourceFailure", "TargetFailure", "source_tags", "targets" }) |decl| {
        if (!@hasDecl(Map, decl)) {
            @compileError("World system Failure morphism is missing " ++ decl);
        }
    }
    if (Map.SourceFailure != SourceFailure or Map.TargetFailure != TargetFailure) {
        @compileError("World system failure morphism has the wrong endpoint types");
    }
    const fields = @typeInfo(SourceFailure).@"enum".fields;
    if (Map.source_tags.len != fields.len or Map.targets.len != fields.len) {
        @compileError("World system Failure morphism must cover every source tag");
    }
    inline for (fields, 0..) |field, index| {
        if (Map.source_tags[index] != field.value or
            @TypeOf(Map.targets[index]) != TargetFailure)
        {
            @compileError("World system Failure morphism is not canonical and total");
        }
    }
}

fn validateMorphism(comptime Morphism: type) void {
    requireMorphism(Morphism);
    const ConsumerBody = body(Morphism.Consumer);
    requireComponentSite(ConsumerBody, Morphism.Site, Morphism.site_ordinal);
    if (Morphism.Site.Payload != Morphism.Target.Payload or
        Morphism.Site.Resume != Morphism.Target.Resume)
    {
        @compileError("World system effect morphism must preserve Payload and Resume");
    }
}

fn requireComponentSite(
    comptime Body: type,
    comptime Site: type,
    comptime site_ordinal: usize,
) void {
    if (site_ordinal >= Body.effect_sites.len or
        Body.effect_sites[site_ordinal] != Site)
    {
        @compileError("World system binding occurrence does not match its Site");
    }
}

fn validateExternalDeclarations(
    comptime components: anytype,
    comptime externals: anytype,
) void {
    inline for (externals, 0..) |External, index| {
        if (isExternalBinding(External)) {
            if (!components.contains(External.Consumer)) {
                @compileError("World system contains an external unreachable from root");
            }
            requireComponentSite(
                body(External.Consumer),
                External.Site,
                External.site_ordinal,
            );
        } else if (!isBoundarySite(External)) {
            @compileError(
                "World system external entries must be Boundary Sites or occurrence wrappers",
            );
        }
        inline for (0..index) |prior| {
            if (externalDeclarationsEqual(External, externals[prior])) {
                @compileError("World system has duplicate external declarations");
            }
        }
    }
}

fn isExternalBinding(comptime External: type) bool {
    if (isBoundarySite(External)) return false;
    return @hasDecl(External, "Consumer") and
        @hasDecl(External, "Site") and
        @hasDecl(External, "site_ordinal");
}

fn isBoundarySite(comptime Site: type) bool {
    if (!@hasDecl(Site, "Payload") or
        !@hasDecl(Site, "Resume") or
        !@hasDecl(Site, "semantic_identity") or
        @TypeOf(Site.Payload) != type or
        @TypeOf(Site.Resume) != type or
        !isByteStringType(@TypeOf(Site.semantic_identity)))
    {
        return false;
    }
    return Site.semantic_identity.len != 0;
}

fn isByteStringType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .array => |array| array.child == u8,
        .pointer => |pointer| switch (pointer.size) {
            .slice => pointer.child == u8,
            .one => switch (@typeInfo(pointer.child)) {
                .array => |array| array.child == u8,
                else => false,
            },
            else => false,
        },
        else => false,
    };
}

fn siteContractsEqual(comptime Left: type, comptime Right: type) bool {
    if (!isBoundarySite(Left) or !isBoundarySite(Right)) return false;
    return schemasEqual(Left.Payload, Right.Payload) and
        schemasEqual(Left.Resume, Right.Resume) and
        std.mem.eql(u8, Left.semantic_identity, Right.semantic_identity);
}

fn schemasEqual(comptime Left: type, comptime Right: type) bool {
    return std.mem.eql(
        u8,
        &boundary.schema.schemaDigest(Left),
        &boundary.schema.schemaDigest(Right),
    );
}

fn externalDeclarationsEqual(comptime Left: type, comptime Right: type) bool {
    if (isExternalBinding(Left) != isExternalBinding(Right)) return false;
    if (!isExternalBinding(Left)) return siteContractsEqual(Left, Right);
    return Left.Consumer == Right.Consumer and
        Left.site_ordinal == Right.site_ordinal;
}

fn handlerCount(
    comptime handlers: anytype,
    comptime Program: type,
    comptime site_ordinal: usize,
) usize {
    var count: usize = 0;
    inline for (handlers) |Handler| {
        if (Handler.Consumer == Program and
            Handler.site_ordinal == site_ordinal) count += 1;
    }
    return count;
}

fn morphismCount(
    comptime morphisms: anytype,
    comptime Program: type,
    comptime site_ordinal: usize,
) usize {
    var count: usize = 0;
    inline for (morphisms) |Morphism| {
        if (Morphism.Consumer == Program and
            Morphism.site_ordinal == site_ordinal) count += 1;
    }
    return count;
}

fn externalTargetCount(comptime externals: anytype, comptime Target: type) usize {
    var count: usize = 0;
    inline for (externals) |External| {
        if (!isExternalBinding(External) and
            siteContractsEqual(External, Target)) count += 1;
    }
    return count;
}

fn bareExternalSourceCount(comptime Plan: type, comptime Site: type) usize {
    return bareExternalSourceCountRaw(
        Plan.components,
        Plan.handlers,
        Plan.morphisms,
        Site,
    );
}

fn bareExternalSourceCountRaw(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime morphisms: anytype,
    comptime Site: type,
) usize {
    var count: usize = 0;
    inline for (0..components.count) |component_index| {
        const Program = components.items[component_index];
        inline for (body(Program).effect_sites, 0..) |Candidate, site_ordinal| {
            if (siteContractsEqual(Candidate, Site) and
                admittedSiteReachableAt(
                    components,
                    component_index,
                    site_ordinal,
                ) and
                handlerCount(handlers, Program, site_ordinal) == 0 and
                morphismCount(morphisms, Program, site_ordinal) == 0)
            {
                count += 1;
            }
        }
    }
    return count;
}

fn externalSourceCountRaw(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime morphisms: anytype,
    comptime externals: anytype,
    comptime Program: type,
    comptime site_ordinal: usize,
    comptime Site: type,
) usize {
    var count: usize = 0;
    inline for (externals) |External| {
        if (isExternalBinding(External)) {
            if (External.Consumer == Program and
                External.site_ordinal == site_ordinal) count += 1;
        } else if (siteContractsEqual(External, Site) and
            handlerCount(handlers, Program, site_ordinal) == 0 and
            morphismCount(morphisms, Program, site_ordinal) == 0 and
            bareExternalSourceCountRaw(
                components,
                handlers,
                morphisms,
                Site,
            ) == 1)
        {
            count += 1;
        }
    }
    return count;
}

fn componentSiteReachable(
    comptime Plan: type,
    comptime component_index: usize,
    comptime site_ordinal: usize,
) bool {
    return admittedSiteReachableAt(Plan.components, component_index, site_ordinal);
}

fn admittedSiteReachableAt(
    comptime components: anytype,
    comptime component_index: usize,
    comptime site_ordinal: usize,
) bool {
    return components.admissionAt(component_index)
        .residual_effects.source_to_residual[site_ordinal] != null;
}

const VisitState = enum {
    unseen,
    visiting,
    complete,
};

fn validateAcyclic(comptime components: anytype, comptime handlers: anytype) void {
    var states = [_]VisitState{.unseen} ** components.items.len;
    visitComponent(components, handlers, &states, 0);
}

fn visitComponent(
    comptime components: anytype,
    comptime handlers: anytype,
    states: *[components.items.len]VisitState,
    comptime component_index: usize,
) void {
    if (states[component_index] == .visiting) {
        @compileError("World system internal handler graph contains a cycle");
    }
    if (states[component_index] == .complete) return;
    states[component_index] = .visiting;
    const Program = components.items[component_index];
    inline for (handlers) |Handler| {
        if (Handler.Consumer == Program and
            handlerActive(components, Handler))
        {
            visitComponent(
                components,
                handlers,
                states,
                components.indexOfInstance(
                    Handler.Provider,
                    handlerFailureMap(
                        Handler,
                        body(components.items[0]).Failure,
                    ),
                ),
            );
        }
    }
    states[component_index] = .complete;
}

fn requireFailureEnum(comptime Failure: type, comptime label: []const u8) void {
    switch (@typeInfo(Failure)) {
        .@"enum" => {},
        else => @compileError("World system " ++ label ++ " must be an enum"),
    }
}

fn LinkedBody(
    comptime name: []const u8,
    comptime Plan: type,
) type {
    @setEvalBranchQuota(system_eval_branch_quota);
    const Root = Plan.RootProgram;
    const components = Plan.components;
    const morphisms = Plan.morphisms;
    const RootComponent = body(Root);
    const schema_set = comptime schemasFor(Plan);
    const value_types = comptime buildValueTypes(Plan, schema_set);
    const linked_constants = comptime buildConstants(Plan);
    const linked_functions = comptime buildFunctions(Plan, schema_set);
    const blocks = comptime buildBlocks(Plan, schema_set);
    const linked_block_costs = comptime buildBlockCosts(Plan, blocks);
    const linked_effect_sites = comptime buildEffectSites(components);
    const linked_effect_handlers = comptime buildEffectHandlers(Plan);
    const linked_effect_morphisms = comptime buildEffectMorphisms(components, morphisms);
    const linked_residual_effects = comptime residualEffects(Plan);
    const linked_limits: cir.CompilerLimits = .{
        .maximum_values = @max(64, value_types.len),
        .maximum_blocks = @max(64, blocks.len),
        .maximum_constructors = 256,
        .maximum_environment_fields = @min(128, @max(64, value_types.len)),
        .maximum_invariant_terms = 64,
        .maximum_generated_operations = 32_768,
    };
    return struct {
        pub const residual_effects = linked_residual_effects;
        pub const schema_count = schema_set.count;
        pub const Body = struct {
            pub const InitialArgs = RootComponent.InitialArgs;
            pub const Result = RootComponent.Result;
            pub const Failure = RootComponent.Failure;
            pub const schema_types = schema_set.items[0..schema_set.count];
            pub const constants = linked_constants;
            pub const effect_sites = linked_effect_sites;
            pub const effect_handlers = linked_effect_handlers;
            pub const effect_morphisms = linked_effect_morphisms;
            pub const block_costs = linked_block_costs;
            pub const compiler_limits = linked_limits;
            pub const control_ir: cir.Program = .{
                .label = name,
                .value_types = &value_types,
                .blocks = &blocks,
                .entry = RootComponent.control_ir.entry,
                .result_type = remapValueType(
                    components,
                    schema_set,
                    0,
                    RootComponent.control_ir.result_type,
                ),
                .functions = &linked_functions,
            };
        };
    };
}

fn TypeSet(comptime capacity: usize) type {
    return struct {
        items: [capacity]type = undefined,
        count: usize = 0,

        fn add(self: *@This(), comptime T: type) void {
            inline for (0..self.count) |index| {
                if (self.items[index] == T) return;
            }
            self.items[self.count] = T;
            self.count += 1;
        }
    };
}

fn ResidualCatalog(comptime capacity: usize) type {
    return struct {
        items: [capacity]type = undefined,
        count: usize = 0,

        fn add(self: *@This(), comptime Site: type) void {
            self.items[self.count] = boundary.effect.site(
                @intCast(self.count),
                Site.semantic_identity,
                Site.Payload,
                Site.Resume,
            );
            self.count += 1;
        }
    };
}

fn totalSchemaCount(comptime Plan: type) usize {
    const components = Plan.components;
    var count: usize = components.count;
    inline for (0..components.count) |index| {
        count += body(components.items[index]).schema_types.len;
    }
    return count + 2 * components.count;
}

fn schemasFor(
    comptime Plan: type,
) TypeSet(totalSchemaCount(Plan)) {
    const components = Plan.components;
    var result: TypeSet(totalSchemaCount(Plan)) = .{};
    inline for (0..components.count) |index| {
        result.add(body(components.items[index]).Failure);
        inline for (body(components.items[index]).schema_types) |Schema| {
            result.add(Schema);
        }
        if (componentSharedFailureCount(Plan, index) != 0) {
            const Map = Plan.failureMap(index);
            result.add(FailureSourceTags(Map));
            result.add(FailureTargets(Map));
        }
    }
    return result;
}

fn schemaIndex(comptime schemas: anytype, comptime Schema: type) u32 {
    inline for (0..schemas.count) |index| {
        if (schemas.items[index] == Schema) return @intCast(index);
    }
    unreachable;
}

fn valueOffset(comptime components: anytype, comptime index: usize) usize {
    var result: usize = 0;
    inline for (0..index) |prior| {
        result += body(components.items[prior]).control_ir.value_types.len;
    }
    return result;
}

fn blockOffset(comptime components: anytype, comptime index: usize) usize {
    var result: usize = 0;
    inline for (0..index) |prior| {
        result += body(components.items[prior]).control_ir.blocks.len;
    }
    return result;
}

fn functionCount(comptime Body: type) usize {
    return if (Body.control_ir.functions.len == 0)
        1
    else
        Body.control_ir.functions.len;
}

fn functionOffset(comptime components: anytype, comptime index: usize) usize {
    var result: usize = 0;
    inline for (0..index) |prior| result += functionCount(body(components.items[prior]));
    return result;
}

fn constantCount(comptime Body: type) usize {
    return if (@hasDecl(Body, "constants")) Body.constants.len else 0;
}

fn constantOffset(comptime components: anytype, comptime index: usize) usize {
    var result: usize = 0;
    inline for (0..index) |prior| result += constantCount(body(components.items[prior]));
    return result;
}

fn effectOffset(comptime components: anytype, comptime index: usize) usize {
    var result: usize = 0;
    inline for (0..index) |prior| result += body(components.items[prior]).effect_sites.len;
    return result;
}

fn totalValues(comptime components: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += body(components.items[index]).control_ir.value_types.len;
    }
    return result;
}

fn totalBlocks(comptime components: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += body(components.items[index]).control_ir.blocks.len;
    }
    return result;
}

fn totalFunctions(comptime components: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += functionCount(body(components.items[index]));
    }
    return result;
}

fn totalConstants(comptime components: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += constantCount(body(components.items[index]));
    }
    return result;
}

fn totalEffects(comptime components: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += body(components.items[index]).effect_sites.len;
    }
    return result;
}

fn totalExtraValues(comptime Plan: type) usize {
    var result: usize = 0;
    inline for (0..Plan.components.count) |index| {
        result += componentExtraValues(Plan, index);
    }
    return result;
}

fn totalExtraBlocks(comptime Plan: type) usize {
    var result: usize = 0;
    inline for (0..Plan.components.count) |index| {
        result += componentExtraBlocks(Plan, index);
    }
    return result;
}

fn totalExtraConstants(comptime Plan: type) usize {
    var result: usize = 0;
    inline for (0..Plan.components.count) |index| {
        result += componentExtraConstants(Plan, index);
    }
    return result;
}

fn totalInstructionFailureValues(comptime Plan: type) usize {
    var result: usize = 0;
    inline for (0..Plan.components.count) |index| {
        result += componentInstructionFailureValues(Plan, index);
    }
    return result;
}

fn precedingInstructionFailureValues(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentInstructionFailureValues(Plan, index);
    }
    return result;
}

fn precedingInstructionFailureValuesInComponent(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    var result: usize = 0;
    inline for (body(Plan.components.items[component_index]).control_ir.blocks) |block| {
        if (block.id == block_id) return result;
        result += blockInstructionFailureTargets(
            Plan,
            component_index,
            block,
        ).count;
    }
    unreachable;
}

fn instructionFailureValueBase(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    return totalValues(Plan.components) +
        precedingInstructionFailureValues(Plan, component_index) +
        precedingInstructionFailureValuesInComponent(
            Plan,
            component_index,
            block_id,
        );
}

fn instructionFailureConstantBase(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    return totalConstants(Plan.components) +
        precedingInstructionFailureValues(Plan, component_index) +
        precedingInstructionFailureValuesInComponent(
            Plan,
            component_index,
            block_id,
        );
}

fn totalSharedFailureValues(comptime Plan: type) usize {
    var result: usize = 0;
    inline for (0..Plan.components.count) |index| {
        result += componentSharedFailureValues(Plan, index);
    }
    return result;
}

fn totalSharedFailureBlocks(comptime Plan: type) usize {
    var result: usize = 0;
    inline for (0..Plan.components.count) |index| {
        result += componentSharedFailureBlocks(Plan, index);
    }
    return result;
}

fn totalSharedFailureConstants(comptime Plan: type) usize {
    var result: usize = 0;
    inline for (0..Plan.components.count) |index| {
        result += componentSharedFailureConstants(Plan, index);
    }
    return result;
}

fn totalSharedFailureFunctions(comptime Plan: type) usize {
    var result: usize = 0;
    inline for (0..Plan.components.count) |index| {
        result += componentSharedFailureCount(Plan, index);
    }
    return result;
}

fn linkedTotalValues(comptime Plan: type) usize {
    return totalValues(Plan.components) +
        totalInstructionFailureValues(Plan) +
        totalExtraValues(Plan) +
        totalSharedFailureValues(Plan) +
        totalVoidReturns(Plan) +
        2 * totalVoidWrappers(Plan.components);
}

fn linkedTotalBlocks(comptime Plan: type) usize {
    return totalBlocks(Plan.components) +
        totalExtraBlocks(Plan) +
        totalSharedFailureBlocks(Plan) +
        totalVoidReturns(Plan) +
        2 * totalVoidWrappers(Plan.components);
}

fn linkedTotalFunctions(comptime Plan: type) usize {
    return totalFunctions(Plan.components) +
        totalSharedFailureFunctions(Plan) +
        totalVoidWrappers(Plan.components);
}

fn linkedTotalConstants(comptime Plan: type) usize {
    return totalConstants(Plan.components) +
        totalInstructionFailureValues(Plan) +
        totalExtraConstants(Plan) +
        totalSharedFailureConstants(Plan) +
        totalVoidReturns(Plan);
}

fn precedingExtraValues(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentExtraValues(Plan, index);
    }
    return result;
}

fn precedingExtraBlocks(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentExtraBlocks(Plan, index);
    }
    return result;
}

fn precedingExtraConstants(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentExtraConstants(Plan, index);
    }
    return result;
}

fn precedingSharedFailureValues(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentSharedFailureValues(Plan, index);
    }
    return result;
}

fn precedingSharedFailureBlocks(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentSharedFailureBlocks(Plan, index);
    }
    return result;
}

fn precedingSharedFailureConstants(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentSharedFailureConstants(Plan, index);
    }
    return result;
}

fn precedingSharedFailureFunctions(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentSharedFailureCount(Plan, index);
    }
    return result;
}

fn precedingFailureValuesInComponent(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    var result: usize = 0;
    inline for (body(Plan.components.items[component_index]).control_ir.blocks) |block| {
        if (block.id == block_id) return result;
        if (!Plan.blockReachable(component_index, block.id)) continue;
        result += Plan.failureLayout(component_index, block.id).value_count;
    }
    unreachable;
}

fn precedingFailureBlocksInComponent(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    var result: usize = 0;
    inline for (body(Plan.components.items[component_index]).control_ir.blocks) |block| {
        if (block.id == block_id) return result;
        if (!Plan.blockReachable(component_index, block.id)) continue;
        result += Plan.failureLayout(component_index, block.id).block_count;
    }
    unreachable;
}

fn precedingFailureConstantsInComponent(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    var result: usize = 0;
    inline for (body(Plan.components.items[component_index]).control_ir.blocks) |block| {
        if (block.id == block_id) return result;
        if (!Plan.blockReachable(component_index, block.id)) continue;
        result += Plan.failureLayout(component_index, block.id).constant_count;
    }
    unreachable;
}

fn failureValueBase(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    return totalValues(Plan.components) +
        totalInstructionFailureValues(Plan) +
        precedingExtraValues(Plan, component_index) +
        precedingFailureValuesInComponent(
            Plan,
            component_index,
            block_id,
        );
}

fn failureBlockBase(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    return totalBlocks(Plan.components) +
        precedingExtraBlocks(Plan, component_index) +
        precedingFailureBlocksInComponent(
            Plan,
            component_index,
            block_id,
        );
}

fn failureConstantBase(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    return totalConstants(Plan.components) +
        totalInstructionFailureValues(Plan) +
        precedingExtraConstants(Plan, component_index) +
        precedingFailureConstantsInComponent(
            Plan,
            component_index,
            block_id,
        );
}

fn sharedFailureValueBase(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    return totalValues(Plan.components) +
        totalInstructionFailureValues(Plan) +
        totalExtraValues(Plan) +
        precedingSharedFailureValues(Plan, component_index);
}

fn sharedFailureBlockBase(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    return totalBlocks(Plan.components) +
        totalExtraBlocks(Plan) +
        precedingSharedFailureBlocks(Plan, component_index);
}

fn sharedFailureConstantBase(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    return totalConstants(Plan.components) +
        totalInstructionFailureValues(Plan) +
        totalExtraConstants(Plan) +
        precedingSharedFailureConstants(Plan, component_index);
}

fn sharedFailureFunctionId(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    return totalFunctions(Plan.components) +
        precedingSharedFailureFunctions(Plan, component_index);
}

fn voidReturnValueBase(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    return totalValues(Plan.components) +
        totalInstructionFailureValues(Plan) +
        totalExtraValues(Plan) +
        totalSharedFailureValues(Plan) +
        precedingVoidReturns(Plan, component_index) +
        voidReturnOrdinal(Plan, component_index, block_id);
}

fn voidReturnConstantBase(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    return totalConstants(Plan.components) +
        totalInstructionFailureValues(Plan) +
        totalExtraConstants(Plan) +
        totalSharedFailureConstants(Plan) +
        precedingVoidReturns(Plan, component_index) +
        voidReturnOrdinal(Plan, component_index, block_id);
}

fn voidReturnBlockBase(
    comptime Plan: type,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    return totalBlocks(Plan.components) +
        totalExtraBlocks(Plan) +
        totalSharedFailureBlocks(Plan) +
        precedingVoidReturns(Plan, component_index) +
        voidReturnOrdinal(Plan, component_index, block_id);
}

fn voidWrapperValueBase(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    return totalValues(Plan.components) +
        totalInstructionFailureValues(Plan) +
        totalExtraValues(Plan) +
        totalSharedFailureValues(Plan) +
        totalVoidReturns(Plan) +
        2 * precedingVoidWrappers(Plan.components, component_index);
}

fn voidWrapperBlockBase(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    return totalBlocks(Plan.components) +
        totalExtraBlocks(Plan) +
        totalSharedFailureBlocks(Plan) +
        totalVoidReturns(Plan) +
        2 * precedingVoidWrappers(Plan.components, component_index);
}

fn voidWrapperFunctionId(
    comptime Plan: type,
    comptime component_index: usize,
) usize {
    return totalFunctions(Plan.components) +
        totalSharedFailureFunctions(Plan) +
        precedingVoidWrappers(Plan.components, component_index);
}

fn remapValueType(
    comptime components: anytype,
    comptime schemas: anytype,
    comptime component_index: usize,
    comptime value_type: cir.ValueType,
) cir.ValueType {
    return switch (value_type) {
        .scalar => value_type,
        .schema => |local| .{ .schema = schemaIndex(
            schemas,
            body(components.items[component_index]).schema_types[local],
        ) },
    };
}

fn buildValueTypes(
    comptime Plan: type,
    comptime schemas: anytype,
) [linkedTotalValues(Plan)]cir.ValueType {
    const components = Plan.components;
    var result: [linkedTotalValues(Plan)]cir.ValueType = undefined;
    var cursor: usize = 0;
    inline for (0..components.count) |component_index| {
        inline for (body(components.items[component_index]).control_ir.value_types) |value_type| {
            result[cursor] = remapValueType(
                components,
                schemas,
                component_index,
                value_type,
            );
            cursor += 1;
        }
    }
    const root_failure_type: cir.ValueType = .{ .schema = schemaIndex(
        schemas,
        body(components.items[0]).Failure,
    ) };
    inline for (0..components.count) |component_index| {
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            const targets = blockInstructionFailureTargets(
                Plan,
                component_index,
                block,
            );
            inline for (0..targets.count) |_| {
                appendValueType(&result, &cursor, root_failure_type);
            }
        }
    }
    inline for (0..components.count) |component_index| {
        appendFailureValueTypes(
            &result,
            &cursor,
            Plan,
            schemas,
            component_index,
        );
    }
    inline for (0..components.count) |component_index| {
        appendSharedFailureValueTypes(
            &result,
            &cursor,
            Plan,
            schemas,
            component_index,
        );
    }
    inline for (1..components.count) |component_index| {
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            if (!Plan.blockReachable(component_index, block.id)) continue;
            if (block.function_id != 0) continue;
            switch (block.terminator) {
                .return_value => |value| if (value == null and
                    block.id == voidReturnOwnerBlock(Plan, component_index) and
                    body(components.items[component_index]).Result == void)
                {
                    result[cursor] = .{ .scalar = .unit };
                    cursor += 1;
                },
                else => {},
            }
        }
    }
    inline for (1..components.count) |component_index| {
        if (componentVoidWrapperCount(components, component_index) == 1) {
            result[cursor] = .{ .scalar = .unit };
            cursor += 1;
            result[cursor] = remapValueType(
                components,
                schemas,
                component_index,
                body(components.items[component_index]).control_ir.result_type,
            );
            cursor += 1;
        }
    }
    return result;
}

fn appendFailureValueTypes(
    result: anytype,
    cursor: *usize,
    comptime Plan: type,
    comptime schemas: anytype,
    comptime component_index: usize,
) void {
    const components = Plan.components;
    const Map = Plan.failureMap(component_index);
    if (Map == void) return;
    const target_type: cir.ValueType = .{ .schema = schemaIndex(
        schemas,
        Map.TargetFailure,
    ) };
    inline for (body(components.items[component_index]).control_ir.blocks) |block| {
        if (!Plan.blockReachable(component_index, block.id)) continue;
        switch (Plan.failureLayout(component_index, block.id).kind) {
            .direct => appendValueType(result, cursor, target_type),
            .dynamic => appendValueType(result, cursor, target_type),
            .none, .impossible, .direct_alias => {},
        }
    }
}

fn appendSharedFailureValueTypes(
    result: anytype,
    cursor: *usize,
    comptime Plan: type,
    comptime schemas: anytype,
    comptime component_index: usize,
) void {
    if (componentSharedFailureCount(Plan, component_index) == 0) return;
    const Map = Plan.failureMap(component_index);
    const source_type: cir.ValueType = .{ .schema = schemaIndex(
        schemas,
        Map.SourceFailure,
    ) };
    const target_type: cir.ValueType = .{ .schema = schemaIndex(
        schemas,
        Map.TargetFailure,
    ) };
    const source_tags_type: cir.ValueType = .{ .schema = schemaIndex(
        schemas,
        FailureSourceTags(Map),
    ) };
    const targets_type: cir.ValueType = .{ .schema = schemaIndex(
        schemas,
        FailureTargets(Map),
    ) };
    appendValueType(result, cursor, source_type);
    appendValueType(result, cursor, .{ .scalar = .u32 });
    appendValueType(result, cursor, source_tags_type);
    appendValueType(result, cursor, targets_type);
    appendValueType(result, cursor, .{ .scalar = .u32 });
    appendValueType(result, cursor, .{ .scalar = .u32 });
    appendValueType(result, cursor, target_type);
    appendValueType(result, cursor, .{ .scalar = .u32 });
    appendValueType(result, cursor, .{ .scalar = .u32 });
    appendValueType(result, cursor, .{ .scalar = .boolean });
    appendValueType(result, cursor, .{ .scalar = .u32 });
    appendValueType(result, cursor, target_type);
}

fn appendValueType(result: anytype, cursor: *usize, value_type: cir.ValueType) void {
    result.*[cursor.*] = value_type;
    cursor.* += 1;
}

fn constantTypes(comptime Plan: type) [linkedTotalConstants(Plan)]type {
    const components = Plan.components;
    var result: [linkedTotalConstants(Plan)]type = undefined;
    var cursor: usize = 0;
    inline for (0..components.count) |component_index| {
        const Body = body(components.items[component_index]);
        if (@hasDecl(Body, "constants")) {
            inline for (Body.constants) |constant| {
                result[cursor] = @TypeOf(constant);
                cursor += 1;
            }
        }
    }
    inline for (0..components.count) |component_index| {
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            const targets = blockInstructionFailureTargets(
                Plan,
                component_index,
                block,
            );
            inline for (0..targets.count) |_| {
                result[cursor] = body(components.items[0]).Failure;
                cursor += 1;
            }
        }
    }
    inline for (0..components.count) |component_index| {
        const Map = Plan.failureMap(component_index);
        if (Map == void) continue;
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            if (!Plan.blockReachable(component_index, block.id)) continue;
            switch (Plan.failureLayout(component_index, block.id).kind) {
                .direct => {
                    result[cursor] = Map.TargetFailure;
                    cursor += 1;
                },
                .dynamic => {},
                .none, .impossible, .direct_alias => {},
            }
        }
    }
    inline for (0..components.count) |component_index| {
        if (componentSharedFailureCount(Plan, component_index) == 0) continue;
        const Map = Plan.failureMap(component_index);
        result[cursor] = FailureSourceTags(Map);
        cursor += 1;
        result[cursor] = FailureTargets(Map);
        cursor += 1;
        result[cursor] = u32;
        cursor += 1;
        result[cursor] = u32;
        cursor += 1;
        result[cursor] = Map.TargetFailure;
        cursor += 1;
    }
    inline for (1..components.count) |component_index| {
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            if (!Plan.blockReachable(component_index, block.id)) continue;
            if (block.function_id != 0) continue;
            switch (block.terminator) {
                .return_value => |value| if (value == null and
                    block.id == voidReturnOwnerBlock(Plan, component_index) and
                    body(components.items[component_index]).Result == void)
                {
                    result[cursor] = void;
                    cursor += 1;
                },
                else => {},
            }
        }
    }
    return result;
}

fn Constants(comptime Plan: type) type {
    const types = constantTypes(Plan);
    return std.meta.Tuple(&types);
}

fn buildConstants(comptime Plan: type) Constants(Plan) {
    const components = Plan.components;
    var result: Constants(Plan) = undefined;
    var cursor: usize = 0;
    inline for (0..components.count) |component_index| {
        const Body = body(components.items[component_index]);
        if (@hasDecl(Body, "constants")) {
            inline for (Body.constants) |constant| {
                @field(
                    result,
                    std.fmt.comptimePrint("{d}", .{cursor}),
                ) = constant;
                cursor += 1;
            }
        }
    }
    inline for (0..components.count) |component_index| {
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            const targets = blockInstructionFailureTargets(
                Plan,
                component_index,
                block,
            );
            inline for (0..targets.count) |index| {
                appendConstant(&result, &cursor, targets.items[index]);
            }
        }
    }
    inline for (0..components.count) |component_index| {
        appendFailureConstants(
            &result,
            &cursor,
            Plan,
            component_index,
        );
    }
    inline for (0..components.count) |component_index| {
        appendSharedFailureConstants(
            &result,
            &cursor,
            Plan,
            component_index,
        );
    }
    inline for (1..components.count) |component_index| {
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            if (!Plan.blockReachable(component_index, block.id)) continue;
            if (block.function_id != 0) continue;
            switch (block.terminator) {
                .return_value => |value| if (value == null and
                    block.id == voidReturnOwnerBlock(Plan, component_index) and
                    body(components.items[component_index]).Result == void)
                {
                    @field(
                        result,
                        std.fmt.comptimePrint("{d}", .{cursor}),
                    ) = {};
                    cursor += 1;
                },
                else => {},
            }
        }
    }
    return result;
}

fn appendFailureConstants(
    result: anytype,
    cursor: *usize,
    comptime Plan: type,
    comptime component_index: usize,
) void {
    const components = Plan.components;
    const Map = Plan.failureMap(component_index);
    if (Map == void) return;
    inline for (body(components.items[component_index]).control_ir.blocks) |block| {
        if (!Plan.blockReachable(component_index, block.id)) continue;
        switch (Plan.failureLayout(component_index, block.id).kind) {
            .direct => switch (block.terminator) {
                .fail => |source_tag| appendConstant(
                    result,
                    cursor,
                    mappedFailureTarget(Map, source_tag),
                ),
                .fail_value => appendConstant(result, cursor, Map.targets[0]),
                else => unreachable,
            },
            .dynamic => {},
            .none, .impossible, .direct_alias => {},
        }
    }
}

fn appendSharedFailureConstants(
    result: anytype,
    cursor: *usize,
    comptime Plan: type,
    comptime component_index: usize,
) void {
    if (componentSharedFailureCount(Plan, component_index) == 0) return;
    const Map = Plan.failureMap(component_index);
    const source_tags = FailureSourceTags(Map).fromSlice(&Map.source_tags) catch
        unreachable;
    const targets = FailureTargets(Map).fromSlice(&Map.targets) catch unreachable;
    appendConstant(result, cursor, source_tags);
    appendConstant(result, cursor, targets);
    appendConstant(result, cursor, @as(u32, 0));
    appendConstant(result, cursor, @as(u32, 1));
    appendConstant(result, cursor, Map.targets[0]);
}

fn appendConstant(result: anytype, cursor: *usize, value: anytype) void {
    @field(
        result.*,
        std.fmt.comptimePrint("{d}", .{cursor.*}),
    ) = value;
    cursor.* += 1;
}

fn buildFunctions(
    comptime Plan: type,
    comptime schemas: anytype,
) [linkedTotalFunctions(Plan)]cir.Function {
    const components = Plan.components;
    var result: [linkedTotalFunctions(Plan)]cir.Function = undefined;
    var cursor: usize = 0;
    inline for (0..components.count) |component_index| {
        const Body = body(components.items[component_index]);
        const function_offset = functionOffset(components, component_index);
        const block_offset = blockOffset(components, component_index);
        if (Body.control_ir.functions.len == 0) {
            result[cursor] = .{
                .id = @intCast(function_offset),
                .entry = @intCast(block_offset + Body.control_ir.entry),
                .result_type = remapValueType(
                    components,
                    schemas,
                    component_index,
                    Body.control_ir.result_type,
                ),
            };
            cursor += 1;
        } else {
            inline for (Body.control_ir.functions) |function| {
                result[cursor] = .{
                    .id = @intCast(function_offset + function.id),
                    .entry = @intCast(block_offset + function.entry),
                    .result_type = remapValueType(
                        components,
                        schemas,
                        component_index,
                        function.result_type,
                    ),
                };
                cursor += 1;
            }
        }
    }
    inline for (0..components.count) |component_index| {
        if (componentSharedFailureCount(Plan, component_index) == 0) continue;
        const Map = Plan.failureMap(component_index);
        result[cursor] = .{
            .id = @intCast(sharedFailureFunctionId(Plan, component_index)),
            .entry = @intCast(sharedFailureBlockBase(Plan, component_index)),
            .result_type = .{ .schema = schemaIndex(schemas, Map.TargetFailure) },
        };
        cursor += 1;
    }
    inline for (1..components.count) |component_index| {
        if (componentVoidWrapperCount(components, component_index) == 0) continue;
        result[cursor] = .{
            .id = @intCast(voidWrapperFunctionId(Plan, component_index)),
            .entry = @intCast(voidWrapperBlockBase(Plan, component_index)),
            .result_type = remapValueType(
                components,
                schemas,
                component_index,
                body(components.items[component_index]).control_ir.result_type,
            ),
        };
        cursor += 1;
    }
    return result;
}

fn buildBlocks(
    comptime Plan: type,
    comptime schemas: anytype,
) [linkedTotalBlocks(Plan)]cir.Block {
    const components = Plan.components;
    var result: [linkedTotalBlocks(Plan)]cir.Block = undefined;
    var cursor: usize = 0;
    inline for (0..components.count) |component_index| {
        const Body = body(components.items[component_index]);
        inline for (Body.control_ir.blocks) |source| {
            result[cursor] = remapBlock(
                Plan,
                schemas,
                component_index,
                source,
            );
            cursor += 1;
        }
    }
    inline for (0..components.count) |component_index| {
        const Map = Plan.failureMap(component_index);
        if (Map == void) continue;
        inline for (body(components.items[component_index]).control_ir.blocks) |source| {
            if (!Plan.blockReachable(component_index, source.id)) continue;
            switch (Plan.failureLayout(component_index, source.id).kind) {
                .direct => {
                    const block_id = failureBlockBase(
                        Plan,
                        component_index,
                        source.id,
                    );
                    result[block_id] = mappedFailureBlock(
                        Plan,
                        component_index,
                        source,
                        block_id,
                    );
                },
                .dynamic => {
                    const block_id = failureBlockBase(
                        Plan,
                        component_index,
                        source.id,
                    );
                    result[block_id] = failureContinuationBlock(
                        Plan,
                        component_index,
                        source,
                        block_id,
                    );
                },
                .none, .impossible, .direct_alias => {},
            }
        }
    }
    inline for (0..components.count) |component_index| {
        if (componentSharedFailureCount(Plan, component_index) == 0) continue;
        const block_base = sharedFailureBlockBase(Plan, component_index);
        result[block_base] = sharedFailureEntryBlock(Plan, component_index);
        result[block_base + 1] = sharedFailureLoopBlock(Plan, component_index);
        result[block_base + 2] = sharedFailureReturnBlock(Plan, component_index);
    }
    inline for (1..components.count) |component_index| {
        inline for (body(components.items[component_index]).control_ir.blocks) |source| {
            if (!Plan.blockReachable(component_index, source.id)) continue;
            if (!expandsVoidReturn(Plan, component_index, source)) continue;
            if (source.id != voidReturnOwnerBlock(Plan, component_index)) continue;
            const block_id = voidReturnBlockBase(
                Plan,
                component_index,
                source.id,
            );
            result[block_id] = voidReturnBlock(
                Plan,
                component_index,
                source,
                block_id,
            );
        }
    }
    inline for (1..components.count) |component_index| {
        if (componentVoidWrapperCount(components, component_index) == 0) continue;
        const block_base = voidWrapperBlockBase(Plan, component_index);
        result[block_base] = voidWrapperEntryBlock(Plan, schemas, component_index);
        result[block_base + 1] = voidWrapperReturnBlock(Plan, component_index);
    }
    return result;
}

fn buildBlockCosts(
    comptime Plan: type,
    comptime blocks: anytype,
) [blocks.len]u64 {
    const components = Plan.components;
    var result: [blocks.len]u64 = undefined;
    inline for (blocks, 0..) |block, index| {
        result[index] = @intCast(block.instructions.len + 1);
    }
    inline for (0..components.count) |component_index| {
        const Program = components.items[component_index];
        const Body = body(Program);
        const Admission = components.admissionAt(component_index);
        inline for (Body.control_ir.blocks) |block| {
            const linked_id = blockOffset(components, component_index) + block.id;
            result[linked_id] = Admission.effective_block_costs[block.id] +
                blockInstructionFailureTargets(
                    Plan,
                    component_index,
                    block,
                ).count;
        }
    }
    return result;
}

fn remapBlock(
    comptime Plan: type,
    comptime schemas: anytype,
    comptime component_index: usize,
    comptime source: cir.Block,
) cir.Block {
    const components = Plan.components;
    const Static = struct {
        const parameters = remapBlockParameters(
            components,
            component_index,
            source,
        );
        const instructions = remapBlockInstructions(
            Plan,
            component_index,
            source,
        );
    };
    return .{
        .id = @intCast(blockOffset(components, component_index) + source.id),
        .function_id = @intCast(
            functionOffset(components, component_index) + source.function_id,
        ),
        .role = source.role,
        .parameters = &Static.parameters,
        .instructions = &Static.instructions,
        .terminator = remapBlockTerminator(
            Plan,
            schemas,
            component_index,
            source,
        ),
    };
}

fn remapBlockParameters(
    comptime components: anytype,
    comptime component_index: usize,
    comptime source: cir.Block,
) [source.parameters.len]cir.ValueId {
    return remapValueIds(
        source.parameters,
        valueOffset(components, component_index),
    );
}

fn expandsVoidReturn(
    comptime Plan: type,
    comptime component_index: usize,
    comptime source: cir.Block,
) bool {
    return Plan.blockReachable(component_index, source.id) and
        isVoidReturn(Plan.components, component_index, source);
}

fn isVoidReturn(
    comptime components: anytype,
    comptime component_index: usize,
    comptime source: cir.Block,
) bool {
    if (component_index == 0 or source.function_id != 0 or
        body(components.items[component_index]).Result != void)
    {
        return false;
    }
    return switch (source.terminator) {
        .return_value => |value| value == null,
        else => false,
    };
}

fn remapBlockInstructions(
    comptime Plan: type,
    comptime component_index: usize,
    comptime source: cir.Block,
) [
    source.instructions.len + blockInstructionFailureTargets(
        Plan,
        component_index,
        source,
    ).count
]cir.Instruction {
    const targets = blockInstructionFailureTargets(
        Plan,
        component_index,
        source,
    );
    var result: [source.instructions.len + targets.count]cir.Instruction = undefined;
    inline for (0..targets.count) |index| {
        result[index] = .{
            .kind = .constant,
            .result = @intCast(instructionFailureValueBase(
                Plan,
                component_index,
                source.id,
            ) + index),
            .operation = .{ .constant = @intCast(instructionFailureConstantBase(
                Plan,
                component_index,
                source.id,
            ) + index) },
        };
    }
    inline for (source.instructions, 0..) |instruction, index| {
        result[targets.count + index] = remapInstruction(
            Plan,
            component_index,
            source,
            instruction,
        );
    }
    return result;
}

fn remapBlockTerminator(
    comptime Plan: type,
    comptime schemas: anytype,
    comptime component_index: usize,
    comptime source_block: cir.Block,
) cir.Terminator {
    const components = Plan.components;
    const source = source_block.terminator;
    if (expandsVoidReturn(Plan, component_index, source_block)) {
        return .{ .jump = .{ .target = @intCast(voidReturnBlockBase(
            Plan,
            component_index,
            source_block.id,
        )) } };
    }
    if (!Plan.blockReachable(component_index, source_block.id) and
        isVoidReturn(components, component_index, source_block))
    {
        return selfLoopTerminator(components, component_index, source_block);
    }
    const Map = Plan.failureMap(component_index);
    if (!Plan.blockReachable(component_index, source_block.id) and Map != void) {
        switch (source) {
            .fail, .fail_value => return selfLoopTerminator(
                components,
                component_index,
                source_block,
            ),
            else => {},
        }
    }
    switch (Plan.failureLayout(component_index, source_block.id).kind) {
        .impossible => return selfLoopTerminator(
            components,
            component_index,
            source_block,
        ),
        .direct => return .{ .jump = .{ .target = @intCast(
            failureBlockBase(
                Plan,
                component_index,
                source_block.id,
            ),
        ) } },
        .direct_alias => return .{ .jump = .{ .target = @intCast(
            failureBlockBase(
                Plan,
                component_index,
                Plan.failureLayout(
                    component_index,
                    source_block.id,
                ).direct_owner_block.?,
            ),
        ) } },
        .dynamic => return failureCallTerminator(
            Plan,
            schemas,
            component_index,
            source_block,
        ),
        .none => {},
    }
    return remapTerminator(
        components,
        schemas,
        component_index,
        source_block.function_id,
        source,
    );
}

fn selfLoopTerminator(
    comptime components: anytype,
    comptime component_index: usize,
    comptime source: cir.Block,
) cir.Terminator {
    const Static = struct {
        const arguments = blockParameterArguments(
            source.parameters,
            valueOffset(components, component_index),
        );
    };
    return .{ .jump = .{
        .target = @intCast(blockOffset(components, component_index) + source.id),
        .arguments = &Static.arguments,
    } };
}

fn blockParameterArguments(
    comptime parameters: []const cir.ValueId,
    comptime value_offset: usize,
) [parameters.len]cir.EdgeArgument {
    var result: [parameters.len]cir.EdgeArgument = undefined;
    inline for (parameters, 0..) |parameter, index| {
        result[index] = .{ .value = @intCast(value_offset + parameter) };
    }
    return result;
}

fn mappedFailureBlock(
    comptime Plan: type,
    comptime component_index: usize,
    comptime source: cir.Block,
    comptime block_id: usize,
) cir.Block {
    const components = Plan.components;
    const Map = Plan.failureMap(component_index);
    if (Map.targets.len == 0) {
        @compileError("World failure morphism cannot map an empty Failure enum");
    }
    const value_id = failureValueBase(
        Plan,
        component_index,
        source.id,
    );
    const Static = struct {
        const instructions = [_]cir.Instruction{.{
            .kind = .constant,
            .result = @intCast(value_id),
            .operation = .{ .constant = @intCast(failureConstantBase(
                Plan,
                component_index,
                source.id,
            )) },
        }};
    };
    return .{
        .id = @intCast(block_id),
        .function_id = @intCast(
            functionOffset(components, component_index) + source.function_id,
        ),
        .role = .terminal_handoff,
        .instructions = &Static.instructions,
        .terminator = .{ .fail_value = @intCast(value_id) },
    };
}

fn failureCallTerminator(
    comptime Plan: type,
    comptime schemas: anytype,
    comptime component_index: usize,
    comptime source: cir.Block,
) cir.Terminator {
    const components = Plan.components;
    const Map = Plan.failureMap(component_index);
    const selector_owner = Plan.failureLayout(
        component_index,
        source.id,
    ).selector_owner_component.?;
    const fail_value = switch (source.terminator) {
        .fail_value => |value| value,
        else => unreachable,
    };
    const Static = struct {
        const callee_arguments = [_]cir.EdgeArgument{.{ .value = @intCast(
            valueOffset(components, component_index) + fail_value,
        ) }};
        const resume_arguments = [_]cir.EdgeArgument{.@"resume"};
    };
    return .{ .@"suspend" = .{
        .kind = .call,
        .callee_function = @intCast(sharedFailureFunctionId(
            Plan,
            selector_owner,
        )),
        .callee = .{
            .target = @intCast(sharedFailureBlockBase(Plan, selector_owner)),
            .arguments = &Static.callee_arguments,
        },
        .continuation = .{
            .target = @intCast(failureBlockBase(
                Plan,
                component_index,
                source.id,
            )),
            .arguments = &Static.resume_arguments,
        },
        .resume_type = .{ .schema = schemaIndex(schemas, Map.TargetFailure) },
    } };
}

fn failureContinuationBlock(
    comptime Plan: type,
    comptime component_index: usize,
    comptime source: cir.Block,
    comptime block_id: usize,
) cir.Block {
    const value_id = failureValueBase(Plan, component_index, source.id);
    const Static = struct {
        const parameters = [_]cir.ValueId{@intCast(value_id)};
    };
    return .{
        .id = @intCast(block_id),
        .function_id = @intCast(
            functionOffset(Plan.components, component_index) + source.function_id,
        ),
        .role = .terminal_handoff,
        .parameters = &Static.parameters,
        .terminator = .{ .fail_value = @intCast(value_id) },
    };
}

fn sharedFailureEntryBlock(
    comptime Plan: type,
    comptime component_index: usize,
) cir.Block {
    const value_base = sharedFailureValueBase(Plan, component_index);
    const block_id = sharedFailureBlockBase(Plan, component_index);
    const constant_base = sharedFailureConstantBase(Plan, component_index);
    const Static = struct {
        const parameters = [_]cir.ValueId{@intCast(value_base)};
        const tag_operands = [_]cir.ValueId{@intCast(value_base)};
        const instructions = [_]cir.Instruction{
            .{
                .kind = .pure,
                .result = @intCast(value_base + 1),
                .operands = &tag_operands,
                .operation = .enum_to_u32,
            },
            .{ .kind = .constant, .result = @intCast(value_base + 2), .operation = .{ .constant = @intCast(constant_base) } },
            .{ .kind = .constant, .result = @intCast(value_base + 3), .operation = .{ .constant = @intCast(constant_base + 1) } },
            .{ .kind = .constant, .result = @intCast(value_base + 4), .operation = .{ .constant = @intCast(constant_base + 2) } },
            .{ .kind = .constant, .result = @intCast(value_base + 5), .operation = .{ .constant = @intCast(constant_base + 3) } },
            .{ .kind = .constant, .result = @intCast(value_base + 6), .operation = .{ .constant = @intCast(constant_base + 4) } },
        };
        const loop_arguments = [_]cir.EdgeArgument{.{ .value = @intCast(value_base + 4) }};
    };
    return .{
        .id = @intCast(block_id),
        .function_id = @intCast(sharedFailureFunctionId(Plan, component_index)),
        .parameters = &Static.parameters,
        .instructions = &Static.instructions,
        .terminator = .{ .jump = .{
            .target = @intCast(block_id + 1),
            .arguments = &Static.loop_arguments,
        } },
    };
}

fn sharedFailureLoopBlock(
    comptime Plan: type,
    comptime component_index: usize,
) cir.Block {
    const value_base = sharedFailureValueBase(Plan, component_index);
    const block_id = sharedFailureBlockBase(Plan, component_index) + 1;
    const Static = struct {
        const parameters = [_]cir.ValueId{@intCast(value_base + 7)};
        const get_operands = [_]cir.ValueId{
            @intCast(value_base + 2),
            @intCast(value_base + 7),
            @intCast(value_base + 6),
        };
        const equal_operands = [_]cir.ValueId{
            @intCast(value_base + 8),
            @intCast(value_base + 1),
        };
        const increment_operands = [_]cir.ValueId{
            @intCast(value_base + 7),
            @intCast(value_base + 5),
            @intCast(value_base + 6),
        };
        const instructions = [_]cir.Instruction{
            .{ .kind = .pure, .result = @intCast(value_base + 8), .operands = &get_operands, .operation = .vector_get },
            .{ .kind = .pure, .result = @intCast(value_base + 9), .operands = &equal_operands, .operation = .integer_equal },
            .{ .kind = .pure, .result = @intCast(value_base + 10), .operands = &increment_operands, .operation = .integer_add },
        };
        const next_arguments = [_]cir.EdgeArgument{.{ .value = @intCast(value_base + 10) }};
    };
    return .{
        .id = @intCast(block_id),
        .function_id = @intCast(sharedFailureFunctionId(Plan, component_index)),
        .role = .loop_header,
        .parameters = &Static.parameters,
        .instructions = &Static.instructions,
        .terminator = .{ .branch = .{
            .condition = @intCast(value_base + 9),
            .then_edge = .{ .target = @intCast(block_id + 1) },
            .else_edge = .{
                .target = @intCast(block_id),
                .arguments = &Static.next_arguments,
            },
        } },
    };
}

fn sharedFailureReturnBlock(
    comptime Plan: type,
    comptime component_index: usize,
) cir.Block {
    const value_base = sharedFailureValueBase(Plan, component_index);
    const block_id = sharedFailureBlockBase(Plan, component_index) + 2;
    const Static = struct {
        const get_operands = [_]cir.ValueId{
            @intCast(value_base + 3),
            @intCast(value_base + 7),
            @intCast(value_base + 6),
        };
        const instructions = [_]cir.Instruction{.{
            .kind = .pure,
            .result = @intCast(value_base + 11),
            .operands = &get_operands,
            .operation = .vector_get,
        }};
    };
    return .{
        .id = @intCast(block_id),
        .function_id = @intCast(sharedFailureFunctionId(Plan, component_index)),
        .role = .terminal_handoff,
        .instructions = &Static.instructions,
        .terminator = .{ .return_to_caller = @intCast(value_base + 11) },
    };
}

fn voidReturnBlock(
    comptime Plan: type,
    comptime component_index: usize,
    comptime source: cir.Block,
    comptime block_id: usize,
) cir.Block {
    const components = Plan.components;
    const value_id = voidReturnValueBase(
        Plan,
        component_index,
        source.id,
    );
    const Static = struct {
        const instructions = [_]cir.Instruction{.{
            .kind = .constant,
            .result = @intCast(value_id),
            .operation = .{ .constant = @intCast(voidReturnConstantBase(
                Plan,
                component_index,
                source.id,
            )) },
        }};
    };
    return .{
        .id = @intCast(block_id),
        .function_id = @intCast(
            functionOffset(components, component_index) + source.function_id,
        ),
        .role = .terminal_handoff,
        .instructions = &Static.instructions,
        .terminator = .{ .return_to_caller = @intCast(value_id) },
    };
}

fn voidWrapperEntryBlock(
    comptime Plan: type,
    comptime schemas: anytype,
    comptime component_index: usize,
) cir.Block {
    const components = Plan.components;
    const Body = body(components.items[component_index]);
    const value_base = voidWrapperValueBase(Plan, component_index);
    const block_base = voidWrapperBlockBase(Plan, component_index);
    const Static = struct {
        const parameters = [_]cir.ValueId{@intCast(value_base)};
        const resume_arguments = [_]cir.EdgeArgument{.@"resume"};
    };
    return .{
        .id = @intCast(block_base),
        .function_id = @intCast(voidWrapperFunctionId(Plan, component_index)),
        .parameters = &Static.parameters,
        .terminator = .{ .@"suspend" = .{
            .kind = .call,
            .callee_function = @intCast(functionOffset(components, component_index)),
            .callee = .{ .target = @intCast(
                blockOffset(components, component_index) + Body.control_ir.entry,
            ) },
            .continuation = .{
                .target = @intCast(block_base + 1),
                .arguments = &Static.resume_arguments,
            },
            .resume_type = remapValueType(
                components,
                schemas,
                component_index,
                Body.control_ir.result_type,
            ),
        } },
    };
}

fn voidWrapperReturnBlock(
    comptime Plan: type,
    comptime component_index: usize,
) cir.Block {
    const value_id = voidWrapperValueBase(Plan, component_index) + 1;
    const Static = struct {
        const parameters = [_]cir.ValueId{@intCast(value_id)};
    };
    return .{
        .id = @intCast(voidWrapperBlockBase(Plan, component_index) + 1),
        .function_id = @intCast(voidWrapperFunctionId(Plan, component_index)),
        .role = .terminal_handoff,
        .parameters = &Static.parameters,
        .terminator = .{ .return_to_caller = @intCast(value_id) },
    };
}

fn remapValueIds(
    comptime source: []const cir.ValueId,
    comptime offset: usize,
) [source.len]cir.ValueId {
    var result: [source.len]cir.ValueId = undefined;
    inline for (source, 0..) |value, index| {
        result[index] = @intCast(offset + value);
    }
    return result;
}

fn remapInstruction(
    comptime Plan: type,
    comptime component_index: usize,
    comptime source_block: cir.Block,
    comptime source: cir.Instruction,
) cir.Instruction {
    const components = Plan.components;
    const value_offset = valueOffset(components, component_index);
    const Map = Plan.failureMap(component_index);
    const Admission = components.admissionAt(component_index);
    const projection = Admission.instructionFailureProjection(source);
    const source_failure_tags = projection.failure_tags;
    const copied_operand_count = if (Map == void)
        source.operands.len
    else
        projection.ordinary_operand_count;
    const mapped_count = if (Map == void) 0 else source_failure_tags.len;
    const targets = blockInstructionFailureTargets(
        Plan,
        component_index,
        source_block,
    );
    const Static = struct {
        const operands = blk: {
            var result: [copied_operand_count + mapped_count]cir.ValueId = undefined;
            for (source.operands[0..copied_operand_count], 0..) |operand, index| {
                result[index] = @intCast(value_offset + operand);
            }
            if (Map != void) {
                for (source_failure_tags, 0..) |source_tag, index| {
                    const target = mappedFailureTarget(Map, source_tag);
                    result[copied_operand_count + index] = @intCast(
                        instructionFailureValueBase(
                            Plan,
                            component_index,
                            source_block.id,
                        ) + targets.indexOf(target),
                    );
                }
            }
            break :blk result;
        };
    };
    var operation = source.operation;
    switch (operation) {
        .constant => |index| operation = .{ .constant = @intCast(
            constantOffset(components, component_index) + index,
        ) },
        else => {},
    }
    return .{
        .kind = source.kind,
        .result = @intCast(value_offset + source.result),
        .operands = &Static.operands,
        .operation = operation,
    };
}

fn remapTerminator(
    comptime components: anytype,
    comptime schemas: anytype,
    comptime component_index: usize,
    comptime source_function: cir.FunctionId,
    comptime source: cir.Terminator,
) cir.Terminator {
    const value_offset = valueOffset(components, component_index);
    return switch (source) {
        .jump => |edge| .{ .jump = remapEdge(
            components,
            component_index,
            edge,
        ) },
        .branch => |branch| .{ .branch = .{
            .condition = @intCast(value_offset + branch.condition),
            .then_edge = remapEdge(
                components,
                component_index,
                branch.then_edge,
            ),
            .else_edge = remapEdge(
                components,
                component_index,
                branch.else_edge,
            ),
        } },
        .@"suspend" => |suspension| .{ .@"suspend" = remapSuspension(
            components,
            schemas,
            component_index,
            suspension,
        ) },
        .return_value => |value| if (component_index != 0 and source_function == 0)
            .{ .return_to_caller = @intCast(value_offset + value.?) }
        else
            .{ .return_value = if (value) |id|
                @intCast(value_offset + id)
            else
                null },
        .return_to_caller => |value| .{
            .return_to_caller = @intCast(value_offset + value),
        },
        .fail => |failure| .{
            .fail = remapFailureTag(
                components,
                component_index,
                failure,
            ),
        },
        .fail_value => |value| .{ .fail_value = @intCast(value_offset + value) },
    };
}

fn remapFailureTag(
    comptime components: anytype,
    comptime component_index: usize,
    comptime source_tag: u16,
) u16 {
    if (component_index == 0) return source_tag;
    const Program = components.items[component_index];
    const ComponentFailure = body(Program).Failure;
    const SystemFailure = body(components.items[0]).Failure;
    if (ComponentFailure == SystemFailure) return source_tag;
    unreachable;
}

fn remapEdge(
    comptime components: anytype,
    comptime component_index: usize,
    comptime source: cir.Edge,
) cir.Edge {
    const Static = struct {
        const arguments = remapEdgeArguments(
            source.arguments,
            valueOffset(components, component_index),
        );
    };
    return .{
        .target = @intCast(blockOffset(components, component_index) + source.target),
        .arguments = &Static.arguments,
    };
}

fn remapEdgeArguments(
    comptime source: []const cir.EdgeArgument,
    comptime value_offset: usize,
) [source.len]cir.EdgeArgument {
    var result: [source.len]cir.EdgeArgument = undefined;
    inline for (source, 0..) |argument, index| {
        result[index] = switch (argument) {
            .value => |value| .{ .value = @intCast(value_offset + value) },
            .@"resume" => .@"resume",
        };
    }
    return result;
}

fn remapSuspension(
    comptime components: anytype,
    comptime schemas: anytype,
    comptime component_index: usize,
    comptime source: cir.Suspension,
) cir.Suspension {
    const Static = struct {
        const request_values = remapValueIds(
            source.request_values,
            valueOffset(components, component_index),
        );
    };
    return .{
        .kind = source.kind,
        .site_id = if (source.site_id) |id|
            @intCast(effectOffset(components, component_index) + id)
        else
            null,
        .request_values = &Static.request_values,
        .callee_function = if (source.callee_function) |id|
            @intCast(functionOffset(components, component_index) + id)
        else
            null,
        .callee = if (source.callee) |edge|
            remapEdge(components, component_index, edge)
        else
            null,
        .continuation = remapEdge(
            components,
            component_index,
            source.continuation,
        ),
        .resume_type = if (source.resume_type) |value_type|
            remapValueType(
                components,
                schemas,
                component_index,
                value_type,
            )
        else
            null,
    };
}

fn buildEffectSites(comptime components: anytype) [totalEffects(components)]type {
    var result: [totalEffects(components)]type = undefined;
    var cursor: usize = 0;
    inline for (0..components.count) |component_index| {
        inline for (body(components.items[component_index]).effect_sites) |Site| {
            result[cursor] = boundary.effect.site(
                @intCast(cursor),
                Site.semantic_identity,
                Site.Payload,
                Site.Resume,
            );
            cursor += 1;
        }
    }
    return result;
}

fn buildEffectHandlers(comptime Plan: type) [
    activeHandlerCount(
        Plan.components,
        Plan.handlers,
    )
]type {
    const components = Plan.components;
    const handlers = Plan.handlers;
    var result: [activeHandlerCount(components, handlers)]type = undefined;
    var cursor: usize = 0;
    inline for (0..components.count) |consumer_index| {
        inline for (handlers) |Handler| {
            if (components.items[consumer_index] != Handler.Consumer or
                !admittedSiteReachableAt(
                    components,
                    consumer_index,
                    Handler.site_ordinal,
                )) continue;
            const provider_index = components.indexOfInstance(
                Handler.Provider,
                handlerFailureMap(
                    Handler,
                    body(components.items[0]).Failure,
                ),
            );
            result[cursor] = boundary.effect.handler(
                @intCast(
                    effectOffset(components, consumer_index) +
                        Handler.site_ordinal,
                ),
                @intCast(if (componentVoidWrapperCount(components, provider_index) == 1)
                    voidWrapperFunctionId(Plan, provider_index)
                else
                    functionOffset(components, provider_index)),
            );
            cursor += 1;
        }
    }
    return result;
}

fn buildEffectMorphisms(
    comptime components: anytype,
    comptime morphisms: anytype,
) [activeMorphismCount(components, morphisms)]type {
    var result: [activeMorphismCount(components, morphisms)]type = undefined;
    var cursor: usize = 0;
    inline for (0..components.count) |consumer_index| {
        inline for (morphisms) |Morphism| {
            if (components.items[consumer_index] != Morphism.Consumer or
                !admittedSiteReachableAt(
                    components,
                    consumer_index,
                    Morphism.site_ordinal,
                )) continue;
            result[cursor] = boundary.effect.morphism(
                @intCast(
                    effectOffset(components, consumer_index) +
                        Morphism.site_ordinal,
                ),
                Morphism.Target,
            );
            cursor += 1;
        }
    }
    return result;
}

fn activeResidualCount(comptime Plan: type) usize {
    var result: usize = 0;
    inline for (0..Plan.components.count) |component_index| {
        inline for (body(Plan.components.items[component_index]).effect_sites, 0..) |_, site_ordinal| {
            switch (Plan.siteDisposition(component_index, site_ordinal)) {
                .morphism, .external => result += 1,
                .inactive, .handler => {},
            }
        }
    }
    return result;
}

fn residualEffects(comptime Plan: type) ResidualCatalog(activeResidualCount(Plan)) {
    const components = Plan.components;
    const morphisms = Plan.morphisms;
    var result: ResidualCatalog(activeResidualCount(Plan)) = .{};
    inline for (0..components.count) |component_index| {
        const Program = components.items[component_index];
        inline for (body(Program).effect_sites, 0..) |Site, site_ordinal| {
            switch (Plan.siteDisposition(component_index, site_ordinal)) {
                .inactive, .handler => {},
                .morphism => result.add(morphismTargetFor(
                    morphisms,
                    Program,
                    site_ordinal,
                )),
                .external => result.add(Site),
            }
        }
    }
    return result;
}

fn morphismTargetFor(
    comptime morphisms: anytype,
    comptime Program: type,
    comptime site_ordinal: usize,
) type {
    inline for (morphisms) |Morphism| {
        if (Morphism.Consumer == Program and
            Morphism.site_ordinal == site_ordinal)
        {
            return Morphism.Target;
        }
    }
    unreachable;
}
