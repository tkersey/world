// Copyright (c) 2026 World contributors. MIT license.
//! Fresh attachments for an immutable template. One map preserves every alias.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const g = data.graph;
const Store = @import("store.zig").Store;
const Error = @import("process.zig").Error;
const Map = std.AutoHashMap(p.Id, g.NodeRef);

pub fn instantiate(allocator: std.mem.Allocator, store: *Store, template: g.Capture) Error!g.Capture {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var copy: Cloner = .{
        .allocator = scratch,
        .store = store,
        .map = Map.init(scratch),
        .waiting = std.AutoHashMap(p.Id, std.ArrayList(g.NodeRef)).init(scratch),
        .considered = std.AutoHashMap(p.Id, void).init(scratch),
        .discovered = std.AutoHashMap(p.Id, void).init(scratch),
        .dependents = std.AutoHashMap(p.Id, std.ArrayList(g.NodeRef)).init(scratch),
    };
    try copy.capture(template, false);
    var index: usize = 0;
    var propagated: usize = 0;
    var refs: std.ArrayList(data.snapshot.Reference) = .empty;
    while (index < copy.pending.items.len or propagated < copy.originals.items.len or copy.templates.items.len != 0) {
        if (copy.templates.pop()) |ref| {
            try copy.template(ref);
            continue;
        }
        if (propagated < copy.originals.items.len) {
            const changed = copy.originals.items[propagated];
            propagated += 1;
            if (copy.dependents.get(changed.id)) |parents| for (parents.items) |parent| try copy.include(parent);
            continue;
        }
        const original = copy.pending.items[index];
        const node = try store.get(original);
        const immutable = switch (node) {
            .environment, .aggregate, .computation => true,
            else => false,
        };
        refs.clearRetainingCapacity();
        try data.snapshot.references(g.Node, node, &refs, scratch);
        index += 1;
        for (refs.items) |reference| if (reference == .node) {
            const ref: g.NodeRef = .{ .id = reference.node };
            // A frozen container needs a new identity only if a contained
            // reference changes. Propagate that need backwards through cycles.
            if (immutable) try copy.addDependency(ref, original);
            switch (try store.get(ref)) {
                .environment, .aggregate, .computation => try copy.discover(ref),
                .cell => |cell| try copy.addDependency(cell.region, ref),
                .multi_template => try copy.template(ref),
                else => {},
            }
        };
    }
    for (copy.originals.items) |ref| {
        const changed = try rebase(g.Node, scratch, try store.get(ref), copy.map);
        try store.replace(copy.map.get(ref.id).?, changed);
    }
    var result = try rebase(g.Capture, scratch, template, copy.map);
    result.use_site_capabilities = try allocator.dupe(g.Value, result.use_site_capabilities);
    return result;
}

const Cloner = struct {
    allocator: std.mem.Allocator,
    store: *Store,
    map: Map,
    originals: std.ArrayList(g.NodeRef) = .empty,
    templates: std.ArrayList(g.NodeRef) = .empty,
    waiting: std.AutoHashMap(p.Id, std.ArrayList(g.NodeRef)),
    considered: std.AutoHashMap(p.Id, void),
    discovered: std.AutoHashMap(p.Id, void),
    pending: std.ArrayList(g.NodeRef) = .empty,
    dependents: std.AutoHashMap(p.Id, std.ArrayList(g.NodeRef)),

    fn discover(self: *Cloner, ref: g.NodeRef) Error!void {
        const entry = try self.discovered.getOrPut(ref.id);
        if (!entry.found_existing) try self.pending.append(self.allocator, ref);
    }

    fn addDependency(self: *Cloner, child: g.NodeRef, parent: g.NodeRef) Error!void {
        const entry = try self.dependents.getOrPut(child.id);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.append(self.allocator, parent);
        if (self.map.contains(child.id)) try self.include(parent);
    }

    fn include(self: *Cloner, ref: g.NodeRef) Error!void {
        if (self.map.contains(ref.id)) return;
        const copied = try self.store.add(try self.store.get(ref));
        try self.map.put(ref.id, copied);
        try self.originals.append(self.allocator, ref);
        try self.discover(ref);
        if (self.waiting.fetchRemove(ref.id)) |waiting| try self.templates.appendSlice(self.allocator, waiting.value.items);
    }

    fn capture(self: *Cloner, saved: g.Capture, include_handler: bool) Error!void {
        var cursor = saved.capture;
        while (cursor) |ref| {
            const record = try self.store.get(ref);
            try self.include(ref);
            if (ref.id == saved.delimiter.id) {
                if (include_handler) try self.include(record.attachment.handler);
                return;
            }
            cursor = switch (record) {
                .continuation => |continuation| continuation.parent,
                .attachment => |attachment| blk: {
                    try self.include(attachment.handler);
                    break :blk attachment.return_to;
                },
                .region_scope => |scope| blk: {
                    try self.include(scope.region);
                    break :blk scope.return_to;
                },
                .injection => |injected| injected.continuation,
                else => return error.InvalidState,
            };
        }
        return error.InvalidScope;
    }

    fn template(self: *Cloner, ref: g.NodeRef) Error!void {
        if (self.map.contains(ref.id)) return;
        const saved = (try self.store.get(ref)).multi_template;
        const delimiter = (try self.store.get(saved.delimiter)).attachment;
        const activation = (try self.store.get(delimiter.handler)).handler;
        const dependencies = [_]?g.NodeRef{ delimiter.outer, activation.region };
        for (dependencies) |dependency| if (dependency) |owner| {
            if (self.map.contains(owner.id)) {
                // A nested template borrows from this capture. Rebase its frozen
                // graph too; templates whose owners are outside retain identity.
                try self.include(ref);
                try self.capture(saved, true);
                return;
            }
        };
        const seen = try self.considered.getOrPut(ref.id);
        if (seen.found_existing) return;
        for (dependencies) |dependency| if (dependency) |owner| {
            const waiting = try self.waiting.getOrPut(owner.id);
            if (!waiting.found_existing) waiting.value_ptr.* = .empty;
            try waiting.value_ptr.append(self.allocator, ref);
        };
    }
};

