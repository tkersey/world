const boundary = @import("boundary");
const std = @import("std");

const cir = boundary.ir;

const BindingKind = enum {
    handler,
    morphism,
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
        pub const Target = config.target;
    };
}

pub fn failureMorphism(
    comptime Source: type,
    comptime Target: type,
    comptime targets: anytype,
) type {
    requireFailureEnum(Source, "failure morphism Source");
    requireFailureEnum(Target, "failure morphism Target");
    const source_fields = @typeInfo(Source).@"enum".fields;
    if (targets.len != source_fields.len) {
        @compileError("World failure morphism must map every provider Failure tag");
    }
    const mapping = comptime blk: {
        var source_tags: [targets.len]u32 = undefined;
        var target_tags: [targets.len]u16 = undefined;
        for (targets, 0..) |target, index| {
            if (@TypeOf(target) != Target) {
                @compileError("World failure morphism targets must use system Failure");
            }
            source_tags[index] = @intCast(source_fields[index].value);
            target_tags[index] = @intCast(@intFromEnum(target));
        }
        break :blk .{ source_tags, target_tags };
    };
    return struct {
        pub const SourceFailure = Source;
        pub const TargetFailure = Target;
        pub const source_tags = mapping[0];
        pub const tags = mapping[1];
    };
}

pub fn system(comptime spec: anytype) type {
    @setEvalBranchQuota(500_000_000);
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
    comptime validateSystem(
        spec.root,
        components,
        handlers,
        morphisms,
        externals,
    );
    const Linked = LinkedBody(
        name,
        spec.root,
        components,
        handlers,
        morphisms,
        externals,
    );
    const LinkedProgram = boundary.program(name, Linked.Body);
    return struct {
        pub const Program = LinkedProgram;
        pub const Root = spec.root;
        pub const InitialArgs = Linked.Body.InitialArgs;
        pub const Result = Linked.Body.Result;
        pub const Failure = Linked.Body.Failure;
        pub const residual_effects = Linked.residual_effects;
        pub const schema_count = Linked.schema_count;
        pub const component_count = components.count;
        pub const internal_handler_count = handlers.len;
    };
}

fn ProgramSet(comptime capacity: usize) type {
    return struct {
        items: [capacity]type = undefined,
        count: usize = 0,

        fn add(self: *@This(), comptime Program: type) void {
            inline for (0..self.count) |index| {
                if (self.items[index] == Program) return;
            }
            self.items[self.count] = Program;
            self.count += 1;
        }
    };
}

fn componentsFor(
    comptime Root: type,
    comptime handlers: anytype,
    comptime morphisms: anytype,
) ProgramSet(1 + handlers.len * 2 + morphisms.len) {
    var result: ProgramSet(1 + handlers.len * 2 + morphisms.len) = .{};
    result.add(Root);
    inline for (handlers) |Handler| {
        requireHandler(Handler);
        result.add(Handler.Consumer);
        result.add(Handler.Provider);
    }
    inline for (morphisms) |Morphism| {
        requireMorphism(Morphism);
        result.add(Morphism.Consumer);
    }
    return result;
}

fn body(comptime Program: type) type {
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
    if (@hasDecl(Body, "effect_handlers") or
        @hasDecl(Body, "effect_morphisms"))
    {
        @compileError(
            "world.system components must leave handler and morphism selection to World",
        );
    }
    return Body;
}

