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
        const world = b.createModule(.{
            .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_source, "src/root.zig" }) },
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
        for ([_]struct { name: []const u8, file: []const u8, fixture: ?[]const u8, owner: []const u8 }{
            .{ .name = "scalar-fixture", .file = "scalar_batch_fixture.zig", .fixture = null, .owner = "" },
            .{ .name = "frame-fixture", .file = "frame_reuse_fixture.zig", .fixture = "frame_reuse_tests.zig", .owner = "frame_fixture" },
            .{ .name = "blob-fixture", .file = "blob_retention_fixture.zig", .fixture = "blob_retention_tests.zig", .owner = "retention_fixture" },
        }) |item| {
            const module = b.createModule(.{
                .root_source_file = b.path(item.file),
                .target = b.graph.host,
                .optimize = optimize,
                .imports = &.{.{ .name = "boundary_data", .module = data }},
            });
            if (item.fixture) |fixture| module.addImport(item.owner, b.createModule(.{
                .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_source, "src/interpreter_v2", fixture }) },
                .target = b.graph.host,
                .optimize = optimize,
                .imports = &.{.{ .name = "boundary_data", .module = data }},
            }));
            b.installArtifact(b.addExecutable(.{ .name = item.name, .root_module = module }));
        }
        for ([_][]const u8{ "scalar_batch_memory", "scalar_batch_bench", "resident_cost", "resident_lifecycle_cost" }) |name| {
            const executable = b.addExecutable(.{ .name = name, .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("{s}.zig", .{name})),
                .target = b.graph.host,
                .optimize = optimize,
                .imports = &.{ .{ .name = "world", .module = world }, .{ .name = "boundary_data", .module = data } },
            }) });
            b.installArtifact(executable);
        }
        if (b.option([]const u8, "agent-source", "Fixed A0 native test consumer")) |agent_source| {
            const consumer = b.addExecutable(.{ .name = "agent-native", .root_module = b.createModule(.{
                .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ agent_source, "test/agent4/native.zig" }) },
                .target = b.graph.host,
                .optimize = optimize,
                .imports = &.{ .{ .name = "world", .module = world }, .{ .name = "boundary_data", .module = data } },
            }) });
            b.installArtifact(consumer);
        }
    }
}
