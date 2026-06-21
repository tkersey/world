const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
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

    var boot = try common.submitAndDecode(&core, allocator, manifest, common.bootCommand(manifest));
    defer boot.deinit(allocator);
    if (boot.status != .needs_host or boot.host_requests.len != 1) return error.WorldSeedOnePortRequestMissing;

    const reply = common.hostReplyFor(boot.host_requests[0], 0x5100_0001);
    const command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = boot.turn_receipt.receipt_fingerprint,
        .host_replies = &.{reply},
    });
    var done = try common.submitAndDecode(&core, allocator, manifest, command);
    defer done.deinit(allocator);
    if (done.status != .completed) return error.WorldSeedOnePortNotCompleted;

    try stdout.print("world_seed=one_port\n", .{});
    try stdout.print("host_requests={d}\n", .{boot.host_requests.len});
    try stdout.print("payload_bytes_present={}\n", .{boot.host_requests[0].payload_value_image_bytes.len != 0});
    try stdout.print("result_bytes_present={}\n", .{done.root_result_value_image_bytes.len != 0});
    try stdout.print("completed={}\n", .{done.status == .completed});
    try stdout.flush();
}
