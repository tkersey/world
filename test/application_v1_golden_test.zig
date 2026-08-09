const std = @import("std");
const v1 = @import("world").protocol.v1;

const fixture_text = @embedFile("goldens/application_v1.hex");
const fixture_labels = [_][]const u8{
    "application_manifest",
    "residual_effect_declarations",
    "effect_request_pending",
    "effect_result_successful",
    "effect_result_rejected",
    "effect_result_failed",
    "effect_result_deferred",
    "effect_result_cancelled",
    "frame_running",
    "frame_pending",
    "frame_completed",
    "frame_failed",
    "step_input_genesis",
    "step_input_continuation",
};

test "Application ABI v1 canonical bytes and admission round trips are frozen" {
    try validateFixtureCorpus();
    const allocator = std.testing.allocator;
    const limits: v1.Limits = .{
        .maximum_manifest_bytes = 4096,
        .maximum_initial_args_bytes = 256,
        .maximum_state_bytes = 256,
        .maximum_payload_bytes = 256,
        .maximum_result_bytes = 256,
        .maximum_host_claim_bytes = 128,
        .maximum_host_metadata_bytes = 128,
        .maximum_failure_bytes = 128,
        .maximum_name_bytes = 64,
        .maximum_internal_handlers = 4,
        .maximum_residual_effects = 4,
        .maximum_fuel_per_step = 1000,
        .maximum_frame_depth = 8,
        .maximum_provider_depth = 4,
    };

    const residual_effects = [_]v1.ResidualEffect{.{
        .interface_id = v1.digestLabel("golden", "interface"),
        .site_id = 7,
        .payload_schema_id = v1.digestLabel("golden", "payload-schema"),
        .result_schema_id = v1.digestLabel("golden", "result-schema"),
        .allowed_statuses = .{ .deferred = true },
        .authority_requirements = 0b0101,
    }};
    var manifest: v1.ApplicationManifest = .{
        .application_name = "golden-app",
        .application_version = "1.0.0",
        .boundary_package_version = "1.0.0",
        .boundary_static_machine_abi_version = 1,
        .world_package_version = "3.0.0",
        .root_program_id = v1.digestLabel("golden", "root-program"),
        .residual_effects = &residual_effects,
        .limits = limits,
        .required_host_capabilities = 0b0101,
    };
    try manifest.seal(allocator);

    var request: v1.EffectRequest = .{
        .application_id = manifest.application_id,
        .parent_frame_id = v1.digestLabel("golden", "parent-frame"),
        .sequence = 1,
        .site_id = 7,
        .interface_id = residual_effects[0].interface_id,
        .payload_schema_id = residual_effects[0].payload_schema_id,
        .result_schema_id = residual_effects[0].result_schema_id,
        .allowed_statuses = residual_effects[0].allowed_statuses,
        .payload_bytes = "request-payload",
        .authority_requirements = residual_effects[0].authority_requirements,
        .limits = .{ .maximum_result_bytes = 64, .maximum_attempts = 3 },
    };
    try request.seal(allocator, limits);

    var results = [_]v1.EffectResult{
        .{ .request_id = request.request_id, .status = .ok, .result_schema_id = request.result_schema_id, .result_bytes = "ok", .host_claims = "host=golden", .attempt = 1 },
        .{ .request_id = request.request_id, .status = .rejected, .result_schema_id = request.result_schema_id, .result_bytes = "denied", .host_claims = "policy=deny", .attempt = 1 },
        .{ .request_id = request.request_id, .status = .failed, .result_schema_id = request.result_schema_id, .result_bytes = "upstream-failure", .host_claims = "retryable=false", .attempt = 2 },
        .{ .request_id = request.request_id, .status = .deferred, .result_schema_id = request.result_schema_id, .host_claims = "retry-after=5", .attempt = 1 },
        .{ .request_id = request.request_id, .status = .cancelled, .result_schema_id = request.result_schema_id, .host_claims = "cancelled=true", .attempt = 1 },
    };
    for (&results) |*result| try result.seal(allocator, limits);

    var pending_frame: v1.Frame = .{
        .application_id = manifest.application_id,
        .parent_frame_id = request.parent_frame_id,
        .sequence = 1,
        .state_bytes = "state:pending",
        .pending_effect = request,
        .status = .needs_effect,
        .resource_counters = .{ .instructions = 11, .external_effects = 1, .value_bytes = 13 },
    };
    try pending_frame.seal(allocator, limits);
    const pending_bytes = try pending_frame.encode(allocator, limits);
    defer allocator.free(pending_bytes);

    var running_frame: v1.Frame = .{
        .application_id = manifest.application_id,
        .parent_frame_id = v1.digestLabel("golden", "running-parent"),
        .sequence = 1,
        .state_bytes = "state:running",
        .status = .yielded_fuel,
        .resource_counters = .{ .instructions = 17, .continuation_operations = 2, .value_bytes = 13 },
        .semantic_warnings = 1,
    };
    try running_frame.seal(allocator, limits);

    var completed_frame: v1.Frame = .{
        .application_id = manifest.application_id,
        .parent_frame_id = pending_frame.frame_id,
        .sequence = 2,
        .state_bytes = "state:completed",
        .accepted_effect_result_id = results[0].result_id,
        .status = .completed,
        .final_result_schema_id = v1.digestLabel("golden", "final-schema"),
        .final_result_bytes = "final-value",
        .resource_counters = .{ .instructions = 23, .continuation_operations = 1, .external_effects = 1, .value_bytes = 26 },
    };
    try completed_frame.seal(allocator, limits);

    var failed_frame: v1.Frame = .{
        .application_id = manifest.application_id,
        .parent_frame_id = pending_frame.frame_id,
        .sequence = 2,
        .state_bytes = "state:failed",
        .accepted_effect_result_id = results[2].result_id,
        .status = .failed,
        .failure = "application-failure",
        .resource_counters = .{ .instructions = 19, .continuation_operations = 1, .external_effects = 1, .value_bytes = 12 },
    };
    try failed_frame.seal(allocator, limits);

    const genesis_input: v1.StepInput = .{
        .application_id = manifest.application_id,
        .initial_args_bytes = "goal=golden",
        .fuel = 100,
        .host_metadata = "trace=genesis",
    };
    const continuation_input: v1.StepInput = .{
        .application_id = manifest.application_id,
        .expected_parent_frame_id = pending_frame.frame_id,
        .prior_frame_bytes = pending_bytes,
        .effect_result = results[0],
        .fuel = 75,
        .host_metadata = "trace=continuation",
    };

    var all_match = true;
    all_match = try checkManifest(allocator, "application_manifest", manifest, limits) and all_match;
    all_match = try checkManifest(allocator, "residual_effect_declarations", manifest, limits) and all_match;
    all_match = try checkRequest(allocator, "effect_request_pending", request, limits) and all_match;
    inline for (.{
        .{ "effect_result_successful", results[0] },
        .{ "effect_result_rejected", results[1] },
        .{ "effect_result_failed", results[2] },
        .{ "effect_result_deferred", results[3] },
        .{ "effect_result_cancelled", results[4] },
    }) |case| all_match = try checkResult(allocator, case[0], case[1], limits) and all_match;
    all_match = try checkFrame(allocator, "frame_running", running_frame, limits) and all_match;
    all_match = try checkFrameBytes(allocator, "frame_pending", pending_bytes, limits) and all_match;
    all_match = try checkFrame(allocator, "frame_completed", completed_frame, limits) and all_match;
    all_match = try checkFrame(allocator, "frame_failed", failed_frame, limits) and all_match;
    all_match = try checkInput(allocator, "step_input_genesis", genesis_input, limits) and all_match;
    all_match = try checkInput(allocator, "step_input_continuation", continuation_input, limits) and all_match;
    try std.testing.expect(all_match);
}

