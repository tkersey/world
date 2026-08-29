const boundary = @import("boundary");
const fixtures = @import("system_v1_fixtures");
const std = @import("std");

const Facts = struct {
    component_count: usize = 0,
    source_values: usize = 0,
    source_blocks: usize = 0,
    source_functions: usize = 0,
    source_constants: usize = 0,
    source_effects: usize = 0,
    unreachable_blocks: usize = 0,
    instruction_failure_values: usize = 0,
    failure_values: usize = 0,
    failure_blocks: usize = 0,
    failure_functions: usize = 0,
    failure_constants: usize = 0,
    void_returns: usize = 0,
    void_wrappers: usize = 0,
};

fn ComponentSet(comptime capacity: usize) type {
    return struct {
        items: [capacity]type = undefined,
        failure_maps: [capacity]type = undefined,
        count: usize = 0,

        fn add(
            self: *@This(),
            comptime Program: type,
            comptime FailureMap: type,
        ) bool {
            inline for (0..self.count) |index| {
                if (self.items[index] == Program and
                    failureMapsEqual(self.failure_maps[index], FailureMap))
                {
                    return false;
                }
            }
            self.items[self.count] = Program;
            self.failure_maps[self.count] = FailureMap;
            self.count += 1;
            return true;
        }

        fn indexOf(
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

fn componentSet(comptime spec: anytype) ComponentSet(1 + spec.handlers.len) {
    var result: ComponentSet(1 + spec.handlers.len) = .{};
    _ = result.add(spec.root, void);
    collectProviders(&result, 0, spec.handlers);
    return result;
}

fn collectProviders(
    result: anytype,
    comptime current_index: usize,
    comptime handlers: anytype,
) void {
    const Current = result.items[current_index];
    inline for (Current.component().effect_sites, 0..) |_, site_ordinal| {
        if (!sourceSiteReachable(Current, site_ordinal)) continue;
        inline for (handlers) |Handler| {
            if (Handler.Consumer != Current or Handler.site_ordinal != site_ordinal) {
                continue;
            }
            const FailureMap = handlerFailureMap(
                Handler,
                result.items[0].component().Failure,
            );
            if (result.add(Handler.Provider, FailureMap)) {
                collectProviders(
                    result,
                    result.indexOf(Handler.Provider, FailureMap),
                    handlers,
                );
            }
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

fn handlerFailureMap(
    comptime Handler: type,
    comptime RootFailure: type,
) type {
    return if (Handler.Provider.component().Failure == RootFailure)
        void
    else
        Handler.FailureMorphism;
}

fn componentFunctionCount(comptime Body: type) usize {
    return if (Body.control_ir.functions.len == 0)
        1
    else
        Body.control_ir.functions.len;
}

fn componentConstantCount(comptime Body: type) usize {
    return if (@hasDecl(Body, "constants")) Body.constants.len else 0;
}

fn failureMapFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) type {
    _ = handlers;
    return components.failure_maps[component_index];
}

fn failureTargetQuotientFor(comptime Map: type) struct {
    targets: [Map.targets.len]Map.TargetFailure,
    source_to_target: [Map.targets.len]usize,
    count: usize,
} {
    comptime var targets: [Map.targets.len]Map.TargetFailure = undefined;
    comptime var source_to_target: [Map.targets.len]usize = undefined;
    comptime var count: usize = 0;
    inline for (Map.targets, 0..) |target, source_index| {
        comptime var found: ?usize = null;
        inline for (Map.targets, 0..) |prior, prior_index| {
            if (prior_index < source_index and
                @intFromEnum(prior) == @intFromEnum(target))
            {
                found = source_to_target[prior_index];
            }
        }
        if (found == null) {
            found = count;
            targets[count] = target;
            count += 1;
        }
        source_to_target[source_index] = found.?;
    }
    return .{ .targets = targets, .source_to_target = source_to_target, .count = count };
}

fn InstructionFailureTargetsFor(
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

fn instructionFailureCapacityFor(comptime block: boundary.ir.Block) usize {
    var result: usize = 0;
    inline for (block.instructions) |instruction| {
        result += boundary.ir.mappedFailureOperandCount(instruction.operation);
    }
    return result;
}

fn mappedTargetForProof(comptime Map: type, comptime source_tag: u32) Map.TargetFailure {
    inline for (Map.source_tags, Map.targets) |candidate, target| {
        if (candidate == source_tag) return target;
    }
    unreachable;
}

fn instructionFailureTargetsForBlock(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block: boundary.ir.Block,
) InstructionFailureTargetsFor(
    components.items[0].component().Failure,
    instructionFailureCapacityFor(block),
) {
    const RootFailure = components.items[0].component().Failure;
    var result: InstructionFailureTargetsFor(
        RootFailure,
        instructionFailureCapacityFor(block),
    ) = .{};
    const Map = failureMapFor(components, handlers, component_index);
    if (Map == void) return result;
    const Admission = boundary.componentAdmission(components.items[component_index]);
    inline for (block.instructions) |instruction| {
        const source_tags = Admission.instructionFailureProjection(
            instruction,
        ).failure_tags;
        inline for (source_tags) |source_tag| {
            result.add(mappedTargetForProof(Map, source_tag));
        }
    }
    return result;
}

fn componentInstructionFailureValueCountFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    var result: usize = 0;
    inline for (components.items[component_index].component().control_ir.blocks) |block| {
        result += instructionFailureTargetsForBlock(
            components,
            handlers,
            component_index,
            block,
        ).count;
    }
    return result;
}

fn totalInstructionFailureValuesFor(
    comptime components: anytype,
    comptime handlers: anytype,
) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += componentInstructionFailureValueCountFor(
            components,
            handlers,
            index,
        );
    }
    return result;
}

fn instructionFailureValueBaseFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block_id: boundary.ir.BlockId,
) usize {
    var result = sourceOffsets(components, components.count).values;
    inline for (0..component_index) |index| {
        result += componentInstructionFailureValueCountFor(
            components,
            handlers,
            index,
        );
    }
    inline for (components.items[component_index].component().control_ir.blocks) |block| {
        if (block.id == block_id) return result;
        result += instructionFailureTargetsForBlock(
            components,
            handlers,
            component_index,
            block,
        ).count;
    }
    unreachable;
}

fn instructionFailureConstantBaseFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block_id: boundary.ir.BlockId,
) usize {
    return instructionFailureValueBaseFor(
        components,
        handlers,
        component_index,
        block_id,
    ) - sourceOffsets(components, components.count).values +
        sourceOffsets(components, components.count).constants;
}

fn addFailureFacts(
    facts: *Facts,
    comptime Map: type,
    comptime terminator: boundary.ir.Terminator,
) void {
    if (Map == void) return;
    switch (terminator) {
        .fail => {
            facts.failure_values += 1;
            facts.failure_blocks += 1;
            facts.failure_constants += 1;
        },
        .fail_value => if (Map.targets.len == 0) {} else if (failureTargetQuotientFor(Map).count == 1) {
            facts.failure_values += 1;
            facts.failure_blocks += 1;
            facts.failure_constants += 1;
        } else {
            facts.failure_values += 1;
            facts.failure_blocks += 1;
        },
        else => {},
    }
}

fn deriveSourceFacts(comptime spec: anytype) Facts {
    const components = componentSet(spec);
    var facts: Facts = .{ .component_count = components.count };
    inline for (0..components.count) |component_index| {
        const Body = components.items[component_index].component();
        const reachable = comptime boundary.componentAdmission(
            components.items[component_index],
        ).reachability;
        facts.source_values += Body.control_ir.value_types.len;
        facts.source_blocks += Body.control_ir.blocks.len;
        facts.source_functions += componentFunctionCount(Body);
        facts.source_constants += componentConstantCount(Body);
        facts.source_effects += Body.effect_sites.len;
        if (component_index != 0 and Body.InitialArgs == void and
            Body.control_ir.blocks[Body.control_ir.entry].parameters.len == 0)
        {
            facts.void_wrappers += 1;
        }
        const Map = failureMapFor(components, spec.handlers, component_index);
        var dynamic_failure_count: usize = 0;
        var void_return_found = false;
        inline for (Body.control_ir.blocks) |block| {
            facts.instruction_failure_values += instructionFailureTargetsForBlock(
                components,
                spec.handlers,
                component_index,
                block,
            ).count;
            if (!reachable.contains(block.id)) {
                facts.unreachable_blocks += 1;
                continue;
            }
            if (Map == void or
                directFailureTargetForProof(Map, block.terminator) == null or
                directFailureOwnerForProof(
                    components,
                    spec.handlers,
                    component_index,
                    block.id,
                ) == block.id)
            {
                addFailureFacts(&facts, Map, block.terminator);
            }
            if (Map != void and failureTargetQuotientFor(Map).count > 1) {
                switch (block.terminator) {
                    .fail_value => dynamic_failure_count += 1,
                    else => {},
                }
            }
            if (component_index != 0 and Body.Result == void and
                block.function_id == 0)
            {
                switch (block.terminator) {
                    .return_value => |value| if (value == null) {
                        void_return_found = true;
                    },
                    else => {},
                }
            }
        }
        if (dynamic_failure_count != 0 and
            failureSelectorOwnerFor(
                components,
                spec.handlers,
                component_index,
            ).? == component_index)
        {
            const Quotient = comptime failureTargetQuotientFor(Map);
            facts.failure_values += 3 * Map.targets.len + Quotient.count - 1;
            facts.failure_blocks += 1;
            facts.failure_functions += 1;
            facts.failure_constants += Map.targets.len - 1 + Quotient.count;
        }
        facts.void_returns += @intFromBool(void_return_found);
    }
    return facts;
}

fn handlerCount(
    comptime handlers: anytype,
    comptime Program: type,
    comptime site_ordinal: usize,
) usize {
    var result: usize = 0;
    inline for (handlers) |Handler| {
        if (Handler.Consumer == Program and Handler.site_ordinal == site_ordinal) {
            result += 1;
        }
    }
    return result;
}

fn morphismCount(
    comptime morphisms: anytype,
    comptime Program: type,
    comptime site_ordinal: usize,
) usize {
    var result: usize = 0;
    inline for (morphisms) |Morphism| {
        if (Morphism.Consumer == Program and Morphism.site_ordinal == site_ordinal) {
            result += 1;
        }
    }
    return result;
}

fn isExternalBinding(comptime External: type) bool {
    if (@hasDecl(External, "Payload") and
        @hasDecl(External, "Resume") and
        @hasDecl(External, "semantic_identity")) return false;
    return @hasDecl(External, "Consumer") and
        @hasDecl(External, "Site") and
        @hasDecl(External, "site_ordinal");
}

fn uncoveredSourceCount(comptime spec: anytype, comptime Site: type) usize {
    const components = componentSet(spec);
    var result: usize = 0;
    inline for (0..components.count) |component_index| {
        const Program = components.items[component_index];
        inline for (Program.component().effect_sites, 0..) |Candidate, ordinal| {
            if (sourceSiteReachable(Program, ordinal) and
                Candidate == Site and
                handlerCount(spec.handlers, Program, ordinal) == 0 and
                morphismCount(spec.morphisms, Program, ordinal) == 0)
            {
                result += 1;
            }
        }
    }
    return result;
}

fn externalCount(
    comptime spec: anytype,
    comptime Program: type,
    comptime site_ordinal: usize,
    comptime Site: type,
) usize {
    var result: usize = 0;
    inline for (spec.external) |External| {
        if (comptime isExternalBinding(External)) {
            if (External.Consumer == Program and External.site_ordinal == site_ordinal) {
                result += 1;
            }
        } else if (External == Site and
            handlerCount(spec.handlers, Program, site_ordinal) == 0 and
            morphismCount(spec.morphisms, Program, site_ordinal) == 0 and
            uncoveredSourceCount(spec, Site) == 1)
        {
            result += 1;
        }
    }
    return result;
}

fn sourceSiteReachable(
    comptime Program: type,
    comptime site_ordinal: usize,
) bool {
    const Body = Program.component();
    const reachable = comptime boundary.componentAdmission(Program).reachability;
    inline for (Body.control_ir.blocks) |block| {
        if (comptime !reachable.contains(block.id)) continue;
        switch (block.terminator) {
            .@"suspend" => |suspension| {
                if (suspension.kind == .effect and
                    suspension.site_id.? == site_ordinal)
                {
                    return true;
                }
            },
            else => {},
        }
    }
    return false;
}

fn morphismActive(comptime components: anytype, comptime Morphism: type) bool {
    return componentsContains(components, Morphism.Consumer) and
        sourceSiteReachable(Morphism.Consumer, Morphism.site_ordinal);
}

fn componentsContains(comptime components: anytype, comptime Program: type) bool {
    inline for (0..components.count) |index| {
        if (components.items[index] == Program) return true;
    }
    return false;
}

fn activeHandlerCount(comptime components: anytype, comptime handlers: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |component_index| {
        inline for (handlers) |Handler| {
            if (components.items[component_index] == Handler.Consumer and
                sourceSiteReachable(Handler.Consumer, Handler.site_ordinal))
            {
                result += 1;
            }
        }
    }
    return result;
}

fn activeMorphismCount(comptime components: anytype, comptime morphisms: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |component_index| {
        inline for (morphisms) |Morphism| {
            if (components.items[component_index] == Morphism.Consumer and
                sourceSiteReachable(Morphism.Consumer, Morphism.site_ordinal))
            {
                result += 1;
            }
        }
    }
    return result;
}

fn assertDispositionClosure(comptime spec: anytype) !void {
    const components = componentSet(spec);
    inline for (0..components.count) |component_index| {
        const Program = components.items[component_index];
        inline for (Program.component().effect_sites, 0..) |Site, ordinal| {
            if (comptime !sourceSiteReachable(Program, ordinal)) continue;
            const count = handlerCount(spec.handlers, Program, ordinal) +
                morphismCount(spec.morphisms, Program, ordinal) +
                externalCount(spec, Program, ordinal, Site);
            try std.testing.expectEqual(@as(usize, 1), count);
        }
    }
    inline for (spec.morphisms) |Morphism| {
        if (comptime !morphismActive(components, Morphism)) continue;
        var target_count: usize = 0;
        inline for (spec.external) |External| {
            if (comptime !isExternalBinding(External)) {
                if (External == Morphism.Target) target_count += 1;
            }
        }
        try std.testing.expectEqual(@as(usize, 1), target_count);
    }
}

fn morphismTargetForProof(
    comptime morphisms: anytype,
    comptime Program: type,
    comptime site_ordinal: usize,
) type {
    inline for (morphisms) |Morphism| {
        if (Morphism.Consumer == Program and Morphism.site_ordinal == site_ordinal) {
            return Morphism.Target;
        }
    }
    unreachable;
}

fn assertResidualEntries(comptime spec: anytype, comptime System: type) !void {
    const components = componentSet(spec);
    comptime var cursor: usize = 0;
    inline for (0..components.count) |component_index| {
        const Program = components.items[component_index];
        inline for (Program.component().effect_sites, 0..) |Site, site_ordinal| {
            if (comptime !sourceSiteReachable(Program, site_ordinal)) continue;
            const morphism_count = comptime morphismCount(
                spec.morphisms,
                Program,
                site_ordinal,
            );
            const external_count = comptime externalCount(
                spec,
                Program,
                site_ordinal,
                Site,
            );
            if (comptime morphism_count == 0 and external_count == 0) continue;
            const Expected = if (morphism_count == 1)
                morphismTargetForProof(spec.morphisms, Program, site_ordinal)
            else
                Site;
            const Actual = System.residual_effects.items[cursor];
            try std.testing.expectEqual(@as(u32, @intCast(cursor)), Actual.id);
            try std.testing.expectEqual(@as(u32, @intCast(cursor)), Actual.site_id);
            try std.testing.expectEqualStrings(
                Expected.semantic_identity,
                Actual.semantic_identity,
            );
            try std.testing.expect(Actual.Payload == Expected.Payload);
            try std.testing.expect(Actual.Resume == Expected.Resume);
            cursor += 1;
        }
    }
    try std.testing.expectEqual(cursor, System.residual_effects.count);
}

fn failureSiteBlockCount(comptime Map: type, comptime terminator: boundary.ir.Terminator) usize {
    if (Map == void) return 0;
    return switch (terminator) {
        .fail => 1,
        .fail_value => @intFromBool(Map.targets.len != 0),
        else => 0,
    };
}

fn failureSiteValueCount(comptime Map: type, comptime terminator: boundary.ir.Terminator) usize {
    return failureSiteBlockCount(Map, terminator);
}

fn failureSiteConstantCount(
    comptime Map: type,
    comptime terminator: boundary.ir.Terminator,
) usize {
    if (Map == void) return 0;
    return switch (terminator) {
        .fail => 1,
        .fail_value => @intFromBool(failureTargetQuotientFor(Map).count == 1),
        else => 0,
    };
}

fn directFailureTargetForProof(
    comptime Map: type,
    comptime terminator: boundary.ir.Terminator,
) ?Map.TargetFailure {
    return switch (terminator) {
        .fail => |source_tag| blk: {
            for (Map.source_tags, Map.targets) |from, target| {
                if (from == source_tag) break :blk target;
            }
            unreachable;
        },
        .fail_value => if (failureTargetQuotientFor(Map).count == 1)
            failureTargetQuotientFor(Map).targets[0]
        else
            null,
        else => null,
    };
}

fn directFailureOwnerForProof(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block_id: boundary.ir.BlockId,
) boundary.ir.BlockId {
    const Program = components.items[component_index];
    const Body = Program.component();
    const Map = failureMapFor(components, handlers, component_index);
    const current = Body.control_ir.blocks[block_id];
    const target = directFailureTargetForProof(Map, current.terminator) orelse unreachable;
    inline for (Body.control_ir.blocks) |candidate| {
        if (candidate.id > block_id) continue;
        if (comptime !boundary.componentAdmission(Program).reachability.contains(candidate.id)) continue;
        if (candidate.function_id != current.function_id) continue;
        const candidate_target = comptime directFailureTargetForProof(Map, candidate.terminator);
        if (comptime candidate_target == null) continue;
        if (@intFromEnum(candidate_target.?) == @intFromEnum(target)) return candidate.id;
    }
    unreachable;
}

fn failureSiteCountForProof(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block: boundary.ir.Block,
    comptime kind: enum { block, value, constant },
) usize {
    const Map = failureMapFor(components, handlers, component_index);
    const base = switch (kind) {
        .block => failureSiteBlockCount(Map, block.terminator),
        .value => failureSiteValueCount(Map, block.terminator),
        .constant => failureSiteConstantCount(Map, block.terminator),
    };
    if (base == 0) return 0;
    if (Map == void) return base;
    if (directFailureTargetForProof(Map, block.terminator) != null and
        directFailureOwnerForProof(components, handlers, component_index, block.id) != block.id)
    {
        return 0;
    }
    return base;
}

fn componentFailureBlockCount(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    const Program = components.items[component_index];
    var result: usize = 0;
    inline for (Program.component().control_ir.blocks) |block| {
        if (comptime !boundary.componentAdmission(Program).reachability.contains(block.id)) continue;
        result += failureSiteCountForProof(components, handlers, component_index, block, .block);
    }
    return result;
}

fn componentFailureValueCount(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    const Program = components.items[component_index];
    var result: usize = 0;
    inline for (Program.component().control_ir.blocks) |block| {
        if (comptime !boundary.componentAdmission(Program).reachability.contains(block.id)) continue;
        result += failureSiteCountForProof(components, handlers, component_index, block, .value);
    }
    return result;
}

fn componentFailureConstantCount(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    const Program = components.items[component_index];
    var result: usize = 0;
    inline for (Program.component().control_ir.blocks) |block| {
        if (comptime !boundary.componentAdmission(Program).reachability.contains(block.id)) continue;
        result += failureSiteCountForProof(components, handlers, component_index, block, .constant);
    }
    return result;
}

fn componentDynamicFailureCountFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    const Program = components.items[component_index];
    const Map = failureMapFor(components, handlers, component_index);
    if (Map == void) return 0;
    if (failureTargetQuotientFor(Map).count <= 1) return 0;
    var result: usize = 0;
    inline for (Program.component().control_ir.blocks) |block| {
        if (comptime !boundary.componentAdmission(Program).reachability.contains(block.id)) continue;
        switch (block.terminator) {
            .fail_value => result += 1,
            else => {},
        }
    }
    return result;
}

