const std = @import("std");
const world = @import("world");
const research_digest = @import("research_digest_application");

const App = research_digest.Application;
const Effects = research_digest.Effects;
const ResearchLookupMachine = research_digest.ResearchLookupMachine;

test "Research Digest v2 formats bounded research items inside compiled Machines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expectEqual(@as(usize, 1), App.internal_handler_ids.len);
    try std.testing.expectEqual(@as(usize, 1), App.residual_effect_row.len);
    try std.testing.expectEqual(
        world.siteId(ResearchLookupMachine, 0),
        App.residual_effect_row[0].site_id,
    );

    const request: Effects.ResearchRequest = .{
        .query = try Effects.Query.fromSlice("portable algebraic effects"),
        .maximum_items = 1,
    };
    const initial_args = try App.encodeInitialArgs(allocator, request);
    const parent = try App.initialFrame(&arena, initial_args, 10_000);
    try std.testing.expectEqual(world.protocol.v1.FrameStatus.needs_effect, parent.status);
    try std.testing.expectEqual(
        world.siteId(ResearchLookupMachine, 0),
        parent.pending_effect.?.site_id,
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        parent.resource_counters.internal_handler_calls,
    );
    try std.testing.expectEqualSlices(
        u8,
        initial_args,
        parent.pending_effect.?.payload_bytes,
    );

    var items = Effects.ResearchItems.empty();
    try items.push(.{
        .title = try Effects.Title.fromSlice(
            "Effect rows as application boundaries",
        ),
        .summary = try Effects.Summary.fromSlice(
            "Static closure leaves authority outside the guest.",
        ),
    });
    try items.push(.{
        .title = try Effects.Title.fromSlice("Portable continuations"),
        .summary = try Effects.Summary.fromSlice(
            "Canonical Frames resume in fresh WASM instances.",
        ),
    });
    const response: Effects.ResearchResponse = .{ .items = items };
    const response_bytes = try App.encodeExternalResult(
        allocator,
        ResearchLookupMachine,
        0,
        response,
    );
    var effect_result: world.protocol.v1.EffectResult = .{
        .request_id = parent.pending_effect.?.request_id,
        .status = .ok,
        .result_schema_id = parent.pending_effect.?.result_schema_id,
        .result_bytes = response_bytes,
        .attempt = 1,
    };
    try effect_result.seal(allocator, App.Limits);
    const parent_bytes = try App.encodeFrame(allocator, parent);
    const input: world.protocol.v1.StepInput = .{
        .application_id = App.Manifest.application_id,
        .expected_parent_frame_id = parent.frame_id,
        .prior_frame_bytes = parent_bytes,
        .effect_result = effect_result,
        .fuel = 10_000,
    };
    const completed = try App.step(&arena, input);
    const retried = try App.step(&arena, input);
    try std.testing.expectEqual(world.protocol.v1.FrameStatus.completed, completed.status);
    try std.testing.expectEqual(
        @as(u64, 2),
        completed.resource_counters.continuation_operations,
    );

    var result = try App.decodeFinalResult(allocator, completed);
    defer result.deinit();
    try std.testing.expectEqualStrings(
        "Effect rows as application boundaries\n" ++
            "Static closure leaves authority outside the guest.\n",
        try result.value.digest.slice(),
    );
    try std.testing.expectEqual(@as(u32, 1), result.value.item_count);

    const completed_bytes = try App.encodeFrame(allocator, completed);
    const retried_bytes = try App.encodeFrame(allocator, retried);
    try std.testing.expectEqualSlices(u8, completed_bytes, retried_bytes);
}

test "Research Digest v2 budget admits the maximum bounded response" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expectEqual(
        @as(u64, 1_000_000),
        ResearchLookupMachine.Manifest.maximum_machine_fuel,
    );
    const request: Effects.ResearchRequest = .{
        .query = try Effects.Query.fromSlice("maximum bounded response"),
        .maximum_items = 1,
    };
    const initial_args = try App.encodeInitialArgs(allocator, request);
    const parent = try App.initialFrame(&arena, initial_args, 10_000);
    try std.testing.expectEqual(world.protocol.v1.FrameStatus.needs_effect, parent.status);

    const title_bytes = [_]u8{'T'} ** 256;
    const summary_bytes = [_]u8{'S'} ** 1024;
    const item: Effects.ResearchItem = .{
        .title = try Effects.Title.fromSlice(&title_bytes),
        .summary = try Effects.Summary.fromSlice(&summary_bytes),
    };
    var items = Effects.ResearchItems.empty();
    for (0..8) |_| try items.push(item);
    const response: Effects.ResearchResponse = .{ .items = items };
    const response_bytes = try App.encodeExternalResult(
        allocator,
        ResearchLookupMachine,
        0,
        response,
    );
    var effect_result: world.protocol.v1.EffectResult = .{
        .request_id = parent.pending_effect.?.request_id,
        .status = .ok,
        .result_schema_id = parent.pending_effect.?.result_schema_id,
        .result_bytes = response_bytes,
        .attempt = 1,
    };
    try effect_result.seal(allocator, App.Limits);
    const parent_bytes = try App.encodeFrame(allocator, parent);
    const completed = try App.step(&arena, .{
        .application_id = App.Manifest.application_id,
        .expected_parent_frame_id = parent.frame_id,
        .prior_frame_bytes = parent_bytes,
        .effect_result = effect_result,
        .fuel = 10_000,
    });
    try std.testing.expectEqual(world.protocol.v1.FrameStatus.completed, completed.status);

    var result = try App.decodeFinalResult(allocator, completed);
    defer result.deinit();
    try std.testing.expectEqual(@as(u32, 1), result.value.item_count);
    const digest = try result.value.digest.slice();
    try std.testing.expectEqual(@as(usize, 1282), digest.len);
    try std.testing.expectEqualSlices(u8, &title_bytes, digest[0..256]);
    try std.testing.expectEqual(@as(u8, '\n'), digest[256]);
    try std.testing.expectEqualSlices(u8, &summary_bytes, digest[257..1281]);
    try std.testing.expectEqual(@as(u8, '\n'), digest[1281]);
}
