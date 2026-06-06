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
    const provider_ref = world.TargetRef.fromTarget(fixtures.ProviderPorts.Target);
    const strict_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    const provider_export = world.Linker.ExportDescriptor.init(.{
        .target_ref = provider_ref,
        .result_ref = .{ .value_table_id = root_import.response_value_table_id, .value_ref_fingerprint = root_import.response_value_ref_fingerprint },
        .label = "provider-main",
    });
    const strict_export = world.Linker.ExportDescriptor.init(.{
        .target_ref = strict_ref,
        .result_ref = .{ .value_table_id = root_import.response_value_table_id, .value_ref_fingerprint = root_import.response_value_ref_fingerprint },
        .label = "strict-main",
    });
    const entries = [_]world.Linker.Catalog.Entry{
        world.Linker.Catalog.Entry.generatedTarget(.{
            .target_ref = provider_ref,
            .export_descriptor = provider_export,
            .import_set = world.ImportSet.fromTarget(fixtures.ProviderPorts.Target),
            .label = "provider",
        }),
        world.Linker.Catalog.Entry.generatedTarget(.{
            .target_ref = strict_ref,
            .export_descriptor = strict_export,
            .import_set = world.ImportSet.fromTarget(fixtures.Strict.Target),
            .label = "strict",
        }),
    };
    var rejected = try world.Linker.link(allocator, .{
        .root_target_ref = root_ref,
        .root_import_set = world.ImportSet.fromTarget(fixtures.Ports.Target),
        .root_imports = &.{root_import},
        .catalog = world.Linker.Catalog.init(&entries),
        .policy = .strict_closed,
    });
    defer rejected.deinit();

    const hint = world.Linker.Hint.init(.{
        .parent_target_ref_fingerprint = root_ref.target_ref_fingerprint,
        .parent_world_port_id = root_import.world_port_id,
        .provider_target_ref_fingerprint = strict_ref.target_ref_fingerprint,
        .provider_export_fingerprint = strict_export.export_fingerprint,
        .route_kind = .target_export,
        .label = "strict",
    });
    var hinted = try world.Linker.link(allocator, .{
        .root_target_ref = root_ref,
        .root_import_set = world.ImportSet.fromTarget(fixtures.Ports.Target),
        .root_imports = &.{root_import},
        .catalog = world.Linker.Catalog.init(&entries),
        .hints = &.{hint},
        .policy = .strict_closed,
    });
    defer hinted.deinit();

    try stdout.print("ambiguous_rejected={}\n", .{!rejected.report.accepted});
    try stdout.print("hinted_accepted={}\n", .{hinted.report.accepted});
    try stdout.flush();
}
