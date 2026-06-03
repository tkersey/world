const abi_version: u32 = 1;
const status_initialized: u32 = 1;
const status_running: u32 = 2;
const status_parked: u32 = 3;
const status_done: u32 = 4;
const status_buffer_too_small: u32 = 6;
const status_invalid_frame: u32 = 7;
const status_unknown_pending: u32 = 9;
const status_stale_pending: u32 = 10;
const max_memory: usize = 64 * 1024;

var memory_buf: [max_memory]u8 align(16) = [_]u8{0} ** max_memory;
var bump: usize = 0;
var current_status: u32 = status_initialized;
var pending_available: bool = false;
var response_seen: bool = false;
var result_ready: bool = false;
var last_error_len_value: usize = 0;
const result_bytes = "world-wasm-guest-one-port";
const request_bytes = [_]u8{
    0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xf0, 0xf8, 0x1a, 0xb9,
    0x01, 0x8a, 0xe0, 0xa2, 0xff, 0xb2, 0x4a, 0x9e, 0x7f, 0x14, 0x56, 0x1c,
    0x01, 0x81, 0x9a, 0x70, 0x9c, 0xf1, 0x34, 0x68, 0x7d, 0x1f, 0x65, 0xbc,
    0x57, 0x23, 0xb6, 0x09, 0xcc, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0xc3, 0xa8, 0xa3, 0xe1, 0xd9, 0xb3, 0x22,
    0x76, 0xa4, 0x3e, 0x10, 0x29, 0x4d, 0xe8, 0x84, 0x1a, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01,
    0x00, 0x00, 0x00, 0x01, 0x4e, 0x99, 0x5d, 0xff, 0x0e, 0x48, 0x8b, 0x8d,
    0x01, 0x34, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
    0x00, 0x01, 0x00, 0x00, 0x00, 0x4e, 0x99, 0x5d, 0xff, 0x0e, 0x48, 0x8b,
    0x8d, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x13, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x64, 0x65, 0x70, 0x6c, 0x6f, 0x79, 0x2d, 0x70, 0x72, 0x6f, 0x64,
    0x00, 0xff, 0xb2, 0x4a, 0x9e, 0x7f, 0x14, 0x56, 0x1c, 0x81, 0x9a, 0x70,
    0x9c, 0xf1, 0x34, 0x68, 0x7d, 0x00, 0x00, 0x00, 0x00, 0xa4, 0x3e, 0x10,
    0x29, 0x4d, 0xe8, 0x84, 0x1a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00,
};
var last_error_storage: [96]u8 = [_]u8{0} ** 96;

export fn world_abi_version() u32 {
    return abi_version;
}

export fn world_init() u32 {
    bump = 0;
    current_status = status_initialized;
    pending_available = false;
    response_seen = false;
    result_ready = false;
    clearError();
    return current_status;
}

export fn world_tick() u32 {
    switch (current_status) {
        status_initialized, status_running => {
            if (response_seen) {
                result_ready = true;
                current_status = status_done;
            } else {
                pending_available = true;
                current_status = status_parked;
            }
        },
        status_parked, status_done => {},
        else => {},
    }
    clearError();
    return current_status;
}

export fn world_status() u32 {
    return current_status;
}

export fn world_pending_count() u32 {
    return if (pending_available) 1 else 0;
}

export fn world_pending_request_len(index: u32) usize {
    if (!hasPending(index)) {
        _ = setError(status_unknown_pending, "pending request not found");
        return 0;
    }
    clearError();
    return request_bytes.len;
}

export fn world_read_pending_request(index: u32, ptr: usize, cap: usize) usize {
    if (!hasPending(index)) {
        _ = setError(status_unknown_pending, "pending request not found");
        return 0;
    }
    const copied = copyToGuest(ptr, cap, &request_bytes);
    if (copied == request_bytes.len and cap >= request_bytes.len) current_status = status_parked;
    return copied;
}

export fn world_submit_response(ptr: usize, len: usize) u32 {
    if (!pending_available) {
        return setError(status_stale_pending, "no pending request is parked");
    }
    if (ptr == 0 or len == 0) {
        return setError(status_invalid_frame, "empty response frame");
    }
    pending_available = false;
    response_seen = true;
    current_status = status_running;
    clearError();
    return current_status;
}

export fn world_result_len() usize {
    if (!result_ready) return 0;
    return result_bytes.len;
}

export fn world_read_result(ptr: usize, cap: usize) usize {
    if (!result_ready) return 0;
    const copied = copyToGuest(ptr, cap, result_bytes);
    if (copied == result_bytes.len and cap >= result_bytes.len) current_status = status_done;
    return copied;
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
    return last_error_len_value;
}

export fn world_read_last_error(ptr: usize, cap: usize) usize {
    return copyToGuestNoStatus(ptr, cap, last_error_storage[0..last_error_len_value]);
}

export fn world_alloc(len: usize) usize {
    const aligned = (len + 15) & ~@as(usize, 15);
    if (bump + aligned > memory_buf.len) {
        _ = setError(status_buffer_too_small, "allocation exceeds guest memory");
        return 0;
    }
    const ptr = @intFromPtr(&memory_buf[bump]);
    bump += aligned;
    return ptr;
}

export fn world_free(_: usize, _: usize) void {}

fn hasPending(index: u32) bool {
    return index == 0 and pending_available;
}

fn setError(status_value: u32, message: []const u8) u32 {
    current_status = status_value;
    const len = if (message.len > last_error_storage.len) last_error_storage.len else message.len;
    @memcpy(last_error_storage[0..len], message[0..len]);
    last_error_len_value = len;
    return current_status;
}

fn clearError() void {
    last_error_len_value = 0;
}

fn copyToGuest(ptr: usize, cap: usize, bytes: []const u8) usize {
    if (cap < bytes.len) {
        _ = setError(status_buffer_too_small, "guest buffer is too small");
        return bytes.len;
    }
    _ = copyToGuestNoStatus(ptr, cap, bytes);
    clearError();
    return bytes.len;
}

fn copyToGuestNoStatus(ptr: usize, cap: usize, bytes: []const u8) usize {
    _ = cap;
    if (bytes.len == 0) return 0;
    const out: [*]u8 = @ptrFromInt(ptr);
    @memcpy(out[0..bytes.len], bytes);
    return bytes.len;
}
