//! Explicit source-pair benchmark; no historical dependency enters normal builds.
const std = @import("std");
pub fn build(b: *std.Build) void {
    const boundary_source = b.option([]const u8, "boundary-source", "Frozen Boundary source") orelse
        @panic("provide -Dboundary-source");
    const legacy_names = b.option(bool, "legacy-names", "Use module names of the frozen older checkout") orelse false;
    const legacy_layout = b.option(bool, "legacy-layout", "Use src/v2 independently of module names") orelse legacy_names;
    const source_prefix = if (legacy_layout) "src/v2" else "src";
    const data_name = if (legacy_names) "boundary_data_v2" else "boundary_data";
    const data = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary_source, source_prefix, "data/root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe });
    const boundary = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary_source, source_prefix, "root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = data_name, .module = data }} });
    if (b.option(bool, "producer-only", "Build only the installation image producer, without World") orelse false) {
        const root = b.createModule(.{ .root_source_file = b.path("producer_bench.zig"), .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "boundary_data", .module = data } } });
        b.installArtifact(b.addExecutable(.{ .name = "producer-bench", .root_module = root }));
        return;
    }
    const world_source = b.option([]const u8, "world-source", "Frozen World source") orelse
        @panic("provide -Dworld-source");
    const world = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_source, "src/root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = data_name, .module = data }} });
    const fixtures = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary_source, "test/v2/compact_fixtures.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = "boundary", .module = boundary }} });
    const root = b.createModule(.{ .root_source_file = b.path("execution_bench.zig"), .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "world", .module = world }, .{ .name = "compact_fixtures", .module = fixtures } } });
    b.installArtifact(b.addExecutable(.{ .name = "execution-bench", .root_module = root }));
}
