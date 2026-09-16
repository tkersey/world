const std = @import("std");
const boundary = @import("boundary");
const source = boundary.source;
const Session = @import("stable_runtime").Session;
const testing = std.testing;

fn checkedCheckpoint(subject: *Session) !void {
    const bytes = try subject.checkpoint(testing.allocator);
    defer testing.allocator.free(bytes);
    var decoded = try boundary.data_v2.state_image.decodeGraph(testing.allocator, bytes);
    defer decoded.deinit();
    const reencoded = try boundary.data_v2.state_image.emit(testing.allocator, decoded.state);
    defer testing.allocator.free(reencoded);
    try testing.expectEqualSlices(u8, bytes, reencoded);
    const repeated = try subject.checkpoint(testing.allocator);
    defer testing.allocator.free(repeated);
    try testing.expectEqualSlices(u8, bytes, repeated);
    try testing.expectEqual(subject.program_identity, decoded.state.program_identity);
}

fn drive(subject: *Session, quantum: ?usize) !@import("stable_runtime").Observation {
    const result = try subject.run(quantum);
    try checkedCheckpoint(subject);
    return result;
}

fn checkpointFailure(allocator: std.mem.Allocator, subject: *Session, before: []const u8) !void {
    const bytes = subject.checkpoint(allocator) catch |err| {
        const after = try subject.checkpoint(testing.allocator);
        defer testing.allocator.free(after);
        try testing.expectEqualSlices(u8, before, after);
        return err;
    };
    defer allocator.free(bytes);
    try testing.expectEqualSlices(u8, before, bytes);
}

test "failed PST3 export retains exactly the same resident instruction boundary" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.installations(&builder, 1));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    try testing.expect(try session.run(1) == .progressed);
    const before = try session.checkpoint(testing.allocator);
    defer testing.allocator.free(before);
    try testing.checkAllAllocationFailures(testing.allocator, checkpointFailure, .{ &session, before });
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqual(1, result.completed.body.scalar[0]);
}

fn initFromImage(allocator: std.mem.Allocator, program: boundary.data_v2.activation.Program, arguments: []const u8) !Session {
    const codec = boundary.data_v2.program_image;
    const image = try allocator.alloc(u8, try codec.encodedLength(program));
    defer allocator.free(image);
    _ = try codec.encode(allocator, program, image);
    const result = try Session.initImage(allocator, image, arguments);
    @memset(image, 0xff);
    return result;
}

test "BPI3 scalar and collection faults preserve the existing independent expectations" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.scalarContracts(&builder));
    defer compiled.deinit();
    const expected = [_]?u64{ 3, null, null, null, null, null, null, null, null, null, null, 8, 2, 0, 4, 20, 240, 9, null };
    const faults = [_]u8{ 0, 3, 2, 3, 2, 2, 4, 5, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 5 };
    for (expected, faults, 0..) |value, fault, index| {
        var session = try initFromImage(testing.allocator, compiled.program, &.{@intCast(index)});
        defer session.deinit();
        const outcome = try drive(&session, null);
        if (value) |n| {
            try testing.expect(outcome == .completed);
            try testing.expectEqual(n, std.mem.readInt(u64, (try session.bytes(&outcome.completed))[0..8], .little));
        } else {
            try testing.expect(outcome == .failed);
            try testing.expectEqualSlices(u8, &.{fault}, try session.bytes(&outcome.failed));
        }
    }
}

test "stable borrow admission distinguishes older from fresh references through return clauses" {
    const fixture = @import("borrow_return_fixtures");
    for (std.enums.values(fixture.ResultFrom)) |from| {
        for ([_]bool{ false, true }) |initial| {
            for ([_]bool{ false, true }) |delegated| {
                for ([_]bool{ false, true }) |younger| {
                    var builder = source.Builder.init(testing.allocator);
                    defer builder.deinit();
                    const module = try fixture.scenario(&builder, from, initial, younger, delegated);
                    if (younger) {
                        try testing.expectError(error.InvalidOwnership, source.construct(testing.allocator, module));
                    } else {
                        var compiled = try source.construct(testing.allocator, module);
                        defer compiled.deinit();
                        var session = try initFromImage(testing.allocator, compiled.program, &.{});
                        defer session.deinit();
                        try testing.expect(try drive(&session, null) == .yielded);
                        try session.resumeYield();
                        const result = try drive(&session, null);
                        try testing.expect(result == .completed);
                        try testing.expectEqual(0, (try session.bytes(&result.completed)).len);
                    }
                }
            }
        }
    }
}

