const std = @import("std");
const protocol = @import("application_v1.zig");

/// Fixed memory regions compiled into one application-specific WASM module.
pub const Options = struct {
    input_capacity: usize = 8 * 1024 * 1024,
    output_capacity: usize = 4 * 1024 * 1024,
    scratch_capacity: usize = 16 * 1024 * 1024,
    manifest_capacity: usize = 64 * 1024,
    error_capacity: usize = 256,
};

/// Bind a closed World application to the import-free Application ABI v1.
///
/// The returned namespace owns only reusable byte regions. A Frame remains the
/// complete semantic state, so resetting or discarding the namespace cannot
/// change application meaning.
pub fn ApplicationAbi(comptime App: type, comptime options: Options) type {
    requireApplication(App);
    validateOptions(options);
    validateApplicationRegions(App, options);

    return struct {
        const Self = @This();

        pub const abi_version = protocol.abi_version;
        pub const application_id = App.Manifest.application_id;
        pub const manifest_bytes = blk: {
            @setEvalBranchQuota(2_000_000);
            var storage: [options.manifest_capacity]u8 = undefined;
            var fixed = std.heap.FixedBufferAllocator.init(&storage);
            const encoded = App.Manifest.encode(fixed.allocator()) catch |err| {
                @compileError("World application manifest does not fit the WASM manifest region: " ++ @errorName(err));
            };
            const result: [encoded.len]u8 = encoded[0..encoded.len].*;
            break :blk result;
        };

        var input_storage: [options.input_capacity]u8 align(16) = [_]u8{0} ** options.input_capacity;
        var output_storage: [options.output_capacity]u8 align(16) = [_]u8{0} ** options.output_capacity;
        var scratch_storage: [options.scratch_capacity]u8 align(16) = [_]u8{0} ** options.scratch_capacity;
        var error_storage: [options.error_capacity]u8 align(16) = [_]u8{0} ** options.error_capacity;
        var scratch = std.heap.FixedBufferAllocator.init(&scratch_storage);
        var output_length: u32 = 0;
        var error_length: u32 = 0;

        pub fn worldAbiVersion() u32 {
            return abi_version;
        }

        pub fn worldManifestPtr() u32 {
            return pointerToU32(&manifest_bytes);
        }

        pub fn worldManifestLen() u32 {
            return @intCast(manifest_bytes.len);
        }

        pub fn worldInputPtr() u32 {
            return pointerToU32(&input_storage);
        }

        pub fn worldInputCapacity() u32 {
            return @intCast(input_storage.len);
        }

        pub fn worldStep(input_len: u32) u32 {
            output_length = 0;
            clearError();
            scratch.reset();

            if (input_len == 0 or input_len > input_storage.len) {
                return fail(.malformed_input, "StepInput is empty or exceeds the input region");
            }

            const allocator = scratch.allocator();
            var input = protocol.StepInput.decode(
                allocator,
                input_storage[0..input_len],
                App.Limits,
            ) catch |err| return fail(decodeStatus(err), @errorName(err));
            defer input.deinit(allocator);

            var frame = App.step(allocator, input) catch |err| {
                return fail(stepStatus(err), @errorName(err));
            };
            defer frame.deinit(allocator);

            const encoded = App.encodeFrame(allocator, frame) catch |err| {
                return fail(stepStatus(err), @errorName(err));
            };
            if (encoded.len > output_storage.len) {
                return fail(.resource_limit, "Frame exceeds the output region");
            }
            @memcpy(output_storage[0..encoded.len], encoded);
            output_length = @intCast(encoded.len);
            return if (frame.status == .yielded_fuel)
                @intFromEnum(Status.yielded_fuel)
            else
                @intFromEnum(Status.success);
        }

        pub fn worldOutputPtr() u32 {
            return pointerToU32(&output_storage);
        }

        pub fn worldOutputLen() u32 {
            return output_length;
        }

        pub fn worldErrorPtr() u32 {
            return pointerToU32(&error_storage);
        }

        pub fn worldErrorLen() u32 {
            return error_length;
        }

        pub fn worldReset() u32 {
            scratch.reset();
            output_length = 0;
            clearError();
            return @intFromEnum(Status.success);
        }

        fn clearError() void {
            error_length = 0;
        }

        fn fail(status: Status, message: []const u8) u32 {
            const length = @min(message.len, error_storage.len);
            @memcpy(error_storage[0..length], message[0..length]);
            error_length = @intCast(length);
            output_length = 0;
            return @intFromEnum(status);
        }

        fn pointerToU32(pointer: anytype) u32 {
            return @intCast(@intFromPtr(pointer));
        }
    };
}

