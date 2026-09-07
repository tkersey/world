//! Test-only compiler/runtime composition. The production World module imports data only.
const std = @import("std");
const boundary = @import("boundary");
const data = @import("boundary_data_v2");
const world = @import("world").process_v2;

fn regionInvocationExample(b: *boundary.source.Builder) !boundary.source.Module {
    const unit = try b.scalar(void);
    const effect = try b.effect(.{
        .identity = "restore/foreign-region",
        .payload = unit,
        .result = unit,
    });
    const region_id = b.region();
    const region = try b.schema(.{ .internal = .{ .region = region_id } });
    const wide_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = unit,
        .effects = &.{effect},
    } } });
    var wrappers: [2]data.program.Id = undefined;
    for (&wrappers, 0..) |*wrapper, index| {
        const row: []const data.program.Id = if (index == 0) &.{} else &.{effect};
        const body = try b.declare(&.{region}, unit, row, &.{region_id});
        const value = try b.constant(void, {});
        const term = if (index == 0) try b.pure(value) else try b.term(.{ .perform = .{
            .effect = effect,
            .payload = value,
        } });
        try b.define(body, term);
        const body_type = try b.schema(.{ .internal = .{ .computation = .{
            .parameters = &.{region},
            .result = unit,
            .effects = row,
            .regions = &.{region_id},
        } } });
        const parameters: []const data.program.Id = if (index == 0) &.{wide_type} else &.{};
        wrapper.* = try b.declare(parameters, unit, row, &.{});
        try b.define(wrapper.*, try b.term(.{ .with_region = .{
            .region = region_id,
            .body = try b.lambda(body, body_type),
        } }));
    }
    const entry = try b.declare(&.{}, unit, &.{}, &.{});
    // Passing an unused computation retains its code without performing its effects.
    try b.define(entry, try b.term(.{ .call = .{
        .function = wrappers[0],
        .arguments = &.{try b.lambda(wrappers[1], wide_type)},
    } }));
    return b.module(entry, unit);
}

const RegionInvocation = struct { scope: data.program.Id, body: data.program.Id };

fn widerRegionInvocation(program: data.program.Program) !RegionInvocation {
    for (program.blocks, 0..) |block, id| {
        if (block.terminator != .with_region) continue;
        const slot = block.terminator.with_region.body;
        const schema = if (slot < block.parameters.len)
            block.parameters[@intCast(slot)]
        else
            block.instructions[@intCast(slot - block.parameters.len)].result_type;
        if (program.schemas[@intCast(schema)].internal.computation.effects.len == 0) continue;
        for (program.constructors) |constructor| {
            if (constructor.schema == schema) return .{
                .scope = id,
                .body = program.functions[@intCast(constructor.function)].entry,
            };
        }
    }
    return error.WiderRegionNotFound;
}

fn checkRegionInvocationBindings(
    program: data.program.Program,
    image: []const u8,
    snapshot: []const u8,
    scope: usize,
    wider: RegionInvocation,
) !void {
    const allocator = std.testing.allocator;
    for (0..4) |mask| {
        var saved = try data.snapshot.decodeGraph(allocator, snapshot);
        defer saved.deinit();
        const nodes = @constCast(saved.state.nodes);
        if (mask & 1 != 0)
            nodes[@intCast(saved.state.roots.current.?.id)].control.block = wider.body;
        if (mask & 2 != 0) nodes[scope].region_scope.source_block = wider.scope;
        if (mask == 0) {
            try data.state_admission.validate(allocator, program, saved.state);
            var original = try world.run(allocator, .{
                .program = .{ .image = image },
                .instance = .{ .snapshot = snapshot },
            });
            defer original.deinit();
            try std.testing.expect(original.record == .completed);
            continue;
        }
        const expected = if (mask == 1) error.InvalidEffect else error.InvalidScope;
        try std.testing.expectError(expected, data.state_admission.validate(
            allocator,
            program,
            saved.state,
        ));
        var encoded = try data.snapshot.emit(allocator, saved.state, allocator, null);
        defer encoded.normalized.deinit();
        defer allocator.free(encoded.bytes);
        inline for (.{ world.run, world.advance }) |execute| {
            try std.testing.expectError(expected, execute(allocator, .{
                .program = .{ .records = program },
                .instance = .{ .records = saved.state },
            }));
            try std.testing.expectError(expected, execute(allocator, .{
                .program = .{ .image = image },
                .instance = .{ .snapshot = encoded.bytes },
            }));
        }
    }
}

test "restored region frames preserve their saved invocation effect contract" {
    const allocator = std.testing.allocator;
    var b = boundary.source.Builder.init(allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(allocator, try regionInvocationExample(&b));
    defer compiled.deinit();
    const program = compiled.program;
    const entry_effects = program.functions[@intCast(program.roots.entry)].effects;
    try std.testing.expectEqual(@as(usize, 0), entry_effects.len);
    const storage = try allocator.alloc(u8, try data.image.encodedLength(program));
    defer allocator.free(storage);
    const image = try data.image.encode(allocator, program, storage);
    const wider = try widerRegionInvocation(program);
    var step = try world.advance(allocator, .{
        .program = .{ .image = image },
        .instance = .{ .initial_args = &.{} },
    });
    defer step.deinit();
    for (0..32) |_| {
        if (step.record != .progressed) return error.RegionScopeNotReached;
        var saved = try data.snapshot.decodeGraph(allocator, step.record.progressed);
        defer saved.deinit();
        try data.state_admission.validate(allocator, program, saved.state);
        for (saved.state.nodes, 0..) |node, id| {
            if (node != .region_scope) continue;
            try checkRegionInvocationBindings(program, image, step.record.progressed, id, wider);
            return;
        }
        const next = try world.advance(allocator, .{
            .program = .{ .image = image },
            .instance = .{ .snapshot = step.record.progressed },
        });
        step.deinit();
        step = next;
    }
    return error.RegionScopeNotReached;
}

fn phaseReturnExample(b: *boundary.source.Builder) !boundary.source.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const returns = try b.declare(&.{integer}, boolean, &.{}, &.{});
    try b.define(returns, try b.pure(try b.constant(bool, true)));
    const handler = try b.handler(.{
        .mode = .deep,
        .input = integer,
        .answer = boolean,
        .return_function = returns,
        .clauses = &.{},
    });
    const body = try b.declare(&.{}, integer, &.{}, &.{});
    try b.define(body, try b.pure(try b.constant(u64, 42)));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = integer,
    } } });
    const main = try b.declare(&.{}, integer, &.{}, &.{});
    const installed = try b.term(.{ .handle = .{
        .handler = handler,
        .body = try b.lambda(body, body_type),
    } });
    try b.define(main, try b.bind(
        try b.variable(boolean),
        installed,
        try b.pure(try b.constant(u64, 9)),
    ));
    return b.module(main, unit);
}

