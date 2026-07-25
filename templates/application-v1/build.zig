const std = @import("std");
const world = @import("world");

pub fn build(b: *std.Build) void {
    _ = world.addApplicationWasm(b, .{
        .name = "research-digest-agent",
        .root_source_file = b.path("src/application.zig"),
        .application_decl = "Application",
        .memory = .{
            .initial_pages = 512,
            .maximum_pages = 512,
        },
        .install_human_readable_manifest = true,
    });
}
