const abi_version: u32 = 2;
const status_ok: u32 = 0;
const status_output_ready: u32 = 1;
const status_completed: u32 = 3;
const status_invalid_command: u32 = 7;
const status_capacity_exceeded: u32 = 12;
const status_buffer_too_small: u32 = 15;

const runtime_manifest =
    "world.universal_appliance.runtime.v2\n" ++
    "imports=0\n" ++
    "wasi=false\n" ++
    "target_specific_boundary_type=false\n" ++
    "max_image_bytes=131072\n" ++
    "max_command_bytes=65536\n" ++
    "max_output_bytes=131072\n" ++
    "max_linear_memory_pages=64\n";

const guest_memory_bytes: usize = 1024 * 1024;
const max_image_bytes: usize = 128 * 1024;
const max_command_bytes: usize = 64 * 1024;
const max_output_bytes: usize = 128 * 1024;
const max_error_bytes: usize = 160;

var guest_memory: [guest_memory_bytes]u8 align(16) = [_]u8{0} ** guest_memory_bytes;
var bump: usize = 16;
var image_bytes: [max_image_bytes]u8 align(16) = [_]u8{0} ** max_image_bytes;
var image_len: usize = 0;
var output_bytes: [max_output_bytes]u8 align(16) = [_]u8{0} ** max_output_bytes;
var output_len_value: usize = 0;
var last_error: [max_error_bytes]u8 = [_]u8{0} ** max_error_bytes;
var last_error_len_value: usize = 0;

pub export fn world_appliance_abi_version() u32 {
    return abi_version;
}

pub export fn world_appliance_runtime_manifest_len() usize {
    return runtime_manifest.len;
}

pub export fn world_appliance_read_runtime_manifest(ptr: usize, cap: usize) usize {
    return copyToGuest(ptr, cap, runtime_manifest);
}

pub export fn world_appliance_load_executable(ptr: usize, len: usize) u32 {
    if (len == 0 or len > max_image_bytes) return setError(status_capacity_exceeded, "invalid executable image length");
    const bytes = guestRange(ptr, len) orelse return setError(status_invalid_command, "executable image outside appliance memory");

    image_len = len;
    var index: usize = 0;
    while (index < len) : (index += 1) image_bytes[index] = bytes[index];
    output_len_value = 0;
    clearError();
    return status_ok;
}

pub export fn world_appliance_unload_executable() u32 {
    image_len = 0;
    output_len_value = 0;
    bump = 16;
    clearError();
    return status_ok;
}

pub export fn world_appliance_manifest_len() usize {
    return image_len;
}

pub export fn world_appliance_read_manifest(ptr: usize, cap: usize) usize {
    if (image_len == 0) return 0;
    return copyToGuest(ptr, cap, image_bytes[0..image_len]);
}

pub export fn world_appliance_submit_command(ptr: usize, len: usize) u32 {
    if (image_len == 0) return setError(status_invalid_command, "no executable image loaded");
    if (len == 0 or len > max_command_bytes) return setError(status_capacity_exceeded, "invalid command length");
    const command = guestRange(ptr, len) orelse return setError(status_invalid_command, "command outside appliance memory");

    output_len_value = 0;
    appendOutput("world.universal_appliance.output.v2\n") catch return setError(status_capacity_exceeded, "output capacity exceeded");
    appendOutput("image=") catch return setError(status_capacity_exceeded, "output capacity exceeded");
    appendHex(fingerprintBytes(image_bytes[0..image_len])) catch return setError(status_capacity_exceeded, "output capacity exceeded");
    appendOutput("\ncommand=") catch return setError(status_capacity_exceeded, "output capacity exceeded");
    appendHex(fingerprintBytes(command)) catch return setError(status_capacity_exceeded, "output capacity exceeded");
    appendOutput("\n") catch return setError(status_capacity_exceeded, "output capacity exceeded");
    clearError();
    return status_completed;
}

pub export fn world_appliance_output_len() usize {
    return output_len_value;
}

pub export fn world_appliance_read_output(ptr: usize, cap: usize) usize {
    return copyToGuest(ptr, cap, output_bytes[0..output_len_value]);
}

pub export fn world_appliance_last_error_len() usize {
    return last_error_len_value;
}

pub export fn world_appliance_read_last_error(ptr: usize, cap: usize) usize {
    return copyToGuest(ptr, cap, last_error[0..last_error_len_value]);
}

pub export fn world_appliance_reset() u32 {
    output_len_value = 0;
    bump = 16;
    clearError();
    return status_ok;
}

pub export fn world_appliance_alloc(len: usize) usize {
    if (len == 0) return @intFromPtr(&guest_memory[16]);
    if (len > ~@as(usize, 0) - 15) {
        _ = setError(status_buffer_too_small, "allocation exceeds appliance memory");
        return 0;
    }
    const aligned = (len + 15) & ~@as(usize, 15);
    if (bump > guest_memory.len or aligned > guest_memory.len - bump) {
        _ = setError(status_buffer_too_small, "allocation exceeds appliance memory");
        return 0;
    }
    const result = @intFromPtr(&guest_memory[bump]);
    bump += aligned;
    return result;
}

pub export fn world_appliance_free(_: usize, _: usize) void {}

fn guestRange(ptr: usize, len: usize) ?[]u8 {
    const base = @intFromPtr(&guest_memory[0]);
    if (ptr < base) return null;
    const offset = ptr - base;
    if (offset > guest_memory.len or len > guest_memory.len - offset) return null;
    return guest_memory[offset .. offset + len];
}

fn copyToGuest(ptr: usize, cap: usize, bytes: []const u8) usize {
    const out = guestRange(ptr, cap) orelse {
        _ = setError(status_buffer_too_small, "buffer outside appliance memory");
        return bytes.len;
    };
    if (cap < bytes.len) {
        _ = setError(status_buffer_too_small, "buffer too small");
        return bytes.len;
    }
    var index: usize = 0;
    while (index < bytes.len) : (index += 1) out[index] = bytes[index];
    clearError();
    return bytes.len;
}

fn appendOutput(bytes: []const u8) !void {
    if (bytes.len > output_bytes.len - output_len_value) return error.CapacityExceeded;
    var index: usize = 0;
    while (index < bytes.len) : (index += 1) output_bytes[output_len_value + index] = bytes[index];
    output_len_value += bytes.len;
}

fn appendHex(value: u64) !void {
    var shift: u6 = 60;
    while (true) {
        const nibble: u8 = @truncate((value >> shift) & 0xf);
        const char: u8 = if (nibble < 10) '0' + nibble else 'a' + (nibble - 10);
        try appendOutput((&[_]u8{char})[0..]);
        if (shift == 0) break;
        shift -= 4;
    }
}

fn fingerprintBytes(bytes: []const u8) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (bytes) |byte| {
        hash ^= byte;
        hash *%= 0x100000001b3;
    }
    return hash;
}

fn setError(status: u32, message: []const u8) u32 {
    last_error_len_value = if (message.len < last_error.len) message.len else last_error.len;
    var index: usize = 0;
    while (index < last_error_len_value) : (index += 1) last_error[index] = message[index];
    return status;
}

fn clearError() void {
    last_error_len_value = 0;
}
