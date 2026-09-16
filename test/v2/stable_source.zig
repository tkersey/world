const std = @import("std");
const boundary = @import("boundary");
const source = boundary.source;
const Session = @import("stable_runtime").Session;
const testing = std.testing;

test "stable source installs real handlers and keeps the final checked sum after them" {
    for ([_]usize{ 1, 8, 64, 128, 256 }) |count| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try source.construct(testing.allocator, try source.examples.installations(&builder, count));
        defer compiled.deinit();
        var session = try Session.init(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        const result = try session.run(null);
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
    var session = try Session.init(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    const result = try session.run(null);
    try testing.expect(result == .completed);
    try testing.expectEqual(67, std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
}

test "stable source keeps two one-shot owners across an explicit yield" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try source.construct(testing.allocator, try source.examples.ownership(&builder));
    defer compiled.deinit();
    var session = try Session.init(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    try testing.expect(try session.run(null) == .yielded);
    try session.resumeYield();
    const result = try session.run(null);
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
    var session = try Session.init(testing.allocator, compiled.program, &.{1});
    defer session.deinit();
    try testing.expect(try session.run(0) == .progressed);
    const pending = try session.run(null);
    try testing.expect(pending == .requested);
    try testing.expectEqual(effect, pending.requested.effect);
    try testing.expectError(error.InvalidValue, session.answer(&.{2}));
    try testing.expect(try session.observe() == .requested);
    try session.answer(&.{ 42, 0, 0, 0, 0, 0, 0, 0 });
    const result = try session.run(null);
    try testing.expect(result == .completed);
    try testing.expectEqual(42, std.mem.readInt(u64, result.completed.body.scalar[0..8], .little));
}

test "stable source owns its input and keeps tail-recursive control bounded" {
    var builder = source.Builder.init(testing.allocator);
    var compiled = try source.construct(testing.allocator, try source.examples.recursive(&builder));
    var session = Session.init(testing.allocator, compiled.program, &.{ 16, 39, 0, 0, 0, 0, 0, 0 }) catch |err| {
        compiled.deinit();
        builder.deinit();
        return err;
    };
    defer session.deinit();
    compiled.deinit();
    builder.deinit();
    var result = try session.run(31);
    while (result == .progressed) {
        try testing.expect(session.frames.entries.count() <= 2);
        try testing.expect(session.store.nodes.items.len <= 512);
        result = try session.run(31);
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
    var session = try Session.init(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    const observed = try session.run(null);
    try testing.expect(observed == .completed);
    try testing.expectEqual(42, std.mem.readInt(u64, observed.completed.body.scalar[0..8], .little));
}

fn failingSession(allocator: std.mem.Allocator, program: boundary.data_v2.activation.Program) !void {
    var session = try Session.init(allocator, program, &.{});
    defer session.deinit();
    const result = try session.run(null);
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
        var session = try Session.init(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        const result = try session.run(null);
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
        var session = try Session.init(testing.allocator, compiled.program, &.{});
        defer session.deinit();
        var result = try session.run(1);
        var yielded = false;
        while (result == .progressed or result == .yielded) {
            // An aggressive correctness lane: every live frame must participate
            // in graph tracing, including the cyclic retained template.
            try session.store.collectWith(session.roots, &session.frames);
            if (result == .yielded) {
                yielded = true;
                try session.resumeYield();
            }
            result = try session.run(1);
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
    var session = try Session.init(testing.allocator, compiled.program, &.{});
    defer session.deinit();
    const result = try session.run(null);
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
    var session = try Session.init(testing.allocator, program, &.{});
    defer session.deinit();
    const result = try session.run(null);
    try testing.expect(result == .completed);
    // Each activation starts at x=1, count=2, then returns 3. The retained
    // template must not inherit the first branch's x=3/count=0 bindings.
    try testing.expectEqual(6, result.completed.body.scalar[0]);
}
