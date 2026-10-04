const std = @import("std");
pub fn build(b: *std.Build) void {
    // Zig 0.17 can reuse a sibling --build-file configuration in a shared cache.
    // These standalone helpers share a directory; keep compiled-artifact caching
    // but recompute their configuration so the selected file remains authoritative.
    b.graph.poisonCache();
    const boundary = b.option(std.Build.LazyPath, "boundary-source", "Frozen Boundary") orelse @panic("boundary-source");
    const world_path = b.option(std.Build.LazyPath, "world-source", "Frozen World") orelse @panic("world-source");
    const data = b.createModule(.{ .root_source_file = boundary.path(b, "src/data/root.zig"), .target = b.graph.host, .optimize = .safe });
    const world = b.createModule(.{ .root_source_file = world_path.path(b, "src/root.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "boundary_data", .module = data }} });
    const module = b.createModule(.{ .root_source_file = b.path("replay_bench.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "data", .module = data }, .{ .name = "world", .module = world } } });
    b.installArtifact(b.addExecutable(.{ .name = "replay-bench", .root_module = module }));
}
