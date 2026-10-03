// Copyright (c) 2026 World contributors. MIT license.
//! One mutable native resident owner. No mutation escapes a failed drive.
const std = @import("std");
const data = @import("boundary_data");
const protocol = data.invocation;
const runtime = @import("stable_session.zig");
const invocation = @import("invocation.zig");
const heap = @import("store.zig");
const Statistics = @import("runtime_types.zig").Statistics;
pub const Drive = struct { quantum: ?u64 = null, checkpoint: bool = false };
pub const Error = runtime.Error || error{ Busy, UnfinishedSession };

const State = struct {
    session: runtime.Session,
    expected: ?[32]u8 = null,
};

/// Read-only, non-contractual diagnostics. No mutable engine reference escapes.
pub const Diagnostics = struct {
    frames: usize,
    nodes: usize,
    transitions: usize,
    collection_cursors: usize,
    pending_blob_collection: bool,
    imported_backing: bool,
    slots: @import("activation_slots.zig").ActivationSlots.Statistics,
    custody: @import("custody.zig").Nodes.Statistics,
    transactions: @import("activation_frames.zig").Frames.Statistics,
};

/// Owning, non-copyable by contract. Caller keeps this handle at a stable address
/// while operations are in flight; the gate rejects concurrent/reentrant calls.
pub const Resident = struct {
    // Inline private representation preserves the existing allocation domain.
    // Only owner() interprets these bytes; native low-level mutation belongs to
    // the separate Session API, which always recomputes expected bindings.
    storage: [@sizeOf(State)]u8 align(@alignOf(State)) = undefined,
    live: bool = false,
    gate: std.atomic.Value(bool) = .init(false),

    pub fn start(allocator: std.mem.Allocator, prepared: *const runtime.Prepared, arguments: []const u8) Error!Resident {
        var result: Resident = .{};
        result.owner().* = .{ .session = try runtime.Session.start(allocator, prepared, arguments) };
        result.live = true;
        return result;
    }
    pub fn restore(allocator: std.mem.Allocator, prepared: *const runtime.Prepared, checkpoint_bytes: []const u8) Error!Resident {
        var result: Resident = .{};
        result.owner().* = .{ .session = try runtime.Session.restore(allocator, prepared, checkpoint_bytes) };
        result.live = true;
        return result;
    }
    fn owner(self: *Resident) *State {
        return @ptrCast(&self.storage);
    }
    fn enter(self: *Resident) Error!*State {
        if (self.gate.cmpxchgStrong(false, true, .acquire, .monotonic) != null) return error.Busy;
        if (self.live) return self.owner();
        self.gate.store(false, .release);
        return error.InvalidState;
    }
    fn leave(self: *Resident) void {
        // No mutable engine borrow escapes this closed owner. Its next drive
        // need not protect pointers whose entire operation has already ended.
        if (self.live) self.owner().session.frames.endMutableBorrows();
        self.gate.store(false, .release);
    }

    const Destination = union(enum) { record: std.mem.Allocator, encoded: std.mem.Allocator, buffer: []u8 };
    const Published = union(enum) { record: invocation.Outcome, encoded: []u8, buffer: []const u8 };

    /// Every publication route shares one commit fence, including allocation of
    /// encoded output. No encoder/capacity failure may follow that fence.
    fn publish(self: *Resident, destination: Destination, control: protocol.Control, options: Drive) Error!Published {
        const state = try self.enter();
        defer self.leave();
        const session = &state.session;
        var input = std.heap.ArenaAllocator.init(session.allocator);
        defer input.deinit();
        const owned = try heap.duplicate(protocol.Control, input.allocator(), control);
        // Restoration starts without private metadata. Establish it from the
        // admitted parked state once; a rejected reply may keep this exact fact.
        if (owned == .reply and state.expected == null) {
            var pending = try session.pendingRequest(session.allocator);
            defer pending.deinit();
            state.expected = pending.request.request_identity;
        }
        const expected = state.expected;
        errdefer state.expected = expected;
        var transaction = try session.begin();
        errdefer transaction.rollback(session);
        if (owned == .reply) {
            if (session.statistics) |statistics| statistics.reused_expected_bindings +|= 1;
            try @import("response.zig").answer(session, owned.reply, state.expected.?);
            state.expected = null;
            _ = try session.run(options.quantum);
        } else {
            if (owned != .none) state.expected = null;
            _ = try invocation.advance(session, owned, options.quantum);
        }
        const published: Published = switch (destination) {
            .record => |allocator| .{ .record = try invocation.finishObserved(allocator, session, options.checkpoint, &state.expected) },
            .encoded, .buffer => blk: {
                var result = try invocation.finishObserved(session.allocator, session, options.checkpoint, &state.expected);
                defer result.deinit();
                break :blk switch (destination) {
                    .encoded => |allocator| .{ .encoded = try protocol.encodeOwned(protocol.Outcome, allocator, result.record) },
                    .buffer => |buffer| .{ .buffer = try protocol.encode(protocol.Outcome, session.allocator, result.record, buffer) },
                    else => unreachable,
                };
            },
        };
        transaction.commit(session);
        session.store.compactImported() catch {};
        return published;
    }

    pub fn drive(self: *Resident, output: std.mem.Allocator, control: protocol.Control, options: Drive) Error!invocation.Outcome {
        return (try self.publish(.{ .record = output }, control, options)).record;
    }
    pub fn driveEncoded(self: *Resident, output: std.mem.Allocator, control: protocol.Control, options: Drive) Error![]u8 {
        return (try self.publish(.{ .encoded = output }, control, options)).encoded;
    }
    pub fn driveInto(self: *Resident, control: protocol.Control, options: Drive, output: []u8) Error![]const u8 {
        return (try self.publish(.{ .buffer = output }, control, options)).buffer;
    }

    pub fn checkpoint(self: *Resident, output: std.mem.Allocator) Error![]u8 {
        const state = try self.enter();
        defer self.leave();
        return state.session.checkpoint(output);
    }
    pub fn takeCheckpoint(self: *Resident, output: std.mem.Allocator) Error![]u8 {
        const state = try self.enter();
        defer self.leave();
        const bytes = try state.session.checkpoint(output);
        state.session.deinit();
        state.expected = null;
        self.live = false;
        return bytes;
    }
    /// Physical release is permitted only after terminal observation. Unfinished
    /// execution must complete cancellation/cleanup or transfer a checkpoint.
    pub fn close(self: *Resident) Error!void {
        const state = try self.enter();
        defer self.leave();
        if (state.session.terminal == null) return error.UnfinishedSession;
        state.session.deinit();
        state.expected = null;
        self.live = false;
    }

    /// Counters are caller-owned and must outlive their attachment to this handle.
    pub fn setStatistics(self: *Resident, statistics: ?*Statistics) Error!void {
        const state = try self.enter();
        defer self.leave();
        state.session.statistics = statistics;
        state.session.store.statistics = if (statistics) |s| &s.storage else null;
    }
    pub fn diagnostics(self: *Resident) Error!Diagnostics {
        const state = try self.enter();
        defer self.leave();
        const session = &state.session;
        return .{
            .frames = session.frames.entries.count(),
            .nodes = session.store.nodes.items.len,
            .transitions = session.transitions,
            .collection_cursors = session.collection_cursors,
            .pending_blob_collection = session.pending_blob_collection,
            .imported_backing = session.store.imported != null,
            .slots = session.frames.slots.statistics,
            .custody = session.frames.custody.nodes.statistics,
            .transactions = session.frames.statistics,
        };
    }
};
