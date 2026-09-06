// Copyright (c) 2026 World contributors. MIT license.
//! Stateless guest entry points. Every invocation starts from caller-supplied bytes.
const std = @import("std");
const data = @import("boundary_data_v2");
const process = @import("world").process_v2;
const options = @import("kernel_options");

var initial_input: [options.input_capacity]u8 align(16) = undefined;
var initial_working: [options.working_capacity]u8 align(16) = undefined;
var initial_output: [options.output_capacity]u8 align(16) = undefined;
var envelope: [256]u8 = undefined;
var diagnostic: [256]u8 = undefined;
var input: []u8 = &initial_input;
var output: []u8 = &initial_output;
var output_length: usize = 0;
var diagnostic_length: usize = 0;
var heap: Pages = .{};
var prepared = false;
extern var __heap_base: u8;

pub export fn world_process_v2_abi_version() u32 {
    return 2;
}
pub export fn world_process_v2_input_ptr() u32 {
    return @intCast(@intFromPtr(input.ptr));
}
pub export fn world_process_v2_input_capacity() u64 {
    return input.len;
}
pub export fn world_process_v2_output_ptr() u32 {
    return @intCast(@intFromPtr(output.ptr));
}
pub export fn world_process_v2_output_len() u64 {
    return output_length;
}
pub export fn world_process_v2_error_ptr() u32 {
    return @intCast(@intFromPtr(&diagnostic));
}
pub export fn world_process_v2_error_len() u64 {
    return diagnostic_length;
}

pub export fn world_process_v2_prepare_input(length: u64) u32 {
    output_length = 0;
    diagnostic_length = 0;
    prepared = false;
    input = &initial_input;
    output = &initial_output;
    heap = .{ .cursor = @intFromPtr(&__heap_base) };
    if (length > std.math.maxInt(usize)) return reject("InvalidInputLength");
    if (length > input.len) {
        input = heap.reserve(@intCast(length)) orelse {
            reportCapacity(.{
                .arena = .input,
                .input = .{ .bytes = length, .provenance = .exact },
                .memory_pages = .{ .bytes = heap.required_pages, .provenance = .lower_bound },
            });
            return 1;
        };
    }
    prepared = true;
    return 0;
}

pub export fn world_process_v2_execute(length: u64) u32 {
    output_length = 0;
    diagnostic_length = 0;
    if (!prepared) return reject("InputNotPrepared");
    prepared = false;
    if (length > input.len) return reject("InvalidInputLength");
    var storage = process.Workspace.init(&initial_working);
    storage.grow_context = &heap;
    storage.grow = Pages.grow;
    execute(input[0..@intCast(length)], &storage) catch |err| {
        if (err == error.OutOfMemory) {
            reportCapacity(.{
                .arena = .working,
                .working = .{ .bytes = storage.required, .provenance = .lower_bound },
                .memory_pages = if (heap.failed) .{ .bytes = heap.required_pages, .provenance = .lower_bound } else .{},
            });
            return 0;
        }
        return reject(@errorName(err));
    };
    return 0;
}

fn execute(bytes: []const u8, storage: *process.Workspace) !void {
    const allocator = storage.allocator();
    const invocation = try data.protocol.decode(data.protocol.Input, allocator, bytes);
    var result = try process.invoke(allocator, invocation);
    defer result.deinit();
    const needed = try data.protocol.encodedLength(data.protocol.Outcome, result.record);
    if (needed > output.len) {
        output = heap.reserve(needed) orelse {
            reportCapacity(.{
                .arena = .output,
                .output = .{ .bytes = needed, .provenance = .exact },
                .memory_pages = .{ .bytes = heap.required_pages, .provenance = .lower_bound },
            });
            return;
        };
    }
    const encoded = try data.protocol.encode(data.protocol.Outcome, allocator, result.record, output);
    output_length = encoded.len;
}

fn reject(message: []const u8) u32 {
    output_length = 0;
    diagnostic_length = @min(message.len, diagnostic.len);
    @memcpy(diagnostic[0..diagnostic_length], message[0..diagnostic_length]);
    return 2;
}

fn reportCapacity(capacity: data.protocol.Capacity) void {
    output = &envelope;
    var zero: [0]u8 = .{};
    var allocator = std.heap.FixedBufferAllocator.init(&zero);
    const encoded = data.protocol.encode(data.protocol.Outcome, allocator.allocator(), .{ .needs_capacity = capacity }, output) catch {
        _ = reject("CapacityEnvelopeUnavailable");
        return;
    };
    output_length = encoded.len;
}

const Pages = struct {
    cursor: usize = 0,
    required_pages: u64 = 0,
    failed: bool = false,

    fn reserve(self: *Pages, length: usize) ?[]u8 {
        const start = (@as(u64, self.cursor) + 15) & ~@as(u64, 15);
        const end = start + length;
        const pages = (end + 65535) / 65536;
        self.required_pages = @max(self.required_pages, pages);
        if (end > std.math.maxInt(usize)) {
            self.failed = true;
            return null;
        }
        const current = @wasmMemorySize(0);
        if (pages > current) {
            const extra: usize = @intCast(pages - current);
            if (@wasmMemoryGrow(0, extra) == -1) {
                self.failed = true;
                return null;
            }
        }
        self.cursor = @intCast(end);
        const pointer: [*]u8 = @ptrFromInt(@as(usize, @intCast(start)));
        return pointer[0..length];
    }

    fn grow(context: *anyopaque, minimum: usize) ?[]u8 {
        const self: *Pages = @ptrCast(@alignCast(context));
        const rounded = (@as(u64, minimum) + 65535) & ~@as(u64, 65535);
        if (rounded > std.math.maxInt(usize)) {
            self.failed = true;
            self.required_pages = 65536;
            return null;
        }
        return self.reserve(@intCast(rounded));
    }
};
