// Copyright (c) 2026 World contributors. MIT license.
//! Private control-node bindings. Every registered frame owns one slot view.
const std = @import("std");
const data = @import("boundary_data_v2");
const Slots = @import("activation_slots.zig").ActivationSlots;
const sets = data.analysis_sets;
pub const Error = Slots.Error || data.snapshot.Error;
pub const Frame = struct {
    view: Slots.Handle,
    present: sets.Root = sets.empty,
    position: usize = 0,
    custody: data.program.Id = 0,
};
pub const Frames = struct {
    allocator: std.mem.Allocator,
    slots: Slots,
    pool: *sets.Pool,
    entries: std.AutoHashMapUnmanaged(data.program.Id, Frame) = .empty,

    pub fn init(allocator: std.mem.Allocator, pool: *sets.Pool) Error!Frames {
        return .{ .allocator = allocator, .slots = try Slots.init(allocator), .pool = pool };
    }
    pub fn deinit(self: *Frames) void {
        self.entries.deinit(self.allocator);
        self.slots.deinit();
        self.* = undefined;
    }
    pub fn get(self: *Frames, id: data.program.Id) Error!Frame {
        return self.entries.get(id) orelse error.InvalidState;
    }
    pub fn put(self: *Frames, id: data.program.Id, frame: Frame) Error!void {
        if (self.entries.contains(id)) return error.InvalidState;
        try self.entries.put(self.allocator, id, frame);
    }
    pub fn update(self: *Frames, id: data.program.Id, frame: Frame) void {
        self.entries.getPtr(id).?.* = frame;
    }
    pub fn move(self: *Frames, from: data.program.Id, to: data.program.Id) Error!Frame {
        if (self.entries.contains(to)) return error.InvalidState;
        try self.entries.ensureUnusedCapacity(self.allocator, 1);
        const frame = (self.entries.fetchRemove(from) orelse return error.InvalidState).value;
        self.entries.putAssumeCapacity(to, frame);
        return frame;
    }
    pub fn remove(self: *Frames, id: data.program.Id) void {
        if (self.entries.fetchRemove(id)) |entry|
            self.slots.release(entry.value.view) catch unreachable;
    }
    pub fn write(self: *Frames, frame: *Frame, slot: data.program.Id, value: data.graph.Value) Error!void {
        const present = try self.pool.insert(frame.present, slot);
        try self.slots.set(frame.view, @intCast(slot), value);
        frame.present = present;
    }
    pub fn clear(self: *Frames, frame: *Frame, slot: data.program.Id) Error!void {
        const present = try self.pool.remove(frame.present, slot);
        try self.slots.clear(frame.view, @intCast(slot));
        frame.present = present;
    }
    pub fn prune(self: *Frames, frame: *Frame, live: sets.Root) Error!void {
        const removed = try self.pool.difference(frame.present, live);
        var iterator = self.pool.iterator(removed);
        while (iterator.next()) |slot| try self.clear(frame, slot);
    }
    pub fn copyFrame(self: *Frames, from: data.program.Id, to: data.program.Id) data.snapshot.Error!void {
        var copy = self.entries.get(from) orelse return;
        if (self.entries.contains(to)) return error.InvalidState;
        copy.view = self.slots.fork(copy.view) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.InvalidState,
        };
        errdefer self.slots.release(copy.view) catch unreachable;
        try self.entries.put(self.allocator, to, copy);
    }

    pub fn rebaseFrame(self: *Frames, id: data.program.Id, map: anytype) data.snapshot.Error!void {
        var frame = self.entries.get(id) orelse return;
        var members = self.pool.iterator(frame.present);
        while (members.next()) |slot| {
            var value = self.slots.get(frame.view, @intCast(slot)) catch return error.InvalidState;
            const reference = switch (value.body) {
                .reference => |*ref| ref,
                .owned => |*owned| &owned.node,
                else => continue,
            };
            const replacement = map.get(reference.id) orelse continue;
            reference.* = replacement;
            self.write(&frame, slot, value) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.InvalidState,
            };
        }
        self.update(id, frame);
    }

    pub fn references(self: *Frames, id: data.program.Id, output: *std.ArrayList(data.snapshot.Reference), allocator: std.mem.Allocator) data.snapshot.Error!void {
        const frame = self.entries.get(id) orelse return;
        var iterator = self.slots.iterator(frame.view) catch return error.InvalidState;
        while (iterator.next() catch return error.InvalidState) |binding|
            try data.snapshot.references(data.graph.Value, binding.value, output, allocator);
    }
};
