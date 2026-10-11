const std = @import("std");
pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const dependency = b.dependency("kronos", .{ .target = target, .optimize = optimize });
    const module = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "kronos", .module = dependency.module("kronos") }} });
    module.addAnonymousImport("image", .{ .root_source_file = b.option(std.Build.LazyPath, "image", "Existing independently emitted program") orelse @panic("provide -Dimage") });
    const executable = b.addExecutable(.{ .name = "kronos-native-consumer", .root_module = module });
    b.getInstallStep().dependOn(&b.addRunArtifact(executable).step);
}
