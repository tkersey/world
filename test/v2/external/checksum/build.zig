const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const boundary = b.dependency("boundary", .{ .target = target, .optimize = .ReleaseSafe }).module("boundary");
    const options = b.addOptions();
    options.addOption(bool, "source", b.option(bool, "source", "Emit source terms for independent checking") orelse false);
    const root = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = .ReleaseSafe, .imports = &.{.{ .name = "boundary", .module = boundary }} });
    root.addOptions("options", options);
    const compiler = b.addExecutable(.{ .name = "compile-checksum", .root_module = root });
    b.step("emit", "Compile the checksum application into portable data").dependOn(&b.addRunArtifact(compiler).step);
}