fn validateSystem(
    comptime Root: type,
    comptime components: anytype,
    comptime handlers: anytype,
    comptime morphisms: anytype,
    comptime externals: anytype,
) void {
    const RootBody = body(Root);
    requireFailureEnum(RootBody.Failure, "root Failure");
    validateExternalDeclarations(externals);
    inline for (handlers) |Handler| validateHandler(Handler, RootBody.Failure);
    inline for (morphisms) |Morphism| {
        validateMorphism(Morphism);
        if (externalCount(externals, Morphism.Target) != 1) {
            @compileError(
                "World system morphism Target must be intentionally residual",
            );
        }
    }
    validateReachability(Root, components, handlers);
    detectCycles(Root, handlers, .{});
    inline for (0..components.count) |component_index| {
        const Program = components.items[component_index];
        const Body = body(Program);
        _ = failureMapFor(components, handlers, component_index);
        inline for (Body.effect_sites) |Site| {
            const internal_count = handlerCount(handlers, Program, Site);
            const morphism_count = morphismCount(morphisms, Program, Site);
            const external_count = externalCount(externals, Site);
            if (internal_count + morphism_count + external_count == 0) {
                @compileError(
                    "World system has an uncovered non-external effect site",
                );
            }
            if (internal_count + morphism_count + external_count != 1) {
                @compileError("World system effect site has ambiguous disposition");
            }
        }
    }
    inline for (externals) |External| {
        var used = false;
        inline for (0..components.count) |component_index| {
            const Program = components.items[component_index];
            inline for (body(Program).effect_sites) |Site| {
                if (Site == External and
                    handlerCount(handlers, Program, Site) == 0 and
                    morphismCount(morphisms, Program, Site) == 0)
                {
                    used = true;
                }
            }
        }
        inline for (morphisms) |Morphism| {
            if (Morphism.Target == External) used = true;
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
        Left.tags.len != Right.tags.len)
    {
        return false;
    }
    inline for (
        Left.source_tags,
        Right.source_tags,
        Left.tags,
        Right.tags,
    ) |left_source, right_source, left_target, right_target| {
        if (left_source != right_source or left_target != right_target) {
            return false;
        }
    }
    return true;
}

fn failureMapFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) type {
    if (component_index == 0) return void;
    const Program = components.items[component_index];
    const ComponentFailure = body(Program).Failure;
    const SystemFailure = body(components.items[0]).Failure;
    if (ComponentFailure == SystemFailure) return void;
    var Result: type = void;
    var found = false;
    inline for (handlers) |Handler| {
        if (Handler.Provider != Program) continue;
        if (!found) {
            Result = Handler.FailureMorphism;
            found = true;
        } else if (!failureMapsEqual(Result, Handler.FailureMorphism)) {
            @compileError(
                "World system requires one canonical Failure morphism per provider",
            );
        }
    }
    if (!found) unreachable;
    return Result;
}

fn failureTagCount(comptime Failure: type) usize {
    return @typeInfo(Failure).@"enum".fields.len;
}

fn failureValueExpansionValues(comptime Map: type) usize {
    if (Map == void or Map.tags.len <= 1) return 0;
    return 1 + 2 * (Map.tags.len - 1);
}

fn failureValueExpansionBlocks(comptime Map: type) usize {
    if (Map == void or Map.tags.len <= 1) return 0;
    return 2 * Map.tags.len - 2;
}

fn failureValueExpansionConstants(comptime Map: type) usize {
    if (Map == void or Map.tags.len <= 1) return 0;
    return Map.tags.len - 1;
}

fn componentFailValueCount(
    comptime components: anytype,
    comptime component_index: usize,
) usize {
    var count: usize = 0;
    inline for (body(components.items[component_index]).control_ir.blocks) |block| {
        switch (block.terminator) {
            .fail_value => count += 1,
            else => {},
        }
    }
    return count;
}

fn componentExtraValues(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    return componentFailValueCount(components, component_index) *
        failureValueExpansionValues(failureMapFor(
            components,
            handlers,
            component_index,
        ));
}

fn componentExtraBlocks(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    return componentFailValueCount(components, component_index) *
        failureValueExpansionBlocks(failureMapFor(
            components,
            handlers,
            component_index,
        ));
}

fn componentExtraConstants(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    return componentFailValueCount(components, component_index) *
        failureValueExpansionConstants(failureMapFor(
            components,
            handlers,
            component_index,
        ));
}

fn componentVoidReturnCount(
    comptime components: anytype,
    comptime component_index: usize,
) usize {
    if (component_index == 0 or
        body(components.items[component_index]).Result != void)
    {
        return 0;
    }
    var count: usize = 0;
    inline for (body(components.items[component_index]).control_ir.blocks) |block| {
        if (block.function_id != 0) continue;
        switch (block.terminator) {
            .return_value => |value| if (value == null) {
                count += 1;
            },
            else => {},
        }
    }
    return count;
}