fn failureSelectorOwnerFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) ?usize {
    if (componentDynamicFailureCountFor(
        components,
        handlers,
        component_index,
    ) == 0) return null;
    const Map = failureMapFor(components, handlers, component_index);
    inline for (0..component_index + 1) |candidate_index| {
        if (componentDynamicFailureCountFor(
            components,
            handlers,
            candidate_index,
        ) == 0) continue;
        if (failureMapsEqual(
            Map,
            failureMapFor(components, handlers, candidate_index),
        )) return candidate_index;
    }
    unreachable;
}

fn componentSharedFailureBlockCountFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    const owner = comptime failureSelectorOwnerFor(
        components,
        handlers,
        component_index,
    );
    if (comptime owner == null) return 0;
    return @intFromBool(owner.? == component_index);
}

fn componentSharedFailureValueCountFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    if (comptime componentSharedFailureBlockCountFor(
        components,
        handlers,
        component_index,
    ) == 0) return 0;
    const Map = failureMapFor(components, handlers, component_index);
    const Quotient = comptime failureTargetQuotientFor(Map);
    return 3 * Map.targets.len + Quotient.count - 1;
}

fn componentSharedFailureConstantCountFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    if (comptime componentSharedFailureBlockCountFor(
        components,
        handlers,
        component_index,
    ) == 0) return 0;
    const Map = failureMapFor(components, handlers, component_index);
    const Quotient = comptime failureTargetQuotientFor(Map);
    return Map.targets.len - 1 + Quotient.count;
}

