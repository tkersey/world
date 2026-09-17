// Copyright (c) 2026 World contributors. MIT license.
//! Private, indexed activation storage. Values are descriptors; this store never
//! clones referenced objects, grants semantic ownership, or executes finalizers.
//! Handles and node addresses must never enter portable State or identity.
const std = @import("std");

pub fn Slots(comptime Value: type) type {
    return struct {
        const Self = @This();
        const bits = 4;
        const width = 1 << bits;
        const maximum_depth = (@bitSizeOf(usize) - bits + bits - 1) / bits;
        const Node = union(enum) { empty, page: *Page, branch: *Branch };
        const Page = struct {
            references: usize = 1,
            initialized: u16 = 0,
            values: [width]Value = undefined,
        };
        const Branch = struct { references: usize = 1, children: [width]Node = @splat(.empty) };
        const View = struct {
            generation: u64 = 1,
            revision: u64 = 0,
            active: bool = true,
            root: Node = .empty,
            limit: usize,
            depth: u8,
        };
        pub const Handle = struct { instance: u64, index: usize, generation: u64 };
        pub const Binding = struct { slot: usize, value: Value };
        pub const ReadError = error{ InvalidHandle, InvalidSlot, UninitializedSlot };
        pub const Error = std.mem.Allocator.Error || error{
            InvalidHandle,
            InvalidSlot,
            UninitializedSlot,
            CapacityExceeded,
            InvalidSelection,
            StaleIterator,
        };
        pub const Statistics = struct {
            live_pages: usize = 0,
            live_directories: usize = 0,
            peak_pages: usize = 0,
            value_copies: u64 = 0,
            directory_copies: u64 = 0,
            writes: u64 = 0,
        };

        allocator: std.mem.Allocator,
        instance: u64,
        views: std.ArrayList(View) = .empty,
        free_views: std.ArrayList(usize) = .empty,
        statistics: Statistics = .{},
        var next_instance = std.atomic.Value(usize).init(1);

        pub fn init(allocator: std.mem.Allocator) Error!Self {
            var current = next_instance.load(.monotonic);
            while (true) {
                if (current == std.math.maxInt(usize)) return error.CapacityExceeded;
                if (next_instance.cmpxchgWeak(current, current + 1, .monotonic, .monotonic)) |next| {
                    current = next;
                } else return .{ .allocator = allocator, .instance = current };
            }
        }

        pub fn deinit(self: *Self) void {
            for (self.views.items) |view| if (view.active) self.drop(view.root);
            self.views.deinit(self.allocator);
            self.free_views.deinit(self.allocator);
            self.* = undefined;
        }

        /// Allocated node bytes and reserved handle-table capacity, excluding
        /// allocator overhead and the separately owned payload graph.
        pub fn retainedBytes(self: *const Self) usize {
            return self.statistics.live_pages * @sizeOf(Page) +
                self.statistics.live_directories * @sizeOf(Branch) +
                self.views.capacity * @sizeOf(View) +
                self.free_views.capacity * @sizeOf(usize);
        }

        pub fn create(self: *Self, limit: usize) Error!Handle {
            var high = if (limit == 0) 0 else (limit - 1) >> bits;
            var depth: u8 = 0;
            while (high != 0) : (high >>= bits) depth += 1;
            return self.addView(.{ .limit = limit, .depth = depth });
        }

        fn addView(self: *Self, view: View) Error!Handle {
            var result = view;
            const index = if (self.free_views.pop()) |free| blk: {
                result.generation = self.views.items[free].generation;
                self.views.items[free] = result;
                break :blk free;
            } else blk: {
                try self.views.ensureUnusedCapacity(self.allocator, 1);
                // Release must be allocation-free, even when all views retire.
                try self.free_views.ensureTotalCapacity(self.allocator, self.views.items.len + 1);
                const id = self.views.items.len;
                self.views.appendAssumeCapacity(result);
                break :blk id;
            };
            return .{ .instance = self.instance, .index = index, .generation = result.generation };
        }

        fn lookupView(self: *Self, handle: Handle) error{InvalidHandle}!*View {
            if (handle.instance != self.instance or handle.index >= self.views.items.len)
                return error.InvalidHandle;
            const result = &self.views.items[handle.index];
            if (!result.active or result.generation != handle.generation) return error.InvalidHandle;
            return result;
        }

        pub fn fork(self: *Self, handle: Handle) Error!Handle {
            var copy = (try self.lookupView(handle)).*;
            copy.root = try retain(copy.root);
            errdefer self.drop(copy.root);
            copy.revision = 0;
            return self.addView(copy);
        }

        pub fn release(self: *Self, handle: Handle) Error!void {
            const entry = try self.lookupView(handle);
            self.retire(handle.index, entry);
        }

        fn retire(self: *Self, index: usize, entry: *View) void {
            const root = entry.root;
            entry.active = false;
            entry.root = .empty;
            if (entry.generation != std.math.maxInt(u64)) {
                entry.generation += 1;
                self.free_views.appendAssumeCapacity(index);
            }
            self.drop(root);
        }

        /// Publish a tentative view after all other fallible operation work.
        /// Consumes the candidate handle. Failure leaves both logical views intact.
        pub fn commit(self: *Self, target: Handle, candidate: Handle) Error!void {
            if (target.index == candidate.index) return error.InvalidHandle;
            const destination = try self.lookupView(target);
            const source = try self.lookupView(candidate);
            if (destination.limit != source.limit or destination.depth != source.depth)
                return error.InvalidSelection;
            if (destination.revision == std.math.maxInt(u64)) return error.CapacityExceeded;
            const previous = destination.root;
            destination.root = source.root;
            source.root = .empty;
            destination.revision += 1;
            self.retire(candidate.index, source);
            self.drop(previous);
        }

        pub fn get(self: *Self, handle: Handle, slot: usize) ReadError!Value {
            const entry = try self.lookupView(handle);
            if (slot >= entry.limit) return error.InvalidSlot;
            const page = locate(entry.root, entry.depth, slot) orelse return error.UninitializedSlot;
            if (page.initialized & mask(slot) == 0) return error.UninitializedSlot;
            return page.values[slot & (width - 1)];
        }

        pub fn lookupLimit(self: *Self, handle: Handle) error{InvalidHandle}!usize {
            return (try self.lookupView(handle)).limit;
        }

        pub const Reader = struct {
            store: *Self,
            handle: Handle,

            pub fn at(self: Reader, slot: usize) ReadError!Value {
                return self.store.get(self.handle, slot);
            }
        };

        pub fn reader(self: *Self, handle: Handle) ReadError!Reader {
            _ = try self.lookupView(handle);
            return .{ .store = self, .handle = handle };
        }

        pub fn set(self: *Self, handle: Handle, slot: usize, value: Value) Error!void {
            try self.change(handle, slot, value);
        }

        pub fn clear(self: *Self, handle: Handle, slot: usize) Error!void {
            try self.change(handle, slot, null);
        }

        fn change(self: *Self, handle: Handle, slot: usize, value: ?Value) Error!void {
            const entry = try self.lookupView(handle);
            if (slot >= entry.limit) return error.InvalidSlot;
            if (entry.revision == std.math.maxInt(u64)) return error.CapacityExceeded;
            if (value == null) {
                const page = locate(entry.root, entry.depth, slot) orelse return;
                if (page.initialized & mask(slot) == 0) return;
            }
            try self.changeOwned(&entry.root, entry.depth, slot, value);
            entry.revision += 1;
            self.statistics.writes +|= 1;
        }

        /// Reclamation after the evaluator has selected live values AND required
        /// disposition. This operation itself has no authority to discard owners.
        pub fn retainOnly(self: *Self, handle: Handle, selected: []const usize) Error!void {
            const original = (try self.lookupView(handle)).*;
            if (original.revision == std.math.maxInt(u64)) return error.CapacityExceeded;
            for (selected, 0..) |slot, index| {
                if (index != 0 and selected[index - 1] >= slot) return error.InvalidSelection;
                _ = try self.get(handle, slot);
            }
            const temporary = try self.create(original.limit);
            defer self.release(temporary) catch unreachable;
            for (selected) |slot| try self.set(temporary, slot, try self.get(handle, slot));
            const replacement = try self.lookupView(temporary);
            const entry = try self.lookupView(handle);
            const previous = entry.root;
            entry.root = replacement.root;
            replacement.root = .empty;
            entry.revision += 1;
            self.drop(previous);
        }

        fn changed(self: *Self, node: Node, depth: u8, slot: usize, value: ?Value) Error!Node {
            if (depth == 0) return self.changedPage(node, slot, value);
            const index = childIndex(depth, slot);
            const old = if (node == .empty) Node.empty else node.branch.children[index];
            const child = try self.changed(old, depth - 1, slot, value);
            errdefer self.drop(child);
            if (child == .empty and (node == .empty or onlyChild(node.branch, index))) return .empty;
            const result = try self.allocator.create(Branch);
            result.* = .{};
            self.statistics.live_directories += 1;
            errdefer self.drop(.{ .branch = result });
            if (node == .branch) for (node.branch.children, 0..) |other, i| {
                if (i == index) continue;
                result.children[i] = try retain(other);
                if (other != .empty) self.statistics.directory_copies +|= 1;
            };
            result.children[index] = child;
            return .{ .branch = result };
        }

        fn changedPage(self: *Self, node: Node, slot: usize, value: ?Value) Error!Node {
            if (value == null and (node == .empty or node.page.initialized == mask(slot)))
                return .empty;
            const page = try self.allocator.create(Page);
            page.* = .{};
            if (node == .page) {
                page.initialized = node.page.initialized;
                var live = page.initialized;
                while (live != 0) {
                    const index = @ctz(live);
                    page.values[index] = node.page.values[index];
                    self.statistics.value_copies +|= 1;
                    live &= live - 1;
                }
            }
            assign(page, slot, value);
            self.statistics.live_pages += 1;
            self.statistics.peak_pages = @max(self.statistics.peak_pages, self.statistics.live_pages);
            return .{ .page = page };
        }

        /// A unique prefix stays in place. Build the first shared/missing suffix
        /// before publishing it; unwinding this recursion performs no fallible work.
        fn changeOwned(self: *Self, node: *Node, depth: u8, slot: usize, value: ?Value) Error!void {
            const unique = switch (node.*) {
                .empty => false,
                .page => |page| page.references == 1,
                .branch => |branch| branch.references == 1,
            };
            if (!unique) {
                const successor = try self.changed(node.*, depth, slot, value);
                const previous = node.*;
                node.* = successor;
                self.drop(previous);
                return;
            }
            if (depth == 0) {
                assign(node.page, slot, value);
                if (node.page.initialized == 0) {
                    self.drop(node.*);
                    node.* = .empty;
                }
                return;
            }
            const index = childIndex(depth, slot);
            try self.changeOwned(&node.branch.children[index], depth - 1, slot, value);
            for (node.branch.children) |child| if (child != .empty) return;
            self.drop(node.*);
            node.* = .empty;
        }

        fn assign(page: *Page, slot: usize, value: ?Value) void {
            if (value) |present| {
                page.values[slot & (width - 1)] = present;
                page.initialized |= mask(slot);
            } else {
                page.initialized &= ~mask(slot);
                page.values[slot & (width - 1)] = undefined;
            }
        }

        fn mask(slot: usize) u16 {
            return @as(u16, 1) << @intCast(slot & (width - 1));
        }

        fn childIndex(depth: u8, slot: usize) usize {
            std.debug.assert(depth > 0 and depth <= maximum_depth);
            return (slot >> @intCast(bits * depth)) & (width - 1);
        }

        fn locate(root: Node, levels: u8, slot: usize) ?*Page {
            var node = root;
            var depth = levels;
            while (node != .empty) {
                if (depth == 0) return node.page;
                node = node.branch.children[childIndex(depth, slot)];
                depth -= 1;
            }
            return null;
        }

        fn onlyChild(branch: *Branch, index: usize) bool {
            for (branch.children, 0..) |child, i| if (i != index and child != .empty) return false;
            return true;
        }

        fn retain(node: Node) Error!Node {
            const references = switch (node) {
                .empty => return .empty,
                .page => |page| &page.references,
                .branch => |branch| &branch.references,
            };
            references.* = std.math.add(usize, references.*, 1) catch return error.CapacityExceeded;
            return node;
        }

        fn drop(self: *Self, node: Node) void {
            switch (node) {
                .empty => {},
                .page => |page| {
                    std.debug.assert(page.references != 0);
                    page.references -= 1;
                    if (page.references != 0) return;
                    self.statistics.live_pages -= 1;
                    self.allocator.destroy(page);
                },
                .branch => |branch| {
                    std.debug.assert(branch.references != 0);
                    branch.references -= 1;
                    if (branch.references != 0) return;
                    for (branch.children) |child| self.drop(child);
                    self.statistics.live_directories -= 1;
                    self.allocator.destroy(branch);
                },
            }
        }

        pub fn iterator(self: *Self, handle: Handle) Error!Iterator {
            const entry = try self.lookupView(handle);
            var result: Iterator = .{
                .store = self,
                .handle = handle,
                .revision = entry.revision,
            };
            if (entry.root != .empty) {
                result.pending[0] = .{ .node = entry.root, .depth = entry.depth, .base = 0 };
                result.length = 1;
            }
            return result;
        }

        pub const Iterator = struct {
            const Visit = struct { node: Node, depth: u8, base: usize };
            store: *Self,
            handle: Handle,
            revision: u64,
            pending: [maximum_depth * (width - 1) + 1]Visit = undefined,
            length: usize = 0,
            page: ?*Page = null,
            live: u16 = 0,
            base: usize = 0,

            pub fn next(self: *Iterator) Error!?Binding {
                if ((try self.store.lookupView(self.handle)).revision != self.revision)
                    return error.StaleIterator;
                while (self.live == 0) {
                    if (self.length == 0) return null;
                    self.length -= 1;
                    const current = self.pending[self.length];
                    if (current.depth == 0) {
                        self.page = current.node.page;
                        self.live = current.node.page.initialized;
                        self.base = current.base;
                    } else {
                        var index: usize = width;
                        while (index != 0) {
                            index -= 1;
                            const child = current.node.branch.children[index];
                            if (child == .empty) continue;
                            std.debug.assert(self.length < self.pending.len);
                            self.pending[self.length] = .{
                                .node = child,
                                .depth = current.depth - 1,
                                .base = current.base | (index << @intCast(bits * current.depth)),
                            };
                            self.length += 1;
                        }
                    }
                }
                const index = @ctz(self.live);
                self.live &= self.live - 1;
                return .{ .slot = self.base + index, .value = self.page.?.values[index] };
            }
        };
    };
}

pub const ActivationSlots = Slots(@import("boundary_data").graph.Value);
