const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const bytes = try fixtures.Ports.Target.Module.fullImage(allocator);
    defer allocator.free(bytes);
    var loaded = try world.Admission.ModuleGateway.decodeBoundaryModule(fixtures.Ports.Target, allocator, bytes);
    defer loaded.deinit();
    const module_ref = world.Admission.ModuleGateway.refFromBoundaryModule(loaded);
    const summary = world.Admission.ModuleGateway.exportSummaryFromBoundaryModule(loaded);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .full_module,
        .module_ref = module_ref,
        .module_image_bytes = bytes,
        .requested_mode = .inspect_only,
    });
    const entry = world.Admission.TargetRegistry.register(fixtures.Ports.Target);
    const admitter = world.Admission.Admitter.init(.{
        .registry = world.Admission.TargetRegistry.init(&.{entry}),
        .policy = world.Admission.AdmissionPolicy.inspect_modules,
    });
    const result = admitter.admitForTarget(fixtures.Ports.Target, world.Environment(fixtures.Ports.Target, .{ .bindings = .{}, .policy = world.EnvironmentPolicy.audit_only }), package, .{});

    try stdout.print("module_ref_fingerprint={x}\n", .{module_ref.module_ref_fingerprint});
    try stdout.print("import_count={d}\n", .{loaded.imports().len});
    try stdout.print("loaded_execution_supported={}\n", .{summary.loaded_execution_supported});
    try stdout.print("admission_accepted={}\n", .{result.report.accepted});
    try stdout.flush();
}