test "stable resource implementations preserve private authority and loans across requests" {
    inline for (.{ source.examples.resourceScalar, source.examples.resourcePair }) |example| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try example(&builder));
        defer compiled.deinit();
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        var borrowed = false;
        for ([_][]const u8{ "example/resource-acquire", "example/resource-use", "example/resource-release" }, 0..) |name, index| {
            const pending = try drive(&session, null);
            try testing.expect(pending == .requested);
            try testing.expectEqualStrings(name, session.program.effects[@intCast(pending.requested.effect)].identity);
            if (index != 0) try testing.expectEqual(41, pending.requested.payload.body.scalar[0]);
            for (session.store.nodes.items, session.store.alive.items) |node, alive| {
                if (alive and node == .borrow) borrowed = true;
            }
            try session.store.collectWith(session.roots, &session.frames);
            try session.answer(if (index == 0) &.{ 41, 0, 0, 0, 0, 0, 0, 0 } else &.{});
        }
        const result = try drive(&session, null);
        try testing.expect(borrowed and result == .completed);
        try testing.expectEqual(42, result.completed.body.scalar[0]);
    }
}

test "stable cancellation releases the resource while its protected borrow is suspended" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.resourceScalar(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    try testing.expect(try drive(&session, null) == .requested);
    try session.answer(&.{ 41, 0, 0, 0, 0, 0, 0, 0 });
    const use = try drive(&session, null);
    try testing.expect(use == .requested);
    try testing.expectEqualStrings("example/resource-use", session.program.effects[@intCast(use.requested.effect)].identity);
    try session.cancel(.{ .text = "stop" });
    const release = try drive(&session, null);
    try testing.expect(release == .requested);
    try testing.expectEqualStrings("example/resource-release", session.program.effects[@intCast(release.requested.effect)].identity);
    try testing.expectEqual(41, release.requested.payload.body.scalar[0]);
    try session.answer(&.{});
    try testing.expect(try drive(&session, null) == .cancelled);
}

test "stable admission rejects a fresh store hidden by a later same-slot rebind" {
    const fixture = @import("borrow_return_fixtures");
    const data = boundary.data_v2;
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try fixture.scenario(&builder, .pair, true, false, false));
    defer compiled.deinit();
    var image = compiled.program;
    const blocks = try testing.allocator.dupe(data.activation.Block, image.blocks);
    defer testing.allocator.free(blocks);
    image.blocks = blocks;
    for (blocks) |*block| {
        for (block.instructions, 0..) |write, at| {
            if (write.opcode != .cell_set) continue;
            for (block.instructions[0..at], 0..) |selected, position| {
                if (selected.opcode != .field or selected.immediate != 1 or
                    selected.destination != write.operands[1]) continue;
                const operations = try testing.allocator.alloc(data.activation.Instruction, block.instructions.len + 1);
                defer testing.allocator.free(operations);
                @memcpy(operations[0..block.instructions.len], block.instructions);
                // Store the fresh field, then overwrite the same slot with the
                // older field. End-of-block provenance would miss the bad store.
                operations[position].immediate = 0;
                operations[operations.len - 1] = selected;
                block.instructions = operations;
                try testing.expectError(error.InvalidOwnership, data.activation_ownership.analyze(testing.allocator, image));
                return;
            }
        }
    }
    return error.TestUnexpectedResult;
}