fn totalVoidReturns(comptime components: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += componentVoidReturnCount(components, index);
    }
    return result;
}

fn precedingVoidReturns(
    comptime components: anytype,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentVoidReturnCount(components, index);
    }
    return result;
}

fn voidReturnOrdinal(
    comptime components: anytype,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    var result: usize = 0;
    inline for (body(components.items[component_index]).control_ir.blocks) |block| {
        if (block.id == block_id) return result;
        if (block.function_id != 0) continue;
        switch (block.terminator) {
            .return_value => |value| if (value == null) {
                result += 1;
            },
            else => {},
        }
    }
    unreachable;
}

fn requireHandler(comptime Handler: type) void {
    if (!@hasDecl(Handler, "binding_kind") or
        Handler.binding_kind != .handler)
    {
        @compileError("world.system handlers contains a non-handler binding");
    }
}

fn requireMorphism(comptime Morphism: type) void {
    if (!@hasDecl(Morphism, "binding_kind") or
        Morphism.binding_kind != .morphism)
    {
        @compileError("world.system morphisms contains a non-morphism binding");
    }
}

fn validateHandler(
    comptime Handler: type,
    comptime SystemFailure: type,
) void {
    requireHandler(Handler);
    const ConsumerBody = body(Handler.Consumer);
    const ProviderBody = body(Handler.Provider);
    requireComponentSite(ConsumerBody, Handler.Site);
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
    if (Map.SourceFailure != ProviderBody.Failure or
        Map.TargetFailure != SystemFailure)
    {
        @compileError("World system failure morphism has the wrong endpoint types");
    }
}

fn validateMorphism(comptime Morphism: type) void {
    requireMorphism(Morphism);
    const ConsumerBody = body(Morphism.Consumer);
    requireComponentSite(ConsumerBody, Morphism.Site);
    if (Morphism.Site.Payload != Morphism.Target.Payload or
        Morphism.Site.Resume != Morphism.Target.Resume)
    {
        @compileError("World system effect morphism must preserve Payload and Resume");
    }
}

fn requireComponentSite(comptime Body: type, comptime Site: type) void {
    var count: usize = 0;
    inline for (Body.effect_sites) |Candidate| {
        if (Candidate == Site) count += 1;
    }
    if (count != 1) {
        @compileError("World system binding site must occur exactly once in consumer");
    }
}

fn validateExternalDeclarations(comptime externals: anytype) void {
    inline for (externals, 0..) |Site, index| {
        inline for (0..index) |prior| {
            if (Site == externals[prior]) {
                @compileError("World system has duplicate external declarations");
            }
        }
    }
}

fn handlerCount(
    comptime handlers: anytype,
    comptime Program: type,
    comptime Site: type,
) usize {
    var count: usize = 0;
    inline for (handlers) |Handler| {
        if (Handler.Consumer == Program and Handler.Site == Site) count += 1;
    }
    return count;
}

fn morphismCount(
    comptime morphisms: anytype,
    comptime Program: type,
    comptime Site: type,
) usize {
    var count: usize = 0;
    inline for (morphisms) |Morphism| {
        if (Morphism.Consumer == Program and Morphism.Site == Site) count += 1;
    }
    return count;
}

fn externalCount(comptime externals: anytype, comptime Site: type) usize {
    var count: usize = 0;
    inline for (externals) |External| {
        if (External == Site) count += 1;
    }
    return count;
}

fn validateReachability(
    comptime Root: type,
    comptime components: anytype,
    comptime handlers: anytype,
) void {
    inline for (0..components.count) |index| {
        const Program = components.items[index];
        if (!reachableFrom(Root, Program, handlers, .{})) {
            @compileError("World system contains a handler component unreachable from root");
        }
    }
}

fn reachableFrom(
    comptime Current: type,
    comptime Target: type,
    comptime handlers: anytype,
    comptime path: anytype,
) bool {
    if (Current == Target) return true;
    inline for (path) |Ancestor| if (Ancestor == Current) return false;
    const next_path = path ++ .{Current};
    inline for (handlers) |Handler| {
        if (Handler.Consumer == Current and
            reachableFrom(Handler.Provider, Target, handlers, next_path))
        {
            return true;
        }
    }
    return false;
}

