const std = @import("std");
const world = @import("world");

const Appliance = world.Appliance;
const Native = Appliance.Native;
const Core = Appliance.Core;
const Image = world.Executable.Image;
const DecodeLimits = Image.DecodeLimits;
const Abi = Appliance.Abi;

const runtime_manifest =
    "world.universal_appliance.runtime.v2\n" ++
    "imports=0\n" ++
    "wasi=false\n" ++
    "target_specific_boundary_type=false\n" ++
    "executable_image_format=2\n" ++
    "manifest=world.Appliance.Manifest.canonical\n" ++
    "max_image_bytes=131072\n" ++
    "max_command_bytes=65536\n" ++
    "max_output_bytes=131072\n" ++
    "max_linear_memory_pages=2048\n";

const guest_memory_bytes: usize = 1024 * 1024;
const max_image_bytes: usize = 128 * 1024;
const max_command_bytes: usize = 64 * 1024;
const max_error_bytes: usize = 160;
const slot_heap_bytes: usize = 40 * 1024 * 1024;
var guest_memory: [guest_memory_bytes]u8 align(16) = [_]u8{0} ** guest_memory_bytes;
var bump: usize = 16;

var slot0_bytes: [slot_heap_bytes]u8 align(16) = [_]u8{0} ** slot_heap_bytes;
var slot1_bytes: [slot_heap_bytes]u8 align(16) = [_]u8{0} ** slot_heap_bytes;
var slot0_fba = std.heap.FixedBufferAllocator.init(&slot0_bytes);
var slot1_fba = std.heap.FixedBufferAllocator.init(&slot1_bytes);

var active_slot: u1 = 0;
var loaded = false;
var native: Native = undefined;

var last_error: [max_error_bytes]u8 = [_]u8{0} ** max_error_bytes;
var last_error_len_value: usize = 0;

pub export fn world_appliance_abi_version() u32 {
    return Abi.universal_version;
}

pub export fn world_appliance_runtime_manifest_len() usize {
    return runtime_manifest.len;
}

pub export fn world_appliance_read_runtime_manifest(ptr: usize, cap: usize) usize {
    return copyToGuest(ptr, cap, runtime_manifest);
}

pub export fn world_appliance_load_executable(ptr: usize, len: usize) u32 {
    if (len == 0 or len > max_image_bytes) return setErrorStatus(.capacity_exceeded, "invalid executable image length");
    const bytes = guestRange(ptr, len) orelse return setErrorStatus(.invalid_command, "executable image outside appliance memory");

    const staging_slot = inactiveSlot();
    resetSlot(staging_slot);
    const allocator = slotAllocator(staging_slot);
    const image = Image.decode(allocator, bytes, decodeLimits(len)) catch |err| {
        const status = setLoadErrorForSlot(err, staging_slot);
        resetSlot(staging_slot);
        return status;
    };
    var core = Core.initExecutable(allocator, image, .{
        .profile = .wasm_small,
        .metadata = "world-universal-appliance",
    }) catch |err| {
        const status = setLoadErrorForSlot(err, staging_slot);
        resetSlot(staging_slot);
        return status;
    };
    errdefer core.deinit();
    const staged_native = Native.init(core);

    if (loaded) clearLoaded();
    active_slot = staging_slot;
    native = staged_native;
    loaded = true;
    bump = 16;
    clearError();
    return @intFromEnum(Abi.Status.ok);
}

pub export fn world_appliance_unload_executable() u32 {
    clearLoaded();
    bump = 16;
    clearError();
    return @intFromEnum(Abi.Status.ok);
}

pub export fn world_appliance_manifest_len() usize {
    if (!loaded) return 0;
    return activeNative().?.manifestLen();
}

pub export fn world_appliance_read_manifest(ptr: usize, cap: usize) usize {
    const current = activeNative() orelse return 0;
    const out = guestRange(ptr, cap) orelse {
        _ = setErrorStatus(.buffer_too_small, "buffer outside appliance memory");
        return current.manifestLen();
    };
    const required = current.readManifest(out);
    if (cap < required) _ = setErrorStatus(.buffer_too_small, "buffer too small");
    return required;
}

pub export fn world_appliance_submit_command(ptr: usize, len: usize) u32 {
    const current = activeNative() orelse return setErrorStatus(.invalid_command, "no executable image loaded");
    if (len == 0 or len > max_command_bytes) return setErrorStatus(.capacity_exceeded, "invalid command length");
    const command = guestRange(ptr, len) orelse return setErrorStatus(.invalid_command, "command outside appliance memory");
    const status = current.submitCommand(command);
    if (Abi.statusHasTurnOutput(status)) clearError() else setSubmitError(status, current.lastErrorBytes());
    return @intFromEnum(status);
}

pub export fn world_appliance_output_len() usize {
    const current = activeNative() orelse return 0;
    return current.outputLen();
}

pub export fn world_appliance_read_output(ptr: usize, cap: usize) usize {
    const current = activeNative() orelse return 0;
    const out = guestRange(ptr, cap) orelse {
        _ = setErrorStatus(.buffer_too_small, "buffer outside appliance memory");
        return current.outputLen();
    };
    const required = current.readOutput(out);
    if (cap < required) _ = setErrorStatus(.buffer_too_small, "buffer too small");
    return required;
}

