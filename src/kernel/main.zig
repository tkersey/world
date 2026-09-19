// Copyright (c) 2026 World contributors. MIT license.
//! ABI 3: one generic import-free guest, fresh and resident execution.
const std = @import("std");
const data = @import("boundary_data");
const protocol = data.invocation;
const runtime = @import("runtime");
const Arena = runtime.Workspace;
const Budget = runtime.AllocationBudget;
const options = @import("kernel_options");

var initial_working: [options.working_capacity]u8 align(16) = undefined;
var envelope: [256]u8 = undefined;
var diagnostic: [256]u8 = undefined;
var diagnostic_length: usize = 0;
var workspace: Arena = undefined;
var heap: Pages = .{};
var input_budget: Budget = undefined;
var working_budget: Budget = undefined;
var output_budget: Budget = undefined;
var input: []u8 = &.{};
var input_ready: ?usize = null;
var owned_output: ?[]u8 = null;
var output: []const u8 = &.{};
var instance: u64 = 0;
var next_handle: u64 = 1;
var prepared: ?runtime.Prepared = null;
var prepared_handle: u64 = 0;
var resident: ?runtime.Resident = null;
var resident_handle: u64 = 0;
var busy = false;
extern var __heap_base: u8;

pub export fn world_abi_version() u32 {
    return 3;
}
pub export fn world_input_ptr() u32 {
    return if (input.len == 0) 0 else @intCast(@intFromPtr(input.ptr));
}
pub export fn world_input_capacity() u64 {
    return input.len;
}
pub export fn world_output_ptr() u32 {
    return if (output.len == 0) 0 else @intCast(@intFromPtr(output.ptr));
}
pub export fn world_output_len() u64 {
    return output.len;
}
pub export fn world_error_ptr() u32 {
    return @intCast(@intFromPtr(&diagnostic));
}
pub export fn world_error_len() u64 {
    return diagnostic_length;
}
pub export fn world_prepared_handle() u64 {
    return prepared_handle;
}
pub export fn world_session_handle() u64 {
    return resident_handle;
}
pub export fn world_working_live() u64 {
    return if (instance == 0) 0 else working_budget.live;
}
pub export fn world_working_peak() u64 {
    return if (instance == 0) 0 else working_budget.peak;
}

pub export fn world_initialize(identity: u64) u32 {
    if (instance != 0 or identity == 0) return reject("InvalidInstance");
    heap.cursor = @intFromPtr(&__heap_base);
    workspace = Arena.init(&initial_working);
    workspace.grow_context = &heap;
    workspace.grow = Pages.grow;
    input_budget = .{ .parent = workspace.allocator(), .limit = options.input_capacity };
    working_budget = .{ .parent = workspace.allocator(), .limit = options.working_capacity };
    output_budget = .{ .parent = workspace.allocator(), .limit = options.output_capacity };
    instance = identity;
    return 0;
}

fn clearOutput() void {
    if (owned_output) |bytes| output_budget.allocator().free(bytes);
    owned_output = null;
    output = &.{};
    diagnostic_length = 0;
}
fn enter(identity: u64) bool {
    if (busy) {
        _ = reject("Busy");
        return false;
    }
    if (instance == 0 or instance != identity) {
        _ = reject("InvalidInstance");
        return false;
    }
    busy = true;
    clearOutput();
    input_budget.resetObservation();
    working_budget.resetObservation();
    output_budget.resetObservation();
    heap.failed = false;
    heap.required_pages = @wasmMemorySize(0);
    return true;
}
fn takeInput(length: u64) ![]const u8 {
    const ready = input_ready orelse return error.InputNotPrepared;
    input_ready = null;
    if (length != ready or length > input.len) return error.InvalidInputLength;
    return input[0..@intCast(length)];
}
fn issueHandle() !u64 {
    if (next_handle == std.math.maxInt(u64)) return error.HandleExhausted;
    const result = next_handle;
    next_handle += 1;
    return result;
}
fn publish(bytes: []u8) u32 {
    owned_output = bytes;
    output = bytes;
    return 0;
}

