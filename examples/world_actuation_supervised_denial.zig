const common = @import("world_actuation_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const ctx = common.context(.{
        .label = "supervised.denial",
        .kind = .tool_like,
        .world_port_id = 0,
        .request_fingerprint = 0xacc7_5001,
    });
    const permit = world.RunPermit.init(.{
        .target_ref_fingerprint = ctx.target_ref_fingerprint,
        .world_surface_fingerprint = ctx.world_surface_fingerprint,
        .target_certificate_fingerprint = 0xacc7_5c01,
        .environment_certificate_fingerprint = 0xacc7_5e01,
        .binding_plan_fingerprint = 0xacc7_5b01,
        .mode = .fresh,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_actuation = false,
            .allow_fresh_actuation = false,
            .require_environment_certificate = true,
        }),
        .budget = world.Budget.init(.{ .max_actuation_calls = 0 }),
    });
    var supervisor = try world.Supervisor.init(allocator, permit, 1);
    defer supervisor.deinit();
    const denied_before_call = if (supervisor.beforeActuationCommit(ctx.intent, true)) false else |_| true;
    const receipt = supervisor.receipt(.parked, 0xacc7_5002, null, null);

    try stdout.print("denied_before_call={}\n", .{denied_before_call});
    try stdout.print("run_receipt_fingerprint={x}\n", .{receipt.receipt_fingerprint});
    try stdout.flush();
}