test "stable source installs real handlers and keeps the final checked sum after them" {
    for ([_]usize{ 1, 8, 64, 128, 256 }) |count| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try source.examples.installations(&builder, count));
        defer compiled.deinit();
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        const result = try drive(&session, null);
        try testing.expect(result == .completed);
        try testing.expectEqual(count * (count + 1) / 2, std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
        try testing.expectEqual(0, session.frames.entries.count());
        try testing.expect(session.frames.slots.statistics.value_copies <= 32 * count + 128);
        for (session.store.nodes.items, session.store.alive.items) |node, alive| {
            if (!alive) continue;
            if (node == .continuation) try testing.expectEqual(0, node.continuation.arguments.len);
            if (node == .control) try testing.expectEqual(0, node.control.arguments.len);
        }
    }
}

test "stable source preserves non-tail resumption and handler answer transformation" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.deep(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqual(67, std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
}

test "stable source keeps two one-shot owners across an explicit yield" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.ownership(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    try testing.expect(try drive(&session, null) == .yielded);
    try session.resumeYield();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqual(1, std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
}

test "stable source retains an external request and joins into the same activation" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const boolean = try builder.scalar(bool);
    const unit = try builder.scalar(void);
    const effect = try builder.effect(.{ .identity = "stable/read", .payload = unit, .result = integer });
    const main = try builder.declare(&.{boolean}, integer, &.{effect}, &.{});
    const value = try builder.variable(integer);
    const branch = try builder.term(.{ .conditional = .{
        .condition = try builder.reference(builder.parameter(main, 0)),
        .when_true = try builder.pure(try builder.reference(value)),
        .when_false = try builder.pure(try builder.constant(u64, 9)),
    } });
    const request = try builder.term(.{ .perform = .{
        .effect = effect,
        .payload = try builder.constant(void, {}),
    } });
    try builder.define(main, try builder.bind(value, request, branch));
    var compiled = try source.construct(testing.allocator, builder.module(main, unit));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{1});
    defer session.deinit();
    try testing.expect(try drive(&session, 0) == .progressed);
    const pending = try drive(&session, null);
    try testing.expect(pending == .requested);
    try testing.expectEqual(effect, pending.requested.effect);
    try testing.expectError(error.InvalidValue, session.answer(&.{2}));
    try testing.expect(try session.observe() == .requested);
    try session.answer(&.{ 42, 0, 0, 0, 0, 0, 0, 0 });
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqual(42, std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
}

test "stable source owns its input and keeps tail-recursive control bounded" {
    var builder = source.Builder.init(testing.allocator);
    var compiled = try source.construct(testing.allocator, try source.examples.recursive(&builder));
    var session = initFromImage(testing.allocator, compiled.program, &.{ 16, 39, 0, 0, 0, 0, 0, 0 }) catch |err| {
        compiled.deinit();
        builder.deinit();
        return err;
    };
    defer session.deinit();
    compiled.deinit();
    builder.deinit();
    var result = try drive(&session, 31);
    while (result == .progressed) {
        try testing.expect(session.frames.entries.count() <= 2);
        try testing.expect(session.store.nodes.items.len <= 512);
        result = try drive(&session, 31);
    }
    try testing.expect(result == .completed);
    try testing.expectEqual(1, result.completed.body.scalar[0]);
}

test "stable source resumes an owned package after its handler clause has returned" {
    var b = source.Builder.init(testing.allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const effect = try b.effect(.{ .identity = "stable/escape", .payload = unit, .result = integer, .external = false });
    const cap = try b.schema(.{ .internal = .{ .capability = effect } });
    const token = try b.reserveSchema();
    const package = try b.schema(.{ .internal = .{ .suspension_package = token } });
    const answer = try b.schema(.{ .sum = &.{ integer, package } });
    try b.defineSchema(token, .{ .internal = .{ .resumption = .{
        .effect = effect,
        .input = integer,
        .answer = answer,
        .handled = &.{effect},
        .mode = .deep,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{integer}, answer, &.{}, &.{});
    try b.define(returns, try b.pure(try b.primitive(answer, .variant, &.{try b.reference(b.parameter(returns, 0))}, 0)));
    const clause = try b.declare(&.{ unit, token }, answer, &.{}, &.{});
    const packaged = try b.primitive(package, .package, &.{try b.reference(b.parameter(clause, 1))}, 0);
    try b.define(clause, try b.pure(try b.primitive(answer, .variant, &.{packaged}, 1)));
    const handler = try b.handler(.{ .mode = .deep, .input = integer, .answer = answer, .return_function = returns, .clauses = &.{.{ .effect = effect, .function = clause, .resumption = token }} });
    const body = try b.declare(&.{cap}, integer, &.{effect}, &.{});
    try b.define(body, try b.term(.{ .perform = .{
        .effect = effect,
        .capability = try b.reference(b.parameter(body, 0)),
        .payload = try b.constant(void, {}),
    } }));
    const finish = try b.declare(&.{answer}, integer, &.{}, &.{});
    const ordinary = try b.variable(integer);
    const suspended = try b.variable(package);
    const k = try b.variable(token);
    const resumed = try b.variable(answer);
    const again = try b.term(.{ .call = .{ .function = finish, .arguments = &.{try b.reference(resumed)} } });
    const resume_value = try b.term(.{ .resume_value = .{
        .resumption = try b.reference(k),
        .argument = try b.constant(u64, 42),
    } });
    const recover = try b.bind(k, try b.pure(try b.primitive(token, .unpack, &.{try b.reference(suspended)}, 0)), try b.bind(resumed, resume_value, again));
    try b.define(finish, try b.term(.{ .match_sum = .{
        .value = try b.reference(b.parameter(finish, 0)),
        .cases = &.{
            .{ .variable = ordinary, .body = try b.pure(try b.reference(ordinary)) },
            .{ .variable = suspended, .body = recover },
        },
    } }));
    const main = try b.declare(&.{}, integer, &.{}, &.{});
    const result = try b.variable(answer);
    const signature = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{cap},
        .result = integer,
        .effects = &.{effect},
    } } });
    const handled = try b.term(.{ .handle = .{
        .handler = handler,
        .body = try b.lambda(body, signature),
    } });
    try b.define(main, try b.bind(result, handled, try b.term(.{ .call = .{
        .function = finish,
        .arguments = &.{try b.reference(result)},
    } })));
    var compiled = try source.construct(testing.allocator, b.module(main, unit));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    const observed = try drive(&session, null);
    try testing.expect(observed == .completed);
    try testing.expectEqual(42, std.mem.readInt(u64, observed.completed.body.scalar[0..8], .little));
}

fn failingSession(allocator: std.mem.Allocator, program: boundary.data_v2.activation.Program) !void {
    var session = try initFromImage(allocator, program, &.{});
    defer session.deinit();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
}

test "stable source releases partial native owners at every allocation failure" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.deep(&builder));
    defer compiled.deinit();
    try testing.checkAllAllocationFailures(testing.allocator, failingSession, .{compiled.program});
}

