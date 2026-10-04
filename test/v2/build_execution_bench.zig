//! Explicit source-pair benchmark; no historical dependency enters normal builds.
const std = @import("std");
pub fn build(b: *std.Build) void {
    // Zig 0.17 can reuse a sibling --build-file configuration in a shared cache.
    // These standalone helpers share a directory; keep compiled-artifact caching
    // but recompute their configuration so the selected file remains authoritative.
    b.graph.poisonCache();
    const boundary_source = b.option(std.Build.LazyPath, "boundary-source", "Frozen Boundary source") orelse
        @panic("provide -Dboundary-source");
    const data = b.createModule(.{ .root_source_file = boundary_source.path(b, "src/data/root.zig"), .target = b.graph.host, .optimize = .safe });
    const boundary = b.createModule(.{ .root_source_file = boundary_source.path(b, "src/root.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "boundary_data", .module = data }} });
    if (b.option(bool, "producer-only", "Build only the installation image producer, without World") orelse false) {
        const root = b.createModule(.{ .root_source_file = b.path("producer_bench.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "boundary_data", .module = data } } });
        b.installArtifact(b.addExecutable(.{ .name = "producer-bench", .root_module = root }));
        return;
    }
    const world_source = b.option(std.Build.LazyPath, "world-source", "Frozen World source") orelse
        @panic("provide -Dworld-source");
    const world = b.createModule(.{ .root_source_file = world_source.path(b, "src/root.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "boundary_data", .module = data }} });
    const fixtures = b.createModule(.{ .root_source_file = boundary_source.path(b, "test/v2/compact_fixtures.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "boundary", .module = boundary }} });
    const root = b.createModule(.{ .root_source_file = b.path("execution_bench.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "world", .module = world }, .{ .name = "compact_fixtures", .module = fixtures } } });
    b.installArtifact(b.addExecutable(.{ .name = "execution-bench", .root_module = root }));
}
