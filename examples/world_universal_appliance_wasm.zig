const std = @import("std");
const world = @import("world");

const Appliance = world.Appliance;
const Native = Appliance.Native;
const Core = Appliance.Core;
const Image = world.Executable.Image;
const DecodeLimits = Image.DecodeLimits;
const Abi = Appliance.Abi;

const max_image_bytes: usize = 128 * 1024;
const max_command_bytes: usize = 64 * 1024;
const max_output_bytes: usize = 128 * 1024;
const max_closure_bytes: usize = max_output_bytes * 4;
const max_host_replies_per_turn: usize = 16;
const max_metadata_bytes: usize = 8192;
const max_wire_resolution_overhead_bytes: usize = 64;
const max_turn_reply_bytes: usize = max_host_replies_per_turn * (max_output_bytes + 2 * max_metadata_bytes + max_wire_resolution_overhead_bytes);
const max_turn_input_bytes: usize = max_closure_bytes + max_command_bytes + max_turn_reply_bytes;
const guest_memory_bytes: usize = 4 * 1024 * 1024;
const max_modules: usize = 8;
const max_provider_depth: usize = 8;
const max_external_bindings: usize = 16;
const max_mailbox_entries: usize = 1024;
const max_linear_memory_pages: usize = 1024;
const max_error_bytes: usize = 160;
const loaded_image_arena_bytes: usize = 16 * 1024 * 1024;
const staging_arena_bytes: usize = 16 * 1024 * 1024;
var guest_memory: [guest_memory_bytes]u8 align(16) = [_]u8{0} ** guest_memory_bytes;
var bump: usize = 16;

var slot0_bytes: [loaded_image_arena_bytes]u8 align(16) = [_]u8{0} ** loaded_image_arena_bytes;
var slot1_bytes: [staging_arena_bytes]u8 align(16) = [_]u8{0} ** staging_arena_bytes;
var slot0_fba = std.heap.FixedBufferAllocator.init(&slot0_bytes);
var slot1_fba = std.heap.FixedBufferAllocator.init(&slot1_bytes);

var active_slot: u1 = 0;
var loaded = false;
var native: Native = undefined;

var last_error: [max_error_bytes]u8 = [_]u8{0} ** max_error_bytes;
var last_error_len_value: usize = 0;

pub const executable_runtime_profile = world.Executable.RuntimeProfile.init(.{
    .supports_internal_providers = true,
    .max_modules = max_modules,
    .max_provider_depth = max_provider_depth,
    .max_external_bindings = max_external_bindings,
    .max_module_bytes = max_image_bytes,
    .max_image_bytes = max_image_bytes,
    .max_command_bytes = max_command_bytes,
    .max_output_bytes = max_output_bytes,
    .max_linear_memory_pages = max_linear_memory_pages,
});

const runtime_manifest =
    "world.universal_appliance.runtime.v3\n" ++
    "abi=3\n" ++
    "imports=0\n" ++
    "wasi=false\n" ++
    "target_specific_boundary_type=false\n" ++
    "executable_image_format=2\n" ++
    "manifest=world.Appliance.Manifest.canonical\n" ++
    std.fmt.comptimePrint("runtime_profile_fingerprint={x}\n", .{executable_runtime_profile.profile_fingerprint}) ++
    std.fmt.comptimePrint("supports_loaded_execution={}\n", .{executable_runtime_profile.supports_loaded_execution}) ++
    std.fmt.comptimePrint("supports_internal_providers={}\n", .{executable_runtime_profile.supports_internal_providers}) ++
    std.fmt.comptimePrint("supports_external_actuation={}\n", .{executable_runtime_profile.supports_external_actuation}) ++
    std.fmt.comptimePrint("max_modules={d}\n", .{executable_runtime_profile.max_modules}) ++
    std.fmt.comptimePrint("max_provider_depth={d}\n", .{executable_runtime_profile.max_provider_depth}) ++
    std.fmt.comptimePrint("max_external_bindings={d}\n", .{executable_runtime_profile.max_external_bindings}) ++
    std.fmt.comptimePrint("max_module_bytes={d}\n", .{executable_runtime_profile.max_module_bytes}) ++
    std.fmt.comptimePrint("max_image_bytes={d}\n", .{executable_runtime_profile.max_image_bytes}) ++
    std.fmt.comptimePrint("max_command_bytes={d}\n", .{executable_runtime_profile.max_command_bytes}) ++
    std.fmt.comptimePrint("max_output_bytes={d}\n", .{executable_runtime_profile.max_output_bytes}) ++
    std.fmt.comptimePrint("max_turn_input_bytes={d}\n", .{max_turn_input_bytes}) ++
    std.fmt.comptimePrint("max_closure_bytes={d}\n", .{max_closure_bytes}) ++
    std.fmt.comptimePrint("max_linear_memory_pages={d}\n", .{executable_runtime_profile.max_linear_memory_pages}) ++
    std.fmt.comptimePrint("encoded_image_bytes_limit={d}\n", .{max_image_bytes}) ++
    std.fmt.comptimePrint("decoded_immutable_bytes_limit={d}\n", .{loaded_image_arena_bytes}) ++
    std.fmt.comptimePrint("staging_high_water_limit={d}\n", .{staging_arena_bytes}) ++
    std.fmt.comptimePrint("runspace_slots={d}\n", .{max_modules}) ++
    std.fmt.comptimePrint("loaded_frames={d}\n", .{max_modules}) ++
    std.fmt.comptimePrint("mailbox_entries={d}\n", .{max_mailbox_entries}) ++
    std.fmt.comptimePrint("fabric_invocations={d}\n", .{max_provider_depth}) ++
    std.fmt.comptimePrint("linear_memory_initial_limit_bytes={d}\n", .{max_linear_memory_pages * 64 * 1024}) ++
    std.fmt.comptimePrint("linear_memory_max_limit_bytes={d}\n", .{max_linear_memory_pages * 64 * 1024}) ++
    std.fmt.comptimePrint("runtime_profile_metadata={s}\n", .{executable_runtime_profile.metadata});

