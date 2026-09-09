// Copyright (c) 2026 World contributors. MIT license.
//! Stable transient handles over Boundary's logical node kinds.
const std = @import("std");
const data = @import("boundary_data_v2");
const g = data.graph;
pub const Error = data.snapshot.Error;
const empty: g.Node = .{ .environment = .{ .values = &.{}, .tail = null } };

pub const Statistics = struct {
    added_nodes: u64 = 0,
    copied_blob_bytes: u64 = 0,
    traced_nodes: u64 = 0,
    traced_edges: u64 = 0,
    swept_slots: u64 = 0,
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    statistics: ?*Statistics = null,
    nodes: std.ArrayList(g.Node) = .empty,
    alive: std.ArrayList(bool) = .empty,
    free_nodes: std.ArrayList(usize) = .empty,
    blobs: std.ArrayList(g.Blob) = .empty,
    blob_alive: std.ArrayList(bool) = .empty,
    free_blobs: std.ArrayList(usize) = .empty,
    interned: std.HashMapUnmanaged(g.Blob, usize, BlobContext, 80) = .empty,

    pub fn deinit(self: *Store) void {
        for (self.nodes.items, self.alive.items) |item, live| if (live) release(g.Node, self.allocator, item);
        for (self.blobs.items, self.blob_alive.items) |blob, live| if (live) self.allocator.free(blob.bytes);
        self.nodes.deinit(self.allocator);
        self.alive.deinit(self.allocator);
        self.free_nodes.deinit(self.allocator);
        self.blobs.deinit(self.allocator);
        self.blob_alive.deinit(self.allocator);
        self.free_blobs.deinit(self.allocator);
        self.interned.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn add(self: *Store, value: g.Node) Error!g.NodeRef {
        const copied = try duplicate(g.Node, self.allocator, value);
        errdefer release(g.Node, self.allocator, copied);
        if (self.free_nodes.pop()) |id| {
            self.nodes.items[id] = copied;
            self.alive.items[id] = true;
            if (self.statistics) |s| s.added_nodes +|= 1;
            return .{ .id = id };
        }
        try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.alive.ensureUnusedCapacity(self.allocator, 1);
        const id = self.nodes.items.len;
        self.nodes.appendAssumeCapacity(copied);
        self.alive.appendAssumeCapacity(true);
        if (self.statistics) |s| s.added_nodes +|= 1;
        return .{ .id = id };
    }

    pub fn get(self: Store, reference: g.NodeRef) Error!g.Node {
        if (reference.id >= self.nodes.items.len or !self.alive.items[@intCast(reference.id)]) return error.InvalidReference;
        return self.nodes.items[@intCast(reference.id)];
    }

    pub fn replace(self: *Store, reference: g.NodeRef, value: g.Node) Error!void {
        const previous = try self.get(reference);
        const replacement = try duplicate(g.Node, self.allocator, value);
        self.nodes.items[@intCast(reference.id)] = replacement;
        release(g.Node, self.allocator, previous);
    }

    pub fn literal(self: *Store, program: data.program.Program, value: data.program.Literal) Error!g.Value {
        if (data.scalar.width(program.schemas[@intCast(value.schema)])) |width| {
            var scalar = [_]u8{0} ** 8;
            @memcpy(scalar[0..width], value.bytes);
            return .{ .schema = value.schema, .body = .{ .scalar = scalar } };
        }
        const key: g.Blob = .{ .schema = value.schema, .bytes = value.bytes };
        if (self.interned.get(key)) |id| return .{ .schema = value.schema, .body = .{ .blob = .{ .id = id } } };
        const copied: g.Blob = .{ .schema = value.schema, .bytes = try self.allocator.dupe(u8, value.bytes) };
        errdefer self.allocator.free(copied.bytes);
        try self.interned.ensureUnusedCapacity(self.allocator, 1);
        const id = if (self.free_blobs.pop()) |free| blk: {
            self.blobs.items[free] = copied;
            self.blob_alive.items[free] = true;
            break :blk free;
        } else blk: {
            try self.blobs.ensureUnusedCapacity(self.allocator, 1);
            try self.blob_alive.ensureUnusedCapacity(self.allocator, 1);
            const id = self.blobs.items.len;
            self.blobs.appendAssumeCapacity(copied);
            self.blob_alive.appendAssumeCapacity(true);
            break :blk id;
        };
        self.interned.putAssumeCapacity(copied, id);
        if (self.statistics) |s| s.copied_blob_bytes +|= copied.bytes.len;
        return .{ .schema = value.schema, .body = .{ .blob = .{ .id = id } } };
    }

    pub fn import(self: *Store, incoming: g.State) Error!void {
        // Preserve incoming IDs until the next canonical emission.
        for (incoming.nodes) |record| _ = try self.add(record);
        for (incoming.blobs) |record| {
            const bytes = try self.allocator.dupe(u8, record.bytes);
            errdefer self.allocator.free(bytes);
            try self.blobs.ensureUnusedCapacity(self.allocator, 1);
            try self.blob_alive.ensureUnusedCapacity(self.allocator, 1);
            try self.interned.ensureUnusedCapacity(self.allocator, 1);
            self.interned.putAssumeCapacity(.{ .schema = record.schema, .bytes = bytes }, self.blobs.items.len);
            self.blobs.appendAssumeCapacity(.{ .schema = record.schema, .bytes = bytes });
            self.blob_alive.appendAssumeCapacity(true);
            if (self.statistics) |s| s.copied_blob_bytes +|= bytes.len;
        }
    }

    pub fn state(self: Store, identity: [32]u8, status: g.Status, roots: g.Roots) g.State {
        return .{ .program_identity = identity, .status = status, .roots = roots, .nodes = self.nodes.items, .blobs = self.blobs.items };
    }

    /// Traces strong reachability, including cycles. Reclamation performs no effects.
    pub fn collect(self: *Store, roots: g.Roots) Error!void {
        const marks = try self.allocator.alloc(bool, self.nodes.items.len);
        defer self.allocator.free(marks);
        const blob_marks = try self.allocator.alloc(bool, self.blobs.items.len);
        defer self.allocator.free(blob_marks);
        @memset(marks, false);
        @memset(blob_marks, false);
        var pending: std.ArrayList(data.snapshot.Reference) = .empty;
        defer pending.deinit(self.allocator);
        try data.snapshot.references(g.Roots, roots, &pending, self.allocator);
        if (self.statistics) |s| s.traced_edges +|= pending.items.len;
        while (pending.pop()) |reference| switch (reference) {
            .node => |id| {
                if (id >= marks.len or !self.alive.items[@intCast(id)]) return error.InvalidReference;
                if (marks[@intCast(id)]) continue;
                marks[@intCast(id)] = true;
                const before = pending.items.len;
                try data.snapshot.references(g.Node, self.nodes.items[@intCast(id)], &pending, self.allocator);
                if (self.statistics) |s| {
                    s.traced_nodes +|= 1;
                    s.traced_edges +|= pending.items.len - before;
                }
            },
            .blob => |id| {
                if (id >= blob_marks.len or !self.blob_alive.items[@intCast(id)]) return error.InvalidReference;
                blob_marks[@intCast(id)] = true;
            },
        };
        try self.free_nodes.ensureTotalCapacity(self.allocator, marks.len);
        try self.free_blobs.ensureTotalCapacity(self.allocator, blob_marks.len);
        if (self.statistics) |s| s.swept_slots +|= marks.len + blob_marks.len;
        for (marks, 0..) |marked, id| if (!marked and self.alive.items[id]) {
            release(g.Node, self.allocator, self.nodes.items[id]);
            self.nodes.items[id] = empty;
            self.alive.items[id] = false;
            self.free_nodes.appendAssumeCapacity(id);
        };
        for (blob_marks, 0..) |marked, id| if (!marked and self.blob_alive.items[id]) {
            _ = self.interned.remove(self.blobs.items[id]);
            self.allocator.free(self.blobs.items[id].bytes);
            self.blobs.items[id] = .{ .schema = 0, .bytes = &.{} };
            self.blob_alive.items[id] = false;
            self.free_blobs.appendAssumeCapacity(id);
        };
    }
};

const BlobContext = struct {
    pub fn hash(_: BlobContext, value: g.Blob) u64 {
        return std.hash.Wyhash.hash(value.schema, value.bytes);
    }
    pub fn eql(_: BlobContext, left: g.Blob, right: g.Blob) bool {
        return left.schema == right.schema and std.mem.eql(u8, left.bytes, right.bytes);
    }
};

/// Allocation ownership follows the closed native record shape, never graph edges.
pub fn duplicate(comptime T: type, allocator: std.mem.Allocator, value: T) std.mem.Allocator.Error!T {
    return switch (@typeInfo(T)) {
        .pointer => |info| blk: {
            const result = try allocator.alloc(info.child, value.len);
            var initialized: usize = 0;
            errdefer {
                for (result[0..initialized]) |item| release(info.child, allocator, item);
                allocator.free(result);
            }
            for (result, value) |*target, source| {
                target.* = try duplicate(info.child, allocator, source);
                initialized += 1;
            }
            break :blk result;
        },
        .optional => |info| if (value) |present| try duplicate(info.child, allocator, present) else null,
        .@"struct" => |info| blk: {
            var result: T = undefined;
            var initialized: usize = 0;
            errdefer inline for (info.fields, 0..) |field, index| {
                if (index < initialized) release(field.type, allocator, @field(result, field.name));
            };
            inline for (info.fields) |field| {
                @field(result, field.name) = try duplicate(field.type, allocator, @field(value, field.name));
                initialized += 1;
            }
            break :blk result;
        },
        .@"union" => |info| blk: {
            inline for (info.fields) |field| if (std.mem.eql(u8, @tagName(value), field.name)) {
                break :blk @unionInit(T, field.name, try duplicate(field.type, allocator, @field(value, field.name)));
            };
            unreachable; // Closed native union.
        },
        else => value,
    };
}

pub fn release(comptime T: type, allocator: std.mem.Allocator, value: T) void {
    switch (@typeInfo(T)) {
        .pointer => |info| {
            for (value) |item| release(info.child, allocator, item);
            allocator.free(value);
        },
        .optional => |info| if (value) |present| release(info.child, allocator, present),
        .@"struct" => |info| inline for (info.fields) |field| release(field.type, allocator, @field(value, field.name)),
        .@"union" => |info| inline for (info.fields) |field| if (std.mem.eql(u8, @tagName(value), field.name)) {
            release(field.type, allocator, @field(value, field.name));
            return;
        },
        else => {},
    }
}
