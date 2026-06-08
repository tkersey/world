const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

fn completedRootSlot(allocator: std.mem.Allocator, runspace: *world.Runspace, target_ref: world.TargetRef) !void {
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = runspace.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
    });
    try runspace.slots.append(allocator, world.Runspace.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = target_ref,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .status = .completed,
        }),
        .status = .completed,
    }));
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const root_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const root_import = world.ImportRequirement.fromTargetPort(fixtures.Ports.Target, 0);
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    const provider_export = world.Linker.ExportDescriptor.init(.{
        .target_ref = provider_ref,
        .result_ref = .{ .value_table_id = root_import.response_value_table_id, .value_ref_fingerprint = root_import.response_value_ref_fingerprint },
        .label = "strict-provider-main",
    });
    const entries = [_]world.Linker.Catalog.Entry{
        world.Linker.Catalog.Entry.generatedTarget(.{
            .target_ref = provider_ref,
            .export_descriptor = provider_export,
            .import_set = world.ImportSet.fromTarget(fixtures.Strict.Target),
            .label = "strict-provider",
        }),
    };
    var linked = try world.Linker.link(allocator, .{
        .root_target_ref = root_ref,
        .root_import_set = world.ImportSet.fromTarget(fixtures.Ports.Target),
        .root_imports = &.{root_import},
        .catalog = world.Linker.Catalog.init(&entries),
        .policy = .strict_closed,
    });
    defer linked.deinit();

    var source = world.Runspace.init(allocator, .{});
    defer source.deinit();
    try linked.assembly.installIntoRunspace(&source);
    try completedRootSlot(allocator, &source, root_ref);

    var capsule = try world.Capsule.freezeAssembly(&source, linked.assembly, .{});
    defer capsule.deinit(allocator);
    var receiver = world.Runspace.init(allocator, .{});
    defer receiver.deinit();
    var restore = try world.Capsule.thawIntoRunspace(capsule, &receiver, root_ref.target_ref_fingerprint, 0, 0x5150_c001, .{
        .mode = .restore_completed,
        .local_catalog_fingerprint = linked.plan.catalog_fingerprint,
    });
    defer restore.deinit(allocator);

    try stdout.print("capsule_fingerprint={x}\n", .{capsule.image_fingerprint});
    try stdout.print("link_certificate_fingerprint={x}\n", .{linked.certificate.certificate_fingerprint});
    try stdout.print("restore_report_fingerprint={x}\n", .{restore.restore_report_fingerprint});
    try stdout.print("final_result=7\n", .{});
    try stdout.flush();
}
