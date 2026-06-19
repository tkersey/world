const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

const wasm_page_bytes: usize = 64 * 1024;
const max_memory: usize = 2 * 1024 * 1024;
const core_storage_bytes: usize = 1024 * 1024;
const manifest = common.AgentAppliance.manifest();
const capacity = world.Appliance.Capacity.wasm_agent;
const memory_plan = common.AgentAppliance.memoryPlan();

var memory_buf: [max_memory]u8 align(16) = [_]u8{0} ** max_memory;
var bump: usize = 0;
var core_storage: [core_storage_bytes]u8 align(16) = [_]u8{0} ** core_storage_bytes;
var core_allocator_state = BoundedFreeListAllocator{ .buffer = &core_storage };
var native = world.Appliance.Native.init(makeCore());
var last_error_storage: [96]u8 = [_]u8{0} ** 96;
var last_error_len_value: usize = 0;

export fn world_appliance_abi_version() u32 {
    return world.Appliance.Abi.version;
}

export fn world_appliance_manifest_len() usize {
    return native.manifestLen();
}

export fn world_appliance_manifest_fingerprint_lo() u32 {
    return @truncate(manifest.manifest_fingerprint);
}

export fn world_appliance_manifest_fingerprint_hi() u32 {
    return @truncate(manifest.manifest_fingerprint >> 32);
}

export fn world_appliance_capacity_fingerprint_lo() u32 {
    return @truncate(capacity.fingerprint());
}

export fn world_appliance_capacity_fingerprint_hi() u32 {
    return @truncate(capacity.fingerprint() >> 32);
}

export fn world_appliance_memory_plan_fingerprint_lo() u32 {
    return @truncate(memory_plan.plan_fingerprint);
}

export fn world_appliance_memory_plan_fingerprint_hi() u32 {
    return @truncate(memory_plan.plan_fingerprint >> 32);
}

export fn world_appliance_required_memory_bytes() usize {
    return @wasmMemorySize(0) * wasm_page_bytes;
}

export fn world_appliance_max_linear_memory_pages() usize {
    return @wasmMemorySize(0);
}

export fn world_appliance_read_manifest(ptr: usize, cap: usize) usize {
    const out = guestMemoryRange(ptr, cap) orelse {
        _ = setError(.buffer_too_small, "buffer outside appliance memory");
        return native.manifestLen();
    };
    const required = native.readManifest(out);
    if (cap < required) _ = setError(.buffer_too_small, "buffer too small") else clearError();
    return required;
}

export fn world_appliance_submit_command(ptr: usize, len: usize) u32 {
    if (ptr == 0 or len == 0) return setError(.invalid_command, "invalid command");
    if (len > capacity.max_command_bytes) return setError(.capacity_exceeded, "command too large");
    const command_bytes = guestMemoryRange(ptr, len) orelse return setError(.invalid_command, "command outside memory");
    const status = native.submitCommand(command_bytes);
    if (!world.Appliance.Abi.statusHasTurnOutput(status)) {
        if (native.lastErrorLen() != 0) return setError(status, native.lastErrorBytes());
        return setError(status, world.Appliance.Abi.statusName(status));
    }
    clearError();
    return @intFromEnum(status);
}

export fn world_appliance_output_len() usize {
    return native.outputLen();
}

export fn world_appliance_read_output(ptr: usize, cap: usize) usize {
    if (native.outputLen() == 0) return 0;
    const out = guestMemoryRange(ptr, cap) orelse {
        _ = setError(.buffer_too_small, "buffer outside appliance memory");
        return native.outputLen();
    };
    const required = native.readOutput(out);
    if (cap < required) _ = setError(.buffer_too_small, "buffer too small") else clearError();
    return required;
}

export fn world_appliance_last_error_len() usize {
    return last_error_len_value;
}

export fn world_appliance_read_last_error(ptr: usize, cap: usize) usize {
    return copyToGuestNoStatus(ptr, cap, last_error_storage[0..last_error_len_value]);
}

export fn world_appliance_reset() u32 {
    bump = 0;
    _ = native.reset();
    core_allocator_state.reset();
    native = world.Appliance.Native.init(makeCore());
    clearError();
    return @intFromEnum(world.Appliance.Abi.Status.ok);
}

export fn world_alloc(len: usize) usize {
    if (len == 0) return @intFromPtr(&memory_buf[0]);
    if (len > memory_buf.len) return setErrorPtr(.buffer_too_small, "allocation exceeds appliance memory");
    const aligned = (len + 15) & ~@as(usize, 15);
    if (bump > memory_buf.len or aligned > memory_buf.len - bump) {
        return setErrorPtr(.buffer_too_small, "allocation exceeds appliance memory");
    }
    const ptr = @intFromPtr(&memory_buf[bump]);
    bump += aligned;
    return ptr;
}

export fn world_free(_: usize, _: usize) void {}

fn guestMemoryRange(ptr: usize, len: usize) ?[]u8 {
    const base = @intFromPtr(&memory_buf[0]);
    if (ptr < base) return null;
    const offset = ptr - base;
    if (offset > memory_buf.len or len > memory_buf.len - offset) return null;
    return memory_buf[offset .. offset + len];
}