fn checkManifest(allocator: std.mem.Allocator, label: []const u8, value: v1.ApplicationManifest, limits: v1.Limits) !bool {
    const actual = try value.encode(allocator);
    defer allocator.free(actual);
    const matches = try expectGolden(allocator, label, actual);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const decoded = try v1.ApplicationManifest.decode(&arena, actual, limits);
    const reencoded = try decoded.encode(allocator);
    defer allocator.free(reencoded);
    try std.testing.expectEqualSlices(u8, actual, reencoded);
    if (std.mem.eql(u8, label, "residual_effect_declarations")) {
        try std.testing.expectEqual(@as(usize, 1), decoded.residual_effects.len);
        try std.testing.expectEqual(@as(u64, 7), decoded.residual_effects[0].site_id);
    }
    return matches;
}

fn checkRequest(allocator: std.mem.Allocator, label: []const u8, value: v1.EffectRequest, limits: v1.Limits) !bool {
    const actual = try value.encode(allocator, limits);
    defer allocator.free(actual);
    const matches = try expectGolden(allocator, label, actual);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const decoded = try v1.EffectRequest.decode(&arena, actual, limits);
    const reencoded = try decoded.encode(allocator, limits);
    defer allocator.free(reencoded);
    try std.testing.expectEqualSlices(u8, actual, reencoded);
    return matches;
}

