const std = @import("std");
const data = @import("boundary_data_v2");
const process = @import("process.zig");
const p = data.program;
const g = data.graph;

pub const Kind = enum { active, yielded, continuation, normal_exit, protection, captured };
pub const Witness = struct {
    program: data.canonical.Normalized,
    state: data.snapshot.Owned,

    pub fn deinit(self: *Witness) void {
        self.state.deinit();
        self.program.deinit();
    }
};

pub fn witness(allocator: std.mem.Allocator, kind: Kind) !Witness {
    var result = try base(allocator, kind == .protection or kind == .captured);
    errdefer result.deinit();
    try change(&result.state, result.program.program, kind);
    return result;
}

fn base(allocator: std.mem.Allocator, expanded: bool) !Witness {
    var temporary = std.heap.ArenaAllocator.init(allocator);
    defer temporary.deinit();
    const a = temporary.allocator();
    var original = @import("abandon_tests.zig").program(true);
    if (expanded) try expandEffects(a, &original);
    const blocks = try a.alloc(p.Block, original.blocks.len + 1);
    @memcpy(blocks[0..original.blocks.len], original.blocks);
    const entry = original.functions[@intCast(original.handlers[0].return_function)].entry;
    blocks[original.blocks.len] = blocks[@intCast(entry)];
    blocks[@intCast(entry)].terminator = .{ .yield_value = .{
        .block = original.blocks.len,
        .arguments = &.{.{ .slot = 0 }},
    } };
    original.blocks = blocks;
    var program = try data.canonical.normalize(allocator, original);
    errdefer program.deinit();
    var pending = try process.run(allocator, .{
        .program = .{ .records = program.program },
        .instance = .{ .initial_args = &.{} },
    });
    defer pending.deinit();
    if (pending.record != .requested) return error.ExpectedCleanupRequest;
    var state = try data.snapshot.decodeGraph(allocator, pending.record.requested.state);
    errdefer state.deinit();
    try data.state_admission.validate(allocator, program.program, state.state);
    return .{ .program = program, .state = state };
}

fn expandEffects(a: std.mem.Allocator, program: *p.Program) !void {
    const effects = try a.dupe(p.Effect, program.effects);
    effects[0].external = true;
    program.effects = effects;
    const functions = try a.dupe(p.Function, program.functions);
    functions[0].effects = &.{ 0, 1 };
    program.functions = functions;
    const schemas = try a.dupe(p.Schema, program.schemas);
    schemas[10].internal.resumption.effects = &.{ 0, 1 };
    program.schemas = schemas;
}

fn change(owner: *data.snapshot.Owned, program: p.Program, kind: Kind) !void {
    if (kind == .captured) return captured(owner, program, true);
    const allocator = owner.arena.allocator();
    const state = &owner.state;
    const nodes = @constCast(state.nodes);
    const current = state.roots.pending.?;
    const saved_ref = nodes[@intCast(current.id)].pending.continuation;
    const saved = nodes[@intCast(saved_ref.id)].continuation;
    const handler = program.handlers[0];
    const function = program.functions[@intCast(handler.return_function)];
    const values = try allocator.alloc(g.Value, 1);
    values[0] = .{ .schema = function.parameters[0], .body = .{ .scalar = [_]u8{0} ** 8 } };
    if (kind == .normal_exit) {
        const cleanup = nodes[@intCast(saved.parent.?.id)].cleanup_return;
        const exit = &nodes[@intCast(state.roots.exit.?.id)].exit;
        exit.reason = .{ .normal = values[0] };
        exit.stop = cleanup.parent;
        return;
    }
    const entry = function.entry;
    const selected = if (kind == .yielded or kind == .protection)
        program.blocks[@intCast(entry)].terminator.yield_value.block
    else
        entry;
    nodes[@intCast(current.id)] = .{ .control = .{
        .block = selected,
        .arguments = values,
        .parent = saved_ref,
        .evidence = saved.evidence,
        .region = saved.region,
    } };
    nodes[@intCast(saved_ref.id)] = .{ .disposal_return = .{
        .schema = handler.clauses[0].resumption,
        .parent = saved.parent,
    } };
    state.status = if (kind == .yielded) .yielded else .active;
    state.roots.current = current;
    state.roots.pending = null;
    state.roots.evidence = saved.evidence;
    if (kind == .protection) try protection(owner, program);
    if (kind == .continuation) {
        const extended = try allocator.alloc(g.Node, nodes.len + 1);
        @memcpy(extended[0..nodes.len], nodes);
        extended[nodes.len] = .{ .continuation = .{
            .source_block = program.functions[@intCast(program.roots.entry)].entry,
            .arguments = &.{null},
            .parent = saved_ref,
            .evidence = saved.evidence,
            .region = saved.region,
        } };
        extended[@intCast(current.id)].control.parent = .{ .id = nodes.len };
        state.nodes = extended;
    }
}

