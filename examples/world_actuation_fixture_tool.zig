const common = @import("world_actuation_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const ctx = common.context(.{
        .label = "fixture.tool",
        .kind = .tool_like,
        .world_port_id = 0,
        .request_fingerprint = 0xacc7_1001,
        .response_value_table_id = 1,
    });
    var response_image = try world.Frame.ValueImage.fromValue(allocator, 1, 0xacc7_1002, null, @as(i32, 7), .portable);
    defer response_image.deinit(allocator);
    const execution = try common.execute(ctx, world.Actuation.Policy.fixture_test, .{
        .tool_like = .{
            .frame_response_fingerprint = 0xacc7_1002,
            .response_image = response_image,
        },
    }, 1);
    try execution.validate();

    var journal = world.Actuation.Journal.init();
    defer journal.deinit(allocator);
    try journal.appendIntent(allocator, ctx.intent);
    try journal.appendDecision(allocator, execution.decision);
    try journal.appendCommit(allocator, execution.commit_value);
    try journal.appendResponse(allocator, execution.response);
    try journal.appendReceipt(allocator, execution.receipt);

    try stdout.print("actuator_ref={x}\n", .{ctx.ref.ref_fingerprint});
    try stdout.print("actuation_receipt_fingerprint={x}\n", .{execution.receipt.receipt_fingerprint});
    try stdout.print("final_result=fixture-tool-ok\n", .{});
    try stdout.flush();
}
