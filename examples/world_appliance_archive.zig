const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const manifest = common.StrictAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    var output = try common.submitAndDecode(&core, allocator, manifest, common.bootCommand(manifest));
    defer output.deinit(allocator);
    if (output.status != .completed) return error.ExpectedCompletedOutput;
    const output_batch_fingerprint = output.archive_append_batch_fingerprint orelse return error.ExpectedArchiveAppendBatch;

    var archive = try world.Archive.Memory.open(allocator, .{});
    defer archive.deinit();
    var plan = try world.Appliance.ArchivePlan.initForTurnOutput(
        allocator,
        archive.image.latestCursor(),
        output,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer plan.deinit();
    const moment = try archive.appendBatch(plan.append_batch);
    const seal = archive.image.latestSeal() orelse return error.ObjectMissing;
    const ack = world.Appliance.RetentionAck.init(.{
        .append_batch_fingerprint = output_batch_fingerprint,
        .resulting_moment_fingerprint = moment.moment_fingerprint,
        .resulting_seal_fingerprint = seal.seal_fingerprint,
        .resulting_chronicle_cursor_fingerprint = moment.chronicle_resulting_cursor.cursor_fingerprint,
        .host_claim_status = .responded,
    });
    try ack.validate(output_batch_fingerprint, world.Appliance.Capacity.tiny_one_port);

    try stdout.print("archive_batches=1\n", .{});
    try stdout.print("output_archive_request={x}\n", .{output_batch_fingerprint});
    try stdout.print("archive_objects={d}\n", .{plan.objects.len});
    try stdout.print("retention_ack={x}\n", .{ack.ack_fingerprint});
    try stdout.print("moment={x}\n", .{moment.moment_fingerprint});
    try stdout.flush();
}
