//! A source-package consumer of the actual public native module.
const std = @import("std");
const kronos = @import("kronos");
pub fn main(init: std.process.Init) !void {
    var session = try kronos.Session.initImage(init.gpa, @embedFile("image"), &.{});
    defer session.deinit();
    const outcome = try session.run(null);
    if (outcome != .completed) return error.UnexpectedOutcome;
    const value = try session.bytes(&outcome.completed);
    if (!std.mem.eql(u8, value, &.{ 0x20, 8, 0, 0, 0, 0, 0, 0 })) return error.UnexpectedValue;
}
