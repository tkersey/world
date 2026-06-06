const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const root_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const root_import = world.ImportRequirement.fromTargetPort(fixtures.Ports.Target, 0);
    const root_export = world.Linker.ExportDescriptor.init(.{
        .target_ref = root_ref,
        .result_ref = .{ .value_table_id = root_import.response_value_table_id },
        .label = "root-self-export",
    });
    const entries = [_]world.Linker.Catalog.Entry{
        world.Linker.Catalog.Entry.init(.{
            .provider_kind = .target,
            .target_ref = root_ref,
            .export_descriptor = root_export,
            .label = "self",
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

    try stdout.print("cycle_blocked={}\n", .{linked.graph.hasBlocker(.CycleDetected)});
    try stdout.print("report_fingerprint={x}\n", .{linked.report.report_fingerprint});
    try stdout.flush();
}