fn totalFailureBlocksFor(comptime components: anytype, comptime handlers: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += componentFailureBlockCount(components, handlers, index);
    }
    return result;
}

fn totalFailureValuesFor(comptime components: anytype, comptime handlers: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += componentFailureValueCount(components, handlers, index);
    }
    return result;
}

fn totalFailureConstantsFor(comptime components: anytype, comptime handlers: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += componentFailureConstantCount(components, handlers, index);
    }
    return result;
}

fn failureValueBaseFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block_id: boundary.ir.BlockId,
) usize {
    var result = sourceOffsets(components, components.count).values +
        totalInstructionFailureValuesFor(components, handlers);
    inline for (0..component_index) |index| {
        result += componentFailureValueCount(components, handlers, index);
    }
    const Program = components.items[component_index];
    inline for (Program.component().control_ir.blocks) |block| {
        if (block.id == block_id) return result;
        if (comptime !boundary.componentAdmission(Program).reachability.contains(block.id)) continue;
        result += failureSiteCountForProof(components, handlers, component_index, block, .value);
    }
    unreachable;
}

fn failureConstantBaseFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block_id: boundary.ir.BlockId,
) usize {
    var result = sourceOffsets(components, components.count).constants +
        totalInstructionFailureValuesFor(components, handlers);
    inline for (0..component_index) |index| {
        result += componentFailureConstantCount(components, handlers, index);
    }
    const Program = components.items[component_index];
    inline for (Program.component().control_ir.blocks) |block| {
        if (block.id == block_id) return result;
        if (comptime !boundary.componentAdmission(Program).reachability.contains(block.id)) continue;
        result += failureSiteCountForProof(components, handlers, component_index, block, .constant);
    }
    unreachable;
}

