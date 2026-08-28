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

fn componentReachability(comptime Body: type) boundary.ir.Reachability(
    Body.control_ir.blocks.len,
) {
    return boundary.ir.Reachability(Body.control_ir.blocks.len).analyze(
        Body.control_ir,
    ) catch unreachable;
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
        if (Handler.Provider == Program) return Handler.FailureMorphism;
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
        const reachable = comptime componentReachability(Body);
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
            if (Candidate == Site and
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

fn assertDispositionClosure(comptime spec: anytype) !void {
    const components = componentSet(spec);
    inline for (0..components.count) |component_index| {
        const Program = components.items[component_index];
        inline for (Program.component().effect_sites, 0..) |Site, ordinal| {
            const count = handlerCount(spec.handlers, Program, ordinal) +
                morphismCount(spec.morphisms, Program, ordinal) +
                externalCount(spec, Program, ordinal, Site);
            try std.testing.expectEqual(@as(usize, 1), count);
        }
    }
    inline for (spec.morphisms) |Morphism| {
        var target_count: usize = 0;
        inline for (spec.external) |External| {
            if (comptime !isExternalBinding(External)) {
                if (External == Morphism.Target) target_count += 1;
            }
        }
        try std.testing.expectEqual(@as(usize, 1), target_count);
    }
}

fn assertUnreachablePrivatization(comptime spec: anytype, comptime System: type) !void {
    const components = componentSet(spec);
    const Linked = System.Program.component();
    var block_offset: usize = 0;
    inline for (0..components.count) |component_index| {
        const Body = components.items[component_index].component();
        const reachable = comptime componentReachability(Body);
        inline for (Body.control_ir.blocks) |source| {
            if (comptime reachable.contains(source.id)) continue;
            const linked_id = block_offset + source.id;
            const linked = Linked.control_ir.blocks[linked_id];
            try std.testing.expectEqual(source.instructions.len, linked.instructions.len);
            try std.testing.expectEqual(source.parameters.len, linked.parameters.len);
            switch (linked.terminator) {
                .jump => |edge| try std.testing.expectEqual(
                    @as(boundary.ir.BlockId, @intCast(linked_id)),
                    edge.target,
                ),
                else => return error.TestUnexpectedResult,
            }
        }
        block_offset += Body.control_ir.blocks.len;
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
    try std.testing.expectEqual(spec.handlers.len, Linked.effect_handlers.len);
    try std.testing.expectEqual(spec.morphisms.len, Linked.effect_morphisms.len);
    try assertDispositionClosure(spec);
    try assertUnreachablePrivatization(spec, System);
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
