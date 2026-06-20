const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const manifest = common.PortsAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    try common.submit(&core, allocator, common.bootCommand(manifest));

    try stdout.print("appliance=one_port\n", .{});
    try stdout.print("turn_state={s}\n", .{@tagName(core.state)});
    try stdout.print("actuation_bindings={d}\n", .{manifest.actuation_binding_fingerprints.len});
    try stdout.print("checkpoint_every_turn={}\n", .{manifest.enabled_features.checkpoint_every_turn});
    try stdout.print("output_bytes={d}\n", .{core.readOutput().len});
    try stdout.print("turn_receipt={x}\n", .{core.previous_turn_receipt_fingerprint.?});
    try stdout.flush();
}
