const std = @import("std");
const world = @import("world");

pub fn build(b: *std.Build) void {
    _ = world.addApplicationWasm(b, .{
        .name = "research-digest-agent",
        .root_source_file = b.path("src/application.zig"),
        .application_decl = "Application",
        .stack_size_bytes = 4 * 1024 * 1024,
        .memory = .{
            .initial_pages = 576,
            .maximum_pages = 576,
        },
        .install_human_readable_manifest = true,
    });
}
