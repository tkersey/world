const std = @import("std");
const application_build = @import("world_application_build_support");

test "World application stack must fit configured initial memory" {
    try application_build.validateStackMemoryEnvelope(32 * 1024 * 1024, 512);
    try std.testing.expectError(
        error.StackExceedsInitialMemory,
        application_build.validateStackMemoryEnvelope(64 * 1024 * 1024, 512),
    );
}