fn rejectSuspendedReturn(program: data.program.Program, block: data.program.Id, handler: data.program.Id) !void {
    const allocator = std.testing.allocator;
    const nodes: []const data.graph.Node = &.{
        .{ .control = .{
            .block = block,
            .arguments = &.{},
            .parent = .{ .id = 1 },
            .evidence = .{ .id = 1 },
        } },
        .{ .attachment = .{
            .handler = .{ .id = 2 },
            .outer = null,
            .return_to = null,
            .phase = .suspended,
        } },
        .{ .handler = .{ .definition = handler, .state = &.{}, .evidence = null } },
    };
    for ([_]data.graph.Status{ .active, .yielded }) |status| {
        const forged: data.graph.State = .{
            .program_identity = try data.image.identity(program),
            .status = status,
            .roots = .{ .current = .{ .id = 0 }, .evidence = .{ .id = 1 } },
            .nodes = nodes,
        };
        try std.testing.expectError(error.InvalidState, data.state_admission.validate(
            allocator,
            program,
            forged,
        ));
        var encoded = try data.snapshot.emit(allocator, forged, allocator, null);
        defer encoded.normalized.deinit();
        defer allocator.free(encoded.bytes);
        inline for (.{ world.run, world.advance }) |execute| {
            try std.testing.expectError(error.InvalidState, execute(allocator, .{
                .program = .{ .records = program },
                .instance = .{ .records = forged },
            }));
            try std.testing.expectError(error.InvalidState, execute(allocator, .{
                .program = .{ .records = program },
                .instance = .{ .snapshot = encoded.bytes },
            }));
        }
    }
}

test "a suspended delimiter cannot terminate a live return spine" {
    const allocator = std.testing.allocator;
    var b = boundary.source.Builder.init(allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(allocator, try phaseReturnExample(&b));
    defer compiled.deinit();
    var step = try world.advance(allocator, .{
        .program = .{ .records = compiled.program },
        .instance = .{ .initial_args = &.{} },
    });
    defer step.deinit();
    var tested = false;
    while (step.record == .progressed) {
        var saved = try data.snapshot.decodeGraph(allocator, step.record.progressed);
        defer saved.deinit();
        const control = saved.state.nodes[@intCast(saved.state.roots.current.?.id)].control;
        if (control.parent) |parent| if (saved.state.nodes[@intCast(parent.id)] == .attachment) {
            const attachment = saved.state.nodes[@intCast(parent.id)].attachment;
            const activation = saved.state.nodes[@intCast(attachment.handler.id)].handler;
            try rejectSuspendedReturn(compiled.program, control.block, activation.definition);
            tested = true;
        };
        const next = try world.advance(allocator, .{
            .program = .{ .records = compiled.program },
            .instance = .{ .snapshot = step.record.progressed },
        });
        step.deinit();
        step = next;
    }
    try std.testing.expect(tested);
    try std.testing.expectEqualSlices(u8, &.{ 9, 0, 0, 0, 0, 0, 0, 0 }, step.record.completed);
}

test "saved same-family capability substitution cannot escape through a helper return" {
    const allocator = std.testing.allocator;
    for ([_]bool{ false, true }) |through_pair| {
        var b = boundary.source.Builder.init(allocator);
        defer b.deinit();
        const unit = try b.scalar(void);
        const effect = try b.effect(.{ .identity = "saved-capability", .payload = unit, .result = unit, .external = false });
        const cap = try b.schema(.{ .internal = .{ .capability = effect } });
        const pair = try b.schema(.{ .product = &.{ cap, cap } });
        var handlers: [2]data.program.Id = undefined;
        for (&handlers, [_]data.program.Id{ unit, cap }) |*handler, result| {
            const returns = try b.declare(&.{result}, result, &.{}, &.{});
            try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 0))));
            const token = try b.schema(.{ .internal = .{ .resumption = .{ .effect = effect, .input = unit, .answer = result, .capture_bound = &.{ unit, cap, pair }, .handled = &.{effect}, .mode = .deep, .use = .linear } } });
            const clause = try b.declare(&.{ unit, token }, result, &.{}, &.{});
            try b.define(clause, try b.term(.{ .resume_value = .{ .resumption = try b.reference(b.parameter(clause, 1)), .argument = try b.constant(void, {}) } }));
            handler.* = try b.handler(.{ .mode = .deep, .input = result, .answer = result, .return_function = returns, .clauses = &.{.{ .effect = effect, .function = clause, .resumption = token }} });
        }
        const inner = try b.declare(&.{ cap, cap }, cap, &.{}, &.{});
        const fresh = try b.reference(b.parameter(inner, 0));
        const older = try b.reference(b.parameter(inner, 1));
        const body = if (through_pair) blk: {
            const helper = try b.declare(&.{ cap, cap }, pair, &.{}, &.{});
            try b.define(helper, try b.pure(try b.primitive(pair, .product, &.{ try b.reference(b.parameter(helper, 0)), try b.reference(b.parameter(helper, 1)) }, 0)));
            const answer = try b.variable(pair);
            break :blk try b.bind(answer, try b.term(.{ .call = .{ .function = helper, .arguments = &.{ fresh, older } } }), try b.pure(try b.primitive(cap, .field, &.{try b.reference(answer)}, 1)));
        } else try b.pure(older);
        try b.define(inner, body);
        const inner_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ cap, cap }, .result = cap } } });
        const outer = try b.declare(&.{cap}, unit, &.{effect}, &.{});
        const answer = try b.variable(cap);
        const installed = try b.term(.{ .handle = .{ .handler = handlers[1], .body = try b.lambda(inner, inner_type), .arguments = &.{try b.reference(b.parameter(outer, 0))} } });
        try b.define(outer, try b.bind(answer, installed, try b.term(.{ .perform = .{ .effect = effect, .capability = try b.reference(answer), .payload = try b.constant(void, {}) } })));
        const outer_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{cap}, .result = unit, .effects = &.{effect} } } });
        const main = try b.declare(&.{}, unit, &.{}, &.{});
        try b.define(main, try b.term(.{ .handle = .{ .handler = handlers[0], .body = try b.lambda(outer, outer_type) } }));
        var compiled = try boundary.program.compile(allocator, b.module(main, unit));
        defer compiled.deinit();
        var step = try world.advance(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{} } });
        defer step.deinit();
        var rejected: usize = 0;
        while (step.record != .completed) {
            const bytes = switch (step.record) {
                .progressed => |bytes| bytes,
                else => return error.UnexpectedOutcome,
            };
            var snapshot = try data.snapshot.decodeGraph(allocator, bytes);
            defer snapshot.deinit();
            const current = snapshot.state.roots.current.?;
            const control = snapshot.state.nodes[@intCast(current.id)].control;
            if (control.arguments.len == 2 and control.arguments[0].body == .reference and control.arguments[1].body == .reference and control.arguments[0].schema == control.arguments[1].schema and control.arguments[0].body.reference.id != control.arguments[1].body.reference.id) {
                const shape = compiled.program.schemas[@intCast(control.arguments[0].schema)];
                if (shape == .internal and shape.internal == .capability) {
                    const forged = try allocator.dupe(data.graph.Node, snapshot.state.nodes);
                    defer allocator.free(forged);
                    const arguments = try allocator.dupe(data.graph.Value, control.arguments);
                    defer allocator.free(arguments);
                    arguments[1] = arguments[0];
                    forged[@intCast(current.id)].control.arguments = arguments;
                    var invalid = snapshot.state;
                    invalid.nodes = forged;
                    try std.testing.expectError(error.InvalidScope, data.state_admission.validate(allocator, compiled.program, invalid));
                    rejected += 1;
                }
            }
            const successor = try world.advance(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = bytes } });
            step.deinit();
            step = successor;
        }
        try std.testing.expect(rejected >= if (through_pair) @as(usize, 2) else 1);
    }
}