/// Application ABI v1 result code.
pub const Status = enum(u32) {
    success = 0,
    malformed_input = 1,
    application_mismatch = 2,
    state_validation = 3,
    effect_result_validation = 4,
    yielded_fuel = 5,
    resource_limit = 6,
    deterministic_failure = 7,
};

fn requireApplication(comptime App: type) void {
    if (!@hasDecl(App, "Manifest") or !@hasDecl(App, "Limits") or
        !@hasDecl(App, "step") or !@hasDecl(App, "encodeFrame"))
    {
        @compileError("World Application ABI requires a type returned by world.application");
    }
    if (App.Manifest.world_application_abi_version != protocol.abi_version) {
        @compileError("World application and WASM ABI versions do not match");
    }
}

fn validateOptions(comptime options: Options) void {
    inline for (.{
        .{ "input_capacity", options.input_capacity },
        .{ "output_capacity", options.output_capacity },
        .{ "scratch_capacity", options.scratch_capacity },
        .{ "manifest_capacity", options.manifest_capacity },
        .{ "error_capacity", options.error_capacity },
    }) |field| {
        if (field[1] == 0 or field[1] > std.math.maxInt(u32)) {
            @compileError("World application WASM " ++ field[0] ++ " must fit a non-empty u32 region");
        }
    }
}

fn validateApplicationRegions(comptime App: type, comptime options: Options) void {
    const limits = App.Limits;
    const required_input = 4096 +
        @as(u64, limits.maximum_state_bytes) +
        @as(u64, limits.maximum_payload_bytes) +
        @as(u64, limits.maximum_result_bytes) +
        @as(u64, limits.maximum_failure_bytes) +
        @as(u64, limits.maximum_initial_args_bytes) +
        @as(u64, limits.maximum_result_bytes) +
        @as(u64, limits.maximum_host_claim_bytes) +
        @as(u64, limits.maximum_host_metadata_bytes);
    const required_output = 1024 +
        @as(u64, limits.maximum_state_bytes) +
        @as(u64, limits.maximum_payload_bytes) +
        @as(u64, limits.maximum_result_bytes) +
        @as(u64, limits.maximum_failure_bytes);
    if (options.input_capacity < required_input) {
        @compileError("World application WASM input region is smaller than the declared StepInput limits");
    }
    if (options.output_capacity < required_output) {
        @compileError("World application WASM output region is smaller than the declared Frame limits");
    }
    if (options.scratch_capacity < required_input + required_output) {
        @compileError("World application WASM scratch region is smaller than one admitted input plus output");
    }
}

fn decodeStatus(err: protocol.Error) Status {
    return switch (err) {
        error.ApplicationMismatch => .application_mismatch,
        error.LimitExceeded, error.OutOfMemory => .resource_limit,
        else => .malformed_input,
    };
}

fn stepStatus(err: protocol.Error) Status {
    return switch (err) {
        error.ApplicationMismatch => .application_mismatch,
        error.InvalidFrame,
        error.InvalidIdentity,
        error.InvalidEncoding,
        error.TrailingBytes,
        error.UnsupportedVersion,
        => .state_validation,
        error.DuplicateResultTarget,
        error.EffectResultMismatch,
        error.InvalidRequest,
        error.InvalidResult,
        error.StaleResultTarget,
        error.UnexpectedResultTarget,
        => .effect_result_validation,
        error.LimitExceeded, error.OutOfMemory => .resource_limit,
        error.InvalidManifest => .deterministic_failure,
    };
}

test {
    _ = ApplicationAbi;
}
