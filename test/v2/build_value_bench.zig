//! Explicit source-pair benchmark; no historical dependency enters normal builds.
const std = @import("std");
pub fn build(b: *std.Build) void {
    const boundary_source = b.option([]const u8, "boundary-source", "Frozen Boundary source") orelse
        @panic("provide -Dboundary-source");
    const world_source = b.option([]const u8, "world-source", "Frozen World source") orelse
        @panic("provide -Dworld-source");
    const data = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary_source, "src/v2/data/root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe });
    const boundary = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary_source, "src/v2/root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = "boundary_data_v2", .module = data }} });
    const world = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_source, "src/root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = "boundary_data_v2", .module = data }} });
    const root = b.createModule(.{ .root_source_file = b.path("value_bench.zig"), .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "world", .module = world } } });
    b.installArtifact(b.addExecutable(.{ .name = "value-bench", .root_module = root }));
}