test "one eight and sixty-four actual installations use one handler and zero captures" {
    for ([_]usize{ 1, 8, 64 }) |count| {
        var b = boundary.computation.Builder.init(std.testing.allocator);
        defer b.deinit();
        var compiled = try boundary.program.compile(std.testing.allocator, try boundary.source.examples.installations(&b, count));
        defer compiled.deinit();
        var statistics: world.Statistics = .{};
        var result = try world.run(std.testing.allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{} }, .statistics = &statistics });
        defer result.deinit();
        try std.testing.expectEqual(@as(u64, count * (count + 1) / 2), std.mem.readInt(u64, result.record.completed[0..8], .little));
        try std.testing.expectEqual(@as(usize, 1), compiled.program.handlers.len);
        try std.testing.expectEqual(count, statistics.direct_clauses);
        try std.testing.expectEqual(@as(u64, 0), statistics.one_shot_captures + statistics.multi_templates);
    }
}

test "one-shot capture retains a large immutable input without copying its payload" {
    var b = boundary.computation.Builder.init(std.testing.allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(std.testing.allocator, try boundary.source.examples.blobCapture(&b));
    defer compiled.deinit();
    const input = try std.testing.allocator.alloc(u8, 65539);
    defer std.testing.allocator.free(input);
    @memset(input, 0x5a);
    @memcpy(input[0..3], &[_]u8{ 0x80, 0x80, 0x04 });
    var statistics: world.Statistics = .{};
    var result = try world.run(std.testing.allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = input }, .statistics = &statistics });
    defer result.deinit();
    try std.testing.expectEqual(@as(u64, 65537), std.mem.readInt(u64, result.record.completed[0..8], .little));
    try std.testing.expectEqual(@as(u64, 1), statistics.one_shot_captures);
    try std.testing.expectEqual(input.len, statistics.storage.copied_blob_bytes);
}

test "authored scalar and collection faults preserve contracts and UTF-8 bytes" {
    const allocator = std.testing.allocator;
    var builder = boundary.source.Builder.init(allocator);
    defer builder.deinit();
    var compiled = try boundary.program.compile(allocator, try boundary.source.examples.scalarContracts(&builder));
    defer compiled.deinit();
    const expected = [_]?u64{ 3, null, null, null, null, null, null, null, null, null, null, 8, 2, 0, 4, 20, 240, 9, null };
    const faults = [_]u8{ 0, 3, 2, 3, 2, 2, 4, 5, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 5 };
    for (expected, faults, 0..) |value, fault, index| {
        var outcome = try world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{@intCast(index)} } });
        defer outcome.deinit();
        if (value) |n| {
            try std.testing.expectEqual(n, std.mem.readInt(u64, outcome.record.completed[0..8], .little));
        } else try std.testing.expectEqualSlices(u8, &.{fault}, outcome.record.failed.value);
    }
}

test "compiled finite values own their enum catalog and retain all collection bounds" {
    const allocator = std.testing.allocator;
    var compiled = blk: {
        var builder = boundary.source.Builder.init(allocator);
        defer builder.deinit();
        break :blk try boundary.program.compile(allocator, try boundary.source.examples.boundedValues(&builder));
    };
    defer compiled.deinit();
    var completed = try world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{} } });
    defer completed.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 7, 0, 0, 0, 9, 8, 2, 0xc3, 0xa9, 2, 0xff, 0 }, completed.record.completed);
}

test "failure in a source clause abandons its owned continuation and transfers running cleanup" {
    const allocator = std.testing.allocator;
    var b = boundary.computation.Builder.init(allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(allocator, try boundary.source.examples.clauseAbort(&b));
    defer compiled.deinit();
    var pending = try world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{} } });
    defer pending.deinit();
    const request = try data.protocol.decode(data.protocol.Request, allocator, pending.record.requested.request);
    try std.testing.expectEqualStrings("example/abandoned-release", request.semantic_identity);
    try std.testing.expectEqualSlices(u8, &.{ 1, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, request.payload);
    var state = try data.snapshot.decodeGraph(allocator, pending.record.requested.state);
    defer state.deinit();
    var running: usize = 0;
    for (state.state.nodes) |node| if (node == .obligation and node.obligation.status == .running) {
        running += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), running);
    const result: data.protocol.Result = .{ .request_identity = request.request_identity, .resume_schema_digest = data.wire.digest(request.resume_schema), .value = &.{} };
    const bytes = try allocator.alloc(u8, try data.protocol.encodedLength(data.protocol.Result, result));
    defer allocator.free(bytes);
    _ = try data.protocol.encode(data.protocol.Result, allocator, result, bytes);
    var failed = try world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = pending.record.requested.state }, .control = .{ .continue_value = bytes } });
    defer failed.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 9, 0, 0, 0, 0, 0, 0, 0 }, failed.record.failed.value);
}