fn failureBlockBaseFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
    comptime block_id: boundary.ir.BlockId,
) usize {
    var result = sourceOffsets(components, components.count).blocks;
    inline for (0..component_index) |index| {
        result += componentFailureBlockCount(components, handlers, index);
    }
    const Program = components.items[component_index];
    inline for (Program.component().control_ir.blocks) |block| {
        if (block.id == block_id) return result;
        if (comptime !boundary.componentAdmission(Program).reachability.contains(block.id)) continue;
        result += failureSiteCountForProof(components, handlers, component_index, block, .block);
    }
    unreachable;
}

fn sharedFailureBlockBaseFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    var result = sourceOffsets(components, components.count).blocks +
        totalFailureBlocksFor(components, handlers);
    inline for (0..component_index) |index| {
        result += componentSharedFailureBlockCountFor(components, handlers, index);
    }
    return result;
}

fn sharedFailureValueBaseFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    var result = sourceOffsets(components, components.count).values +
        totalInstructionFailureValuesFor(components, handlers) +
        totalFailureValuesFor(components, handlers);
    inline for (0..component_index) |index| {
        result += componentSharedFailureValueCountFor(components, handlers, index);
    }
    return result;
}

fn sharedFailureConstantBaseFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    var result = sourceOffsets(components, components.count).constants +
        totalInstructionFailureValuesFor(components, handlers) +
        totalFailureConstantsFor(components, handlers);
    inline for (0..component_index) |index| {
        result += componentSharedFailureConstantCountFor(components, handlers, index);
    }
    return result;
}

fn sharedFailureFunctionIdFor(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime component_index: usize,
) usize {
    var result = totalSourceFunctions(components);
    inline for (0..component_index) |index| {
        result += componentSharedFailureBlockCountFor(components, handlers, index);
    }
    return result;
}

const SourceOffsets = struct {
    values: usize,
    blocks: usize,
    functions: usize,
    constants: usize,
    effects: usize,
};

fn sourceOffsets(
    comptime components: anytype,
    comptime component_index: usize,
) SourceOffsets {
    var result: SourceOffsets = .{
        .values = 0,
        .blocks = 0,
        .functions = 0,
        .constants = 0,
        .effects = 0,
    };
    inline for (0..component_index) |index| {
        const Body = components.items[index].component();
        result.values += Body.control_ir.value_types.len;
        result.blocks += Body.control_ir.blocks.len;
        result.functions += componentFunctionCount(Body);
        result.constants += componentConstantCount(Body);
        result.effects += Body.effect_sites.len;
    }
    return result;
}

fn linkedSchemaIndex(comptime Linked: type, comptime Schema: type) usize {
    inline for (Linked.schema_types, 0..) |Candidate, index| {
        if (Candidate == Schema) return index;
    }
    unreachable;
}

fn expectedValueType(
    comptime Body: type,
    comptime Linked: type,
    comptime source: boundary.ir.ValueType,
) boundary.ir.ValueType {
    return switch (source) {
        .scalar => source,
        .schema => |index| .{ .schema = @intCast(linkedSchemaIndex(
            Linked,
            Body.schema_types[index],
        )) },
    };
}

fn assertInstructionMapping(
    comptime source: boundary.ir.Instruction,
    comptime linked: boundary.ir.Instruction,
    comptime copied_operand_count: usize,
    value_offset: usize,
    constant_offset: usize,
) !void {
    try std.testing.expectEqual(source.kind, linked.kind);
    try std.testing.expectEqual(
        @as(boundary.ir.ValueId, @intCast(value_offset + source.result)),
        linked.result,
    );
    try std.testing.expect(copied_operand_count <= linked.operands.len);
    inline for (
        source.operands[0..copied_operand_count],
        linked.operands[0..copied_operand_count],
    ) |source_operand, linked_operand| {
        try std.testing.expectEqual(
            @as(boundary.ir.ValueId, @intCast(value_offset + source_operand)),
            linked_operand,
        );
    }
    switch (source.operation) {
        .constant => |index| switch (linked.operation) {
            .constant => |linked_index| try std.testing.expectEqual(
                @as(u32, @intCast(constant_offset + index)),
                linked_index,
            ),
            else => return error.TestUnexpectedResult,
        },
        else => try std.testing.expect(std.meta.eql(source.operation, linked.operation)),
    }
}

fn assertEdgeMapping(
    comptime source: boundary.ir.Edge,
    comptime linked: boundary.ir.Edge,
    block_offset: usize,
    value_offset: usize,
) !void {
    try std.testing.expectEqual(
        @as(boundary.ir.BlockId, @intCast(block_offset + source.target)),
        linked.target,
    );
    try std.testing.expectEqual(source.arguments.len, linked.arguments.len);
    inline for (source.arguments, linked.arguments) |source_arg, linked_arg| {
        switch (source_arg) {
            .value => |value| switch (linked_arg) {
                .value => |linked_value| try std.testing.expectEqual(
                    @as(boundary.ir.ValueId, @intCast(value_offset + value)),
                    linked_value,
                ),
                else => return error.TestUnexpectedResult,
            },
            .@"resume" => switch (linked_arg) {
                .@"resume" => {},
                else => return error.TestUnexpectedResult,
            },
        }
    }
}

