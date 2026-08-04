const std = @import("std");
const application_build = @import("world_application_build_support");
const application_wasm = @import("world_application_wasm_v1");

test "build support tracks the default Application ABI fixed regions" {
    const options: application_wasm.Options = .{};
    const actual = @as(u64, options.input_capacity) +
        @as(u64, options.output_capacity) +
        @as(u64, options.scratch_capacity) +
        @as(u64, options.manifest_capacity) +
        @as(u64, options.error_capacity);
    try std.testing.expectEqual(
        actual,
        application_build.default_application_abi_fixed_region_bytes,
    );
}

test "World application stack and fixed regions must fit initial memory" {
    const initial_bytes: u64 = 512 * 64 * 1024;
    const maximum_stack = initial_bytes -
        application_build.default_application_abi_fixed_region_bytes;

    try application_build.validateStackMemoryEnvelope(maximum_stack, 512);
    try std.testing.expectError(
        error.StackExceedsInitialMemory,
        application_build.validateStackMemoryEnvelope(maximum_stack + 1, 512),
    );
    try std.testing.expectError(
        error.StackExceedsInitialMemory,
        application_build.validateStackMemoryEnvelope(std.math.maxInt(u64), 512),
    );
}