test "source reentry preserves a live template-cell cycle and collects it after the handler" {
    const allocator = std.testing.allocator;
    inline for (.{ boundary.source.examples.reentrant, boundary.source.examples.cloned }, 0..) |example, converted| {
        var b = boundary.computation.Builder.init(allocator);
        defer b.deinit();
        var compiled = try boundary.program.compile(allocator, try example(&b));
        defer compiled.deinit();
        var statistics: world.Statistics = .{};
        var step = try world.advance(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{} }, .statistics = &statistics });
        defer step.deinit();
        var saw_template = false;
        var reclaimed = false;
        var yielded = false;
        while (step.record != .completed) {
            const snapshot = if (step.record == .yielded) step.record.yielded else step.record.progressed;
            yielded = yielded or step.record == .yielded;
            var state = try data.snapshot.decodeGraph(allocator, snapshot);
            defer state.deinit();
            var templates: usize = 0;
            for (state.state.nodes) |node| if (node == .multi_template) {
                templates += 1;
            };
            if (templates == 0 and saw_template) reclaimed = true;
            saw_template = saw_template or templates != 0;
            const next = try world.advance(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = snapshot }, .statistics = &statistics });
            step.deinit();
            step = next;
        }
        try std.testing.expect(yielded and saw_template and reclaimed);
        try std.testing.expectEqual(@as(u64, converted), statistics.one_shot_captures);
        try std.testing.expectEqual(@as(u64, 1), statistics.multi_templates);
        try std.testing.expectEqual(@as(u64, 2), statistics.branch_activations);
        try std.testing.expectEqualSlices(u8, &.{ 113, 0, 0, 0, 0, 0, 0, 0 }, step.record.completed);
    }
}

test "a failing source branch retains owned custody across a residual call and transfer" {
    const allocator = std.testing.allocator;
    var b = boundary.computation.Builder.init(allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(allocator, try boundary.source.examples.abortCustody(&b));
    defer compiled.deinit();
    var pending = try world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{0} } });
    defer pending.deinit();
    var state = try data.snapshot.decodeGraph(allocator, pending.record.requested.state);
    defer state.deinit();
    var resources: usize = 0;
    for (state.state.nodes) |node| if (node == .resource) {
        resources += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), resources);
    const request = try data.protocol.decode(data.protocol.Request, allocator, pending.record.requested.request);
    const result: data.protocol.Result = .{ .request_identity = request.request_identity, .resume_schema_digest = data.wire.digest(request.resume_schema), .value = &.{} };
    const bytes = try allocator.alloc(u8, try data.protocol.encodedLength(data.protocol.Result, result));
    defer allocator.free(bytes);
    _ = try data.protocol.encode(data.protocol.Result, allocator, result, bytes);
    var failed = try world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = pending.record.requested.state }, .control = .{ .continue_value = bytes } });
    defer failed.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 9, 0, 0, 0, 0, 0, 0, 0 }, failed.record.failed.value);
    var returned = try world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{1} } });
    defer returned.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 41, 0, 0, 0, 0, 0, 0, 0 }, returned.record.completed);
}

test "injected failure reaches the use-site handler while clause failure reaches its own handler" {
    const allocator = std.testing.allocator;
    var b = boundary.computation.Builder.init(allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(allocator, try boundary.source.examples.injection(&b));
    defer compiled.deinit();
    for ([_]u8{ 0, 1 }) |injected| {
        inline for (.{ world.run, world.advance }) |execute| {
            var outcome = try execute(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{injected} } });
            defer outcome.deinit();
            var saw_injection = false;
            while (outcome.record == .progressed) {
                var state = try data.snapshot.decodeGraph(allocator, outcome.record.progressed);
                defer state.deinit();
                for (state.state.nodes) |node| if (node == .injection) {
                    saw_injection = true;
                };
                const next = try execute(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = outcome.record.progressed } });
                outcome.deinit();
                outcome = next;
            }
            try std.testing.expectEqualSlices(u8, &.{ if (injected == 0) 109 else 209, 0, 0, 0, 0, 0, 0, 0 }, outcome.record.completed);
            if (execute == world.advance) try std.testing.expectEqual(injected == 1, saw_injection);
        }
    }
}

test "indexed results and a row-polymorphic library preserve typing through failed resume and retry" {
    const allocator = std.testing.allocator;
    var b = boundary.computation.Builder.init(allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(allocator, try boundary.source.examples.indexed(&b));
    defer compiled.deinit();
    var outcome = try world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{} } });
    defer outcome.deinit();
    for ([_][]const u8{ &.{ 37, 0, 0, 0, 0, 0, 0, 0 }, &.{1} }, 0..) |value, index| {
        const request = try data.protocol.decode(data.protocol.Request, allocator, outcome.record.requested.request);
        try std.testing.expectEqualStrings(if (index == 0) "example/indexed/number" else "example/indexed/flag", request.semantic_identity);
        var result: data.protocol.Result = .{ .request_identity = request.request_identity, .resume_schema_digest = data.wire.digest(request.resume_schema), .value = if (index == 0) &.{1} else &.{2} };
        const bytes = try allocator.alloc(u8, try data.protocol.encodedLength(data.protocol.Result, result) + 8);
        defer allocator.free(bytes);
        const invalid = try data.protocol.encode(data.protocol.Result, allocator, result, bytes);
        try std.testing.expectError(error.InvalidValue, world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = outcome.record.requested.state }, .control = .{ .continue_value = invalid } }));
        result.value = value;
        const encoded = try data.protocol.encode(data.protocol.Result, allocator, result, bytes);
        const next = try world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = outcome.record.requested.state }, .control = .{ .continue_value = encoded } });
        outcome.deinit();
        outcome = next;
    }
    try std.testing.expectEqualSlices(u8, &.{ 1, 37, 0, 0, 0, 0, 0, 0, 0, 1, 1 }, outcome.record.completed);
}

test "nested non-tail and shallow source handlers preserve answers and failure custody" {
    const allocator = std.testing.allocator;
    inline for (.{ boundary.source.examples.nested, boundary.source.examples.shallow }, 0..) |example, index| {
        var b = boundary.computation.Builder.init(allocator);
        defer b.deinit();
        var compiled = try boundary.program.compile(allocator, try example(&b));
        defer compiled.deinit();
        for (0..if (index == 0) @as(usize, 1) else 2) |invalid| {
            inline for (.{ world.run, world.advance }) |execute| {
                var outcome = try execute(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = if (index == 0) &.{} else if (invalid == 0) &.{0} else &.{1} } });
                defer outcome.deinit();
                while (outcome.record == .progressed) {
                    const next = try execute(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = outcome.record.progressed } });
                    outcome.deinit();
                    outcome = next;
                }
                if (invalid != 0) try std.testing.expectEqualSlices(u8, &.{}, outcome.record.failed.value) else try std.testing.expectEqualSlices(u8, if (index == 0) &.{ 165, 2, 0, 0, 0, 0, 0, 0 } else &.{1}, outcome.record.completed);
            }
        }
    }
}

