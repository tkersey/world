const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const artifact_path = args.next() orelse return error.MissingWasmArtifactPath;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, artifact_path, allocator, .limited(world.world_max_decoded_byte_field_len));
    defer allocator.free(bytes);

    const inspection = try world.Appliance.Abi.inspectWasm(bytes);
    if (!inspection.passed()) return error.WasmInspectionFailed;
    const manifest = common.AgentAppliance.manifest();
    const capacity = world.Appliance.Capacity.wasm_agent;
    const memory_plan = common.AgentAppliance.memoryPlan();
    if (inspection.memory_initial_pages < memory_plan.maximum_linear_memory_pages) return error.WasmMemoryBelowMemoryPlan;
    const actual_memory_bytes = @as(u64, inspection.memory_initial_pages) * 64 * 1024;

    try stdout.print("appliance_wasm_artifact={s}\n", .{artifact_path});
    try stdout.print("abi_version={d}\n", .{inspection.abi_version});
    try stdout.print("manifest={x}\n", .{manifest.manifest_fingerprint});
    try stdout.print("capacity={x}\n", .{capacity.fingerprint()});
    try stdout.print("memory_plan={x}\n", .{memory_plan.plan_fingerprint});
    try stdout.print("required_memory_bytes={d}\n", .{actual_memory_bytes});
    try stdout.print("max_linear_memory_pages={d}\n", .{inspection.memory_initial_pages});
    try stdout.print("export_count={d}\n", .{inspection.export_count});
    try stdout.print("required_exports=true\n", .{});
    try stdout.print("metadata_exports=true\n", .{});
    try stdout.print("forbidden_imports={d}\n", .{inspection.forbidden_import_count});
    try stdout.flush();
}
