//! Same-operation Session rollback discriminator for W0 and both candidates.
const std = @import("std");
const runtime = @import("runtime");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const path = args.next() orelse return error.Image;
    const mode = args.next() orelse "direct";
    const removed = std.mem.eql(u8, mode, "removed");
    if (!removed and !std.mem.eql(u8, mode, "direct")) return error.Mode;
    const image = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(64 << 20));
    defer init.gpa.free(image);
    var arguments: [16]u8 = undefined;
    std.mem.writeInt(u64, arguments[0..8], 1, .little);
    std.mem.writeInt(u64, arguments[8..16], 17, .little);
    var session = try runtime.Session.initImage(init.gpa, image, &arguments);
    defer session.deinit();
    var ids = session.frames.entries.keyIterator();
    const id = (ids.next() orelse return error.NoFrame).*;
    const descriptor = try session.frames.get(id);
    var slots = try session.frames.slots.iterator(descriptor.view);
    const binding = (try slots.next()) orelse return error.NoSlot;
    const before = try session.checkpoint(init.gpa);
    defer init.gpa.free(before);
    var transaction = try session.begin();
    var changed = binding.value;
    changed.body.scalar[0] ^= 1;
    if (removed) {
        const removal = session.frames.remove(id);
        if (@typeInfo(@TypeOf(removal)) == .error_union) try removal;
    }
    const mutation = session.frames.slots.set(descriptor.view, binding.slot, changed);
    transaction.rollback(&session);
    const restored = try session.frames.get(id);
    const value = try session.frames.slots.get(restored.view, binding.slot);
    try std.testing.expectEqualDeep(binding.value, value);
    const after = try session.checkpoint(init.gpa);
    defer init.gpa.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
    if (removed) try std.testing.expectError(error.InvalidHandle, mutation) else try mutation;
}