test "tail-resumptive State preserves both answer types with zero captured resumptions" {
    const allocator = std.testing.allocator;
    var b = boundary.computation.Builder.init(allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(allocator, try boundary.source.examples.answers(&b));
    defer compiled.deinit();
    for (compiled.program.handlers) |handler| for (handler.clauses) |clause| try std.testing.expect(clause.direct);
    inline for (.{ world.run, world.advance }) |execute| {
        var statistics: world.Statistics = .{};
        var outcome = try execute(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{} }, .statistics = &statistics });
        defer outcome.deinit();
        while (outcome.record == .progressed) {
            const next = try execute(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = outcome.record.progressed }, .statistics = &statistics });
            outcome.deinit();
            outcome = next;
        }
        try std.testing.expectEqualSlices(u8, &.{ 1, 10, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0 }, outcome.record.completed);
        try std.testing.expectEqual(@as(u64, 2), statistics.direct_clauses);
        try std.testing.expectEqual(@as(u64, 0), statistics.one_shot_captures);
        try std.testing.expectEqual(@as(u64, 0), statistics.multi_templates);
    }
}

test "source expressions observe a write between repeated occurrences of the same read syntax" {
    var b = boundary.source.Builder.init(std.testing.allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(std.testing.allocator, try boundary.source.examples.cellOrder(&b));
    defer compiled.deinit();
    var result = try world.run(std.testing.allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{} } });
    defer result.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 1, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0 }, result.record.completed);
}

test "DFS and BFS solve queens with shared metrics, retained templates, and transferred cleanup" {
    const allocator = std.testing.allocator;
    inline for (.{ boundary.source.examples.queensDfs, boundary.source.examples.queensBfs }, 0..) |example, policy| {
        var b = boundary.source.Builder.init(allocator);
        defer b.deinit();
        var compiled = try boundary.program.compile(allocator, try example(&b));
        defer compiled.deinit();
        inline for (.{ world.run, world.advance }) |execute| {
            var step = try execute(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{} } });
            defer step.deinit();
            var requests: usize = 0;
            var yields: usize = 0;
            var running_cleanups: usize = 0;
            while (step.record != .completed) {
                var result_bytes: ?[]u8 = null;
                defer if (result_bytes) |bytes| allocator.free(bytes);
                const state = switch (step.record) {
                    .progressed => |state| state,
                    .yielded => |state| blk: {
                        var decoded = try data.snapshot.decodeGraph(allocator, state);
                        defer decoded.deinit();
                        var templates: usize = 0;
                        for (decoded.state.nodes) |node| if (node == .multi_template) {
                            templates += 1;
                        };
                        try std.testing.expect(templates >= 2);
                        yields += 1;
                        break :blk state;
                    },
                    .requested => |request| blk: {
                        const decoded = try data.protocol.decode(data.protocol.Request, allocator, request.request);
                        try std.testing.expectEqualStrings(([_][]const u8{ "example/queens-acquire", "example/queens-use", "example/queens-release" })[requests % 3], decoded.semantic_identity);
                        if (requests % 3 == 1) {
                            try std.testing.expectEqual(@as(u8, if (policy == 0) (if (requests < 3) 26 else 38) else (if (requests < 3) 51 else 54)), decoded.payload[decoded.payload.len - 8]);
                        }
                        if (requests % 3 == 2) {
                            var saved = try data.snapshot.decodeGraph(allocator, request.state);
                            defer saved.deinit();
                            var running: usize = 0;
                            for (saved.state.nodes) |node| if (node == .obligation and node.obligation.status == .running) {
                                running += 1;
                            };
                            try std.testing.expectEqual(@as(usize, 1), running);
                            running_cleanups += 1;
                        }
                        const acquired = [_]u8{ @intCast(201 + requests / 3), 0, 0, 0, 0, 0, 0, 0 };
                        const result: data.protocol.Result = .{ .request_identity = decoded.request_identity, .resume_schema_digest = data.wire.digest(decoded.resume_schema), .value = if (requests % 3 == 0) &acquired else &.{} };
                        result_bytes = try allocator.alloc(u8, try data.protocol.encodedLength(data.protocol.Result, result));
                        _ = try data.protocol.encode(data.protocol.Result, allocator, result, result_bytes.?);
                        requests += 1;
                        break :blk request.state;
                    },
                    else => return error.UnexpectedOutcome,
                };
                const next = try execute(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = state }, .control = .{ .continue_value = result_bytes } });
                step.deinit();
                step = next;
            }
            try std.testing.expectEqual(@as(usize, 6), requests);
            try std.testing.expectEqual(@as(usize, 1), yields);
            try std.testing.expectEqual(@as(usize, 2), running_cleanups);
            try std.testing.expectEqualSlices(u8, &.{ 2, 4, 2, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 4, 3, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 60, 0, 0, 0, 0, 0, 0, 0 }, step.record.completed);
        }
    }
}

test "authored FIFO scheduling transfers two packages and resolves a blocked typed join" {
    const allocator = std.testing.allocator;
    var b = boundary.source.Builder.init(allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(allocator, try boundary.source.examples.schedulerFifo(&b));
    defer compiled.deinit();
    var first = try world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = &.{} } });
    defer first.deinit();
    var saved = try data.snapshot.decodeGraph(allocator, first.record.yielded);
    defer saved.deinit();
    var packages: usize = 0;
    for (saved.state.nodes) |record| if (record == .package) {
        packages += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), packages);
    var step = try world.advance(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = first.record.yielded } });
    defer step.deinit();
    while (step.record == .progressed) {
        const next = try world.advance(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .snapshot = step.record.progressed } });
        step.deinit();
        step = next;
    }
    try std.testing.expectEqualSlices(u8, &.{ 30, 0, 0, 0, 0, 0, 0, 0, 4, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0 }, step.record.completed);
}