fn assertTerminatorMapping(
    comptime source: boundary.ir.Block,
    comptime linked: boundary.ir.Block,
    comptime components: anytype,
    comptime handlers: anytype,
    comptime Body: type,
    comptime LinkedBody: type,
    comptime Map: type,
    comptime reachable: bool,
    comptime component_index: usize,
    comptime offsets: SourceOffsets,
) !void {
    const value_offset = offsets.values;
    const block_offset = offsets.blocks;
    switch (source.terminator) {
        .jump => |edge| try assertEdgeMapping(
            edge,
            linked.terminator.jump,
            block_offset,
            value_offset,
        ),
        .branch => |branch| {
            const linked_branch = linked.terminator.branch;
            try std.testing.expectEqual(
                @as(boundary.ir.ValueId, @intCast(value_offset + branch.condition)),
                linked_branch.condition,
            );
            try assertEdgeMapping(
                branch.then_edge,
                linked_branch.then_edge,
                block_offset,
                value_offset,
            );
            try assertEdgeMapping(
                branch.else_edge,
                linked_branch.else_edge,
                block_offset,
                value_offset,
            );
        },
        .@"suspend" => |suspension| {
            const linked_suspension = linked.terminator.@"suspend";
            try std.testing.expectEqual(suspension.kind, linked_suspension.kind);
            try std.testing.expectEqual(
                if (suspension.site_id) |site_id|
                    @as(u32, @intCast(offsets.effects + site_id))
                else
                    null,
                linked_suspension.site_id,
            );
            try std.testing.expectEqual(
                if (suspension.callee_function) |function_id|
                    @as(boundary.ir.FunctionId, @intCast(
                        offsets.functions + function_id,
                    ))
                else
                    null,
                linked_suspension.callee_function,
            );
            try std.testing.expectEqual(
                suspension.request_values.len,
                linked_suspension.request_values.len,
            );
            inline for (
                suspension.request_values,
                linked_suspension.request_values,
            ) |value, linked_value| {
                try std.testing.expectEqual(
                    @as(boundary.ir.ValueId, @intCast(value_offset + value)),
                    linked_value,
                );
            }
            if (suspension.callee) |callee| {
                try assertEdgeMapping(
                    callee,
                    linked_suspension.callee.?,
                    block_offset,
                    value_offset,
                );
            } else {
                try std.testing.expect(linked_suspension.callee == null);
            }
            try assertEdgeMapping(
                suspension.continuation,
                linked_suspension.continuation,
                block_offset,
                value_offset,
            );
            if (suspension.resume_type) |resume_type| {
                try std.testing.expect(expectedValueType(
                    Body,
                    LinkedBody,
                    resume_type,
                ).eql(linked_suspension.resume_type.?));
            } else {
                try std.testing.expect(linked_suspension.resume_type == null);
            }
        },
        .return_value => |value| {
            if (component_index != 0 and source.function_id == 0) {
                if (value) |value_id| {
                    try std.testing.expectEqual(
                        @as(boundary.ir.ValueId, @intCast(
                            value_offset + value_id,
                        )),
                        linked.terminator.return_to_caller,
                    );
                } else {
                    try std.testing.expect(linked.terminator == .jump);
                    if (!reachable) {
                        try std.testing.expectEqual(
                            linked.id,
                            linked.terminator.jump.target,
                        );
                    }
                }
            } else switch (linked.terminator) {
                .return_value => |linked_value| try std.testing.expectEqual(
                    if (value) |value_id|
                        @as(boundary.ir.ValueId, @intCast(value_offset + value_id))
                    else
                        null,
                    linked_value,
                ),
                else => return error.TestUnexpectedResult,
            }
        },
        .return_to_caller => |value| try std.testing.expectEqual(
            @as(boundary.ir.ValueId, @intCast(value_offset + value)),
            linked.terminator.return_to_caller,
        ),
        .fail, .fail_value => if (Map == void) switch (source.terminator) {
            .fail => |failure| try std.testing.expectEqual(
                failure,
                linked.terminator.fail,
            ),
            .fail_value => |value| try std.testing.expectEqual(
                @as(boundary.ir.ValueId, @intCast(value_offset + value)),
                linked.terminator.fail_value,
            ),
            else => unreachable,
        } else if (!reachable or Map.targets.len == 0) {
            try std.testing.expect(linked.terminator == .jump);
            try std.testing.expectEqual(
                linked.id,
                linked.terminator.jump.target,
            );
        } else switch (source.terminator) {
            .fail => try std.testing.expect(linked.terminator == .jump),
            .fail_value => |value| if (comptime failureTargetQuotientFor(Map).count == 1) {
                try std.testing.expect(linked.terminator == .jump);
            } else {
                const selector_owner = comptime failureSelectorOwnerFor(
                    components,
                    handlers,
                    component_index,
                ).?;
                const suspension = linked.terminator.@"suspend";
                try std.testing.expectEqual(boundary.ir.SuspensionKind.call, suspension.kind);
                try std.testing.expectEqual(
                    @as(boundary.ir.FunctionId, @intCast(sharedFailureFunctionIdFor(
                        components,
                        handlers,
                        selector_owner,
                    ))),
                    suspension.callee_function.?,
                );
                try std.testing.expectEqual(
                    @as(boundary.ir.BlockId, @intCast(sharedFailureBlockBaseFor(
                        components,
                        handlers,
                        selector_owner,
                    ))),
                    suspension.callee.?.target,
                );
                try std.testing.expectEqual(@as(usize, 1), suspension.callee.?.arguments.len);
                switch (suspension.callee.?.arguments[0]) {
                    .value => |linked_value| try std.testing.expectEqual(
                        @as(boundary.ir.ValueId, @intCast(value_offset + value)),
                        linked_value,
                    ),
                    else => return error.TestUnexpectedResult,
                }
                try std.testing.expectEqual(
                    @as(boundary.ir.BlockId, @intCast(failureBlockBaseFor(
                        components,
                        handlers,
                        component_index,
                        source.id,
                    ))),
                    suspension.continuation.target,
                );
                try std.testing.expectEqual(@as(usize, 1), suspension.continuation.arguments.len);
                switch (suspension.continuation.arguments[0]) {
                    .@"resume" => {},
                    else => return error.TestUnexpectedResult,
                }
                const expected_resume: boundary.ir.ValueType = .{ .schema = @intCast(
                    linkedSchemaIndex(LinkedBody, Map.TargetFailure),
                ) };
                try std.testing.expect(expected_resume.eql(suspension.resume_type.?));
            },
            else => unreachable,
        },
    }
}

fn totalSourceFunctions(comptime components: anytype) usize {
    var result: usize = 0;
    inline for (0..components.count) |index| {
        result += componentFunctionCount(components.items[index].component());
    }
    return result;
}

fn voidWrapperFunctionId(
    comptime components: anytype,
    comptime handlers: anytype,
    comptime provider_index: usize,
) usize {
    var result = totalSourceFunctions(components);
    inline for (0..components.count) |index| {
        result += componentSharedFailureBlockCountFor(components, handlers, index);
    }
    inline for (1..provider_index) |index| {
        const Body = components.items[index].component();
        if (Body.InitialArgs == void and
            Body.control_ir.blocks[Body.control_ir.entry].parameters.len == 0)
        {
            result += 1;
        }
    }
    return result;
}

