const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const report = world.Appliance.WorldV0Report.init(.{});
    try report.validate();
    if (report.passed) return error.WorldV0ReportUnexpectedlyComplete;

    try stdout.print("world_v0_complete={}\n", .{report.passed});
    try stdout.print("two_program_plans_one_wasm={}\n", .{report.genuinely_unrelated_images_executed});
    try stdout.print("loaded_internal_provider_executed={}\n", .{report.internal_loaded_provider_executed});
    try stdout.print("active_fabric_restore_accepted={}\n", .{report.active_loaded_fabric_restored});
    try stdout.print("verified_replay_without_fresh_effect={}\n", .{report.verified_replay_without_fresh_effect_passed});
    try stdout.print("actuated_replay_supported=false\n", .{});
    try stdout.print("unsupported_actuated_replay_rejected={}\n", .{report.unsupported_actuated_replay_rejected});
    try stdout.print("javascript_codec_independent={}\n", .{report.independent_javascript_codec_passed});
    try stdout.print("deterministic_retry={}\n", .{report.deterministic_retry_passed});
    try stdout.print("universal_memory_bound_passed={}\n", .{report.memory_bound_passed});
    try stdout.flush();
}
