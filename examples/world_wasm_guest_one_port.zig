const abi_version: u32 = 1;
const status_initialized: u32 = 1;
const status_done: u32 = 4;
const status_buffer_too_small: u32 = 6;
const max_memory: usize = 64 * 1024;

var memory_buf: [max_memory]u8 align(16) = [_]u8{0} ** max_memory;
var bump: usize = 0;
var current_status: u32 = status_initialized;
const result_bytes = "world-wasm-guest-one-port";
const last_error_bytes = "";

export fn world_abi_version() u32 {
    return abi_version;
}

export fn world_init() u32 {
    current_status = status_initialized;
    return current_status;
}

export fn world_tick() u32 {
    current_status = status_done;
    return current_status;
}

export fn world_status() u32 {
    return current_status;
}

export fn world_pending_count() u32 {
    return 0;
}

export fn world_pending_request_len(_: u32) usize {
    return 0;
}

export fn world_read_pending_request(_: u32, _: usize, _: usize) usize {
    return 0;
}

export fn world_submit_response(_: usize, _: usize) u32 {
    return current_status;
}

export fn world_result_len() usize {
    return result_bytes.len;
}

export fn world_read_result(ptr: usize, cap: usize) usize {
    return copyToGuest(ptr, cap, result_bytes);
}

export fn world_receipt_len() usize {
    return 0;
}

export fn world_read_receipt(_: usize, _: usize) usize {
    return 0;
}

export fn world_transcript_len() usize {
    return 0;
}

export fn world_read_transcript(_: usize, _: usize) usize {
    return 0;
}

export fn world_last_error_len() usize {
    return last_error_bytes.len;
}

export fn world_read_last_error(ptr: usize, cap: usize) usize {
    return copyToGuest(ptr, cap, last_error_bytes);
}

export fn world_alloc(len: usize) usize {
    const aligned = (len + 15) & ~@as(usize, 15);
    if (bump + aligned > memory_buf.len) {
        current_status = status_buffer_too_small;
        return 0;
    }
    const ptr = @intFromPtr(&memory_buf[bump]);
    bump += aligned;
    return ptr;
}

export fn world_free(_: usize, _: usize) void {}

fn copyToGuest(ptr: usize, cap: usize, bytes: []const u8) usize {
    if (cap < bytes.len) {
        current_status = status_buffer_too_small;
        return bytes.len;
    }
    if (bytes.len == 0) return 0;
    const out: [*]u8 = @ptrFromInt(ptr);
    @memcpy(out[0..bytes.len], bytes);
    return bytes.len;
}