fn assertSharedFailureMappings(comptime spec: anytype, comptime System: type) !void {
    const components = componentSet(spec);
    const Linked = System.Program.component();
    inline for (0..components.count) |component_index| {
        if (comptime componentSharedFailureBlockCountFor(
            components,
            spec.handlers,
            component_index,
        ) == 0) continue;
        const Program = components.items[component_index];
        const Map = failureMapFor(components, spec.handlers, component_index);
        const Quotient = comptime failureTargetQuotientFor(Map);
        const function_id = comptime sharedFailureFunctionIdFor(
            components,
            spec.handlers,
            component_index,
        );
        const block_base = comptime sharedFailureBlockBaseFor(
            components,
            spec.handlers,
            component_index,
        );
        const value_base = comptime sharedFailureValueBaseFor(
            components,
            spec.handlers,
            component_index,
        );
        const constant_base = comptime sharedFailureConstantBaseFor(
            components,
            spec.handlers,
            component_index,
        );
        const function = Linked.control_ir.functions[function_id];
        try std.testing.expectEqual(
            @as(boundary.ir.FunctionId, @intCast(function_id)),
            function.id,
        );
        try std.testing.expectEqual(
            @as(boundary.ir.BlockId, @intCast(block_base)),
            function.entry,
        );
        const target_type: boundary.ir.ValueType = .{ .schema = @intCast(
            linkedSchemaIndex(Linked, Map.TargetFailure),
        ) };
        try std.testing.expect(target_type.eql(function.result_type));
        const source_type: boundary.ir.ValueType = .{ .schema = @intCast(
            linkedSchemaIndex(Linked, Map.SourceFailure),
        ) };
        try std.testing.expect(source_type.eql(Linked.control_ir.value_types[value_base]));
        try std.testing.expect((boundary.ir.ValueType{ .scalar = .u32 }).eql(
            Linked.control_ir.value_types[value_base + 1],
        ));
        const block = Linked.control_ir.blocks[block_base];
        try std.testing.expectEqual(boundary.ir.BlockRole.terminal_handoff, block.role);
        try std.testing.expectEqual(@as(boundary.ir.BlockId, @intCast(block_base)), block.id);
        try std.testing.expectEqual(
            @as(boundary.ir.FunctionId, @intCast(function_id)),
            block.function_id,
        );
        try std.testing.expectEqual(@as(usize, 1), block.parameters.len);
        try std.testing.expectEqual(
            @as(boundary.ir.ValueId, @intCast(value_base)),
            block.parameters[0],
        );
        try std.testing.expectEqual(
            3 * Map.targets.len + Quotient.count - 2,
            block.instructions.len,
        );
        try std.testing.expect(block.instructions[0].operation == .enum_to_u32);
        try std.testing.expectEqual(
            @as(boundary.ir.ValueId, @intCast(value_base + 1)),
            block.instructions[0].result,
        );
        inline for (0..Quotient.count) |index| {
            switch (block.instructions[1 + index].operation) {
                .constant => |constant_index| try std.testing.expectEqual(
                    @as(u16, @intCast(constant_base + Map.targets.len - 1 + index)),
                    constant_index,
                ),
                else => return error.TestUnexpectedResult,
            }
            try std.testing.expectEqual(Quotient.targets[index], @field(
                Linked.constants,
                std.fmt.comptimePrint("{d}", .{constant_base + Map.targets.len - 1 + index}),
            ));
            try std.testing.expect(target_type.eql(
                Linked.control_ir.value_types[value_base + 2 + index],
            ));
        }
        inline for (0..Map.targets.len - 1) |tag| {
            const cursor = 1 + Quotient.count + 3 * tag;
            const source_value = value_base + 2 + Quotient.count + 3 * tag;
            const condition_value = source_value + 1;
            const selected_value = source_value + 2;
            switch (block.instructions[cursor].operation) {
                .constant => |index| try std.testing.expectEqual(
                    @as(u16, @intCast(constant_base + tag)),
                    index,
                ),
                else => return error.TestUnexpectedResult,
            }
            try std.testing.expect(block.instructions[cursor + 1].operation == .integer_equal);
            try std.testing.expectEqual(
                @as(boundary.ir.ValueId, @intCast(condition_value)),
                block.instructions[cursor + 1].result,
            );
            try std.testing.expectEqual(
                @as(boundary.ir.ValueId, @intCast(value_base + 1)),
                block.instructions[cursor + 1].operands[0],
            );
            try std.testing.expectEqual(
                @as(boundary.ir.ValueId, @intCast(source_value)),
                block.instructions[cursor + 1].operands[1],
            );
            try std.testing.expect(block.instructions[cursor + 2].operation == .select);
            try std.testing.expectEqual(
                @as(boundary.ir.ValueId, @intCast(condition_value)),
                block.instructions[cursor + 2].operands[0],
            );
            try std.testing.expectEqual(
                @as(boundary.ir.ValueId, @intCast(
                    value_base + 2 + Quotient.source_to_target[tag],
                )),
                block.instructions[cursor + 2].operands[1],
            );
            try std.testing.expectEqual(
                @as(boundary.ir.ValueId, @intCast(if (tag == 0)
                    value_base + 2 + Quotient.source_to_target[Map.targets.len - 1]
                else
                    value_base + 1 + Quotient.count + 3 * tag)),
                block.instructions[cursor + 2].operands[2],
            );
            try std.testing.expectEqual(Map.source_tags[tag], @field(
                Linked.constants,
                std.fmt.comptimePrint("{d}", .{constant_base + tag}),
            ));
            try std.testing.expect((boundary.ir.ValueType{ .scalar = .u32 }).eql(
                Linked.control_ir.value_types[source_value],
            ));
            try std.testing.expect((boundary.ir.ValueType{ .scalar = .boolean }).eql(
                Linked.control_ir.value_types[condition_value],
            ));
            try std.testing.expect(target_type.eql(
                Linked.control_ir.value_types[selected_value],
            ));
        }
        try std.testing.expectEqual(
            @as(boundary.ir.ValueId, @intCast(
                value_base + 3 * Map.targets.len + Quotient.count - 2,
            )),
            block.terminator.return_to_caller,
        );

        inline for (Program.component().control_ir.blocks) |source| {
            if (comptime !boundary.componentAdmission(Program).reachability.contains(source.id)) {
                continue;
            }
            switch (source.terminator) {
                .fail_value => if (failureTargetQuotientFor(Map).count > 1) {
                    const block_id = comptime failureBlockBaseFor(
                        components,
                        spec.handlers,
                        component_index,
                        source.id,
                    );
                    const value_id = comptime failureValueBaseFor(
                        components,
                        spec.handlers,
                        component_index,
                        source.id,
                    );
                    const continuation = Linked.control_ir.blocks[block_id];
                    try std.testing.expectEqual(
                        boundary.ir.BlockRole.terminal_handoff,
                        continuation.role,
                    );
                    try std.testing.expectEqual(@as(usize, 1), continuation.parameters.len);
                    try std.testing.expectEqual(
                        @as(boundary.ir.ValueId, @intCast(value_id)),
                        continuation.parameters[0],
                    );
                    try std.testing.expectEqual(
                        @as(boundary.ir.ValueId, @intCast(value_id)),
                        continuation.terminator.fail_value,
                    );
                    try std.testing.expect(target_type.eql(
                        Linked.control_ir.value_types[value_id],
                    ));
                },
                else => {},
            }
        }
    }
}

