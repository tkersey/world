const common = @import("world_actuation_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const model = common.context(.{
        .label = "model.decide",
        .kind = .model_like,
        .world_port_id = 0,
        .request_fingerprint = 0xacc7_2001,
    });
    const tool = common.context(.{
        .label = "tool.call",
        .kind = .tool_like,
        .world_port_id = 1,
        .request_fingerprint = 0xacc7_2002,
    });

    const model_exec = try common.execute(model, world.Actuation.Policy.fixture_test, .{
        .model_like = .{ .frame_response_fingerprint = 0xacc7_2101 },
    }, 1);
    const tool_exec = try common.execute(tool, world.Actuation.Policy.fixture_test, .{
        .tool_like = .{ .frame_response_fingerprint = 0xacc7_2102 },
    }, 1);

    var journal = world.Actuation.Journal.init();
    defer journal.deinit(allocator);
    try journal.appendIntent(allocator, model.intent);
    try journal.appendReceipt(allocator, model_exec.receipt);
    try journal.appendIntent(allocator, tool.intent);
    try journal.appendReceipt(allocator, tool_exec.receipt);

    try stdout.print("model_actuation_calls=1\n", .{});
    try stdout.print("tool_actuation_calls=1\n", .{});
    try stdout.print("final_result=agent-actuation-complete\n", .{});
    try stdout.flush();
}
