// Copyright (c) 2026 World contributors. MIT license.
//! Reusable immutable Program ownership. Sessions retain their own strong lease.
const std = @import("std");
const data = @import("boundary_data_v2");
pub const Error = data.program_image.Error || error{ InvalidState, UnsupportedTransition };
pub const Contract = struct { payload: []const u8, resume_value: []const u8 };

const Storage = struct {
    allocator: std.mem.Allocator,
    references: usize = 1,
    admitted: *data.program_image.Admitted,
    arena: std.heap.ArenaAllocator,
    contracts: []const ?Contract,
};

pub const Core = opaque {
    fn storage(self: *Core) *Storage {
        return @ptrCast(@alignCast(self));
    }
    pub fn retain(self: *Core) Error!void {
        const owner = self.storage();
        owner.references = std.math.add(usize, owner.references, 1) catch return error.InvalidState;
    }
    pub fn release(self: *Core) void {
        const owner = self.storage();
        std.debug.assert(owner.references != 0);
        owner.references -= 1;
        if (owner.references != 0) return;
        const allocator = owner.allocator;
        owner.arena.deinit();
        owner.admitted.deinit();
        allocator.destroy(owner);
    }
    pub fn admitted(self: *Core) *const data.program_image.Admitted {
        return self.storage().admitted;
    }
    pub fn contract(self: *Core, effect: u64) Error!Contract {
        const contracts = self.storage().contracts;
        if (effect >= contracts.len) return error.InvalidState;
        return contracts[@intCast(effect)] orelse error.InvalidState;
    }
    pub fn storageBytes(self: *Core) usize {
        const owner = self.storage();
        return @sizeOf(Storage) + owner.arena.queryCapacity() + owner.admitted.storageBytes();
    }
};

/// An owning handle: clone explicitly to acquire another reference. Operations
/// on the handle are sequential; its immutable data may serve independent Sessions.
pub const Prepared = struct {
    core: ?*Core,

    pub fn init(allocator: std.mem.Allocator, image: []const u8) Error!Prepared {
        const admitted = try data.program_image.Admitted.decode(allocator, image);
        errdefer admitted.deinit();
        const program = admitted.program();
        for (program.blocks) |block| if (block.terminator == .forward) return error.UnsupportedTransition;
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();
        const contracts = try a.alloc(?Contract, program.effects.len);
        @memset(contracts, null);
        for (program.effects, contracts) |effect, *contract| if (effect.external) {
            contract.* = .{
                .payload = try data.schema.encodeOwned(a, program.schemas, effect.payload),
                .resume_value = try data.schema.encodeOwned(a, program.schemas, effect.result),
            };
        };
        const core = try allocator.create(Storage);
        core.* = .{ .allocator = allocator, .admitted = admitted, .arena = arena, .contracts = contracts };
        return .{ .core = @ptrCast(core) };
    }

    pub fn clone(self: *const Prepared) Error!Prepared {
        return .{ .core = try self.acquire() };
    }
    pub fn acquire(self: *const Prepared) Error!*Core {
        const core = self.core orelse return error.InvalidState;
        try core.retain();
        return core;
    }
    pub fn deinit(self: *Prepared) void {
        const core = self.core orelse return;
        self.core = null;
        core.release();
    }
    pub fn storageBytes(self: *const Prepared) Error!usize {
        const core = self.core orelse return error.InvalidState;
        return core.storageBytes();
    }
};
