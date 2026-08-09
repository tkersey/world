const std = @import("std");
const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = fixtures.OneEffectApp;

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const output_path = args.next() orelse return error.InvalidArguments;
    if (args.next() != null) return error.InvalidArguments;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const manifest = try App.Manifest.encode(allocator);
    const initial_args = try App.encodeInitialArgs(allocator, @as(u32, 7));
    const parent = try App.initialFrame(&arena, initial_args, 100);
    const parent_bytes = try App.encodeFrame(allocator, parent);
    const request = parent.pending_effect orelse return error.InvalidFrame;
    const request_bytes = try request.encode(allocator, App.Limits);

    const value_bytes = try App.encodeExternalResult(
        allocator,
        fixtures.RootMachine,
        0,
        @as(u32, 41),
    );
    var result: world.protocol.v1.EffectResult = .{
        .request_id = request.request_id,
        .status = .ok,
        .result_schema_id = request.result_schema_id,
        .result_bytes = value_bytes,
        .attempt = 1,
    };
    try result.seal(allocator, App.Limits);
    const input: world.protocol.v1.StepInput = .{
        .application_id = App.Manifest.application_id,
        .expected_parent_frame_id = parent.frame_id,
        .prior_frame_bytes = parent_bytes,
        .effect_result = result,
        .fuel = 100,
    };
    const child = try App.step(&arena, input);
    const child_bytes = try App.encodeFrame(allocator, child);
    const retry = try App.step(&arena, input);
    const retry_bytes = try App.encodeFrame(allocator, retry);
    const final_result = child.final_result_bytes orelse return error.InvalidFrame;

    var trace: std.ArrayList(u8) = .empty;
    defer trace.deinit(allocator);
    try trace.appendSlice(allocator, "WRLDNTR1");
    for ([_][]const u8{
        manifest,
        parent_bytes,
        parent.state_bytes,
        request_bytes,
        child_bytes,
        final_result,
        retry_bytes,
    }) |field| {
        var length: [4]u8 = undefined;
        std.mem.writeInt(u32, &length, @intCast(field.len), .little);
        try trace.appendSlice(allocator, &length);
        try trace.appendSlice(allocator, field);
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = output_path,
        .data = trace.items,
    });
}