fn checkResult(allocator: std.mem.Allocator, label: []const u8, value: v1.EffectResult, limits: v1.Limits) !bool {
    const actual = try value.encode(allocator, limits);
    defer allocator.free(actual);
    const matches = try expectGolden(allocator, label, actual);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const decoded = try v1.EffectResult.decode(&arena, actual, limits);
    const reencoded = try decoded.encode(allocator, limits);
    defer allocator.free(reencoded);
    try std.testing.expectEqualSlices(u8, actual, reencoded);
    return matches;
}

fn checkFrame(allocator: std.mem.Allocator, label: []const u8, value: v1.Frame, limits: v1.Limits) !bool {
    const actual = try value.encode(allocator, limits);
    defer allocator.free(actual);
    return checkFrameBytes(allocator, label, actual, limits);
}

fn checkFrameBytes(allocator: std.mem.Allocator, label: []const u8, actual: []const u8, limits: v1.Limits) !bool {
    const matches = try expectGolden(allocator, label, actual);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const decoded = try v1.Frame.decode(&arena, actual, limits);
    const reencoded = try decoded.encode(allocator, limits);
    defer allocator.free(reencoded);
    try std.testing.expectEqualSlices(u8, actual, reencoded);
    return matches;
}

fn checkInput(allocator: std.mem.Allocator, label: []const u8, value: v1.StepInput, limits: v1.Limits) !bool {
    const actual = try value.encode(allocator, limits);
    defer allocator.free(actual);
    const matches = try expectGolden(allocator, label, actual);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const decoded = try v1.StepInput.decode(&arena, actual, limits);
    const reencoded = try decoded.encode(allocator, limits);
    defer allocator.free(reencoded);
    try std.testing.expectEqualSlices(u8, actual, reencoded);
    return matches;
}

fn expectGolden(allocator: std.mem.Allocator, label: []const u8, actual: []const u8) !bool {
    const expected = try fixture(allocator, label) orelse {
        printRecord(label, actual);
        return false;
    };
    defer allocator.free(expected);
    if (!std.mem.eql(u8, expected, actual)) {
        printRecord(label, actual);
        return false;
    }
    return true;
}

fn printRecord(label: []const u8, bytes: []const u8) void {
    std.debug.print("{s}=", .{label});
    for (bytes) |byte| std.debug.print("{x:0>2}", .{byte});
    std.debug.print("\n", .{});
}

fn validateFixtureCorpus() !void {
    var seen = [_]bool{false} ** fixture_labels.len;
    var lines = std.mem.tokenizeScalar(u8, fixture_text, '\n');
    while (lines.next()) |line| {
        const separator = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidGoldenFixture;
        const label = line[0..separator];
        const hex = line[separator + 1 ..];
        var label_index: ?usize = null;
        for (fixture_labels, 0..) |expected, index| {
            if (std.mem.eql(u8, label, expected)) {
                label_index = index;
                break;
            }
        }
        const index = label_index orelse return error.InvalidGoldenFixture;
        if (seen[index] or hex.len == 0 or hex.len % 2 != 0) return error.InvalidGoldenFixture;
        for (hex) |character| {
            if (!std.ascii.isDigit(character) and !(character >= 'a' and character <= 'f')) {
                return error.InvalidGoldenFixture;
            }
        }
        seen[index] = true;
    }
    for (seen) |present| if (!present) return error.InvalidGoldenFixture;
}

fn fixture(allocator: std.mem.Allocator, label: []const u8) !?[]u8 {
    var lines = std.mem.tokenizeScalar(u8, fixture_text, '\n');
    while (lines.next()) |line| {
        const separator = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        if (!std.mem.eql(u8, line[0..separator], label)) continue;
        const hex = line[separator + 1 ..];
        if (hex.len % 2 != 0) return error.InvalidGoldenFixture;
        const bytes = try allocator.alloc(u8, hex.len / 2);
        errdefer allocator.free(bytes);
        _ = try std.fmt.hexToBytes(bytes, hex);
        return bytes;
    }
    return null;
}