fn rebase(comptime T: type, allocator: std.mem.Allocator, value: T, map: Map) Error!T {
    if (T == g.NodeRef) return map.get(value.id) orelse value;
    if (T == g.BlobRef) return value;
    return switch (@typeInfo(T)) {
        .pointer => |info| blk: {
            const result = try allocator.alloc(info.child, value.len);
            for (result, value) |*to, from| to.* = try rebase(info.child, allocator, from, map);
            break :blk result;
        },
        .optional => |info| if (value) |present| try rebase(info.child, allocator, present, map) else null,
        .@"struct" => |info| blk: {
            var result: T = undefined;
            inline for (info.fields) |field| @field(result, field.name) = try rebase(field.type, allocator, @field(value, field.name), map);
            break :blk result;
        },
        .@"union" => |info| blk: {
            inline for (info.fields) |field| if (std.mem.eql(u8, @tagName(value), field.name))
                break :blk @unionInit(T, field.name, try rebase(field.type, allocator, @field(value, field.name), map));
            unreachable;
        },
        .array => |info| blk: {
            var result: T = undefined;
            for (&result, value) |*to, from| to.* = try rebase(info.child, allocator, from, map);
            break :blk result;
        },
        else => value,
    };
}

test "nested templates rebase borrowed local scopes and preserve repeated aliases" {
    const allocator = std.testing.allocator;
    var store: Store = .{ .allocator = allocator };
    defer store.deinit();
    const outer = try store.add(.{ .region = .{ .descriptor = 0, .outer = null, .obligations = &.{} } });
    const activation = try store.add(.{ .handler = .{ .definition = 0, .state = &.{}, .evidence = null, .region = outer } });
    const delimiter = try store.add(.{ .attachment = .{ .handler = activation, .outer = null, .return_to = null, .phase = .suspended, .region = outer } });
    const local = try store.add(.{ .region = .{ .descriptor = 1, .outer = outer, .obligations = &.{} } });
    const scope = try store.add(.{ .region_scope = .{ .source_block = 0, .region = local, .return_to = delimiter } });
    const inner_activation = try store.add(.{ .handler = .{ .definition = 0, .state = &.{}, .evidence = delimiter, .region = local } });
    const inner_delimiter = try store.add(.{ .attachment = .{ .handler = inner_activation, .outer = delimiter, .return_to = null, .phase = .suspended, .region = local } });
    const inner_position = try store.add(.{ .continuation = .{ .source_block = 0, .arguments = &.{}, .parent = inner_delimiter, .evidence = inner_delimiter, .region = local } });
    const inner = try store.add(.{ .multi_template = .{ .schema = 0, .capture = inner_position, .delimiter = inner_delimiter, .evidence = inner_delimiter } });
    const value: g.Value = .{ .schema = 0, .body = .{ .reference = inner } };
    const position = try store.add(.{ .continuation = .{ .source_block = 0, .arguments = &.{ value, value }, .parent = scope, .evidence = delimiter, .region = local } });
    const copy = try instantiate(allocator, &store, .{ .schema = 0, .capture = position, .delimiter = delimiter, .evidence = delimiter });
    defer allocator.free(copy.use_site_capabilities);
    const copied_position = (try store.get(copy.capture.?)).continuation;
    const left = copied_position.arguments[0].?.body.reference;
    const right = copied_position.arguments[1].?.body.reference;
    try std.testing.expectEqual(left.id, right.id);
    try std.testing.expect(left.id != inner.id);
    const copied_inner = (try store.get(left)).multi_template;
    const copied_delimiter = (try store.get(copied_inner.delimiter)).attachment;
    const copied_activation = (try store.get(copied_delimiter.handler)).handler;
    try std.testing.expectEqual(copy.delimiter.id, copied_delimiter.outer.?.id);
    try std.testing.expectEqual(copied_position.region.?.id, copied_activation.region.?.id);
    try std.testing.expect(copied_activation.region.?.id != local.id);
    try std.testing.expectEqual(outer.id, (try store.get(copied_activation.region.?)).region.outer.?.id);
    try std.testing.expectEqual(activation.id, (try store.get(copy.delimiter)).attachment.handler.id);
}