test "stable source preserves multi-shot choice and branch-local versus outer shared cells" {
    const examples = .{ source.examples.choicesAll, source.examples.choicesFirst, source.examples.stateLocal, source.examples.stateShared, source.examples.answers };
    const expected = [_][]const u8{
        &.{ 4, 0, 0, 0, 1, 1, 0, 1, 1 },                                                   &.{ 1, 0, 0 },
        &.{ 2, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0 },                           &.{ 2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0 },
        &.{ 1, 10, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0 },
    };
    inline for (examples, 0..) |example, index| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try example(&builder));
        defer compiled.deinit();
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        const result = try drive(&session, null);
        try testing.expect(result == .completed);
        try testing.expectEqualSlices(u8, expected[index], try session.bytes(&result.completed));
    }
}

test "stable source reenters a live template-cell cycle without sharing branch control" {
    inline for (.{ source.examples.reentrant, source.examples.cloned }) |example| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try example(&builder));
        defer compiled.deinit();
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        var result = try drive(&session, 1);
        var yielded = false;
        while (result == .progressed or result == .yielded) {
            const before = try session.checkpoint(testing.allocator);
            defer testing.allocator.free(before);
            // Replace every private view handle without changing logical values.
            var frames = session.frames.entries.valueIterator();
            while (frames.next()) |frame| {
                const replacement = try session.frames.forkFrame(frame.*);
                session.frames.releaseFrame(frame.*);
                frame.* = replacement;
            }
            // An aggressive correctness lane: every live frame must participate
            // in graph tracing, including the cyclic retained template.
            try session.store.collectWith(session.roots, &session.frames);
            const after = try session.checkpoint(testing.allocator);
            defer testing.allocator.free(after);
            try testing.expectEqualSlices(u8, before, after);
            if (result == .yielded) {
                yielded = true;
                try session.resumeYield();
            }
            result = try drive(&session, 1);
        }
        try testing.expect(yielded and result == .completed);
        try testing.expectEqualSlices(u8, &.{ 113, 0, 0, 0, 0, 0, 0, 0 }, try session.bytes(&result.completed));
    }
}