pub const abi_capacity = blk: {
    var capacity = Appliance.Capacity.wasm_agent;
    capacity.max_pending_ports = max_mailbox_entries;
    capacity.max_capsule_bytes = 4 * 1024 * 1024;
    capacity.max_archive_append_bytes = 4 * 1024 * 1024;
    capacity.max_command_bytes = max_command_bytes;
    capacity.max_output_bytes = max_output_bytes;
    break :blk Appliance.Capacity.init(capacity);
};

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
    const compatibility = image.validateWithAllocator(allocator, executable_runtime_profile) catch |err| {
        const status = setLoadErrorForSlot(err, staging_slot);
        resetSlot(staging_slot);
        return status;
    };
    if (!compatibility.compatible) {
        resetSlot(staging_slot);
        return setErrorStatus(.capacity_exceeded, "executable runtime profile exceeds appliance ABI");
    }
    if (!imageSupportedByUniversalAppliance(image)) {
        resetSlot(staging_slot);
        return setErrorStatus(.invalid_command, "executable image requires unsupported loaded routes");
    }
    var core = Core.initExecutable(allocator, image, .{
        .profile = .wasm_small,
        .capacity = abi_capacity,
        .supported_runtime_profile = executable_runtime_profile,
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

fn imageSupportedByUniversalAppliance(image: Image) bool {
    if (image.module_set.modules.len == 0 or image.module_set.modules.len > max_modules) return false;
    var root_count: usize = 0;
    for (image.module_set.modules) |module| {
        switch (module.role) {
            .root => root_count += 1,
            .provider => {},
        }
    }
    if (root_count != 1) return false;
    if (image.dispatch_image.route_ids.len > max_provider_depth) return false;
    if (image.dispatch_image.fabric_plan_fingerprints.len > max_provider_depth) return false;
    if (image.dispatch_image.route_provider_module_fingerprints.len > max_provider_depth) return false;
    return true;
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
    if (cap < required) {
        _ = setErrorStatus(.buffer_too_small, "buffer too small");
    } else {
        clearError();
    }
    return required;
}

pub export fn world_appliance_submit_command(ptr: usize, len: usize) u32 {
    const current = activeNative() orelse return setErrorStatus(.invalid_command, "no executable image loaded");
    if (len == 0 or len > max_command_bytes) {
        current.clearOutput();
        current.clearClosure();
        return setErrorStatus(.capacity_exceeded, "invalid command length");
    }
    const command = guestRange(ptr, len) orelse {
        current.clearOutput();
        current.clearClosure();
        return setErrorStatus(.invalid_command, "command outside appliance memory");
    };
    const status = current.submitCommand(command);
    if (Abi.statusHasTurnOutput(status)) {
        clearError();
    } else {
        current.clearOutput();
        setSubmitError(status, current.lastErrorBytes());
    }
    return @intFromEnum(status);
}

pub export fn world_appliance_submit_turn(ptr: usize, len: usize) u32 {
    const current = activeNative() orelse return setErrorStatus(.invalid_command, "no executable image loaded");
    if (len == 0 or len > max_turn_input_bytes) {
        current.clearOutput();
        current.clearClosure();
        return setErrorStatus(.capacity_exceeded, "invalid turn input length");
    }
    const turn_input = guestRange(ptr, len) orelse {
        current.clearOutput();
        current.clearClosure();
        return setErrorStatus(.invalid_command, "turn input outside appliance memory");
    };
    const status = current.submitTurn(turn_input);
    if (Abi.statusHasTurnOutput(status)) {
        clearError();
    } else {
        current.clearOutput();
        current.clearClosure();
        setSubmitError(status, current.lastErrorBytes());
    }
    return @intFromEnum(status);
}

pub export fn world_appliance_closure_len() usize {
    const current = activeNative() orelse return 0;
    return current.closureLen();
}

pub export fn world_appliance_read_closure(ptr: usize, cap: usize) usize {
    const current = activeNative() orelse return 0;
    const out = guestRange(ptr, cap) orelse {
        _ = setErrorStatus(.buffer_too_small, "buffer outside appliance memory");
        return current.closureLen();
    };
    const required = current.readClosure(out);
    if (cap < required) {
        _ = setErrorStatus(.buffer_too_small, "buffer too small");
    } else {
        clearError();
    }
    return required;
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
    if (cap < required) {
        _ = setErrorStatus(.buffer_too_small, "buffer too small");
    } else {
        clearError();
    }
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

pub export fn world_appliance_free(ptr: usize, len: usize) void {
    if (len == 0) return;
    if (len > ~@as(usize, 0) - 15) return;
    const aligned = (len + 15) & ~@as(usize, 15);
    const offset = guestOffset(ptr, len) orelse return;
    if (offset % 16 != 0) return;
    if (offset + aligned == bump) bump = offset;
}

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
    native.deinit();
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
    const offset = guestOffset(ptr, len) orelse return null;
    return guest_memory[offset .. offset + len];
}

fn guestOffset(ptr: usize, len: usize) ?usize {
    const base = @intFromPtr(&guest_memory[0]);
    if (ptr < base) return null;
    const offset = ptr - base;
    if (offset > guest_memory.len or len > guest_memory.len - offset) return null;
    return offset;
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
            slotCapacity(slot),
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

fn slotCapacity(slot: u1) usize {
    return switch (slot) {
        0 => loaded_image_arena_bytes,
        1 => staging_arena_bytes,
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
        appendLastErrorUsize(slotCapacity(active_slot));
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
