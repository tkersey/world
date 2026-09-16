// Copyright (c) 2026 World contributors. MIT license.
//! One mutable native resident owner. No mutation escapes a failed drive.
const std = @import("std");
const data = @import("boundary_data_v2");
const protocol = data.invocation;
const runtime = @import("stable_session.zig");
const invocation = @import("invocation.zig");
const heap = @import("store.zig");
pub const Drive = struct { quantum: ?u64 = null, checkpoint: bool = false };
pub const Error = runtime.Error || error{ Busy, UnfinishedSession };

/// Owning, non-copyable by contract. Caller keeps this handle at a stable address
/// while operations are in flight; the gate rejects concurrent/reentrant calls.
pub const Resident = struct {
    session: ?runtime.Session,
    gate: std.atomic.Value(bool) = .init(false),

    pub fn start(allocator: std.mem.Allocator, prepared: *const runtime.Prepared, arguments: []const u8) Error!Resident {
        return .{ .session = try runtime.Session.start(allocator, prepared, arguments) };
    }
    pub fn restore(allocator: std.mem.Allocator, prepared: *const runtime.Prepared, checkpoint_bytes: []const u8) Error!Resident {
        return .{ .session = try runtime.Session.restore(allocator, prepared, checkpoint_bytes) };
    }
    fn enter(self: *Resident) Error!*runtime.Session {
        if (self.gate.cmpxchgStrong(false, true, .acquire, .monotonic) != null) return error.Busy;
        if (self.session) |*session| return session;
        self.gate.store(false, .release);
        return error.InvalidState;
    }
    fn leave(self: *Resident) void {
        self.gate.store(false, .release);
    }

    /// Commit only after detached result/checkpoint buffers exist. Optional
    /// imported-backing compaction may retain its backing on allocation failure.
    pub fn drive(self: *Resident, output: std.mem.Allocator, control: protocol.Control, options: Drive) Error!invocation.Outcome {
        const session = try self.enter();
        defer self.leave();
        var input = std.heap.ArenaAllocator.init(session.allocator);
        defer input.deinit();
        const owned = try heap.duplicate(protocol.Control, input.allocator(), control);
        var transaction = try session.begin();
        errdefer transaction.rollback(session);
        _ = try invocation.advance(session, owned, options.quantum);
        const result = try invocation.finish(output, session, options.checkpoint);
        transaction.commit(session);
        if (session.terminal == null) session.store.compactImported() catch {};
        return result;
    }

    /// Caller-output capacity is checked inside the same transaction as reply
    /// consumption and execution, before publication commits the successor.
    pub fn driveInto(self: *Resident, control: protocol.Control, options: Drive, output: []u8) Error![]const u8 {
        const session = try self.enter();
        defer self.leave();
        var input = std.heap.ArenaAllocator.init(session.allocator);
        defer input.deinit();
        const owned = try heap.duplicate(protocol.Control, input.allocator(), control);
        var transaction = try session.begin();
        errdefer transaction.rollback(session);
        _ = try invocation.advance(session, owned, options.quantum);
        var result = try invocation.finish(session.allocator, session, options.checkpoint);
        defer result.deinit();
        const bytes = try protocol.encode(protocol.Outcome, session.allocator, result.record, output);
        transaction.commit(session);
        if (session.terminal == null) session.store.compactImported() catch {};
        return bytes;
    }

    pub fn checkpoint(self: *Resident, output: std.mem.Allocator) Error![]u8 {
        const session = try self.enter();
        defer self.leave();
        return session.checkpoint(output);
    }
    pub fn takeCheckpoint(self: *Resident, output: std.mem.Allocator) Error![]u8 {
        const session = try self.enter();
        defer self.leave();
        const bytes = try session.checkpoint(output);
        session.deinit();
        self.session = null;
        return bytes;
    }
    /// Physical release is permitted only after terminal observation. Unfinished
    /// execution must complete cancellation/cleanup or transfer a checkpoint.
    pub fn close(self: *Resident) Error!void {
        const session = try self.enter();
        defer self.leave();
        if (session.terminal == null) return error.UnfinishedSession;
        session.deinit();
        self.session = null;
    }
};
