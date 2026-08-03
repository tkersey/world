const std = @import("std");
const world = @import("world");

pub fn build(b: *std.Build) void {
    const application = world.addApplicationWasm(b, .{
        .name = "research-digest-agent",
        .root_source_file = b.path("../../templates/application-v1/src/application.zig"),
        .application_decl = "Application",
        .stack_size_bytes = 4 * 1024 * 1024,
        .memory = .{
            .initial_pages = 576,
            .maximum_pages = 576,
        },
        .install_human_readable_manifest = true,
    });
    const world_dependency = b.dependencyFromBuildZig(world, .{
        .target = b.graph.host,
        .optimize = .ReleaseSmall,
    });
    const lifecycle = b.addSystemCommand(&.{"node"});
    lifecycle.addFileArg(world_dependency.path(
        "scripts/world_application_v1_research_digest_conformance.mjs",
    ));
    lifecycle.addFileArg(application.wasm.getEmittedBin());
    lifecycle.addFileArg(application.manifest);
    b.getInstallStep().dependOn(&lifecycle.step);
}
