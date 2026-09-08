const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const dependency = b.dependency("boundary", .{ .target = target, .optimize = .ReleaseSafe });
    const options = b.addOptions();
    options.addOption(bool, "source", b.option(bool, "source", "Emit source terms") orelse false);
    const root = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "boundary", .module = dependency.module("boundary") }},
    });
    root.addOptions("options", options);
    const compiler = b.addExecutable(.{ .name = "compile-prefix-maximum", .root_module = root });
    b.step("emit", "Compile a stateful prefix maximum into portable data")
        .dependOn(&b.addRunArtifact(compiler).step);
}
