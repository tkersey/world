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
    failure_values: usize = 0,
    failure_blocks: usize = 0,
    failure_constants: usize = 0,
    void_returns: usize = 0,
    void_wrappers: usize = 0,
};

fn TypeSet(comptime capacity: usize) type {
    return struct {
        items: [capacity]type = undefined,
        count: usize = 0,

        fn add(self: *@This(), comptime Item: type) bool {
            inline for (0..self.count) |index| {
                if (self.items[index] == Item) return false;
            }
            self.items[self.count] = Item;
            self.count += 1;
            return true;
        }
    };
}

fn componentSet(comptime spec: anytype) TypeSet(1 + spec.handlers.len) {
    var result: TypeSet(1 + spec.handlers.len) = .{};
    _ = result.add(spec.root);
    collectProviders(&result, spec.root, spec.handlers);
    return result;
}

fn collectProviders(
    result: anytype,
    comptime Current: type,
    comptime handlers: anytype,
) void {
    inline for (Current.component().effect_sites, 0..) |_, site_ordinal| {
        if (!sourceSiteReachable(Current, site_ordinal)) continue;
        inline for (handlers) |Handler| {
            if (Handler.Consumer != Current or Handler.site_ordinal != site_ordinal) {
                continue;
            }
            if (result.add(Handler.Provider)) {
                collectProviders(result, Handler.Provider, handlers);
            }
        }
    }
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
    if (component_index == 0) return void;
    const Program = components.items[component_index];
    const SourceFailure = Program.component().Failure;
    const SystemFailure = components.items[0].component().Failure;
    if (SourceFailure == SystemFailure) return void;
    inline for (handlers) |Handler| {
        if (Handler.Provider == Program and
            handlerActive(components, Handler)) return Handler.FailureMorphism;
    }
    unreachable;
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
        .fail_value => if (Map.targets.len == 0) {} else if (Map.targets.len == 1) {
            facts.failure_values += 1;
            facts.failure_blocks += 1;
            facts.failure_constants += 1;
        } else {
            facts.failure_values += 1 + 2 * (Map.targets.len - 1) + Map.targets.len;
            facts.failure_blocks += 2 * Map.targets.len - 1;
            facts.failure_constants += 2 * Map.targets.len - 1;
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
        inline for (Body.control_ir.blocks) |block| {
            if (!reachable.contains(block.id)) {
                facts.unreachable_blocks += 1;
                continue;
            }
            addFailureFacts(&facts, Map, block.terminator);
            if (component_index != 0 and Body.Result == void and
                block.function_id == 0)
            {
                switch (block.terminator) {
                    .return_value => |value| if (value == null) {
                        facts.void_returns += 1;
                    },
                    else => {},
                }
            }
        }
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
    return @hasDecl(External, "binding_kind") and
        @hasDecl(External, "Consumer") and
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

fn handlerActive(comptime components: anytype, comptime Handler: type) bool {
    return componentsContains(components, Handler.Consumer) and
        sourceSiteReachable(Handler.Consumer, Handler.site_ordinal);
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
    inline for (handlers) |Handler| {
        if (handlerActive(components, Handler)) result += 1;
    }
    return result;
}

fn activeMorphismCount(comptime components: anytype, comptime morphisms: anytype) usize {
    var result: usize = 0;
    inline for (morphisms) |Morphism| {
        if (morphismActive(components, Morphism)) result += 1;
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

fn componentIndex(comptime components: anytype, comptime Program: type) usize {
    inline for (0..components.count) |index| {
        if (components.items[index] == Program) return index;
    }
    unreachable;
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
    value_offset: usize,
    constant_offset: usize,
) !void {
    try std.testing.expectEqual(source.kind, linked.kind);
    try std.testing.expectEqual(
        @as(boundary.ir.ValueId, @intCast(value_offset + source.result)),
        linked.result,
    );
    try std.testing.expectEqual(source.operands.len, linked.operands.len);
    inline for (source.operands, linked.operands) |source_operand, linked_operand| {
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
        } else {
            try std.testing.expect(linked.terminator == .jump);
            if (!reachable or Map.targets.len == 0) {
                try std.testing.expectEqual(
                    linked.id,
                    linked.terminator.jump.target,
                );
            }
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
    comptime provider_index: usize,
) usize {
    var result = totalSourceFunctions(components);
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
            try std.testing.expect(Linked.effect_sites[offsets.effects + index] == Site);
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
            try std.testing.expectEqual(source.instructions.len, linked.instructions.len);
            try std.testing.expectEqual(source.parameters.len, linked.parameters.len);
            inline for (source.parameters, linked.parameters) |parameter, linked_parameter| {
                try std.testing.expectEqual(
                    @as(boundary.ir.ValueId, @intCast(offsets.values + parameter)),
                    linked_parameter,
                );
            }
            inline for (
                source.instructions,
                linked.instructions,
            ) |instruction, linked_instruction| {
                try assertInstructionMapping(
                    instruction,
                    linked_instruction,
                    offsets.values,
                    offsets.constants,
                );
            }
            const Map = failureMapFor(components, spec.handlers, component_index);
            const reachable = comptime Program.componentAdmission()
                .reachability.contains(source.id);
            try assertTerminatorMapping(
                source,
                linked,
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
    inline for (spec.handlers) |Handler| {
        if (comptime !handlerActive(components, Handler)) continue;
        const consumer = comptime componentIndex(components, Handler.Consumer);
        const source_id = comptime sourceOffsets(components, consumer).effects +
            Handler.site_ordinal;
        const linked = Linked.effect_handlers[handler_cursor];
        try std.testing.expectEqual(@as(u32, @intCast(source_id)), linked.source_id);
        const provider = comptime componentIndex(components, Handler.Provider);
        const ProviderBody = Handler.Provider.component();
        const expected_function = if (ProviderBody.InitialArgs == void and
            ProviderBody.control_ir.blocks[
                ProviderBody.control_ir.entry
            ].parameters.len == 0)
            voidWrapperFunctionId(components, provider)
        else
            sourceOffsets(components, provider).functions;
        try std.testing.expectEqual(
            @as(boundary.ir.FunctionId, @intCast(expected_function)),
            linked.function_id,
        );
        handler_cursor += 1;
    }
    comptime var morphism_cursor: usize = 0;
    inline for (spec.morphisms) |Morphism| {
        if (comptime !morphismActive(components, Morphism)) continue;
        const consumer = comptime componentIndex(components, Morphism.Consumer);
        const source_id = comptime sourceOffsets(components, consumer).effects +
            Morphism.site_ordinal;
        const linked = Linked.effect_morphisms[morphism_cursor];
        try std.testing.expectEqual(@as(u32, @intCast(source_id)), linked.source_id);
        try std.testing.expect(linked.Target == Morphism.Target);
        morphism_cursor += 1;
    }
}

fn assertTopology(comptime spec: anytype, comptime System: type) !void {
    const source = comptime deriveSourceFacts(spec);
    const Linked = System.Program.component();
    try std.testing.expectEqual(source.component_count, System.component_count);
    try std.testing.expectEqual(
        source.source_values + source.failure_values + source.void_returns +
            2 * source.void_wrappers,
        Linked.control_ir.value_types.len,
    );
    try std.testing.expectEqual(
        source.source_blocks + source.failure_blocks + source.void_returns +
            2 * source.void_wrappers,
        Linked.control_ir.blocks.len,
    );
    try std.testing.expectEqual(
        source.source_functions + source.void_wrappers,
        Linked.control_ir.functions.len,
    );
    try std.testing.expectEqual(
        source.source_constants + source.failure_constants + source.void_returns,
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
    try assertElementMappings(spec, System);
}

test "source-derived topology closes void wrapper and unreachable syntax" {
    try assertTopology(fixtures.VoidDeadSpec, fixtures.VoidDeadSystem);
}

test "source-derived topology separates external source and target roles" {
    try assertTopology(fixtures.ExternalRoleSpec, fixtures.ExternalRoleSystem);
}

test "source-derived topology closes empty Failure domains" {
    try assertTopology(fixtures.EmptyFailureSpec, fixtures.EmptyFailureSystem);
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
