//! Compiler-dependent source agreement, separate from World's production build.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const world_source = b.option([]const u8, "world-source", "Exact World checkout") orelse @panic("missing World source");
    const boundary_source = b.option([]const u8, "boundary-v2-source", "Exact Boundary checkout") orelse @panic("missing Boundary source");
    const data = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary_source, "src/v2/data/root.zig" }) },
        .target = b.graph.host,
        .optimize = optimize,
    });
    const boundary = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ boundary_source, "src/v2/root.zig" }) },
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data_v2", .module = data }},
    });
    const world = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_source, "src/root.zig" }) },
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data_v2", .module = data }},
    });
    const borrow_returns = b.createModule(.{
        .root_source_file = .{
            .cwd_relative = b.pathJoin(&.{ boundary_source, "test/v2/borrow_returns.zig" }),
        },
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    });
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ world_source, "test/v2/source_agreement.zig" }) },
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "boundary_data_v2", .module = data },
            .{ .name = "boundary", .module = boundary },
            .{ .name = "borrow_return_fixtures", .module = borrow_returns },
        },
    }) });
    b.getInstallStep().dependOn(&b.addRunArtifact(tests).step);
}
