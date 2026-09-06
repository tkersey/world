// Copyright (c) 2026 World contributors. MIT license.
//! One production evaluator for native records and the portable guest ABI.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const g = data.graph;
const Machine = @import("machine.zig").Machine;
pub const Workspace = @import("arena.zig").Arena;

pub const Error = data.image.Error || data.state_admission.Error || data.protocol.Error || data.scalar.Error || error{UnsupportedTransition};
pub const ProgramInput = union(enum) { records: p.Program, image: []const u8 };
pub const Instance = union(enum) { initial_args: []const u8, records: g.State, snapshot: []const u8 };
/// Optional observation of native execution. Counters are never serialized and
/// saturate rather than imposing an execution limit.
pub const Statistics = struct {
    transitions: u64 = 0,
    direct_clauses: u64 = 0,
    one_shot_captures: u64 = 0,
    multi_templates: u64 = 0,
    branch_activations: u64 = 0,
    storage: @import("store.zig").Statistics = .{},
    snapshot: data.snapshot.Statistics = .{},
};
pub const Invocation = struct {
    program: ProgramInput,
    instance: Instance,
    control: data.protocol.Control = .{ .continue_value = null },
    statistics: ?*Statistics = null,
};
pub const Outcome = struct {
    arena: std.heap.ArenaAllocator,
    record: data.protocol.Outcome,
    pub fn deinit(self: *Outcome) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Input admission and every transition complete in private storage before output.
pub fn advance(allocator: std.mem.Allocator, invocation: Invocation) Error!Outcome {
    return execute(allocator, invocation, .advance);
}

/// Runs through internal blocks. There is no semantic fuel or implicit callback.
pub fn run(allocator: std.mem.Allocator, invocation: Invocation) Error!Outcome {
    return execute(allocator, invocation, .run);
}

pub fn invoke(allocator: std.mem.Allocator, input: data.protocol.Input) Error!Outcome {
    return execute(allocator, .{
        .program = .{ .image = input.image },
        .instance = switch (input.instance) {
            .initial_args => |bytes| .{ .initial_args = bytes },
            .state => |bytes| .{ .snapshot = bytes },
        },
        .control = input.control,
    }, input.mode);
}

fn execute(allocator: std.mem.Allocator, invocation: Invocation, mode: data.protocol.Mode) Error!Outcome {
    var decoded: ?data.image.Decoded = null;
    defer if (decoded) |*owner| owner.deinit();
    var normalized: ?data.canonical.Normalized = null;
    defer if (normalized) |*owner| owner.deinit();
    const program = switch (invocation.program) {
        .records => |records| blk: {
            normalized = try data.canonical.normalize(allocator, records);
            break :blk normalized.?.program;
        },
        .image => |bytes| blk: {
            decoded = try data.image.decode(allocator, bytes);
            break :blk decoded.?.program;
        },
    };
    var machine: Machine = .{ .allocator = allocator, .program = program, .identity = try data.image.identity(program), .store = .{ .allocator = allocator, .statistics = if (invocation.statistics) |s| &s.storage else null }, .statistics = invocation.statistics };
    defer machine.store.deinit();
    var saved: ?data.snapshot.Owned = null;
    defer if (saved) |*owner| owner.deinit();
    switch (invocation.instance) {
        .initial_args => |bytes| {
            if (invocation.control != .continue_value or invocation.control.continue_value != null) return error.InvalidControl;
            try machine.initialize(bytes);
        },
        .records, .snapshot => {
            const state = switch (invocation.instance) {
                .records => |records| blk: {
                    try data.state_admission.validate(allocator, program, records);
                    saved = try data.snapshot.canonicalize(allocator, records);
                    break :blk saved.?.state;
                },
                .snapshot => |bytes| blk: {
                    saved = try data.snapshot.decodeGraph(allocator, bytes);
                    break :blk saved.?.state;
                },
                else => unreachable, // Selected State variant.
            };
            try data.state_admission.validate(allocator, program, state);
            try machine.store.import(state);
            machine.roots = state.roots;
            machine.status = state.status;
            if (invocation.control == .cancel) {
                try @import("unwind.zig").cancel(&machine, invocation.control.cancel);
                if (machine.status == .parked) return machine.finish();
            } else if (state.status == .parked) {
                if (invocation.control.continue_value) |bytes| {
                    var parked = try machine.finish();
                    defer parked.deinit();
                    const request = try data.protocol.decode(data.protocol.Request, allocator, parked.record.requested.request);
                    const result = try data.protocol.decode(data.protocol.Result, allocator, bytes);
                    try data.protocol.validateResult(allocator, request, result);
                    const pending = (try machine.store.get(machine.roots.pending.?)).pending;
                    const resumed = try machine.store.literal(program, .{ .schema = program.effects[@intCast(pending.effect)].result, .bytes = result.value });
                    machine.roots.pending = null;
                    machine.status = .active;
                    try machine.resumeContinuation(pending.continuation, resumed);
                } else return machine.finish();
            } else {
                if (invocation.control.continue_value != null) return error.InvalidControl;
                if (machine.status == .yielded) machine.status = .active;
            }
        },
    }
    while (true) {
        if (try machine.step()) |terminal| return terminal;
        try machine.store.collect(machine.roots);
        if ((machine.status != .active and machine.status != .unwinding) or mode == .advance) return machine.finish();
    }
}

test {
    _ = @import("arena.zig");
}