test "stable source does not read a reclaimed copyable result only assigned to a dead binding" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const unit = try builder.scalar(void);
    const main = try builder.declare(&.{}, integer, &.{}, &.{});
    const unused = try builder.variable(integer);
    try builder.define(main, try builder.bind(unused, try builder.pure(try builder.constant(u64, 7)), try builder.pure(try builder.constant(u64, 42))));
    var compiled = try source.construct(testing.allocator, builder.module(main, unit));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqual(42, result.completed.body.scalar[0]);
}

test "stable retained template preserves an older activation across loop-slot rebindings" {
    const d = boundary.data_v2;
    const program: d.activation.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 2 },
        .schemas = &.{
            .u64,                                  .boolean,                                                                                                                                              .unit,
            .{ .internal = .{ .capability = 0 } }, .{ .internal = .{ .resumption = .{ .effect = 0, .input = 1, .answer = 0, .capture_bound = &.{0}, .handled = &.{0}, .mode = .deep, .use = .multi } } }, .{ .internal = .{ .computation = .{ .parameters = &.{3}, .result = 0, .effects = &.{0} } } },
        },
        .constants = &.{
            .{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } },
            .{ .schema = 0, .bytes = &.{ 2, 0, 0, 0, 0, 0, 0, 0 } },
            .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } },
            .{ .schema = 1, .bytes = &.{0} },
            .{ .schema = 1, .bytes = &.{1} },
            .{ .schema = 2, .bytes = &.{} },
        },
        .effects = &.{.{ .identity = "stable/loop", .payload = 2, .result = 1, .control_use = .multi, .external = false }},
        .functions = &.{
            .{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = &.{ 5, 0 } }, .result = 0 },
            .{ .entry = 2, .inputs = &.{0}, .layout = .{ .slots = &.{ 3, 0, 0, 2, 1, 0, 0, 0, 1, 0 } }, .result = 0, .effects = &.{0} },
            .{ .entry = 5, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
            .{ .entry = 6, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 2, 4, 1, 0, 1, 0, 0 } }, .result = 0 },
        },
        .blocks = &.{
            .{ .function = 0, .instructions = &.{.{ .destination = 0, .opcode = .computation }}, .terminator = .{ .handle = .{ .handler = 0, .body = 0, .arguments = &.{}, .state = &.{}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 1, .source = .returned }} } } } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
            .{ .function = 1, .instructions = &.{
                .{ .destination = 1, .opcode = .constant, .immediate = 0 },
                .{ .destination = 2, .opcode = .constant, .immediate = 1 },
                .{ .destination = 3, .opcode = .constant, .immediate = 5 },
                .{ .destination = 9, .opcode = .constant, .immediate = 2 },
            }, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 3, .next = .{ .block = 3, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
            .{ .function = 1, .instructions = &.{
                .{ .destination = 5, .opcode = .constant, .immediate = 0 },
                .{ .destination = 6, .opcode = .integer_add, .operands = &.{ 1, 5 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 5 }} },
                .{ .destination = 7, .opcode = .integer_sub, .operands = &.{ 2, 5 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 5 }} },
                .{ .destination = 8, .opcode = .equal, .operands = &.{ 7, 9 } },
            }, .terminator = .{ .branch = .{
                .condition = 8,
                .when_true = .{ .block = 4, .assignments = &.{
                    .{ .destination = 1, .source = .{ .slot = 6 } },
                    .{ .destination = 2, .source = .{ .slot = 7 } },
                } },
                .when_false = .{ .block = 3, .assignments = &.{
                    .{ .destination = 1, .source = .{ .slot = 6 } },
                    .{ .destination = 2, .source = .{ .slot = 7 } },
                } },
            } } },
            .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
            .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 3, .instructions = &.{.{ .destination = 2, .opcode = .constant, .immediate = 4 }}, .terminator = .{ .resume_value = .{ .resumption = 1, .argument = 2, .next = .{ .block = 7, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
            .{ .function = 3, .instructions = &.{.{ .destination = 4, .opcode = .constant, .immediate = 3 }}, .terminator = .{ .resume_value = .{ .resumption = 1, .argument = 4, .next = .{ .block = 8, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
            .{ .function = 3, .instructions = &.{.{ .destination = 6, .opcode = .integer_add, .operands = &.{ 3, 5 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 5 }} }}, .terminator = .{ .return_value = 6 } },
        },
        .handlers = &.{.{ .mode = .deep, .input = 0, .answer = 0, .return_function = 2, .clauses = &.{.{ .effect = 0, .function = 3, .resumption = 4 }} }},
        .scopes = .{ .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
        .constructors = &.{.{ .function = 1, .capture = 0, .schema = 5 }},
    };
    var session = try initFromImage(testing.allocator, program, &.{});
    defer session.deinit();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    // Each activation starts at x=1, count=2, then returns 3. The retained
    // template must not inherit the first branch's x=3/count=0 bindings.
    try testing.expectEqual(6, result.completed.body.scalar[0]);
}

test "stable shallow value and computation resumptions omit the original return clause" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.shallowResumptions(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    var result = try drive(&session, 1);
    while (result == .progressed) {
        try session.store.collectWith(session.roots, &session.frames);
        result = try drive(&session, 1);
    }
    try testing.expect(result == .completed);
    const bytes = try session.bytes(&result.completed);
    try testing.expectEqual(64, bytes.len);
    for (0..8) |index| {
        const expected: u64 = if (index < 4) 99 else 42;
        try testing.expectEqual(expected, std.mem.readInt(u64, bytes[index * 8 ..][0..8], .little));
    }
}

test "stable injection selects definition-site versus use-site capabilities" {
    inline for (.{ source.examples.injection, source.examples.shallowInjection }) |example| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try example(&builder));
        defer compiled.deinit();
        for ([_]u8{ 0, 1 }) |injecting| {
            var session = try initFromImage(testing.allocator, compiled.program, &.{injecting});
            defer session.deinit();
            var result = try drive(&session, 1);
            var saw_injection = false;
            while (result == .progressed) {
                for (session.store.nodes.items, session.store.alive.items) |node, alive|
                    if (alive and node == .injection) {
                        saw_injection = true;
                    };
                try session.store.collectWith(session.roots, &session.frames);
                result = try drive(&session, 1);
            }
            try testing.expect(result == .completed);
            try testing.expectEqual(@as(u64, if (injecting == 0) 109 else 209), std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
            try testing.expectEqual(injecting == 1, saw_injection);
        }
    }
}

test "stable successor handling preserves the shallow protocol" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.shallow(&builder));
    defer compiled.deinit();
    for ([_]u8{ 0, 1 }) |invalid| {
        var session = try initFromImage(testing.allocator, compiled.program, &.{invalid});
        defer session.deinit();
        const result = try drive(&session, null);
        if (invalid == 0) {
            try testing.expect(result == .completed);
            try testing.expectEqual(1, result.completed.body.scalar[0]);
        } else {
            try testing.expect(result == .failed);
            try testing.expectEqual(0, (try session.bytes(&result.failed)).len);
        }
    }
}

test "stable cleanup preserves primary failure and resumes external cleanup" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.unwind(&builder));
    defer compiled.deinit();
    for ([_]u8{ 0, 1 }) |primary| {
        var session = try initFromImage(testing.allocator, compiled.program, &.{primary});
        defer session.deinit();
        for ([_][]const u8{ "example/middle-cleanup", "example/outer-cleanup" }) |name| {
            const pending = try drive(&session, null);
            try testing.expect(pending == .requested);
            try testing.expectEqualStrings(name, session.program.effects[@intCast(pending.requested.effect)].identity);
            try session.store.collectWith(session.roots, &session.frames);
            try session.answer(&.{});
        }
        const result = try drive(&session, null);
        try testing.expect(result == .failed);
        try testing.expectEqual(@as(u8, if (primary == 1) 9 else 7), result.failed.body.scalar[0]);
        try testing.expectEqual(2, session.exit.?.cleanup_failures.len);
        try testing.expectEqual(7, session.exit.?.cleanup_failures[0].body.scalar[0]);
        try testing.expectEqual(8, session.exit.?.cleanup_failures[1].body.scalar[0]);
    }
}

