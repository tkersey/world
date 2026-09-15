const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const dependency = b.dependency("boundary", .{ .target = target, .optimize = .ReleaseSafe });
    const options = b.addOptions();
    options.addOption(bool, "source", b.option(bool, "source", "Emit source terms") orelse false);
    options.addOption(bool, "compact", b.option(bool, "compact", "Emit the compact successor codec") orelse false);
    const packed_probe = b.option(bool, "packed-probe", "Compile the post-BPC1-freeze request/XOR consumer") orelse false;
    const ordered_pair = b.option(bool, "ordered-pair", "Compile the post-reader-freeze sorting consumer") orelse false;
    const squares = b.option(bool, "squares", "Compile the post-freeze recursive sum-of-squares consumer") orelse false;
    const bytes = b.option(bool, "bytes", "Compile the post-freeze byte-length consumer") orelse false;
    const root = b.createModule(.{
        .root_source_file = b.path(if (ordered_pair) "ordered_pair.zig" else if (packed_probe) "request_xor.zig" else if (bytes) "byte_length.zig" else if (squares) "sum_squares.zig" else "main.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "boundary", .module = dependency.module("boundary") }},
    });
    root.addOptions("options", options);
    const compiler = b.addExecutable(.{ .name = "compile-consent-scan", .root_module = root });
    b.step("emit", "Compile composed consent handlers into portable data")
        .dependOn(&b.addRunArtifact(compiler).step);
}