fn copyToGuestNoStatus(ptr: usize, cap: usize, bytes: []const u8) usize {
    const out = guestMemoryRange(ptr, cap) orelse return bytes.len;
    if (cap < bytes.len) return bytes.len;
    for (bytes, 0..) |byte, index| out[index] = byte;
    return bytes.len;
}

fn setError(status: world.Appliance.Abi.Status, message: []const u8) u32 {
    last_error_len_value = @min(message.len, last_error_storage.len);
    for (message[0..last_error_len_value], 0..) |byte, index| last_error_storage[index] = byte;
    return @intFromEnum(status);
}

fn setErrorPtr(status: world.Appliance.Abi.Status, message: []const u8) usize {
    _ = setError(status, message);
    return 0;
}

fn clearError() void {
    last_error_len_value = 0;
}

fn makeCore() world.Appliance.Core {
    return world.Appliance.Core.initWithCapacity(
        core_allocator_state.allocator(),
        manifest,
        memory_plan,
        capacity,
    );
}

const BoundedFreeListAllocator = struct {
    buffer: []u8,
    initialized: bool = false,

    const Self = @This();
    const none = std.math.maxInt(usize);
    const block_alignment: usize = 16;
    const Header = struct {
        size: usize,
        next: usize,
        prev: usize,
        free: bool,
    };
    const header_bytes = std.mem.alignForward(usize, @sizeOf(Header), block_alignment);

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    pub fn reset(self: *Self) void {
        if (self.buffer.len <= header_bytes) {
            self.initialized = true;
            return;
        }
        const first = self.headerAt(0);
        first.* = .{
            .size = self.buffer.len - header_bytes,
            .next = none,
            .prev = none,
            .free = true,
        };
        self.initialized = true;
    }

    fn ensureInitialized(self: *Self) void {
        if (!self.initialized) self.reset();
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (len == 0) return self.buffer.ptr;
        if (alignment.toByteUnits() > block_alignment) return null;
        self.ensureInitialized();

        const needed = alignBlock(len);
        var offset: usize = 0;
        while (offset != none) {
            const header = self.headerAt(offset);
            if (header.free and header.size >= needed) {
                self.claimBlock(offset, needed);
                return self.payloadPtr(offset);
            }
            offset = header.next;
        }
        return null;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (alignment.toByteUnits() > block_alignment) return false;
        if (memory.len == 0) return false;
        self.ensureInitialized();
        const offset = self.headerOffsetFor(memory) orelse return false;
        const header = self.headerAt(offset);
        const needed = alignBlock(new_len);
        if (needed <= header.size) return true;

        const next_offset = header.next;
        if (next_offset == none) return false;
        const next = self.headerAt(next_offset);
        if (!next.free) return false;
        const combined = header.size + header_bytes + next.size;
        if (combined < needed) return false;

        header.size = combined;
        header.next = next.next;
        if (next.next != none) self.headerAt(next.next).prev = offset;
        self.claimBlock(offset, needed);
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        return if (resize(ctx, memory, alignment, new_len, ret_addr)) memory.ptr else null;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        _ = alignment;
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (memory.len == 0) return;
        self.ensureInitialized();
        const offset = self.headerOffsetFor(memory) orelse return;
        const header = self.headerAt(offset);
        header.free = true;
        self.coalesceForward(offset);
        if (header.prev != none and self.headerAt(header.prev).free) {
            self.coalesceForward(header.prev);
        }
    }

    fn claimBlock(self: *Self, offset: usize, needed: usize) void {
        const header = self.headerAt(offset);
        if (header.size > needed + header_bytes) {
            const next_offset = offset + header_bytes + needed;
            const next = self.headerAt(next_offset);
            next.* = .{
                .size = header.size - needed - header_bytes,
                .next = header.next,
                .prev = offset,
                .free = true,
            };
            if (header.next != none) self.headerAt(header.next).prev = next_offset;
            header.next = next_offset;
            header.size = needed;
        }
        header.free = false;
    }

    fn coalesceForward(self: *Self, offset: usize) void {
        const header = self.headerAt(offset);
        const next_offset = header.next;
        if (next_offset == none) return;
        const next = self.headerAt(next_offset);
        if (!next.free) return;
        header.size += header_bytes + next.size;
        header.next = next.next;
        if (next.next != none) self.headerAt(next.next).prev = offset;
    }

    fn headerAt(self: *Self, offset: usize) *Header {
        return @ptrCast(@alignCast(self.buffer.ptr + offset));
    }

    fn payloadPtr(self: *Self, offset: usize) [*]u8 {
        return self.buffer.ptr + offset + header_bytes;
    }

    fn headerOffsetFor(self: *Self, memory: []u8) ?usize {
        const base = @intFromPtr(self.buffer.ptr);
        const ptr = @intFromPtr(memory.ptr);
        if (ptr < base + header_bytes) return null;
        const offset = ptr - base - header_bytes;
        if (offset >= self.buffer.len) return null;
        if (offset + header_bytes > self.buffer.len) return null;
        if (self.payloadPtr(offset) != memory.ptr) return null;
        return offset;
    }

    fn alignBlock(len: usize) usize {
        return std.mem.alignForward(usize, len, block_alignment);
    }
};