test "scoped Reader forwarding preserves inside and outside bindings through logging and transfer" {
    const allocator = std.testing.allocator;
    var b = boundary.source.Builder.init(allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(allocator, try boundary.source.examples.scopedReader(&b));
    defer compiled.deinit();
    const image = try allocator.alloc(u8, try data.image.encodedLength(compiled.program));
    defer allocator.free(image);
    _ = try compiled.encode(allocator, image);
    var step = try world.advance(allocator, .{ .program = .{ .image = image }, .instance = .{ .initial_args = &.{} } });
    defer step.deinit();
    var logs: usize = 0;
    while (step.record != .completed) {
        var result_bytes: ?[]u8 = null;
        defer if (result_bytes) |bytes| allocator.free(bytes);
        const state = switch (step.record) {
            .progressed => |state| state,
            .requested => |request| blk: {
                const decoded = try data.protocol.decode(data.protocol.Request, allocator, request.request);
                try std.testing.expectEqualStrings("example/reader-log", decoded.semantic_identity);
                try std.testing.expectEqual(@as(u8, if (logs == 0) 2 else 1), decoded.payload[0]);
                logs += 1;
                const result: data.protocol.Result = .{ .request_identity = decoded.request_identity, .resume_schema_digest = data.wire.digest(decoded.resume_schema), .value = &.{} };
                result_bytes = try allocator.alloc(u8, try data.protocol.encodedLength(data.protocol.Result, result));
                _ = try data.protocol.encode(data.protocol.Result, allocator, result, result_bytes.?);
                break :blk request.state;
            },
            else => return error.UnexpectedOutcome,
        };
        const next = try world.advance(allocator, .{ .program = .{ .image = image }, .instance = .{ .snapshot = state }, .control = .{ .continue_value = result_bytes } });
        step.deinit();
        step = next;
    }
    try std.testing.expectEqual(@as(usize, 3), logs);
    try std.testing.expectEqualSlices(u8, &.{ 20, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0 }, step.record.completed);
}

test "private resource representations share a client and preserve scoped borrows through transfer" {
    const allocator = std.testing.allocator;
    inline for (.{ boundary.source.examples.resourceScalar, boundary.source.examples.resourcePair }) |example| {
        var b = boundary.source.Builder.init(allocator);
        defer b.deinit();
        var compiled = try boundary.program.compile(allocator, try example(&b));
        defer compiled.deinit();
        const image = try allocator.alloc(u8, try data.image.encodedLength(compiled.program));
        defer allocator.free(image);
        _ = try compiled.encode(allocator, image);
        var step = try world.advance(allocator, .{ .program = .{ .image = image }, .instance = .{ .initial_args = &.{} } });
        defer step.deinit();
        var requests: usize = 0;
        var borrowed = false;
        while (step.record != .completed) {
            var result_bytes: ?[]u8 = null;
            defer if (result_bytes) |bytes| allocator.free(bytes);
            const state = switch (step.record) {
                .progressed => |state| state,
                .requested => |request| blk: {
                    const decoded = try data.protocol.decode(data.protocol.Request, allocator, request.request);
                    try std.testing.expectEqualStrings(([_][]const u8{ "example/resource-acquire", "example/resource-use", "example/resource-release" })[requests], decoded.semantic_identity);
                    if (requests != 0) try std.testing.expectEqualSlices(u8, &.{ 41, 0, 0, 0, 0, 0, 0, 0 }, decoded.payload);
                    const result: data.protocol.Result = .{ .request_identity = decoded.request_identity, .resume_schema_digest = data.wire.digest(decoded.resume_schema), .value = if (requests == 0) &.{ 41, 0, 0, 0, 0, 0, 0, 0 } else &.{} };
                    result_bytes = try allocator.alloc(u8, try data.protocol.encodedLength(data.protocol.Result, result));
                    _ = try data.protocol.encode(data.protocol.Result, allocator, result, result_bytes.?);
                    requests += 1;
                    break :blk request.state;
                },
                else => return error.UnexpectedOutcome,
            };
            var snapshot = try data.snapshot.decodeGraph(allocator, state);
            defer snapshot.deinit();
            for (snapshot.state.nodes) |record| if (record == .borrow) {
                borrowed = true;
                const forged = try allocator.dupe(data.graph.Node, snapshot.state.nodes);
                defer allocator.free(forged);
                for (forged) |*node| if (node.* == .protection) {
                    node.protection.loan = null;
                };
                var invalid = snapshot.state;
                invalid.nodes = forged;
                try std.testing.expectError(error.InvalidOwnership, data.state_admission.validate(allocator, compiled.program, invalid));
                break;
            };
            const next = try world.advance(allocator, .{ .program = .{ .image = image }, .instance = .{ .snapshot = state }, .control = .{ .continue_value = result_bytes } });
            step.deinit();
            step = next;
        }
        try std.testing.expect(borrowed);
        try std.testing.expectEqual(@as(usize, 3), requests);
        try std.testing.expectEqualSlices(u8, &.{ 42, 0, 0, 0, 0, 0, 0, 0 }, step.record.completed);
    }
}

test "source generator transfers its private cell and cleanup obligation, then resumes and closes" {
    const allocator = std.testing.allocator;
    var b = boundary.source.Builder.init(allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(allocator, try boundary.source.examples.generator(&b));
    defer compiled.deinit();
    const image = try allocator.alloc(u8, try data.image.encodedLength(compiled.program));
    defer allocator.free(image);
    _ = try compiled.encode(allocator, image);
    var step = try world.advance(allocator, .{ .program = .{ .image = image }, .instance = .{ .initial_args = &.{} } });
    defer step.deinit();
    var yields: usize = 0;
    var releases: usize = 0;
    while (step.record != .completed) {
        var result_bytes: ?[]u8 = null;
        defer if (result_bytes) |bytes| allocator.free(bytes);
        const state = switch (step.record) {
            .progressed => |state| state,
            .yielded => |state| blk: {
                yields += 1;
                var graph = try data.snapshot.decodeGraph(allocator, state);
                defer graph.deinit();
                var packages: usize = 0;
                var cells: usize = 0;
                var obligations: usize = 0;
                for (graph.state.nodes) |node| switch (node) {
                    .package => packages += 1,
                    .cell => cells += 1,
                    .obligation => obligations += 1,
                    else => {},
                };
                try std.testing.expectEqual(@as(usize, 1), packages);
                try std.testing.expectEqual(@as(usize, 1), cells);
                try std.testing.expectEqual(@as(usize, 1), obligations);
                break :blk state;
            },
            .requested => |request| blk: {
                releases += 1;
                const decoded = try data.protocol.decode(data.protocol.Request, allocator, request.request);
                try std.testing.expectEqualStrings("example/generator-release", decoded.semantic_identity);
                try std.testing.expectEqualSlices(u8, &.{ 43, 0, 0, 0, 0, 0, 0, 0 }, decoded.payload);
                const result: data.protocol.Result = .{ .request_identity = decoded.request_identity, .resume_schema_digest = data.wire.digest(decoded.resume_schema), .value = &.{} };
                result_bytes = try allocator.alloc(u8, try data.protocol.encodedLength(data.protocol.Result, result));
                _ = try data.protocol.encode(data.protocol.Result, allocator, result, result_bytes.?);
                break :blk request.state;
            },
            else => return error.UnexpectedOutcome,
        };
        const next = try world.advance(allocator, .{ .program = .{ .image = image }, .instance = .{ .snapshot = state }, .control = .{ .continue_value = result_bytes } });
        step.deinit();
        step = next;
    }
    try std.testing.expectEqual(@as(usize, 1), yields);
    try std.testing.expectEqual(@as(usize, 1), releases);
    try std.testing.expectEqualSlices(u8, &.{ 42, 0, 0, 0, 0, 0, 0, 0, 43, 0, 0, 0, 0, 0, 0, 0 }, step.record.completed);
}

test "higher-order source lambdas, non-tail handlers, and mutual recursion execute as data" {
    const allocator = std.testing.allocator;
    inline for (.{ boundary.source.examples.lexical, boundary.source.examples.deep, boundary.source.examples.recursive, boundary.source.examples.choicesAll, boundary.source.examples.choicesFirst, boundary.source.examples.stateLocal, boundary.source.examples.stateShared, boundary.source.examples.answers }, 0..) |example, index| {
        var builder = boundary.source.Builder.init(allocator);
        var compiled = boundary.program.compile(allocator, try example(&builder)) catch |err| {
            builder.deinit();
            return err;
        };
        defer compiled.deinit();
        builder.deinit();
        const initial: []const u8 = switch (index) {
            0 => &.{ 40, 0, 0, 0, 0, 0, 0, 0 },
            1, 3, 4, 5, 6, 7 => &.{},
            2 => &.{ 16, 39, 0, 0, 0, 0, 0, 0 },
            else => unreachable,
        };
        const expected: []const u8 = switch (index) {
            0 => &.{ 42, 0, 0, 0, 0, 0, 0, 0 },
            1 => &.{ 67, 0, 0, 0, 0, 0, 0, 0 },
            2 => &.{1},
            3 => &.{ 4, 0, 0, 0, 1, 1, 0, 1, 1 },
            4 => &.{ 1, 0, 0 },
            5 => &.{ 2, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0 },
            6 => &.{ 2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0 },
            7 => &.{ 1, 10, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0 },
            else => unreachable,
        };
        var records = try world.run(allocator, .{ .program = .{ .records = compiled.program }, .instance = .{ .initial_args = initial } });
        defer records.deinit();
        try std.testing.expectEqualSlices(u8, expected, records.record.completed);
        const image = try allocator.alloc(u8, try data.image.encodedLength(compiled.program));
        defer allocator.free(image);
        _ = try compiled.encode(allocator, image);
        var serialized = try world.run(allocator, .{ .program = .{ .image = image }, .instance = .{ .initial_args = initial } });
        defer serialized.deinit();
        try std.testing.expectEqualSlices(u8, records.record.completed, serialized.record.completed);
        if (index == 1 or index == 3 or index == 5 or index == 6) {
            var step = try world.advance(allocator, .{ .program = .{ .image = image }, .instance = .{ .initial_args = initial } });
            defer step.deinit();
            while (step.record == .progressed) {
                const next = try world.advance(allocator, .{ .program = .{ .image = image }, .instance = .{ .snapshot = step.record.progressed } });
                step.deinit();
                step = next;
            }
            try std.testing.expectEqualSlices(u8, expected, step.record.completed);
        }
    }
}

fn shallowReturnExample(b: *boundary.source.Builder, comptime mode: data.program.Mode, comptime use: data.program.Use, comptime injecting: bool) !boundary.source.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const effect = try b.effect(.{ .identity = "review/shallow-return", .payload = unit, .result = unit, .external = true, .control_use = use });
    const cap = try b.schema(.{ .internal = .{ .capability = effect } });
    const token = try b.reserveSchema();
    try b.defineSchema(token, .{ .internal = .{ .resumption = .{
        .effect = effect,
        .input = unit,
        .answer = integer,
        .mode = mode,
        .use = use,
        .handled = &.{effect},
        .effects = &.{effect},
        .capture_bound = &.{ unit, cap, integer, token },
    } } });
    const returns = try b.declare(&.{integer}, integer, &.{}, &.{});
    try b.define(returns, try b.pure(try b.constant(u64, 99)));
    const clause = try b.declare(&.{ unit, token }, integer, &.{effect}, &.{});
    const k = try b.reference(b.parameter(clause, 1));
    const resume_term = if (injecting) blk: {
        const thunk = try b.declare(&.{}, unit, &.{}, &.{});
        try b.define(thunk, try b.pure(try b.constant(void, {})));
        const thunk_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{}, .result = unit } } });
        break :blk try b.term(.{ .resume_computation = .{ .resumption = k, .computation = try b.lambda(thunk, thunk_type) } });
    } else try b.term(.{ .resume_value = .{ .resumption = k, .argument = try b.constant(void, {}) } });
    const body_term = if (use == .multi)
        try b.bind(try b.variable(integer), resume_term, resume_term)
    else
        resume_term;
    try b.define(clause, body_term);
    const handler = try b.handler(.{ .mode = mode, .input = integer, .answer = integer, .effects = &.{effect}, .return_function = returns, .clauses = &.{.{ .effect = effect, .function = clause, .resumption = token }} });
    const body = try b.declare(&.{cap}, integer, &.{effect}, &.{});
    const call = try b.term(.{ .perform = .{ .effect = effect, .capability = try b.reference(b.parameter(body, 0)), .payload = try b.constant(void, {}) } });
    try b.define(body, try b.bind(try b.variable(unit), call, try b.pure(try b.constant(u64, 42))));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{cap}, .result = integer, .effects = &.{effect} } } });
    const entry = try b.declare(&.{}, integer, &.{effect}, &.{});
    try b.define(entry, try b.term(.{ .handle = .{ .handler = handler, .body = try b.lambda(body, body_type) } }));
    return b.module(entry, unit);
}