pub export fn world_set_limits(identity: u64, input_limit: u64, working_limit: u64, output_limit: u64) u32 {
    if (!enter(identity)) return 2;
    defer busy = false;
    if (input_limit > std.math.maxInt(usize) or working_limit > std.math.maxInt(usize) or output_limit > std.math.maxInt(usize) or
        working_limit < working_budget.live) return reject("InvalidCapacity");
    input_budget.allocator().free(input);
    input = &.{};
    input_ready = null;
    input_budget.limit = @intCast(input_limit);
    working_budget.limit = @intCast(working_limit);
    output_budget.limit = @intCast(output_limit);
    return 0;
}
pub export fn world_prepare_input(identity: u64, length: u64) u32 {
    if (!enter(identity)) return 2;
    defer busy = false;
    input_ready = null;
    if (length > std.math.maxInt(usize)) return reject("InvalidInputLength");
    if (length > input.len) {
        input_budget.allocator().free(input);
        input = &.{};
        input = input_budget.allocator().alloc(u8, @intCast(length)) catch |err| return failed(err);
    }
    input_ready = @intCast(length);
    return 0;
}
pub export fn world_invoke(identity: u64, length: u64) u32 {
    if (!enter(identity)) return 2;
    defer busy = false;
    const bytes = takeInput(length) catch |err| return failed(err);
    return publish(runtime.invocation.invokeBytesWith(working_budget.allocator(), output_budget.allocator(), bytes) catch |err| return failed(err));
}
pub export fn world_prepare(identity: u64, length: u64) u32 {
    if (!enter(identity)) return 2;
    defer busy = false;
    if (prepared != null) return reject("PreparedAlreadyPresent");
    const bytes = takeInput(length) catch |err| return failed(err);
    const handle = issueHandle() catch |err| return failed(err);
    prepared = runtime.Prepared.init(working_budget.allocator(), bytes) catch |err| return failed(err);
    prepared_handle = handle;
    return 0;
}
pub export fn world_release_prepared(identity: u64, handle: u64) u32 {
    if (!enter(identity)) return 2;
    defer busy = false;
    if (prepared == null or handle == 0 or handle != prepared_handle) return reject("InvalidHandle");
    prepared.?.deinit();
    prepared = null;
    prepared_handle = 0;
    return 0;
}
fn createSession(handle: u64, length: u64, restore: bool) u32 {
    if (resident != null) return reject("SessionAlreadyPresent");
    if (prepared == null or handle == 0 or handle != prepared_handle) return reject("InvalidHandle");
    const bytes = takeInput(length) catch |err| return failed(err);
    const token = issueHandle() catch |err| return failed(err);
    resident = if (restore)
        runtime.Resident.restore(working_budget.allocator(), &prepared.?, bytes) catch |err| return failed(err)
    else
        runtime.Resident.start(working_budget.allocator(), &prepared.?, bytes) catch |err| return failed(err);
    resident_handle = token;
    return 0;
}
pub export fn world_start(identity: u64, handle: u64, length: u64) u32 {
    if (!enter(identity)) return 2;
    defer busy = false;
    return createSession(handle, length, false);
}
pub export fn world_restore(identity: u64, handle: u64, length: u64) u32 {
    if (!enter(identity)) return 2;
    defer busy = false;
    return createSession(handle, length, true);
}
pub export fn world_drive(identity: u64, handle: u64, control: u32, quantum_present: u32, quantum: u64, checkpoint: u32, length: u64) u32 {
    if (!enter(identity)) return 2;
    defer busy = false;
    if (resident == null or handle == 0 or handle != resident_handle) return reject("InvalidHandle");
    if (quantum_present > 1 or checkpoint > 1 or (quantum_present == 0 and quantum != 0)) return reject("InvalidControl");
    const bytes = takeInput(length) catch |err| return failed(err);
    const command: protocol.Control = switch (control) {
        0 => if (bytes.len == 0) .none else return reject("InvalidControl"),
        1 => .{ .reply = bytes },
        2 => if (bytes.len == 0) .resume_yield else return reject("InvalidControl"),
        3 => .{ .cancel = .{ .text = bytes } },
        4 => .{ .cancel = .{ .bytes = bytes } },
        else => return reject("InvalidControl"),
    };
    return publish(resident.?.driveEncoded(output_budget.allocator(), command, .{
        .quantum = if (quantum_present == 0) null else quantum,
        .checkpoint = checkpoint == 1,
    }) catch |err| return failed(err));
}
pub export fn world_checkpoint(identity: u64, handle: u64, transfer: u32) u32 {
    if (!enter(identity)) return 2;
    defer busy = false;
    if (resident == null or handle == 0 or handle != resident_handle) return reject("InvalidHandle");
    if (transfer > 1) return reject("InvalidControl");
    const bytes = if (transfer == 1)
        resident.?.takeCheckpoint(output_budget.allocator()) catch |err| return failed(err)
    else
        resident.?.checkpoint(output_budget.allocator()) catch |err| return failed(err);
    if (transfer == 1) {
        resident = null;
        resident_handle = 0;
    }
    return publish(bytes);
}
pub export fn world_close(identity: u64, handle: u64) u32 {
    if (!enter(identity)) return 2;
    defer busy = false;
    if (resident == null or handle == 0 or handle != resident_handle) return reject("InvalidHandle");
    resident.?.close() catch |err| return failed(err);
    resident = null;
    resident_handle = 0;
    return 0;
}

