//! Test-only compiler and runtime inputs remain independently pinned by callers.
const std = @import("std");
pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const compiler_source = b.option([]const u8, "compiler-source", "Fixed C0 compiler") orelse @panic("compiler-source required");
    const compiler_data = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ compiler_source, "src/data/root.zig" }) },
        .target = b.graph.host,
        .optimize = optimize,
    });
    const compiler = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ compiler_source, "src/root.zig" }) },
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = compiler_data }},
    });
    const emitter = b.addExecutable(.{ .name = "retained-history-fixture", .root_module = b.createModule(.{
        .root_source_file = b.path("retained_history_fixture.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = compiler }},
    }) });
    b.installArtifact(emitter);
    if (b.option([]const u8, "world-source", "Runtime source for the probe")) |world_source| {
        const data_source = b.option([]const u8, "data-source", "Fixed D0 data") orelse @panic("data-source required");
        const data = b.createModule(.{
            .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ data_source, "src/data/root.zig" }) },
            .target = b.graph.host,
            .optimize = optimize,
        });
        const runtime = b.createModule(.{
            .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_source, "src/interpreter_v2/stable_session.zig" }) },
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{.{ .name = "boundary_data", .module = data }},
        });
        const probe = b.addExecutable(.{ .name = "retained-history-native", .root_module = b.createModule(.{
            .root_source_file = b.path("retained_history_native.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{ .{ .name = "runtime", .module = runtime }, .{ .name = "boundary_data", .module = data } },
        }) });
        b.installArtifact(probe);
    }
}