test "shallow value and computation resumption omit the original return clause" {
    const allocator = std.testing.allocator;
    inline for (.{ data.program.Mode.deep, data.program.Mode.shallow }) |mode| {
        inline for (.{ data.program.Use.linear, data.program.Use.multi }) |use| {
            inline for (.{ false, true }) |injecting| {
                var b = boundary.source.Builder.init(allocator);
                defer b.deinit();
                const source = try shallowReturnExample(&b, mode, use, injecting);
                var compiled = try boundary.program.compile(allocator, source);
                defer compiled.deinit();
                inline for (.{ world.run, world.advance }) |execute| {
                    var statistics: world.Statistics = .{};
                    var step = try execute(allocator, .{
                        .program = .{ .records = compiled.program },
                        .instance = .{ .initial_args = &.{} },
                        .statistics = &statistics,
                    });
                    defer step.deinit();
                    while (step.record == .progressed) {
                        const next = try execute(allocator, .{
                            .program = .{ .records = compiled.program },
                            .instance = .{ .snapshot = step.record.progressed },
                            .statistics = &statistics,
                        });
                        step.deinit();
                        step = next;
                    }
                    const expected = [_]u8{ if (mode == .deep) 99 else 42, 0, 0, 0, 0, 0, 0, 0 };
                    try std.testing.expectEqualSlices(u8, &expected, step.record.completed);
                    if (use == .multi)
                        try std.testing.expectEqual(@as(u64, 2), statistics.branch_activations);
                }
            }
        }
    }
}

