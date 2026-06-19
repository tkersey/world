const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const manifest = common.PortsAppliance.manifest();
    var seed = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer seed.reset();
    try common.submit(&seed, allocator, common.bootCommand(manifest));
    var boot_output = try common.decodeOutput(allocator, manifest, seed.readOutput());
    defer boot_output.deinit(allocator);
    const checkpoint = boot_output.checkpoint;
    const reply = common.hostReplyFor(checkpoint.outstanding_host_requests[0], 0xC0DE_0003);
    const command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = checkpoint.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = checkpoint.previous_turn_receipt_fingerprint,
        .host_replies = &.{reply},
    });

    var resident = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer resident.reset();
    try resident.restore(checkpoint);
    try common.submit(&resident, allocator, command);

    var restored = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer restored.reset();
    try restored.restore(checkpoint);
    try common.submit(&restored, allocator, command);

    const report = world.Appliance.ReconstructionReport.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .resident_turn_output_fingerprint = common.bytesFingerprint(resident.readOutput()),
        .reconstructed_turn_output_fingerprint = common.bytesFingerprint(restored.readOutput()),
    });
    try report.validate(manifest.manifest_fingerprint);

    try stdout.print("reconstruction_equivalent={}\n", .{report.equivalent});
    try stdout.print("resident_output={x}\n", .{report.resident_turn_output_fingerprint});
    try stdout.print("restored_output={x}\n", .{report.reconstructed_turn_output_fingerprint});
    try stdout.flush();
}