fn detectCycles(
    comptime Current: type,
    comptime handlers: anytype,
    comptime path: anytype,
) void {
    inline for (path) |Ancestor| {
        if (Ancestor == Current) {
            @compileError("World system internal handler graph contains a cycle");
        }
    }
    const next_path = path ++ .{Current};
    inline for (handlers) |Handler| {
        if (Handler.Consumer == Current) {
            detectCycles(Handler.Provider, handlers, next_path);
        }
    }
}

fn requireFailureEnum(comptime Failure: type, comptime label: []const u8) void {
    switch (@typeInfo(Failure)) {
        .@"enum" => {},
        else => @compileError("World system " ++ label ++ " must be an enum"),
    }
}

fn LinkedBody(
    comptime name: []const u8,
    comptime Root: type,
    comptime components: anytype,
    comptime handlers: anytype,
    comptime morphisms: anytype,
    comptime externals: anytype,
) type {
    const RootComponent = body(Root);
    const schema_set = comptime schemasFor(components);
    const value_types = comptime buildValueTypes(components, schema_set, handlers);
    const linked_constants = comptime buildConstants(components, handlers);
    const linked_functions = comptime buildFunctions(components, schema_set);
    const blocks = comptime buildBlocks(
        components,
        schema_set,
        handlers,
    );
    const linked_effect_sites = comptime buildEffectSites(components);
    const linked_effect_handlers = comptime buildEffectHandlers(components, handlers);
    const linked_effect_morphisms = comptime buildEffectMorphisms(components, morphisms);
    const linked_residual_effects = comptime residualEffects(
        components,
        handlers,
        morphisms,
        externals,
    );
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

fn totalSchemaCount(comptime components: anytype) usize {
    var count: usize = 0;
    inline for (0..components.count) |index| {
        count += body(components.items[index]).schema_types.len;
    }
    return count;
}

fn schemasFor(
    comptime components: anytype,
) TypeSet(totalSchemaCount(components)) {
    var result: TypeSet(totalSchemaCount(components)) = .{};
    inline for (0..components.count) |index| {
        inline for (body(components.items[index]).schema_types) |Schema| {
            result.add(Schema);
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

fn componentIndex(comptime components: anytype, comptime Program: type) usize {
    inline for (0..components.count) |index| {
        if (components.items[index] == Program) return index;
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

fn totalExtraValues(
    comptime components: anytype,
    comptime handlers: anytype,
) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += componentExtraValues(components, handlers, index);
    }
    return result;
}

fn totalExtraBlocks(
    comptime components: anytype,
    comptime handlers: anytype,
) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += componentExtraBlocks(components, handlers, index);
    }
    return result;
}

fn totalExtraConstants(
    comptime components: anytype,
    comptime handlers: anytype,
) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += componentExtraConstants(components, handlers, index);
    }
    return result;
}

fn linkedTotalValues(
    comptime components: anytype,
    comptime handlers: anytype,
) usize {
    return totalValues(components) +
        totalExtraValues(components, handlers) +
        totalVoidReturns(components);
}

fn linkedTotalBlocks(
    comptime components: anytype,
    comptime handlers: anytype,
) usize {
    return totalBlocks(components) + totalExtraBlocks(components, handlers);
}

fn linkedTotalConstants(
    comptime components: anytype,
    comptime handlers: anytype,
) usize {
    return totalConstants(components) +
        totalExtraConstants(components, handlers) +
        totalVoidReturns(components);
}

fn precedingExtraValues(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentExtraValues(components, handlers, index);
    }
    return result;
}

fn precedingExtraBlocks(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentExtraBlocks(components, handlers, index);
    }
    return result;
}

fn precedingExtraConstants(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (0..component_index) |index| {
        result += componentExtraConstants(components, handlers, index);
    }
    return result;
}

fn failValueOrdinal(
    comptime components: anytype,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    var result: usize = 0;
    inline for (body(components.items[component_index]).control_ir.blocks) |block| {
        if (block.id == block_id) return result;
        switch (block.terminator) {
            .fail_value => result += 1,
            else => {},
        }
    }
    unreachable;
}

