//! Compiler-dependent source agreement, separate from World's production build.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const world_source = b.option([]const u8, "world-source", "Exact World checkout") orelse @panic("missing World source");
    const boundary_source = b.option([]const u8, "boundary-source", "Exact Boundary checkout") orelse @panic("missing Boundary source");
    const data = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary_source, "src/v2/data/root.zig" }) },
        .target = b.graph.host,
        .optimize = optimize,
    });
    const boundary = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary_source, "src/v2/root.zig" }) },
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
    const borrow_returns = b.createModule(.{
        .root_source_file = .{
            .cwd_relative = b.pathJoin(&.{ boundary_source, "test/v2/borrow_returns.zig" }),
        },
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    });
    const stable_runtime = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_source, "src/interpreter_v2/stable_session.zig" }) },
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    });
    if (b.option(bool, "current-fixtures", "Build the current compiler-dependent fixture tool") orelse false) {
        const fixture = b.addExecutable(.{ .name = "current-fixtures", .root_module = b.createModule(.{
            .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_source, "test/current/fixtures.zig" }) },
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{ .{ .name = "stable_runtime", .module = stable_runtime }, .{ .name = "boundary", .module = boundary } },
        }) });
        b.installArtifact(fixture);
        return;
    }
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_source, "test/v2/stable_source.zig" }) },
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "stable_runtime", .module = stable_runtime },
            .{ .name = "boundary_data", .module = data },
            .{ .name = "boundary", .module = boundary },
            .{ .name = "borrow_return_fixtures", .module = borrow_returns },
        },
    }) });
    b.getInstallStep().dependOn(&b.addRunArtifact(tests).step);
}
