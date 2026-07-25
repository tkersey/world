const std = @import("std");
const world = @import("world");
const research_digest = @import("research_digest_application");

const App = research_digest.Application;
const Effects = research_digest.Effects;
const ResearchLookupSite = research_digest.ResearchLookupSite;

test "Research Digest template closes one provider and completes one custom effect" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expectEqual(@as(usize, 1), App.internal_handler_ids.len);
    try std.testing.expectEqual(@as(usize, 1), App.residual_effect_row.len);
    try std.testing.expectEqual(
        ResearchLookupSite.canonical_fingerprint,
        App.residual_effect_row[0].site_id,
    );

    const request: Effects.ResearchRequest = .{
        .query = "portable algebraic effects",
        .maximum_items = 2,
    };
    const initial_args = try App.encodeInitialArgs(allocator, .{request});
    const parent = try App.initialFrame(&arena, initial_args, 100);
    try std.testing.expectEqual(world.v1.FrameStatus.needs_effect, parent.status);
    try std.testing.expectEqual(
        ResearchLookupSite.canonical_fingerprint,
        parent.pending_effect.?.site_id,
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        parent.resource_counters.internal_handler_calls,
    );

    const expected_payload = try world.v1.encodeValue(allocator, request);
    try std.testing.expectEqualSlices(
        u8,
        expected_payload,
        parent.pending_effect.?.payload_bytes,
    );

    const response: Effects.ResearchResponse = .{
        .first = .{
            .title = "Effect rows as application boundaries",
            .summary = "Static closure leaves authority outside the guest.",
        },
        .second = .{
            .title = "Portable continuations",
            .summary = "Canonical Frames resume in fresh WASM instances.",
        },
        .digest_result = .{
            .digest = "Static closure keeps authority external; canonical Frames keep continuation portable.",
            .item_count = 2,
        },
    };
    const response_bytes = try App.encodeExternalResult(
        allocator,
        ResearchLookupSite,
        response,
    );
    var effect_result: world.v1.EffectResult = .{
        .request_id = parent.pending_effect.?.request_id,
        .status = .ok,
        .result_schema_id = parent.pending_effect.?.result_schema_id,
        .result_bytes = response_bytes,
        .attempt = 1,
    };
    try effect_result.seal(allocator, App.Limits);
    const parent_bytes = try App.encodeFrame(allocator, parent);
    const input: world.v1.StepInput = .{
        .application_id = App.Manifest.application_id,
        .expected_parent_frame_id = parent.frame_id,
        .prior_frame_bytes = parent_bytes,
        .effect_result = effect_result,
        .fuel = 100,
    };
    const completed = try App.step(&arena, input);
    const retried = try App.step(&arena, input);
    try std.testing.expectEqual(world.v1.FrameStatus.completed, completed.status);
    try std.testing.expectEqual(
        @as(u64, 2),
        completed.resource_counters.continuation_operations,
    );

    var result = try App.decodeFinalResult(allocator, completed);
    defer result.deinit();
    try std.testing.expectEqualStrings(
        response.digest_result.digest,
        result.value.digest,
    );
    try std.testing.expectEqual(
        response.digest_result.item_count,
        result.value.item_count,
    );

    const completed_bytes = try App.encodeFrame(allocator, completed);
    const retried_bytes = try App.encodeFrame(allocator, retried);
    try std.testing.expectEqualSlices(u8, completed_bytes, retried_bytes);
}