fn failureValueBase(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    const Map = failureMapFor(components, handlers, component_index);
    return totalValues(components) +
        precedingExtraValues(components, handlers, component_index) +
        failValueOrdinal(components, component_index, block_id) *
            failureValueExpansionValues(Map);
}

fn failureBlockBase(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    const Map = failureMapFor(components, handlers, component_index);
    return totalBlocks(components) +
        precedingExtraBlocks(components, handlers, component_index) +
        failValueOrdinal(components, component_index, block_id) *
            failureValueExpansionBlocks(Map);
}

fn failureConstantBase(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    const Map = failureMapFor(components, handlers, component_index);
    return totalConstants(components) +
        precedingExtraConstants(components, handlers, component_index) +
        failValueOrdinal(components, component_index, block_id) *
            failureValueExpansionConstants(Map);
}

fn voidReturnValueBase(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    return totalValues(components) +
        totalExtraValues(components, handlers) +
        precedingVoidReturns(components, component_index) +
        voidReturnOrdinal(components, component_index, block_id);
}

fn voidReturnConstantBase(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block_id: cir.BlockId,
) usize {
    return totalConstants(components) +
        totalExtraConstants(components, handlers) +
        precedingVoidReturns(components, component_index) +
        voidReturnOrdinal(components, component_index, block_id);
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
    comptime components: anytype,
    comptime schemas: anytype,
    comptime handlers: anytype,
) [linkedTotalValues(components, handlers)]cir.ValueType {
    var result: [linkedTotalValues(components, handlers)]cir.ValueType = undefined;
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
    inline for (0..components.count) |component_index| {
        const Map = failureMapFor(components, handlers, component_index);
        if (Map == void or Map.tags.len <= 1) continue;
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            switch (block.terminator) {
                .fail_value => {
                    result[cursor] = .{ .scalar = .u32 };
                    cursor += 1;
                    inline for (0..Map.tags.len - 1) |_| {
                        result[cursor] = .{ .scalar = .u32 };
                        result[cursor + 1] = .{ .scalar = .boolean };
                        cursor += 2;
                    }
                },
                else => {},
            }
        }
    }
    inline for (1..components.count) |component_index| {
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            if (block.function_id != 0) continue;
            switch (block.terminator) {
                .return_value => |value| if (value == null and
                    body(components.items[component_index]).Result == void)
                {
                    result[cursor] = .{ .scalar = .unit };
                    cursor += 1;
                },
                else => {},
            }
        }
    }
    return result;
}