fn protection(owner: *data.snapshot.Owned, program: p.Program) !void {
    const state = &owner.state;
    const a = owner.arena.allocator();
    const count = state.nodes.len;
    const nodes = try a.alloc(g.Node, count + 5);
    @memcpy(nodes[0..count], state.nodes);
    const current = &nodes[@intCast(state.roots.current.?.id)].control;
    const disposal = current.parent.?;
    const cleanup_ref = nodes[@intCast(disposal.id)].disposal_return.parent.?;
    const cleanup = nodes[@intCast(cleanup_ref.id)].cleanup_return;
    const source_block = nodes[@intCast(cleanup.obligation.node.id)].obligation.source_block;
    const code = program.blocks[@intCast(source_block)];
    const instruction = code.instructions[
        @intCast(code.terminator.protect.cleanup -
            code.parameters.len)
    ];
    const constructor = program.constructors[@intCast(instruction.immediate)];
    nodes[count] = .{ .environment = .{ .values = &.{}, .tail = null } };
    nodes[count + 1] = .{ .computation = .{
        .constructor = instruction.immediate,
        .environment = .{ .id = count },
    } };
    nodes[count + 2] = .{ .obligation = .{
        .source_block = source_block,
        .status = .pending,
        .cleanup = .{ .schema = constructor.schema, .body = .{
            .reference = .{ .id = count + 1 },
        } },
    } };
    nodes[count + 3] = .{ .continuation = .{
        .source_block = source_block,
        .arguments = &.{null},
        .parent = disposal,
        .evidence = current.evidence,
        .region = current.region,
    } };
    nodes[count + 4] = .{ .protection = .{
        .source_block = source_block,
        .obligation = .{ .node = .{ .id = count + 2 } },
        .return_to = .{ .id = count + 3 },
        .evidence = current.evidence,
        .region = current.region,
    } };
    current.parent = .{ .id = count + 4 };
    state.nodes = nodes;
}

fn captured(owner: *data.snapshot.Owned, program: p.Program, marker: bool) !void {
    const state = &owner.state;
    const a = owner.arena.allocator();
    const count = state.nodes.len;
    const nodes = try a.alloc(g.Node, count + 4 + @intFromBool(marker));
    @memcpy(nodes[0..count], state.nodes);
    const parked = nodes[@intCast(state.roots.pending.?.id)].pending;
    const saved = nodes[@intCast(parked.continuation.id)].continuation;
    const schema = program.handlers[0].clauses[0].resumption;
    var perform: ?p.Id = null;
    for (program.blocks, 0..) |block, id| {
        if (block.terminator == .perform and block.terminator.perform.capability != null) {
            perform = id;
            break;
        }
    }
    nodes[count] = .{ .handler = .{
        .definition = 0,
        .state = &.{},
        .evidence = saved.evidence,
        .region = saved.region,
    } };
    nodes[count + 1] = .{ .attachment = .{
        .handler = .{ .id = count },
        .outer = saved.evidence,
        .return_to = null,
        .phase = .suspended,
        .region = saved.region,
    } };
    nodes[count + 2] = .{ .continuation = .{
        .source_block = perform orelse return error.ExpectedHandledOperation,
        .arguments = &.{null},
        .parent = .{ .id = if (marker) count + 4 else count + 1 },
        .evidence = .{ .id = count + 1 },
        .region = saved.region,
    } };
    nodes[count + 3] = .{ .one_shot = .{
        .schema = schema,
        .capture = .{ .id = count + 2 },
        .delimiter = .{ .id = count + 1 },
        .evidence = .{ .id = count + 1 },
    } };
    if (marker) nodes[count + 4] = .{ .disposal_return = .{
        .schema = schema,
        .parent = .{ .id = count + 1 },
    } };
    state.nodes = nodes;
    const value: g.Value = .{ .schema = schema, .body = .{
        .owned = .{ .node = .{ .id = count + 3 } },
    } };
    nodes[@intCast(state.roots.exit.?.id)].exit.discarded = try a.dupe(g.Value, &.{value});
}

test "normal returns cannot enter disposal markers directly or through saved control" {
    const allocator = std.testing.allocator;
    for (std.enums.values(Kind)) |kind| {
        var example = try witness(allocator, kind);
        defer example.deinit();
        try std.testing.expectError(error.InvalidState, data.state_admission.validate(
            allocator,
            example.program.program,
            example.state.state,
        ));
        const invocation: process.Invocation = .{
            .program = .{ .records = example.program.program },
            .instance = .{ .records = example.state.state },
        };
        try std.testing.expectError(error.InvalidState, process.advance(allocator, invocation));
        try std.testing.expectError(error.InvalidState, process.run(allocator, invocation));
    }
}

test "a captured return path remains admissible during cleanup when it reaches its delimiter" {
    const allocator = std.testing.allocator;
    var example = try base(allocator, true);
    defer example.deinit();
    try captured(&example.state, example.program.program, false);
    try data.state_admission.validate(allocator, example.program.program, example.state.state);
    var outcome = try process.run(allocator, .{
        .program = .{ .records = example.program.program },
        .instance = .{ .records = example.state.state },
    });
    defer outcome.deinit();
    try std.testing.expect(outcome.record == .requested);
}
