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
    journal_nodes: u64 = 0,
    journal_blobs: u64 = 0,
    aggregate_field_copies: u64 = 0,
    owned_blob_bytes: u64 = 0,
};

const SharedFields = struct { values: []g.Value, references: usize = 1 };
pub const EncodedSequence = struct { backing: g.BlobRef, start: usize, length: usize, count: u64 };
const SavedNode = struct { value: g.Node, alive: bool, borrowed: bool, fields: ?*SharedFields, sequence: ?EncodedSequence };
const SavedBlob = struct { value: g.Blob, alive: bool, borrowed: bool };
const Journal = struct {
    node_count: usize,
    blob_count: usize,
    nodes: std.AutoHashMapUnmanaged(usize, SavedNode) = .empty,
    blobs: std.AutoHashMapUnmanaged(usize, SavedBlob) = .empty,
    fn deinit(self: *Journal, allocator: std.mem.Allocator) void {
        self.nodes.deinit(allocator);
        self.blobs.deinit(allocator);
    }
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
    marks: std.ArrayList(bool) = .empty,
    blob_marks: std.ArrayList(bool) = .empty,
    pending: std.ArrayList(data.snapshot.Reference) = .empty,
    imported: ?data.state_image.Owned = null,
    borrowed_nodes: []bool = &.{},
    borrowed_blobs: []bool = &.{},
    journal: ?Journal = null,
    field_owners: std.AutoHashMapUnmanaged(usize, *SharedFields) = .empty,
    shared_field_values: usize = 0,
    encoded_sequences: std.AutoHashMapUnmanaged(usize, EncodedSequence) = .empty,

    pub fn begin(self: *Store) Error!void {
        if (self.journal != null) return error.InvalidState;
        // Rollback rebuilds only private indexes, and must never allocate.
        try self.free_nodes.ensureTotalCapacity(self.allocator, self.nodes.items.len);
        try self.free_blobs.ensureTotalCapacity(self.allocator, self.blobs.items.len);
        try self.interned.ensureTotalCapacity(self.allocator, std.math.cast(u32, self.blobs.items.len) orelse return error.Capacity);
        self.journal = .{ .node_count = self.nodes.items.len, .blob_count = self.blobs.items.len };
    }

    fn holdNode(self: *Store, id: usize) Error!bool {
        const journal = if (self.journal) |*value| value else return false;
        if (id >= journal.node_count or journal.nodes.contains(id)) return false;
        try journal.nodes.put(self.allocator, id, .{
            .value = self.nodes.items[id],
            .alive = self.alive.items[id],
            .borrowed = id < self.borrowed_nodes.len and self.borrowed_nodes[id],
            .fields = self.field_owners.get(id),
            .sequence = self.encoded_sequences.get(id),
        });
        if (self.statistics) |statistics| statistics.journal_nodes +|= 1;
        return true;
    }
    fn holdBlob(self: *Store, id: usize) Error!bool {
        const journal = if (self.journal) |*value| value else return false;
        if (id >= journal.blob_count or journal.blobs.contains(id)) return false;
        try journal.blobs.put(self.allocator, id, .{
            .value = self.blobs.items[id],
            .alive = self.blob_alive.items[id],
            .borrowed = id < self.borrowed_blobs.len and self.borrowed_blobs[id],
        });
        if (self.statistics) |statistics| statistics.journal_blobs +|= 1;
        return true;
    }
    fn retireNode(self: *Store, id: usize, value: g.Node, held: bool) void {
        if (held) {
            _ = self.field_owners.remove(id); // Physical ownership moves to the journal.
            _ = self.encoded_sequences.remove(id);
            if (id < self.borrowed_nodes.len) self.borrowed_nodes[id] = false;
        } else self.releaseNode(id, value);
    }
    fn retireBlob(self: *Store, id: usize, value: g.Blob, held: bool) void {
        if (held) {
            if (id < self.borrowed_blobs.len) self.borrowed_blobs[id] = false;
        } else self.releaseBlob(id, value);
    }

    pub fn commit(self: *Store) void {
        var journal = self.journal.?;
        self.journal = null;
        var nodes = journal.nodes.valueIterator();
        while (nodes.next()) |saved| if (saved.alive and !saved.borrowed) {
            if (saved.fields) |fields| self.releaseFields(fields) else release(g.Node, self.allocator, saved.value);
        };
        var blobs = journal.blobs.valueIterator();
        while (blobs.next()) |saved| if (saved.alive and !saved.borrowed) self.allocator.free(saved.value.bytes);
        journal.deinit(self.allocator);
    }

    pub fn rollback(self: *Store) void {
        var journal = self.journal.?;
        self.journal = null;
        var nodes = journal.nodes.iterator();
        while (nodes.next()) |entry| {
            const id = entry.key_ptr.*;
            if (self.alive.items[id]) self.releaseNode(id, self.nodes.items[id]);
        }
        for (journal.node_count..self.nodes.items.len) |id| if (self.alive.items[id])
            self.releaseNode(id, self.nodes.items[id]);
        // Remove successor owners before restoring the entry set: retained map
        // capacity then suffices and rollback cannot allocate.
        nodes = journal.nodes.iterator();
        while (nodes.next()) |entry| {
            const id = entry.key_ptr.*;
            self.nodes.items[id] = entry.value_ptr.value;
            self.alive.items[id] = entry.value_ptr.alive;
            if (id < self.borrowed_nodes.len) self.borrowed_nodes[id] = entry.value_ptr.borrowed;
            if (entry.value_ptr.fields) |fields| self.field_owners.putAssumeCapacity(id, fields);
            if (entry.value_ptr.sequence) |sequence| self.encoded_sequences.putAssumeCapacity(id, sequence);
        }
        self.nodes.items.len = journal.node_count;
        self.alive.items.len = journal.node_count;
        var blobs = journal.blobs.iterator();
        while (blobs.next()) |entry| {
            const id = entry.key_ptr.*;
            if (self.blob_alive.items[id]) self.releaseBlob(id, self.blobs.items[id]);
            self.blobs.items[id] = entry.value_ptr.value;
            self.blob_alive.items[id] = entry.value_ptr.alive;
            if (id < self.borrowed_blobs.len) self.borrowed_blobs[id] = entry.value_ptr.borrowed;
        }
        for (journal.blob_count..self.blobs.items.len) |id| if (self.blob_alive.items[id]) self.releaseBlob(id, self.blobs.items[id]);
        self.blobs.items.len = journal.blob_count;
        self.blob_alive.items.len = journal.blob_count;
        self.free_nodes.clearRetainingCapacity();
        for (self.alive.items, 0..) |alive, id| if (!alive) self.free_nodes.appendAssumeCapacity(id);
        self.free_blobs.clearRetainingCapacity();
        self.interned.clearRetainingCapacity();
        for (self.blob_alive.items, 0..) |alive, id| {
            if (alive) self.interned.putAssumeCapacity(self.blobs.items[id], id) else self.free_blobs.appendAssumeCapacity(id);
        }
        journal.deinit(self.allocator);
    }

    fn releaseNode(self: *Store, id: usize, value: g.Node) void {
        _ = self.encoded_sequences.remove(id);
        if (self.field_owners.fetchRemove(id)) |entry| {
            self.releaseFields(entry.value);
            return;
        }
        if (id < self.borrowed_nodes.len and self.borrowed_nodes[id]) {
            self.borrowed_nodes[id] = false;
        } else release(g.Node, self.allocator, value);
    }
    fn releaseBlob(self: *Store, id: usize, value: g.Blob) void {
        if (id < self.borrowed_blobs.len and self.borrowed_blobs[id]) {
            self.borrowed_blobs[id] = false;
        } else self.allocator.free(value.bytes);
    }

    pub fn deinit(self: *Store) void {
        if (self.journal != null) self.rollback();
        for (self.nodes.items, self.alive.items, 0..) |item, live, id| if (live) self.releaseNode(id, item);
        for (self.blobs.items, self.blob_alive.items, 0..) |blob, live, id| if (live) self.releaseBlob(id, blob);
        if (self.imported) |*base| base.deinit();
        self.allocator.free(self.borrowed_nodes);
        self.allocator.free(self.borrowed_blobs);
        self.nodes.deinit(self.allocator);
        self.alive.deinit(self.allocator);
        self.free_nodes.deinit(self.allocator);
        self.blobs.deinit(self.allocator);
        self.blob_alive.deinit(self.allocator);
        self.free_blobs.deinit(self.allocator);
        self.interned.deinit(self.allocator);
        self.field_owners.deinit(self.allocator);
        self.encoded_sequences.deinit(self.allocator);
        self.marks.deinit(self.allocator);
        self.blob_marks.deinit(self.allocator);
        self.pending.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn add(self: *Store, value: g.Node) Error!g.NodeRef {
        const copied = try duplicate(g.Node, self.allocator, value);
        errdefer release(g.Node, self.allocator, copied);
        const result = try self.addOwned(copied);
        if (value == .aggregate) if (self.statistics) |statistics| {
            statistics.aggregate_field_copies +|= value.aggregate.fields.len;
        };
        return result;
    }

    /// Takes all record-slice allocations on success only. They must be distinct
    /// allocations from this allocator; graph references retain logical aliases.
    pub fn addOwned(self: *Store, copied: g.Node) Error!g.NodeRef {
        return self.insertNode(copied);
    }

    fn insertNode(self: *Store, copied: g.Node) Error!g.NodeRef {
        if (self.free_nodes.items.len != 0) {
            const id = self.free_nodes.items[self.free_nodes.items.len - 1];
            _ = try self.holdNode(id);
            _ = self.free_nodes.pop();
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

    fn releaseFields(self: *Store, owner: *SharedFields) void {
        std.debug.assert(owner.references != 0);
        owner.references -= 1;
        if (owner.references != 0) return;
        self.shared_field_values -= owner.values.len;
        self.allocator.free(owner.values);
        self.allocator.destroy(owner);
    }

    /// Execution-only immutable leaf; public projection restores canonical bytes.
    pub fn encodedSequence(self: *Store, schema: data.program.Id, sequence: EncodedSequence) Error!g.NodeRef {
        if (sequence.backing.id >= self.blobs.items.len or
            !self.blob_alive.items[@intCast(sequence.backing.id)]) return error.InvalidReference;
        const bytes = self.blobs.items[@intCast(sequence.backing.id)].bytes;
        if (sequence.start > bytes.len or sequence.length > bytes.len - sequence.start)
            return error.InvalidLength;
        try self.encoded_sequences.ensureUnusedCapacity(self.allocator, 1);
        const reference = try self.insertNode(.{ .aggregate = .{
            .schema = schema,
            .tag = 0,
            .fields = &.{},
        } });
        self.encoded_sequences.putAssumeCapacity(@intCast(reference.id), sequence);
        return reference;
    }

    /// Shares only physical descriptor storage. Graph tracing, ownership checks
    /// and serialization see each node's live fields, never discarded prefixes.
    pub fn aggregateSlice(self: *Store, schema: data.program.Id, parent: g.NodeRef, start: usize, count: usize) Error!g.NodeRef {
        const node = try self.get(parent);
        if (node != .aggregate or start > node.aggregate.fields.len or
            count > node.aggregate.fields.len - start) return error.InvalidReference;
        if (count == 0) return self.add(.{ .aggregate = .{
            .schema = schema,
            .tag = 0,
            .fields = &.{},
        } });
        var fields = node.aggregate.fields[start..][0..count];
        const owner = if (self.field_owners.get(@intCast(parent.id))) |existing| reuse: {
            if (count <= existing.values.len / 4) break :reuse null;
            existing.references = std.math.add(usize, existing.references, 1) catch
                return error.OutOfMemory;
            break :reuse existing;
        } else null;
        const retained = owner orelse allocate: {
            const created = try self.allocator.create(SharedFields);
            errdefer self.allocator.destroy(created);
            created.* = .{ .values = try self.allocator.dupe(g.Value, fields) };
            self.shared_field_values += fields.len;
            if (self.statistics) |statistics| {
                statistics.aggregate_field_copies +|= fields.len;
            }
            fields = created.values;
            break :allocate created;
        };
        errdefer self.releaseFields(retained);
        try self.field_owners.ensureUnusedCapacity(self.allocator, 1);
        const reference = try self.insertNode(.{ .aggregate = .{
            .schema = schema,
            .tag = 0,
            .fields = fields,
        } });
        self.field_owners.putAssumeCapacity(@intCast(reference.id), retained);
        return reference;
    }

    pub fn get(self: Store, reference: g.NodeRef) Error!g.Node {
        if (reference.id >= self.nodes.items.len or !self.alive.items[@intCast(reference.id)]) return error.InvalidReference;
        return self.nodes.items[@intCast(reference.id)];
    }

    pub fn replace(self: *Store, reference: g.NodeRef, value: g.Node) Error!void {
        const previous = try self.get(reference);
        const replacement = try duplicate(g.Node, self.allocator, value);
        errdefer release(g.Node, self.allocator, replacement);
        const held = try self.holdNode(@intCast(reference.id));
        self.nodes.items[@intCast(reference.id)] = replacement;
        self.retireNode(@intCast(reference.id), previous, held);
    }

    /// Takes independently allocated record slices on success. No incoming
    /// slice may overlap storage owned by the node being replaced.
    pub fn replaceOwned(self: *Store, reference: g.NodeRef, value: g.Node) Error!void {
        const previous = try self.get(reference);
        const held = try self.holdNode(@intCast(reference.id));
        self.nodes.items[@intCast(reference.id)] = value;
        self.retireNode(@intCast(reference.id), previous, held);
    }

    pub fn literal(self: *Store, schemas: []const data.program.Schema, value: data.program.Literal) Error!g.Value {
        if (data.scalar.width(schemas[@intCast(value.schema)])) |width| {
            var scalar = [_]u8{0} ** 8;
            @memcpy(scalar[0..width], value.bytes);
            return .{ .schema = value.schema, .body = .{ .scalar = scalar } };
        }
        const key: g.Blob = .{ .schema = value.schema, .bytes = value.bytes };
        if (self.interned.get(key)) |id| return .{ .schema = value.schema, .body = .{ .blob = .{ .id = id } } };
        const copied: g.Blob = .{ .schema = value.schema, .bytes = try self.allocator.dupe(u8, value.bytes) };
        errdefer self.allocator.free(copied.bytes);
        const result = try self.insertBlobOwned(copied);
        if (self.statistics) |statistics| statistics.copied_blob_bytes +|= copied.bytes.len;
        return result;
    }

    /// Takes a unique, independently allocated buffer from this Store's allocator
    /// on success only. It must not alias existing Store storage. Success consumes
    /// it even when interning finds an existing value or the result is inline.
    pub fn literalOwned(
        self: *Store,
        schemas: []const data.program.Schema,
        schema: data.program.Id,
        bytes: []u8,
    ) Error!g.Value {
        if (data.scalar.width(schemas[@intCast(schema)])) |width| {
            var scalar = [_]u8{0} ** 8;
            @memcpy(scalar[0..width], bytes);
            if (self.statistics) |statistics| statistics.owned_blob_bytes +|= bytes.len;
            self.allocator.free(bytes);
            return .{ .schema = schema, .body = .{ .scalar = scalar } };
        }
        const value: g.Blob = .{ .schema = schema, .bytes = bytes };
        if (self.interned.get(value)) |id| {
            if (self.statistics) |statistics| statistics.owned_blob_bytes +|= bytes.len;
            self.allocator.free(bytes);
            return .{ .schema = schema, .body = .{ .blob = .{ .id = id } } };
        }
        const result = try self.insertBlobOwned(value);
        if (self.statistics) |statistics| statistics.owned_blob_bytes +|= bytes.len;
        return result;
    }

    fn insertBlobOwned(self: *Store, copied: g.Blob) Error!g.Value {
        try self.interned.ensureUnusedCapacity(self.allocator, 1);
        const id = if (self.free_blobs.items.len != 0) blk: {
            const free = self.free_blobs.items[self.free_blobs.items.len - 1];
            _ = try self.holdBlob(free);
            _ = self.free_blobs.pop();
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
        return .{ .schema = copied.schema, .body = .{ .blob = .{ .id = id } } };
    }

    pub fn import(self: *Store, incoming: g.State) Error!void {
        if (self.journal != null) return error.InvalidState;
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

    /// Adopt immutable decoded storage; transfer only on complete success.
    /// Semantic admission belongs to the caller before this physical operation.
    pub fn importOwned(self: *Store, incoming: *data.state_image.Owned) Error!void {
        if (self.nodes.items.len != 0 or self.blobs.items.len != 0 or self.imported != null or self.journal != null) return error.InvalidState;
        const state_ = incoming.state;
        const node_flags = try self.allocator.alloc(bool, state_.nodes.len);
        errdefer self.allocator.free(node_flags);
        const blob_flags = try self.allocator.alloc(bool, state_.blobs.len);
        errdefer self.allocator.free(blob_flags);
        try self.nodes.ensureTotalCapacityPrecise(self.allocator, state_.nodes.len);
        try self.alive.ensureTotalCapacityPrecise(self.allocator, state_.nodes.len);
        try self.blobs.ensureTotalCapacityPrecise(self.allocator, state_.blobs.len);
        try self.blob_alive.ensureTotalCapacityPrecise(self.allocator, state_.blobs.len);
        try self.interned.ensureUnusedCapacity(self.allocator, @intCast(state_.blobs.len));
        for (state_.nodes) |record| {
            self.nodes.appendAssumeCapacity(record.record);
            self.alive.appendAssumeCapacity(true);
        }
        for (state_.blobs, 0..) |blob, id| {
            self.blobs.appendAssumeCapacity(blob);
            self.blob_alive.appendAssumeCapacity(true);
            self.interned.putAssumeCapacity(blob, id);
        }
        @memset(node_flags, true);
        @memset(blob_flags, true);
        self.borrowed_nodes = node_flags;
        self.borrowed_blobs = blob_flags;
        self.imported = incoming.*;
        incoming.* = undefined;
    }

    /// Release a large imported backing once only small records survive. Copies
    /// are prepared individually before publication; failure preserves graph values.
    pub fn compactImported(self: *Store) Error!void {
        if (self.journal != null) return;
        const base = self.imported orelse return;
        var retained: usize = 0;
        for (self.borrowed_nodes, 0..) |borrowed, id| if (borrowed) {
            retained +|= @sizeOf(g.Node) +| ownedBytes(g.Node, self.nodes.items[id]);
        };
        for (self.borrowed_blobs, 0..) |borrowed, id| if (borrowed) {
            retained +|= @sizeOf(g.Blob) +| self.blobs.items[id].bytes.len;
        };
        if (retained > base.arena.queryCapacity() / 4) return;
        for (self.borrowed_nodes, 0..) |borrowed, id| if (borrowed) {
            const copy = try duplicate(g.Node, self.allocator, self.nodes.items[id]);
            self.nodes.items[id] = copy;
            self.borrowed_nodes[id] = false;
        };
        for (self.borrowed_blobs, 0..) |borrowed, id| if (borrowed) {
            const previous = self.blobs.items[id];
            const copy: g.Blob = .{ .schema = previous.schema, .bytes = try self.allocator.dupe(u8, previous.bytes) };
            _ = self.interned.remove(previous);
            self.interned.putAssumeCapacity(copy, id);
            self.blobs.items[id] = copy;
            self.borrowed_blobs[id] = false;
            if (self.statistics) |statistics| statistics.copied_blob_bytes +|= copy.bytes.len;
        };
        self.imported.?.deinit();
        self.imported = null;
        self.allocator.free(self.borrowed_nodes);
        self.allocator.free(self.borrowed_blobs);
        self.borrowed_nodes = &.{};
        self.borrowed_blobs = &.{};
    }

    pub fn state(self: Store, identity: [32]u8, status: g.Status, roots: g.Roots) g.State {
        return .{ .program_identity = identity, .status = status, .roots = roots, .nodes = self.nodes.items, .blobs = self.blobs.items };
    }

    /// Traces strong reachability, including cycles. Reclamation performs no effects.
    pub fn collect(self: *Store, roots: g.Roots) Error!void {
        return self.collectWith(roots, NoFrames{});
    }

    pub fn collectWith(self: *Store, roots: g.Roots, frames: anytype) Error!void {
        try self.marks.ensureTotalCapacityPrecise(self.allocator, self.nodes.items.len);
        try self.blob_marks.ensureTotalCapacityPrecise(self.allocator, self.blobs.items.len);
        self.marks.items.len = self.nodes.items.len;
        self.blob_marks.items.len = self.blobs.items.len;
        const marks = self.marks.items;
        const blob_marks = self.blob_marks.items;
        @memset(marks, false);
        @memset(blob_marks, false);
        const pending = &self.pending;
        pending.clearRetainingCapacity();
        try data.snapshot.references(g.Roots, roots, pending, self.allocator);
        if (self.statistics) |s| s.traced_edges +|= pending.items.len;
        while (pending.pop()) |reference| switch (reference) {
            .node => |id| {
                if (id >= marks.len or !self.alive.items[@intCast(id)]) return error.InvalidReference;
                if (marks[@intCast(id)]) continue;
                marks[@intCast(id)] = true;
                const before = pending.items.len;
                try data.snapshot.references(g.Node, self.nodes.items[@intCast(id)], pending, self.allocator);
                if (self.encoded_sequences.get(@intCast(id))) |sequence|
                    try pending.append(self.allocator, .{ .blob = sequence.backing.id });
                try frames.references(id, pending, self.allocator);
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
            const held = try self.holdNode(id);
            frames.remove(id);
            self.retireNode(id, self.nodes.items[id], held);
            self.nodes.items[id] = empty;
            self.alive.items[id] = false;
            self.free_nodes.appendAssumeCapacity(id);
        };
        for (blob_marks, 0..) |marked, id| if (!marked and self.blob_alive.items[id]) {
            const held = try self.holdBlob(id);
            _ = self.interned.remove(self.blobs.items[id]);
            self.retireBlob(id, self.blobs.items[id], held);
            self.blobs.items[id] = .{ .schema = 0, .bytes = &.{} };
            self.blob_alive.items[id] = false;
            self.free_blobs.appendAssumeCapacity(id);
        };
        try self.compactImported();
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
fn ownedBytes(comptime T: type, value: T) usize {
    return switch (@typeInfo(T)) {
        .pointer => |info| blk: {
            var size = @sizeOf(info.child) *| value.len;
            if (info.child != u8) for (value) |item| {
                size +|= ownedBytes(info.child, item);
            };
            break :blk size;
        },
        .optional => |info| if (value) |present| ownedBytes(info.child, present) else 0,
        .@"struct" => |info| blk: {
            var size: usize = 0;
            inline for (info.fields) |field| size +|= ownedBytes(field.type, @field(value, field.name));
            break :blk size;
        },
        .@"union" => switch (value) {
            inline else => |payload| ownedBytes(@TypeOf(payload), payload),
        },
        else => 0,
    };
}

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

const NoFrames = struct {
    fn references(_: NoFrames, _: data.program.Id, _: *std.ArrayList(data.snapshot.Reference), _: std.mem.Allocator) Error!void {}
    fn remove(_: NoFrames, _: data.program.Id) void {}
};