test "stable cancellation during yielded cleanup preserves the first reason" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.yieldingCleanup(&builder));
    defer compiled.deinit();
    for ([_]u8{ 0, 1 }) |primary| {
        var session = try initFromImage(testing.allocator, compiled.program, &.{primary});
        defer session.deinit();
        for (0..2) |round| {
            try testing.expect(try drive(&session, null) == .yielded);
            try session.cancel(.{ .text = if (round == 0) "stop" else "later" });
            try session.resumeYield();
            const pending = try drive(&session, null);
            try testing.expect(pending == .requested);
            try session.answer(&.{});
        }
        const result = try drive(&session, null);
        try testing.expect(result == .failed);
        try testing.expectEqual(@as(u8, if (primary == 1) 9 else 7), result.failed.body.scalar[0]);
        try testing.expectEqualStrings("stop", session.exit.?.cancellation.?.text);
    }
}

test "stable unwind preserves lexical and temporary-owner cleanup order" {
    for (0..10) |mode| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try source.examples.custodyOrder(&builder, @intCast(mode)));
        defer compiled.deinit();
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        var requests: usize = 0;
        var yields: usize = 0;
        var result = try drive(&session, 1);
        while (result == .progressed or result == .yielded or result == .requested) {
            if (result == .yielded) {
                yields += 1;
                try session.resumeYield();
            }
            if (result == .requested) {
                try testing.expect(requests < 2);
                const reversed = mode == 1 or mode == 3 or mode >= 4;
                const label: u64 = if (reversed) 2 - requests else requests + 1;
                try testing.expectEqual(label, std.mem.readInt(u64, result.requested.payload.body.scalar[0..8], .little));
                requests += 1;
                try session.answer(&.{});
            }
            try session.store.collectWith(session.roots, &session.frames);
            result = try drive(&session, 1);
        }
        try testing.expect(result == .failed);
        try testing.expectEqual(8, result.failed.body.scalar[0]);
        try testing.expectEqual(2, requests);
        try testing.expectEqual(1, yields);
    }
}