pub export fn world_appliance_last_error_len() usize {
    if (last_error_len_value != 0) return last_error_len_value;
    if (activeNative()) |current| return current.lastErrorLen();
    return 0;
}

pub export fn world_appliance_read_last_error(ptr: usize, cap: usize) usize {
    if (last_error_len_value != 0) return copyToGuest(ptr, cap, last_error[0..last_error_len_value]);
    if (activeNative()) |current| {
        return copyToGuest(ptr, cap, current.lastErrorBytes());
    }
    return 0;
}

pub export fn world_appliance_reset() u32 {
    const current = activeNative() orelse return setErrorStatus(.invalid_command, "no executable image loaded");
    bump = 16;
    const status = current.reset();
    clearError();
    return @intFromEnum(status);
}

pub export fn world_appliance_alloc(len: usize) usize {
    if (len == 0) return @intFromPtr(&guest_memory[16]);
    if (len > ~@as(usize, 0) - 15) {
        _ = setErrorStatus(.buffer_too_small, "allocation exceeds appliance memory");
        return 0;
    }
    const aligned = (len + 15) & ~@as(usize, 15);
    if (bump > guest_memory.len or aligned > guest_memory.len - bump) {
        _ = setErrorStatus(.buffer_too_small, "allocation exceeds appliance memory");
        return 0;
    }
    const result = @intFromPtr(&guest_memory[bump]);
    bump += aligned;
    return result;
}

pub export fn world_appliance_free(_: usize, _: usize) void {}

fn decodeLimits(len: usize) DecodeLimits {
    return .{
        .max_image_bytes = len,
        .max_modules = 16,
        .max_external_bindings = 64,
        .max_dispatch_entries = 8192,
        .max_module_bytes = max_image_bytes,
    };
}

fn activeNative() ?*Native {
    if (!loaded) return null;
    return &native;
}

fn clearLoaded() void {
    if (!loaded) {
        resetSlot(active_slot);
        return;
    }
    native.core.deinit();
    loaded = false;
    resetSlot(active_slot);
}

fn inactiveSlot() u1 {
    return if (loaded) active_slot ^ 1 else active_slot;
}

fn slotAllocator(slot: u1) std.mem.Allocator {
    return switch (slot) {
        0 => slot0_fba.allocator(),
        1 => slot1_fba.allocator(),
    };
}

fn resetSlot(slot: u1) void {
    switch (slot) {
        0 => slot0_fba.reset(),
        1 => slot1_fba.reset(),
    }
}

fn guestRange(ptr: usize, len: usize) ?[]u8 {
    const base = @intFromPtr(&guest_memory[0]);
    if (ptr < base) return null;
    const offset = ptr - base;
    if (offset > guest_memory.len or len > guest_memory.len - offset) return null;
    return guest_memory[offset .. offset + len];
}

fn copyToGuest(ptr: usize, cap: usize, bytes: []const u8) usize {
    const out = guestRange(ptr, cap) orelse {
        _ = setErrorStatus(.buffer_too_small, "buffer outside appliance memory");
        return bytes.len;
    };
    if (cap < bytes.len) {
        _ = setErrorStatus(.buffer_too_small, "buffer too small");
        return bytes.len;
    }
    @memcpy(out[0..bytes.len], bytes);
    clearError();
    return bytes.len;
}

fn setLoadError(err: anyerror) u32 {
    return setLoadErrorForSlot(err, inactiveSlot());
}

fn setLoadErrorForSlot(err: anyerror, slot: u1) u32 {
    if (err == error.OutOfMemory) {
        var buffer: [96]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "OutOfMemory slot={d} used={d} cap={d}", .{
            slot,
            slotAllocatorEndIndex(slot),
            slot_heap_bytes,
        }) catch "OutOfMemory";
        return setErrorStatus(Abi.statusForError(err), message);
    }
    return setErrorStatus(Abi.statusForError(err), @errorName(err));
}

fn slotAllocatorEndIndex(slot: u1) usize {
    return switch (slot) {
        0 => slot0_fba.end_index,
        1 => slot1_fba.end_index,
    };
}

fn setErrorStatus(status: Abi.Status, message: []const u8) u32 {
    setLastError(message);
    return @intFromEnum(status);
}

fn setLastError(message: []const u8) void {
    last_error_len_value = @min(message.len, last_error.len);
    @memcpy(last_error[0..last_error_len_value], message[0..last_error_len_value]);
}

fn setSubmitError(status: Abi.Status, detail: []const u8) void {
    clearError();
    appendLastError(Abi.statusName(status));
    appendLastError(":");
    appendLastError(detail);
    if (std.mem.indexOf(u8, detail, "OutOfMemory") != null) {
        appendLastError(" slot=");
        appendLastErrorUsize(active_slot);
        appendLastError(" used=");
        appendLastErrorUsize(slotAllocatorEndIndex(active_slot));
        appendLastError(" cap=");
        appendLastErrorUsize(slot_heap_bytes);
    }
}

fn appendLastError(bytes: []const u8) void {
    const available = last_error.len - last_error_len_value;
    const copied = @min(bytes.len, available);
    @memcpy(last_error[last_error_len_value..][0..copied], bytes[0..copied]);
    last_error_len_value += copied;
}

fn appendLastErrorUsize(value: usize) void {
    var buffer: [32]u8 = undefined;
    const bytes = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return;
    appendLastError(bytes);
}

fn clearError() void {
    last_error_len_value = 0;
}