fn assertDirectFailureMappings(comptime spec: anytype, comptime System: type) !void {
    const components = componentSet(spec);
    const Linked = System.Program.component();
    inline for (0..components.count) |component_index| {
        if (comptime failureMapFor(components, spec.handlers, component_index) == void) {
            continue;
        }
        const Program = components.items[component_index];
        const Map = failureMapFor(components, spec.handlers, component_index);
        const offsets = comptime sourceOffsets(components, component_index);
        const target_type: boundary.ir.ValueType = .{ .schema = @intCast(
            linkedSchemaIndex(Linked, Map.TargetFailure),
        ) };
        inline for (Program.component().control_ir.blocks) |source| {
            if (comptime !boundary.componentAdmission(Program).reachability.contains(source.id)) {
                continue;
            }
            const expected_target: ?Map.TargetFailure = comptime switch (source.terminator) {
                .fail => |source_tag| blk: {
                    for (Map.source_tags, Map.targets) |from, target| {
                        if (from == source_tag) break :blk target;
                    }
                    unreachable;
                },
                .fail_value => if (failureTargetQuotientFor(Map).count == 1) Map.targets[0] else null,
                else => null,
            };
            if (expected_target == null) continue;
            const owner_id = comptime directFailureOwnerForProof(
                components,
                spec.handlers,
                component_index,
                source.id,
            );
            const block_id = comptime failureBlockBaseFor(
                components,
                spec.handlers,
                component_index,
                owner_id,
            );
            const value_id = comptime failureValueBaseFor(
                components,
                spec.handlers,
                component_index,
                owner_id,
            );
            const constant_id = comptime failureConstantBaseFor(
                components,
                spec.handlers,
                component_index,
                owner_id,
            );
            const linked_source = Linked.control_ir.blocks[offsets.blocks + source.id];
            try std.testing.expectEqual(
                @as(boundary.ir.BlockId, @intCast(block_id)),
                linked_source.terminator.jump.target,
            );
            const adapter = Linked.control_ir.blocks[block_id];
            try std.testing.expectEqual(
                boundary.ir.BlockRole.terminal_handoff,
                adapter.role,
            );
            try std.testing.expectEqual(@as(boundary.ir.BlockId, @intCast(block_id)), adapter.id);
            try std.testing.expectEqual(
                @as(boundary.ir.FunctionId, @intCast(offsets.functions + source.function_id)),
                adapter.function_id,
            );
            try std.testing.expectEqual(@as(usize, 1), adapter.instructions.len);
            try std.testing.expectEqual(
                @as(boundary.ir.ValueId, @intCast(value_id)),
                adapter.instructions[0].result,
            );
            switch (adapter.instructions[0].operation) {
                .constant => |index| try std.testing.expectEqual(
                    @as(u16, @intCast(constant_id)),
                    index,
                ),
                else => return error.TestUnexpectedResult,
            }
            try std.testing.expectEqual(expected_target.?, @field(
                Linked.constants,
                std.fmt.comptimePrint("{d}", .{constant_id}),
            ));
            try std.testing.expect(target_type.eql(Linked.control_ir.value_types[value_id]));
            try std.testing.expectEqual(
                @as(boundary.ir.ValueId, @intCast(value_id)),
                adapter.terminator.fail_value,
            );
        }
    }
}

fn assertElementMappings(comptime spec: anytype, comptime System: type) !void {
    const components = componentSet(spec);
    const Linked = System.Program.component();
    inline for (0..components.count) |component_index| {
        const Program = components.items[component_index];
        const Body = components.items[component_index].component();
        const offsets = comptime sourceOffsets(components, component_index);
        inline for (Body.control_ir.value_types, 0..) |source, index| {
            const expected = expectedValueType(Body, Linked, source);
            try std.testing.expect(expected.eql(
                Linked.control_ir.value_types[offsets.values + index],
            ));
        }
        if (@hasDecl(Body, "constants")) {
            inline for (Body.constants, 0..) |source, index| {
                const linked = @field(
                    Linked.constants,
                    std.fmt.comptimePrint("{d}", .{offsets.constants + index}),
                );
                try std.testing.expect(std.meta.eql(source, linked));
            }
        }
        inline for (Body.effect_sites, 0..) |Site, index| {
            const linked = Linked.effect_sites[offsets.effects + index];
            try std.testing.expectEqual(
                @as(u32, @intCast(offsets.effects + index)),
                linked.id,
            );
            try std.testing.expectEqualStrings(
                Site.semantic_identity,
                linked.semantic_identity,
            );
            try std.testing.expect(linked.Payload == Site.Payload);
            try std.testing.expect(linked.Resume == Site.Resume);
        }
        if (Body.control_ir.functions.len == 0) {
            const function = Linked.control_ir.functions[offsets.functions];
            try std.testing.expectEqual(
                @as(boundary.ir.FunctionId, @intCast(offsets.functions)),
                function.id,
            );
            try std.testing.expectEqual(
                @as(boundary.ir.BlockId, @intCast(
                    offsets.blocks + Body.control_ir.entry,
                )),
                function.entry,
            );
        } else {
            inline for (Body.control_ir.functions) |source| {
                const linked = Linked.control_ir.functions[offsets.functions + source.id];
                try std.testing.expectEqual(
                    @as(boundary.ir.FunctionId, @intCast(offsets.functions + source.id)),
                    linked.id,
                );
                try std.testing.expectEqual(
                    @as(boundary.ir.BlockId, @intCast(offsets.blocks + source.entry)),
                    linked.entry,
                );
                try std.testing.expect(expectedValueType(
                    Body,
                    Linked,
                    source.result_type,
                ).eql(linked.result_type));
            }
        }
        inline for (Body.control_ir.blocks) |source| {
            const linked_id = offsets.blocks + source.id;
            const linked = Linked.control_ir.blocks[linked_id];
            const Map = comptime failureMapFor(
                components,
                spec.handlers,
                component_index,
            );
            const targets = comptime instructionFailureTargetsForBlock(
                components,
                spec.handlers,
                component_index,
                source,
            );
            try std.testing.expectEqual(
                @as(boundary.ir.BlockId, @intCast(linked_id)),
                linked.id,
            );
            try std.testing.expectEqual(
                @as(boundary.ir.FunctionId, @intCast(
                    offsets.functions + source.function_id,
                )),
                linked.function_id,
            );
            try std.testing.expectEqual(source.role, linked.role);
            try std.testing.expectEqual(
                source.instructions.len + targets.count,
                linked.instructions.len,
            );
            try std.testing.expectEqual(source.parameters.len, linked.parameters.len);
            inline for (source.parameters, linked.parameters) |parameter, linked_parameter| {
                try std.testing.expectEqual(
                    @as(boundary.ir.ValueId, @intCast(offsets.values + parameter)),
                    linked_parameter,
                );
            }
            inline for (0..targets.count) |index| {
                const instruction = linked.instructions[index];
                try std.testing.expectEqual(
                    boundary.ir.InstructionKind.constant,
                    instruction.kind,
                );
                try std.testing.expectEqual(
                    @as(boundary.ir.ValueId, @intCast(
                        instructionFailureValueBaseFor(
                            components,
                            spec.handlers,
                            component_index,
                            source.id,
                        ) + index,
                    )),
                    instruction.result,
                );
                const constant_id = comptime instructionFailureConstantBaseFor(
                    components,
                    spec.handlers,
                    component_index,
                    source.id,
                ) + index;
                try std.testing.expectEqual(
                    @as(u16, @intCast(constant_id)),
                    instruction.operation.constant,
                );
                try std.testing.expectEqual(
                    targets.items[index],
                    @field(
                        Linked.constants,
                        std.fmt.comptimePrint("{d}", .{constant_id}),
                    ),
                );
            }
            inline for (
                source.instructions,
                linked.instructions[targets.count..],
            ) |instruction, linked_instruction| {
                const projection = comptime Program.componentAdmission()
                    .instructionFailureProjection(instruction);
                const copied_operand_count = if (Map == void)
                    instruction.operands.len
                else
                    projection.ordinary_operand_count;
                try assertInstructionMapping(
                    instruction,
                    linked_instruction,
                    copied_operand_count,
                    offsets.values,
                    offsets.constants,
                );
                const source_tags = projection.failure_tags;
                const mapped_count = if (Map == void) 0 else source_tags.len;
                try std.testing.expectEqual(
                    copied_operand_count + mapped_count,
                    linked_instruction.operands.len,
                );
                if (Map != void) {
                    inline for (source_tags, 0..) |source_tag, index| {
                        const target = comptime mappedTargetForProof(
                            Map,
                            source_tag,
                        );
                        try std.testing.expectEqual(
                            @as(boundary.ir.ValueId, @intCast(
                                instructionFailureValueBaseFor(
                                    components,
                                    spec.handlers,
                                    component_index,
                                    source.id,
                                ) + comptime targets.indexOf(target),
                            )),
                            linked_instruction.operands[
                                copied_operand_count + index
                            ],
                        );
                    }
                }
            }
            const reachable = comptime Program.componentAdmission()
                .reachability.contains(source.id);
            try assertTerminatorMapping(
                source,
                linked,
                components,
                spec.handlers,
                Body,
                Linked,
                Map,
                reachable,
                component_index,
                offsets,
            );
        }
    }
    comptime var handler_cursor: usize = 0;
    inline for (0..components.count) |consumer| {
        inline for (spec.handlers) |Handler| {
            if (comptime components.items[consumer] != Handler.Consumer or
                !sourceSiteReachable(Handler.Consumer, Handler.site_ordinal)) continue;
            const source_id = comptime sourceOffsets(components, consumer).effects +
                Handler.site_ordinal;
            const linked = Linked.effect_handlers[handler_cursor];
            try std.testing.expectEqual(@as(u32, @intCast(source_id)), linked.source_id);
            const provider = comptime components.indexOf(
                Handler.Provider,
                handlerFailureMap(
                    Handler,
                    components.items[0].component().Failure,
                ),
            );
            const ProviderBody = Handler.Provider.component();
            const expected_function = if (ProviderBody.InitialArgs == void and
                ProviderBody.control_ir.blocks[
                    ProviderBody.control_ir.entry
                ].parameters.len == 0)
                voidWrapperFunctionId(components, spec.handlers, provider)
            else
                sourceOffsets(components, provider).functions;
            try std.testing.expectEqual(
                @as(boundary.ir.FunctionId, @intCast(expected_function)),
                linked.function_id,
            );
            handler_cursor += 1;
        }
    }
    comptime var morphism_cursor: usize = 0;
    inline for (0..components.count) |consumer| {
        inline for (spec.morphisms) |Morphism| {
            if (comptime components.items[consumer] != Morphism.Consumer or
                !sourceSiteReachable(Morphism.Consumer, Morphism.site_ordinal)) continue;
            const source_id = comptime sourceOffsets(components, consumer).effects +
                Morphism.site_ordinal;
            const linked = Linked.effect_morphisms[morphism_cursor];
            try std.testing.expectEqual(@as(u32, @intCast(source_id)), linked.source_id);
            try std.testing.expect(linked.Target == Morphism.Target);
            morphism_cursor += 1;
        }
    }
}

