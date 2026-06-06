const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const ApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);

fn approve(_: *void, _: []const u8) !i32 {
    return 7;
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const parent_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const route = world.Fabric.Route.init(.{
        .route_id = 0xfab5,
        .kind = .target_export,
        .parent_world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .parent_target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .parent_world_port_id = ApprovalPort.world_port_id,
        .provider_target_ref_fingerprint = parent_ref.target_ref_fingerprint,
        .provider_world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .provider_target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .max_depth = 4,
    });
    const plan = world.Fabric.Plan.init(.{
        .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
        .module_fingerprint = parent_ref.boundary_module_fingerprint,
        .world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .routes = &.{route},
        .max_depth = 4,
    });
    const blocked = if (plan.assertNoCycles()) false else |err| err == error.FabricCycle;
    const report = plan.coverage(parent_ref, world.ImportSet.fromTarget(fixtures.Ports.Target));

    try stdout.print("cycle_blocked={}\n", .{blocked});
    try stdout.print("report_fingerprint={x}\n", .{report.coverage_report_fingerprint});
    try stdout.flush();
}