test "stable cancellation preserves cleanup at entry yield request and answered boundaries" {
    var b = source.Builder.init(testing.allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const info = try boundary.library.cleanup.exitInfo(&b, integer);
    const read_effect = try b.effect(.{ .identity = "cancel/read", .payload = unit, .result = integer });
    const release = try b.effect(.{ .identity = "cancel/release", .payload = info, .result = unit });
    const body = try b.declare(&.{}, integer, &.{read_effect}, &.{});
    const request = try b.term(.{ .perform = .{ .effect = read_effect, .payload = try b.constant(void, {}) } });
    const repeated = try b.bind(try b.variable(integer), request, request);
    try b.define(body, try b.term(.{ .yield_then = repeated }));
    const cleanup = try b.declare(&.{info}, unit, &.{release}, &.{});
    try b.define(cleanup, try b.term(.{ .perform = .{ .effect = release, .payload = try b.reference(b.parameter(cleanup, 0)) } }));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = integer,
        .effects = &.{read_effect},
    } } });
    const cleanup_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{info},
        .result = unit,
        .effects = &.{release},
    } } });
    const main = try b.declare(&.{}, integer, &.{ read_effect, release }, &.{});
    try b.define(main, try b.term(.{ .protect = .{
        .body = try b.lambda(body, body_type),
        .cleanup = try b.lambda(cleanup, cleanup_type),
    } }));
    var compiled = try source.construct(testing.allocator, b.module(main, integer));
    defer compiled.deinit();
    for (0..4) |phase| {
        var session = try initFromImage(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        try testing.expectError(error.InvalidUtf8, session.cancel(.{ .text = &.{0xff} }));
        if (phase >= 1) try testing.expect(try drive(&session, null) == .yielded);
        if (phase >= 2) {
            try session.resumeYield();
            const pending = try drive(&session, null);
            try testing.expect(pending == .requested and pending.requested.effect == read_effect);
        }
        if (phase == 3) try session.answer(&.{ 7, 0, 0, 0, 0, 0, 0, 0 });
        try session.cancel(.{ .text = "stop" });
        var result = try drive(&session, null);
        if (phase != 0) {
            try testing.expect(result == .requested and result.requested.effect == release);
            try session.answer(&.{});
            result = try drive(&session, null);
        }
        try testing.expect(result == .cancelled);
        try testing.expectEqualStrings("stop", result.cancelled.text);
        try testing.expectEqual(0, session.exit.?.cleanup_failures.len);
    }
}