fn reject(message: []const u8) u32 {
    output = &.{};
    diagnostic_length = @min(message.len, diagnostic.len);
    @memcpy(diagnostic[0..diagnostic_length], message[0..diagnostic_length]);
    return 2;
}
fn failed(err: anyerror) u32 {
    if (err != error.OutOfMemory and err != error.Capacity) return reject(@errorName(err));
    const capacity: protocol.Capacity = if (heap.failed) .{
        .arena = .memory,
        .memory_pages = .{ .bytes = heap.required_pages, .provenance = .lower_bound },
    } else if (input_budget.failed) .{
        .arena = .input,
        .input = .{ .bytes = input_budget.required, .provenance = .lower_bound },
    } else if (output_budget.failed) .{
        .arena = .output,
        .output = .{ .bytes = output_budget.required, .provenance = .exact },
    } else .{
        .arena = .working,
        .working = if (working_budget.failed) .{ .bytes = working_budget.required, .provenance = .lower_bound } else .{},
    };
    var empty: [0]u8 = .{};
    var allocator = std.heap.FixedBufferAllocator.init(&empty);
    output = protocol.encode(protocol.Outcome, allocator.allocator(), .{ .needs_capacity = capacity }, &envelope) catch return reject("CapacityEnvelopeUnavailable");
    return 1;
}

const Pages = struct {
    cursor: usize = 0,
    required_pages: u64 = 0,
    failed: bool = false,
    fn grow(context: *anyopaque, minimum: usize) ?[]u8 {
        const self: *Pages = @ptrCast(@alignCast(context));
        const start = (@as(u64, self.cursor) + 15) & ~@as(u64, 15);
        const length = (@as(u64, minimum) + 65535) & ~@as(u64, 65535);
        const end = start + length;
        const pages = (end + 65535) / 65536;
        self.required_pages = @max(self.required_pages, pages);
        if (end > std.math.maxInt(usize) or (pages > @wasmMemorySize(0) and @wasmMemoryGrow(0, @intCast(pages - @wasmMemorySize(0))) == -1)) {
            self.failed = true;
            return null;
        }
        self.cursor = @intCast(end);
        const pointer: [*]u8 = @ptrFromInt(@as(usize, @intCast(start)));
        return pointer[0..@intCast(length)];
    }
};
