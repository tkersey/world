//! Explicit source-pair benchmark; no historical dependency enters normal builds.
const std = @import("std");
pub fn build(b: *std.Build) void {
    const boundary_source = b.option([]const u8, "boundary-source", "Frozen Boundary source") orelse
        @panic("provide -Dboundary-source");
    const world_source = b.option([]const u8, "world-source", "Frozen World source") orelse
        @panic("provide -Dworld-source");
    const legacy_names = b.option(bool, "legacy-names", "Use layout and module names of the frozen older checkout") orelse false;
    const source_prefix = if (legacy_names) "src/v2" else "src";
    const data_name = if (legacy_names) "boundary_data_v2" else "boundary_data";
    const data = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary_source, source_prefix, "data/root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe });
    const boundary = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary_source, source_prefix, "root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = data_name, .module = data }} });
    const world = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_source, "src/root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = data_name, .module = data }} });
    const root = b.createModule(.{ .root_source_file = b.path("value_bench.zig"), .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "world", .module = world } } });
    b.installArtifact(b.addExecutable(.{ .name = "value-bench", .root_module = root }));
}