fn restoredEffectExample(b: *boundary.source.Builder) !boundary.source.Module {
    const unit = try b.scalar(void);
    const boolean = try b.scalar(bool);
    const a = try b.effect(.{ .identity = "restore/A", .payload = unit, .result = unit, .external = false });
    const residual = try b.effect(.{ .identity = "restore/B", .payload = unit, .result = unit, .external = true });
    const cap = try b.schema(.{ .internal = .{ .capability = a } });
    const returns = try b.declare(&.{unit}, unit, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 0))));
    var branches: [2]data.program.Id = undefined;
    for (&branches, 0..) |*branch, index| {
        const row: []const data.program.Id = if (index == 0) &.{} else &.{residual};
        const token = try b.schema(.{ .internal = .{ .resumption = .{ .effect = a, .input = unit, .answer = unit, .mode = .deep, .use = .linear, .handled = &.{a}, .effects = row, .capture_bound = &.{ unit, cap } } } });
        const clause = try b.declare(&.{ unit, token }, unit, row, &.{});
        const resume_term = try b.term(.{ .resume_value = .{ .resumption = try b.reference(b.parameter(clause, 1)), .argument = try b.constant(void, {}) } });
        const yield = try b.term(.{ .yield_then = try b.pure(try b.constant(void, {})) });
        try b.define(clause, try b.bind(try b.variable(unit), resume_term, yield));
        const handler = try b.handler(.{ .mode = .deep, .input = unit, .answer = unit, .effects = row, .return_function = returns, .clauses = &.{.{ .effect = a, .function = clause, .resumption = token }} });
        const body_row: []const data.program.Id = if (index == 0) &.{a} else &.{ a, residual };
        const body = try b.declare(&.{cap}, unit, body_row, &.{});
        const first = try b.term(.{ .perform = .{ .effect = a, .capability = try b.reference(b.parameter(body, 0)), .payload = try b.constant(void, {}) } });
        const last = if (index == 0) try b.pure(try b.constant(void, {})) else try b.term(.{ .perform = .{ .effect = residual, .payload = try b.constant(void, {}) } });
        try b.define(body, try b.bind(try b.variable(unit), first, last));
        const signature = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{cap}, .result = unit, .effects = body_row } } });
        branch.* = try b.term(.{ .handle = .{ .handler = handler, .body = try b.lambda(body, signature) } });
    }
    const entry = try b.declare(&.{boolean}, unit, &.{residual}, &.{});
    try b.define(entry, try b.term(.{ .conditional = .{ .condition = try b.reference(b.parameter(entry, 0)), .when_true = branches[1], .when_false = branches[0] } }));
    return b.module(entry, unit);
}

test "restored token interfaces bound the actual captured continuation effects" {
    const allocator = std.testing.allocator;
    var b = boundary.source.Builder.init(allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(allocator, try restoredEffectExample(&b));
    defer compiled.deinit();
    var replacement: ?usize = null;
    for (compiled.program.handlers, 0..) |handler, id| {
        if (handler.effects.len == 0) replacement = id;
    }
    const handler = compiled.program.handlers[replacement.?];
    const schema = handler.clauses[0].resumption;
    const clause_block = compiled.program.functions[@intCast(handler.clauses[0].function)].entry;
    var step = try world.advance(allocator, .{
        .program = .{ .records = compiled.program },
        .instance = .{ .initial_args = &.{1} },
    });
    defer step.deinit();
    while (step.record == .progressed) {
        var saved = try data.snapshot.decodeGraph(allocator, step.record.progressed);
        defer saved.deinit();
        try data.state_admission.validate(allocator, compiled.program, saved.state);
        const nodes = @constCast(saved.state.nodes);
        for (nodes) |*node| {
            if (node.* != .one_shot) continue;
            const old_schema = node.one_shot.schema;
            if (compiled.program.schemas[@intCast(old_schema)].internal.resumption.effects.len == 0)
                continue;
            node.one_shot.schema = schema;
            const delimiter = nodes[@intCast(node.one_shot.delimiter.id)].attachment;
            nodes[@intCast(delimiter.handler.id)].handler.definition = replacement.?;
            const control = &nodes[@intCast(saved.state.roots.current.?.id)].control;
            control.block = clause_block;
            for (@constCast(control.arguments)) |*argument| {
                if (argument.schema == old_schema) argument.schema = schema;
            }
            try std.testing.expectError(error.InvalidEffect, data.state_admission.validate(allocator, compiled.program, saved.state));
            var encoded = try data.snapshot.emit(allocator, saved.state, allocator, null);
            defer encoded.normalized.deinit();
            defer allocator.free(encoded.bytes);
            inline for (.{ world.run, world.advance }) |execute| {
                try std.testing.expectError(error.InvalidEffect, execute(allocator, .{
                    .program = .{ .records = compiled.program },
                    .instance = .{ .records = saved.state },
                }));
                try std.testing.expectError(error.InvalidEffect, execute(allocator, .{
                    .program = .{ .records = compiled.program },
                    .instance = .{ .snapshot = encoded.bytes },
                }));
            }
            var original = try world.run(allocator, .{
                .program = .{ .records = compiled.program },
                .instance = .{ .snapshot = step.record.progressed },
            });
            defer original.deinit();
            try std.testing.expect(original.record == .requested);
            return;
        }
        const next = try world.advance(allocator, .{
            .program = .{ .records = compiled.program },
            .instance = .{ .snapshot = step.record.progressed },
        });
        step.deinit();
        step = next;
    }
    return error.CaptureNotFound;
}
