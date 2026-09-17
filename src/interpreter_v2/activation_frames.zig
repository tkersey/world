// Copyright (c) 2026 World contributors. MIT license.
//! Private control-node bindings. Every registered frame owns one slot view.
const std = @import("std");
const data = @import("boundary_data");
const Slots = @import("activation_slots.zig").ActivationSlots;
const sets = data.analysis_sets;
const custody = @import("custody.zig");
pub const Error = Slots.Error || data.graph_order.Error;
/// Runtime initialization is not an authority or a liveness declaration. Small
/// layouts need no interned analysis nodes; large layouts keep compact trees.
pub const Present = union(enum) {
    bits: u64,
    tree: sets.Root,

    fn changed(self: Present, pool: *sets.Pool, slot: u64, add: bool) Error!Present {
        return switch (self) {
            .bits => |bits| blk: {
                if (slot >= 64) return error.InvalidSlot;
                const bit = @as(u64, 1) << @intCast(slot);
                break :blk .{ .bits = if (add) bits | bit else bits & ~bit };
            },
            .tree => |root| .{ .tree = if (add)
                try pool.insert(root, slot)
            else
                try pool.remove(root, slot) },
        };
    }
    pub fn contains(self: Present, pool: *const sets.Pool, slot: u64) bool {
        return switch (self) {
            .bits => |bits| slot < 64 and bits & (@as(u64, 1) << @intCast(slot)) != 0,
            .tree => |root| pool.contains(root, slot),
        };
    }
    fn iterator(self: Present, pool: *const sets.Pool) Iterator {
        return switch (self) {
            .bits => |bits| .{ .bits = bits },
            .tree => |root| .{ .tree = pool.iterator(root) },
        };
    }
    const Iterator = union(enum) {
        bits: u64,
        tree: sets.Iterator,
        fn next(self: *Iterator) ?u64 {
            return switch (self.*) {
                .bits => |*bits| blk: {
                    if (bits.* == 0) break :blk null;
                    const slot = @ctz(bits.*);
                    bits.* &= bits.* - 1;
                    break :blk slot;
                },
                .tree => |*tree| tree.next(),
            };
        }
    };
};
pub const Frame = struct {
    view: Slots.Handle,
    present: Present,
    position: usize = 0,
    function: data.program.Id,
    custody: custody.State,
};
pub const Frames = struct {
    allocator: std.mem.Allocator,
    slots: Slots,
    pool: *sets.Pool,
    program: data.activation.Program,
    custody: custody.Custody,
    entries: std.AutoHashMapUnmanaged(data.program.Id, Frame) = .empty,

    pub const Backup = struct {
        entries: std.AutoHashMapUnmanaged(data.program.Id, Frame) = .empty,
        pub fn discard(self: *Backup, frames: *Frames) void {
            var values = self.entries.valueIterator();
            while (values.next()) |frame| frames.releaseFrame(frame.*);
            self.entries.deinit(frames.allocator);
            self.* = .{};
        }
        pub fn restore(self: *Backup, frames: *Frames) void {
            var current = frames.entries.valueIterator();
            while (current.next()) |frame| frames.releaseFrame(frame.*);
            frames.entries.deinit(frames.allocator);
            frames.entries = self.entries;
            self.* = .{};
        }
    };

    /// Fork only view roots and custody handles, never their value descriptors.
    pub fn backup(self: *Frames) Error!Backup {
        var saved: Backup = .{};
        errdefer saved.discard(self);
        try saved.entries.ensureTotalCapacity(self.allocator, self.entries.count());
        var entries = self.entries.iterator();
        while (entries.next()) |entry| {
            const frame = try self.forkFrame(entry.value_ptr.*);
            saved.entries.putAssumeCapacity(entry.key_ptr.*, frame);
        }
        return saved;
    }

    pub fn init(allocator: std.mem.Allocator, pool: *sets.Pool, program: data.activation.Program) Error!Frames {
        var slots = try Slots.init(allocator);
        errdefer slots.deinit();
        return .{ .allocator = allocator, .slots = slots, .pool = pool, .program = program, .custody = try custody.Custody.init(allocator) };
    }
    pub fn deinit(self: *Frames) void {
        self.entries.deinit(self.allocator);
        self.slots.deinit();
        self.custody.deinit();
        self.* = undefined;
    }
    pub fn get(self: *Frames, id: data.program.Id) Error!Frame {
        return self.entries.get(id) orelse error.InvalidState;
    }
    pub fn project(self: *Frames, id: data.program.Id, allocator: std.mem.Allocator) Error!?data.process_state.Activation {
        const frame = self.entries.get(id) orelse return null;
        var bindings: std.ArrayList(data.process_state.Binding) = .empty;
        errdefer bindings.deinit(allocator);
        var iterator = try self.slots.iterator(frame.view);
        while (try iterator.next()) |binding|
            try bindings.append(allocator, .{ .slot = binding.slot, .value = binding.value });
        const owners = try self.custody.project(frame.custody, allocator);
        errdefer allocator.free(owners);
        return .{ .position = frame.position, .scope = frame.custody.scope, .bindings = try bindings.toOwnedSlice(allocator), .owners = owners };
    }
    /// The caller admits the complete portable State before materializing views.
    pub fn restore(self: *Frames, id: data.program.Id, function: data.program.Id, activation: data.process_state.Activation) Error!void {
        var frame = try self.create(function);
        errdefer self.releaseFrame(frame);
        for (activation.bindings) |binding| try self.rewriteValue(&frame, binding.slot, binding.value);
        try self.custody.restore(&frame.custody, self.program.functions[@intCast(function)].custody, @intCast(activation.scope), activation.owners);
        frame.position = @intCast(activation.position);
        try self.put(id, frame);
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
        if (self.entries.fetchRemove(id)) |entry| self.releaseFrame(entry.value);
    }
    pub fn create(self: *Frames, function: data.program.Id) Error!Frame {
        const definition = self.program.functions[@intCast(function)];
        const view = try self.slots.create(definition.layout.slots.len);
        errdefer self.slots.release(view) catch unreachable;
        return .{ .view = view, .function = function, .present = if (definition.layout.slots.len <= 64)
            .{ .bits = 0 }
        else
            .{ .tree = sets.empty }, .custody = try self.custody.create(definition.layout.slots.len, definition.custody.len) };
    }
    pub fn releaseFrame(self: *Frames, frame: Frame) void {
        self.slots.release(frame.view) catch unreachable;
        self.custody.release(frame.custody);
    }
    pub fn forkFrame(self: *Frames, original: Frame) Error!Frame {
        var result = original;
        result.view = try self.slots.fork(original.view);
        errdefer self.slots.release(result.view) catch unreachable;
        result.custody = try self.custody.fork(original.custody);
        return result;
    }
    pub fn scope(self: *Frames, frame: *Frame, target: data.program.Id) Error!void {
        try self.custody.moveTo(&frame.custody, self.program.functions[@intCast(frame.function)].custody, @intCast(target));
    }
    pub fn write(self: *Frames, frame: *Frame, slot: data.program.Id, value: data.graph.Value) Error!void {
        try self.custody.remove(&frame.custody, @intCast(slot));
        if (value.body == .owned) try self.custody.establish(&frame.custody, self.program.functions[@intCast(frame.function)].custody, @intCast(slot));
        try self.rewriteValue(frame, slot, value);
    }
    fn rewriteValue(self: *Frames, frame: *Frame, slot: data.program.Id, value: data.graph.Value) Error!void {
        const present = try frame.present.changed(self.pool, slot, true);
        try self.slots.set(frame.view, @intCast(slot), value);
        frame.present = present;
    }
    pub fn discards(self: *Frames, id: data.program.Id) Error![]data.graph.Value {
        const frame = try self.get(id);
        const ordered = try self.custody.ordered(frame.custody, self.allocator);
        defer self.allocator.free(ordered);
        const values = try self.allocator.alloc(data.graph.Value, ordered.len);
        errdefer self.allocator.free(values);
        for (values, ordered) |*value, slot| value.* = try self.slots.get(frame.view, slot);
        return values;
    }
    pub fn clear(self: *Frames, frame: *Frame, slot: data.program.Id) Error!void {
        const present = try frame.present.changed(self.pool, slot, false);
        try self.custody.remove(&frame.custody, @intCast(slot));
        try self.slots.clear(frame.view, @intCast(slot));
        frame.present = present;
    }
    pub fn prune(self: *Frames, frame: *Frame, live: sets.Root) Error!void {
        var retained: Present = undefined;
        const removed: Present = switch (frame.present) {
            .bits => |bits| blk: {
                const mask = self.pool.lowWord(live);
                retained = .{ .bits = bits & mask };
                if (bits & ~mask == 0) return;
                break :blk .{ .bits = bits & ~mask };
            },
            .tree => |root| blk: {
                retained = .{ .tree = try self.pool.intersect(root, live) };
                if (retained.tree == root) return;
                break :blk .{ .tree = try self.pool.difference(root, live) };
            },
        };
        var iterator = removed.iterator(self.pool);
        while (iterator.next()) |slot| {
            try self.custody.remove(&frame.custody, @intCast(slot));
            try self.slots.clear(frame.view, @intCast(slot));
        }
        // Publish one set root after the complete private transition. Callers
        // discard/poison failed frames or restore Resident's retained backup.
        frame.present = retained;
    }
    pub fn copyFrame(self: *Frames, from: data.program.Id, to: data.program.Id) data.graph_order.Error!void {
        var copy = self.entries.get(from) orelse return;
        if (self.entries.contains(to)) return error.InvalidState;
        copy = self.forkFrame(copy) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.InvalidState,
        };
        errdefer self.releaseFrame(copy);
        try self.entries.put(self.allocator, to, copy);
    }

    pub fn rebaseFrame(self: *Frames, id: data.program.Id, map: anytype) data.graph_order.Error!void {
        var frame = self.entries.get(id) orelse return;
        var members = frame.present.iterator(self.pool);
        while (members.next()) |slot| {
            var value = self.slots.get(frame.view, @intCast(slot)) catch return error.InvalidState;
            const reference = switch (value.body) {
                .reference => |*ref| ref,
                .owned => |*owned| &owned.node,
                else => continue,
            };
            const replacement = map.get(reference.id) orelse continue;
            reference.* = replacement;
            self.rewriteValue(&frame, slot, value) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.InvalidState,
            };
        }
        self.update(id, frame);
    }

    pub fn references(self: *Frames, id: data.program.Id, output: *std.ArrayList(data.graph_order.Reference), allocator: std.mem.Allocator) data.graph_order.Error!void {
        const frame = self.entries.get(id) orelse return;
        var iterator = self.slots.iterator(frame.view) catch return error.InvalidState;
        while (iterator.next() catch return error.InvalidState) |binding|
            try data.graph_order.references(data.graph.Value, binding.value, output, allocator);
    }
};
