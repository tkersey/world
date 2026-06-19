const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const manifest = common.AgentAppliance.manifest();
    const capacity = world.Appliance.Capacity.wasm_agent;
    const memory_plan = common.AgentAppliance.memoryPlan();

    try stdout.print("appliance_abi_version={d}\n", .{world.Appliance.Abi.version});
    try stdout.print("manifest={x}\n", .{manifest.manifest_fingerprint});
    try stdout.print("capacity={x}\n", .{capacity.fingerprint()});
    try stdout.print("memory_plan={x}\n", .{memory_plan.plan_fingerprint});
    try stdout.print("required_exports={d}\n", .{world.Appliance.Abi.required_exports.len});
    try stdout.print("forbidden_import_count=0\n", .{});
    try stdout.flush();
}
