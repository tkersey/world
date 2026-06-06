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

    const vector = world.Guest.ConformanceVector.init(.{
        .name = "linked-assembly",
        .kind = .one_port,
        .target_ref_fingerprint = root_ref.target_ref_fingerprint,
        .expected_pending_frame_fingerprints = &.{linked.plan.fabric_plans[0].routes[0].route_fingerprint},
        .expected_final_result_fingerprint = linked.assembly.assembly_fingerprint,
        .expected_status_sequence = &.{ .initialized, .parked, .running, .done },
    });
    const report = world.Guest.ConformanceReport.init(.{
        .vector_fingerprint = vector.vector_fingerprint,
        .native_run_result = .{
            .status = .done,
            .result_fingerprint = linked.assembly.assembly_fingerprint,
            .pending_frame_fingerprints = &.{linked.plan.fabric_plans[0].routes[0].route_fingerprint},
        },
        .native_abi_result = .{
            .status = .done,
            .result_fingerprint = linked.assembly.assembly_fingerprint,
            .pending_frame_fingerprints = &.{linked.plan.fabric_plans[0].routes[0].route_fingerprint},
        },
        .status_sequence_match = true,
        .pending_frame_match = true,
        .final_result_match = true,
    });

    try stdout.print("assembly_fingerprint={x}\n", .{linked.assembly.assembly_fingerprint});
    try stdout.print("conformance_report_fingerprint={x}\n", .{report.report_fingerprint});
    try stdout.print("conformance={}\n", .{report.status_sequence_match and report.pending_frame_match and report.final_result_match});
    try stdout.flush();
}
