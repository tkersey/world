const std = @import("std");
pub fn build(b: *std.Build) void {
    const boundary = b.option([]const u8, "boundary-source", "Frozen Boundary") orelse @panic("boundary-source");
    const world_path = b.option([]const u8, "world-source", "Frozen World") orelse @panic("world-source");
    const legacy = b.option(bool, "legacy-names", "Frozen predecessor names") orelse false;
    const data = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary, "src/v2/data/root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe });
    const world = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_path, "src/root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = if (legacy) "boundary_data_v2" else "boundary_data", .module = data }} });
    const module = b.createModule(.{ .root_source_file = b.path("replay_bench.zig"), .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{ .{ .name = "data", .module = data }, .{ .name = "world", .module = world } } });
    b.installArtifact(b.addExecutable(.{ .name = "replay-bench", .root_module = module }));
}