test "stable clause failure abandons a captured cleanup without losing its primary exit" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.clauseAbort(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    const pending = try drive(&session, null);
    try testing.expect(pending == .requested);
    try testing.expectEqualStrings("example/abandoned-release", session.program.effects[@intCast(pending.requested.effect)].identity);
    try testing.expectEqualSlices(u8, &.{ 1, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, try session.bytes(&pending.requested.payload));
    try session.store.collectWith(session.roots, &session.frames);
    try session.answer(&.{});
    const result = try drive(&session, null);
    try testing.expect(result == .failed);
    try testing.expectEqual(9, result.failed.body.scalar[0]);
}

test "stable generator resumes private state and closes its retained cleanup" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.generator(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    var yields: usize = 0;
    var releases: usize = 0;
    var result = try drive(&session, 1);
    while (result != .completed) {
        switch (result) {
            .progressed => {},
            .yielded => {
                yields += 1;
                try session.resumeYield();
            },
            .requested => |pending| {
                releases += 1;
                try testing.expectEqualStrings("example/generator-release", session.program.effects[@intCast(pending.effect)].identity);
                try testing.expectEqual(43, pending.payload.body.scalar[0]);
                try session.answer(&.{});
            },
            else => return error.TestUnexpectedResult,
        }
        try session.store.collectWith(session.roots, &session.frames);
        result = try drive(&session, 1);
    }
    try testing.expectEqual(1, yields);
    try testing.expectEqual(1, releases);
    try testing.expectEqualSlices(u8, &.{ 42, 0, 0, 0, 0, 0, 0, 0, 43, 0, 0, 0, 0, 0, 0, 0 }, try session.bytes(&result.completed));
}

test "stable successor return clauses retain older capability and cell references" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.successorState(&builder));
    defer compiled.deinit();
    var session = try initFromImage(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    try testing.expect(try drive(&session, null) == .yielded);
    try session.store.collectWith(session.roots, &session.frames);
    try session.resumeYield();
    const result = try drive(&session, null);
    try testing.expect(result == .completed);
    try testing.expectEqualSlices(u8, &.{ 42, 0, 0, 0, 0, 0, 0, 0, 37, 0, 0, 0, 0, 0, 0, 0 }, try session.bytes(&result.completed));
}