fn constantTypes(
    comptime components: anytype,
    comptime handlers: anytype,
) [linkedTotalConstants(components, handlers)]type {
    var result: [linkedTotalConstants(components, handlers)]type = undefined;
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
        const Map = failureMapFor(components, handlers, component_index);
        if (Map == void or Map.tags.len <= 1) continue;
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            switch (block.terminator) {
                .fail_value => inline for (0..Map.tags.len - 1) |_| {
                    result[cursor] = u32;
                    cursor += 1;
                },
                else => {},
            }
        }
    }
    inline for (1..components.count) |component_index| {
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            if (block.function_id != 0) continue;
            switch (block.terminator) {
                .return_value => |value| if (value == null and
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

fn Constants(comptime components: anytype, comptime handlers: anytype) type {
    const types = constantTypes(components, handlers);
    return std.meta.Tuple(&types);
}

fn buildConstants(
    comptime components: anytype,
    comptime handlers: anytype,
) Constants(components, handlers) {
    var result: Constants(components, handlers) = undefined;
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
        const Map = failureMapFor(components, handlers, component_index);
        if (Map == void or Map.tags.len <= 1) continue;
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            switch (block.terminator) {
                .fail_value => inline for (0..Map.tags.len - 1) |tag| {
                    @field(
                        result,
                        std.fmt.comptimePrint("{d}", .{cursor}),
                    ) = Map.source_tags[tag];
                    cursor += 1;
                },
                else => {},
            }
        }
    }
    inline for (1..components.count) |component_index| {
        inline for (body(components.items[component_index]).control_ir.blocks) |block| {
            if (block.function_id != 0) continue;
            switch (block.terminator) {
                .return_value => |value| if (value == null and
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

fn buildFunctions(
    comptime components: anytype,
    comptime schemas: anytype,
) [totalFunctions(components)]cir.Function {
    var result: [totalFunctions(components)]cir.Function = undefined;
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
    return result;
}

fn buildBlocks(
    comptime components: anytype,
    comptime schemas: anytype,
    comptime handlers: anytype,
) [linkedTotalBlocks(components, handlers)]cir.Block {
    var result: [linkedTotalBlocks(components, handlers)]cir.Block = undefined;
    var cursor: usize = 0;
    inline for (0..components.count) |component_index| {
        const Body = body(components.items[component_index]);
        inline for (Body.control_ir.blocks) |source| {
            result[cursor] = remapBlock(
                components,
                schemas,
                handlers,
                component_index,
                source,
            );
            cursor += 1;
        }
    }
    inline for (0..components.count) |component_index| {
        const Map = failureMapFor(components, handlers, component_index);
        if (Map == void or Map.tags.len <= 1) continue;
        inline for (body(components.items[component_index]).control_ir.blocks) |source| {
            switch (source.terminator) {
                .fail_value => {
                    const extra_base = failureBlockBase(
                        components,
                        handlers,
                        component_index,
                        source.id,
                    );
                    const fail_base = extra_base + Map.tags.len - 2;
                    inline for (1..Map.tags.len - 1) |tag| {
                        result[extra_base + tag - 1] = failureCheckBlock(
                            components,
                            handlers,
                            component_index,
                            source,
                            tag,
                            extra_base,
                            fail_base,
                        );
                    }
                    inline for (0..Map.tags.len) |tag| {
                        result[fail_base + tag] = .{
                            .id = @intCast(fail_base + tag),
                            .function_id = @intCast(
                                functionOffset(components, component_index) +
                                    source.function_id,
                            ),
                            .role = .terminal_handoff,
                            .terminator = .{ .fail = Map.tags[tag] },
                        };
                    }
                },
                else => {},
            }
        }
    }
    return result;
}

fn remapBlock(
    comptime components: anytype,
    comptime schemas: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime source: cir.Block,
) cir.Block {
    const Static = struct {
        const parameters = remapValueIds(
            source.parameters,
            valueOffset(components, component_index),
        );
        const instructions = remapBlockInstructions(
            components,
            handlers,
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
            components,
            schemas,
            handlers,
            component_index,
            source,
        ),
    };
}

fn expandsFailureValue(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime source: cir.Block,
) bool {
    const Map = failureMapFor(components, handlers, component_index);
    if (Map == void or Map.tags.len <= 1) return false;
    return switch (source.terminator) {
        .fail_value => true,
        else => false,
    };
}

fn expandsVoidReturn(
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
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime source: cir.Block,
) [
    source.instructions.len +
        @as(usize, if (expandsFailureValue(
            components,
            handlers,
            component_index,
            source,
        )) 3 else 0) +
        @as(usize, if (expandsVoidReturn(
            components,
            component_index,
            source,
        )) 1 else 0)
]cir.Instruction {
    const failure_extra: usize = if (expandsFailureValue(
        components,
        handlers,
        component_index,
        source,
    )) 3 else 0;
    const void_extra: usize = if (expandsVoidReturn(
        components,
        component_index,
        source,
    )) 1 else 0;
    const extra_count = failure_extra + void_extra;
    var result: [source.instructions.len + extra_count]cir.Instruction = undefined;
    const remapped = remapInstructions(
        components,
        component_index,
        source.instructions,
    );
    inline for (remapped, 0..) |instruction, index| result[index] = instruction;
    if (extra_count == 0) return result;

    if (void_extra == 1) {
        appendVoidReturnInstruction(
            &result,
            components,
            handlers,
            component_index,
            source,
        );
        return result;
    }

    appendFailureValueInstructions(
        &result,
        components,
        handlers,
        component_index,
        source,
    );
    return result;
}

fn appendVoidReturnInstruction(
    result: anytype,
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime source: cir.Block,
) void {
    result.*[source.instructions.len] = .{
        .kind = .constant,
        .result = @intCast(voidReturnValueBase(
            components,
            handlers,
            component_index,
            source.id,
        )),
        .operation = .{ .constant = @intCast(voidReturnConstantBase(
            components,
            handlers,
            component_index,
            source.id,
        )) },
    };
}

fn appendFailureValueInstructions(
    result: anytype,
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime source: cir.Block,
) void {
    const fail_value = switch (source.terminator) {
        .fail_value => |value| value,
        else => unreachable,
    };
    const value_base = failureValueBase(
        components,
        handlers,
        component_index,
        source.id,
    );
    const constant_base = failureConstantBase(
        components,
        handlers,
        component_index,
        source.id,
    );
    const Static = struct {
        const tag_operands = [_]cir.ValueId{@intCast(
            valueOffset(components, component_index) + fail_value,
        )};
        const compare_operands = [_]cir.ValueId{
            @intCast(value_base),
            @intCast(value_base + 1),
        };
    };
    result.*[source.instructions.len] = .{
        .kind = .pure,
        .result = @intCast(value_base),
        .operands = &Static.tag_operands,
        .operation = .enum_to_u32,
    };
    result.*[source.instructions.len + 1] = .{
        .kind = .constant,
        .result = @intCast(value_base + 1),
        .operation = .{ .constant = @intCast(constant_base) },
    };
    result.*[source.instructions.len + 2] = .{
        .kind = .pure,
        .result = @intCast(value_base + 2),
        .operands = &Static.compare_operands,
        .operation = .integer_equal,
    };
}

fn remapBlockTerminator(
    comptime components: anytype,
    comptime schemas: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime source_block: cir.Block,
) cir.Terminator {
    const source = source_block.terminator;
    if (expandsVoidReturn(components, component_index, source_block)) {
        return .{ .return_to_caller = @intCast(voidReturnValueBase(
            components,
            handlers,
            component_index,
            source_block.id,
        )) };
    }
    if (failureMapFor(components, handlers, component_index) != void) {
        switch (source) {
            .fail_value => {
                const Map = failureMapFor(components, handlers, component_index);
                if (Map.tags.len == 0) {
                    @compileError("World failure morphism cannot map an empty Failure enum");
                }
                if (Map.tags.len == 1) return .{ .fail = Map.tags[0] };
                const value_base = failureValueBase(
                    components,
                    handlers,
                    component_index,
                    source_block.id,
                );
                const extra_base = failureBlockBase(
                    components,
                    handlers,
                    component_index,
                    source_block.id,
                );
                const fail_base = extra_base + Map.tags.len - 2;
                return .{ .branch = .{
                    .condition = @intCast(value_base + 2),
                    .then_edge = .{ .target = @intCast(fail_base) },
                    .else_edge = .{ .target = @intCast(if (Map.tags.len == 2)
                        fail_base + 1
                    else
                        extra_base) },
                } };
            },
            else => {},
        }
    }
    return remapTerminator(
        components,
        schemas,
        handlers,
        component_index,
        source_block.function_id,
        source,
    );
}

fn failureCheckBlock(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime source: cir.Block,
    comptime tag: usize,
    comptime extra_base: usize,
    comptime fail_base: usize,
) cir.Block {
    const Map = failureMapFor(components, handlers, component_index);
    const value_base = failureValueBase(
        components,
        handlers,
        component_index,
        source.id,
    );
    const constant_value = value_base + 1 + 2 * tag;
    const condition_value = value_base + 2 + 2 * tag;
    const constant_base = failureConstantBase(
        components,
        handlers,
        component_index,
        source.id,
    );
    const Static = struct {
        const compare_operands = [_]cir.ValueId{
            @intCast(value_base),
            @intCast(constant_value),
        };
        const instructions = [_]cir.Instruction{
            .{
                .kind = .constant,
                .result = @intCast(constant_value),
                .operation = .{ .constant = @intCast(constant_base + tag) },
            },
            .{
                .kind = .pure,
                .result = @intCast(condition_value),
                .operands = &compare_operands,
                .operation = .integer_equal,
            },
        };
    };
    return .{
        .id = @intCast(extra_base + tag - 1),
        .function_id = @intCast(
            functionOffset(components, component_index) + source.function_id,
        ),
        .instructions = &Static.instructions,
        .terminator = .{ .branch = .{
            .condition = @intCast(condition_value),
            .then_edge = .{ .target = @intCast(fail_base + tag) },
            .else_edge = .{ .target = @intCast(if (tag + 1 == Map.tags.len - 1)
                fail_base + Map.tags.len - 1
            else
                extra_base + tag) },
        } },
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

fn remapInstructions(
    comptime components: anytype,
    comptime component_index: usize,
    comptime source: []const cir.Instruction,
) [source.len]cir.Instruction {
    var result: [source.len]cir.Instruction = undefined;
    inline for (source, 0..) |instruction, index| {
        result[index] = remapInstruction(
            components,
            component_index,
            instruction,
        );
    }
    return result;
}

fn remapInstruction(
    comptime components: anytype,
    comptime component_index: usize,
    comptime source: cir.Instruction,
) cir.Instruction {
    const value_offset = valueOffset(components, component_index);
    const Static = struct {
        const operands = remapValueIds(source.operands, value_offset);
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
    comptime handlers: anytype,
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
            .then_edge = remapEdge(components, component_index, branch.then_edge),
            .else_edge = remapEdge(components, component_index, branch.else_edge),
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
                handlers,
                component_index,
                failure,
            ),
        },
        .fail_value => |value| .{ .fail_value = @intCast(value_offset + value) },
    };
}

fn remapFailureTag(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime source_tag: u16,
) u16 {
    if (component_index == 0) return source_tag;
    const Program = components.items[component_index];
    const ComponentFailure = body(Program).Failure;
    const SystemFailure = body(components.items[0]).Failure;
    if (ComponentFailure == SystemFailure) return source_tag;
    inline for (handlers) |Handler| {
        if (Handler.Provider == Program) {
            const Map = Handler.FailureMorphism;
            inline for (Map.source_tags, Map.tags) |from, to| {
                if (from == source_tag) return to;
            }
            unreachable;
        }
    }
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

fn siteIndex(comptime Program: type, comptime Site: type) usize {
    inline for (body(Program).effect_sites, 0..) |Candidate, index| {
        if (Candidate == Site) return index;
    }
    unreachable;
}

fn buildEffectHandlers(
    comptime components: anytype,
    comptime handlers: anytype,
) [handlers.len]type {
    var result: [handlers.len]type = undefined;
    inline for (handlers, 0..) |Handler, index| {
        const consumer_index = componentIndex(components, Handler.Consumer);
        const provider_index = componentIndex(components, Handler.Provider);
        result[index] = boundary.effect.handler(
            @intCast(
                effectOffset(components, consumer_index) +
                    siteIndex(Handler.Consumer, Handler.Site),
            ),
            @intCast(functionOffset(components, provider_index)),
        );
    }
    return result;
}

fn buildEffectMorphisms(
    comptime components: anytype,
    comptime morphisms: anytype,
) [morphisms.len]type {
    var result: [morphisms.len]type = undefined;
    inline for (morphisms, 0..) |Morphism, index| {
        const consumer_index = componentIndex(components, Morphism.Consumer);
        result[index] = boundary.effect.morphism(
            @intCast(
                effectOffset(components, consumer_index) +
                    siteIndex(Morphism.Consumer, Morphism.Site),
            ),
            Morphism.Target,
        );
    }
    return result;
}

fn residualEffects(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime morphisms: anytype,
    comptime externals: anytype,
) TypeSet(totalEffects(components) + morphisms.len) {
    var result: TypeSet(totalEffects(components) + morphisms.len) = .{};
    inline for (0..components.count) |component_index| {
        const Program = components.items[component_index];
        inline for (body(Program).effect_sites) |Site| {
            if (handlerCount(handlers, Program, Site) == 1) continue;
            inline for (morphisms) |Morphism| {
                if (Morphism.Consumer == Program and Morphism.Site == Site) {
                    result.add(Morphism.Target);
                }
            }
            if (externalCount(externals, Site) == 1) result.add(Site);
        }
    }
    return result;
}