fn assertTopology(comptime spec: anytype, comptime System: type) !void {
    const source = comptime deriveSourceFacts(spec);
    const Linked = System.Program.component();
    try std.testing.expectEqual(
        System.residual_effects.count,
        System.residual_effects.items.len,
    );
    try std.testing.expectEqual(
        System.residual_effects.count,
        boundary.componentAdmission(System.Program).residual_effects.residual_count,
    );
    try std.testing.expectEqual(source.component_count, System.component_count);
    try std.testing.expectEqual(
        source.source_values + source.instruction_failure_values +
            source.failure_values + source.void_returns +
            2 * source.void_wrappers,
        Linked.control_ir.value_types.len,
    );
    try std.testing.expectEqual(
        source.source_blocks + source.failure_blocks + source.void_returns +
            2 * source.void_wrappers,
        Linked.control_ir.blocks.len,
    );
    try std.testing.expectEqual(
        source.source_functions + source.failure_functions + source.void_wrappers,
        Linked.control_ir.functions.len,
    );
    try std.testing.expectEqual(
        source.source_constants + source.instruction_failure_values +
            source.failure_constants + source.void_returns,
        Linked.constants.len,
    );
    try std.testing.expectEqual(source.source_effects, Linked.effect_sites.len);
    const components = comptime componentSet(spec);
    try std.testing.expectEqual(
        activeHandlerCount(components, spec.handlers),
        Linked.effect_handlers.len,
    );
    try std.testing.expectEqual(
        activeMorphismCount(components, spec.morphisms),
        Linked.effect_morphisms.len,
    );
    try assertDispositionClosure(spec);
    try assertResidualEntries(spec, System);
    try assertElementMappings(spec, System);
    try assertDirectFailureMappings(spec, System);
    try assertSharedFailureMappings(spec, System);
}

test "source-derived topology closes void wrapper and unreachable syntax" {
    try assertTopology(fixtures.VoidDeadSpec, fixtures.VoidDeadSystem);
}

test "source-derived topology remaps provider effect sites" {
    try assertTopology(fixtures.GenericSpec, fixtures.System);
}

test "source-derived topology maps provider instruction failures" {
    try assertTopology(
        fixtures.MappedInstructionSpec,
        fixtures.MappedInstructionSystem,
    );
    try assertTopology(
        fixtures.AuthoredInstructionSpec,
        fixtures.AuthoredInstructionSystem,
    );
}

test "source-derived topology separates external source and target roles" {
    try assertTopology(fixtures.ExternalRoleSpec, fixtures.ExternalRoleSystem);
}

test "source-derived topology closes empty Failure domains" {
    try assertTopology(fixtures.EmptyFailureSpec, fixtures.EmptyFailureSystem);
}

test "source-derived topology shares wide Failure maps across fail sites" {
    try assertTopology(fixtures.WideFailureSpec, fixtures.WideFailureSystem);
}

test "source-derived topology shares selectors by mapping identity across providers" {
    try assertTopology(fixtures.SharedMapSpec, fixtures.SharedMapSystem);
}

test "source-derived topology preserves distinct maps for repeated providers" {
    try assertTopology(
        fixtures.RepeatedProviderMapSpec,
        fixtures.RepeatedProviderMapSystem,
    );
}

test "source-derived topology quotients repeated Failure targets" {
    try assertTopology(
        fixtures.ConstantWideFailureSpec,
        fixtures.ConstantWideFailureSystem,
    );
    try assertTopology(
        fixtures.AlternatingWideFailureSpec,
        fixtures.AlternatingWideFailureSystem,
    );
}

test "source-derived topology admits unreachable effect declarations" {
    try assertTopology(fixtures.UnusedDeclaredSpec, fixtures.UnusedDeclaredSystem);
}

test "source-derived topology excludes handlers behind unreachable sites" {
    try assertTopology(fixtures.InertHandlerSpec, fixtures.InertHandlerSystem);
}

test "source-derived topology excludes morphisms behind unreachable sites" {
    try assertTopology(fixtures.InertMorphismSpec, fixtures.InertMorphismSystem);
}

test "source-derived topology preserves unreachable helper mappings" {
    try assertTopology(fixtures.UnreachableHelperSpec, fixtures.UnreachableHelperSystem);
}

test "source-derived topology shares one void-return adapter" {
    try assertTopology(fixtures.SharedVoidExitSpec, fixtures.SharedVoidExitSystem);
}
