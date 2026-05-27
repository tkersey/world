const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const PortsCtx = struct {
    calls: usize = 0,
    response: i32 = 7,
};

fn approve(ctx: *PortsCtx, payload: []const u8) !i32 {
    try std.testing.expectEqualStrings("deploy-prod", payload);
    ctx.calls += 1;
    return ctx.response;
}

const PortsDecl = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);
const PortsMachine = world.Machine(fixtures.Ports.Target, .{
    .ports = .{PortsDecl},
    .strict_handler_coverage = true,
});

fn recordPortsTranscript(transcript: *world.Transcript) !void {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var result = try PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = transcript,
    });
    defer result.deinit(std.testing.allocator);
}

fn firstRespondedEvent(transcript: *world.Transcript) !*world.Transcript.Event {
    for (transcript.events.items) |*event| {
        if (event.kind == .port_responded) return event;
    }
    return error.MissingResponseEvent;
}

test "world machine accepts strict zero-port certified target" {
    const Machine = world.Machine(fixtures.Strict.Target, .{
        .ports = .{},
        .strict_handler_coverage = true,
    });
    Machine.assertSurfaceMatches(fixtures.Strict.Target.WorldSurface.surface_fingerprint);
    Machine.assertNoSearchHotPath();

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    var result = try Machine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
        .expected_world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .expected_target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 1), result.value);
    try std.testing.expectEqual(@as(usize, 0), result.audit.port_request_count);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().run_started);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().run_completed);
}

test "world machine rejects mismatched surface fingerprint" {
    const Machine = world.Machine(fixtures.Strict.Target, .{ .ports = .{} });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.SurfaceMismatch, Machine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .expected_world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint + 1,
    }));
}

test "world machine rejects mismatched target certificate fingerprint" {
    const Machine = world.Machine(fixtures.Strict.Target, .{ .ports = .{} });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.TargetCertificateMismatch, Machine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .expected_target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint + 1,
    }));
}

test "world port dispatch uses dense dispatch table and records transcript" {
    PortsMachine.assertAllPortsHandled();
    PortsMachine.assertNoExtraHandlers();
    PortsMachine.assertNoSearchHotPath();

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    var result = try PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
        .expected_world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 7), result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), result.audit.port_request_count);
    try std.testing.expectEqual(@as(usize, 1), result.audit.fresh_response_count);
    try std.testing.expectEqual(@as(usize, 1), result.audit.per_port_counts[0]);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().port_requested);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().port_responded);
    try std.testing.expectEqual(@as(u32, 0), fixtures.Ports.Target.WorldDispatchTable.lookup(fixtures.Ports.ApprovalRequest.index).?);
}

test "world fresh port run does not require transcript option" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};

    var result = try PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 7), result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
}

test "world runtime step API parks on port and resumes to done" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    var run = try PortsMachine.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer run.deinit();

    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    switch (try run.next()) {
        .port_required => {},
        else => return error.ExpectedPortRequired,
    }
    try run.dispatch();
    const done = try run.next();
    switch (done) {
        .done => |value| try std.testing.expectEqual(@as(i32, 7), value),
        else => return error.ExpectedDone,
    }
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
}

test "world dispatch uses WorldDispatchTable residual site mapping" {
    const site_index = fixtures.Ports.ApprovalRequest.index;
    const world_port_id = fixtures.Ports.Target.WorldDispatchTable.lookup(site_index) orelse return error.MissingDispatch;
    try std.testing.expectEqual(PortsDecl.world_port_id, world_port_id);
    try std.testing.expectEqual(fixtures.Ports.ApprovalRequest.fingerprint, fixtures.Ports.Target.WorldPortTable.entries[world_port_id].residual_site_fingerprint);
}

test "world port request includes WorldValueTable payload and response ids" {
    try std.testing.expectEqual(@as(u32, 0), fixtures.Ports.Target.WorldValueTable.entries[0].world_port_id);
    try std.testing.expectEqual(@as(u32, 0), fixtures.Ports.Target.WorldValueTable.entries[0].value_id);
    try std.testing.expectEqual(@as(u32, 1), fixtures.Ports.Target.WorldValueTable.entries[1].value_id);
    try std.testing.expectEqual(.payload, fixtures.Ports.Target.WorldValueTable.entries[0].kind);
    try std.testing.expectEqual(.@"resume", fixtures.Ports.Target.WorldValueTable.entries[1].kind);
}

test "world replay consumes transcript and does not call handlers" {
    var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
    defer fresh_runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var fresh_ctx: PortsCtx = .{};

    var fresh = try PortsMachine.run(&fresh_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
    });
    defer fresh.deinit(std.testing.allocator);

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replay_ctx: PortsCtx = .{ .response = 99 };
    var replayed = try PortsMachine.run(&replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript = &transcript,
    });
    defer replayed.deinit(std.testing.allocator);

    try std.testing.expectEqual(fresh.value, replayed.value);
    try std.testing.expectEqual(@as(usize, 1), fresh_ctx.calls);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), replayed.audit.replayed_response_count);
}

test "world replay missing response fails" {
    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    try std.testing.expectError(error.ReplayMissing, PortsMachine.run(&replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &ctx,
        .transcript = &transcript,
    }));
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "world replay does not require handler context option" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    try std.testing.expectError(error.ReplayMissing, PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &transcript,
    }));
}

test "world dispatch failures record failed audit and transcript events" {
    const MissingMachine = world.Machine(fixtures.Ports.Target, .{ .ports = .{} });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    try std.testing.expectError(error.MissingHandler, MissingMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    }));

    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.port_requested);
    try std.testing.expectEqual(@as(usize, 1), summary.port_failed);
    try std.testing.expectEqual(@as(usize, 1), summary.run_failed);
}

test "world replay rejects forged transcript dimensions" {
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        (try firstRespondedEvent(&transcript)).world_surface_fingerprint += 1;

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplaySurfaceMismatch, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
        try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        (try firstRespondedEvent(&transcript)).target_certificate_fingerprint += 1;

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayTargetCertificateMismatch, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
        try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        (try firstRespondedEvent(&transcript)).world_port_id.? += 1;

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayPortMismatch, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
        try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        (try firstRespondedEvent(&transcript)).request_fingerprint.? += 1;

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayRequestFingerprintMismatch, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
        try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    }
}

test "world verify rejects forged transcript dimensions before calling handlers" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    (try firstRespondedEvent(&transcript)).target_certificate_fingerprint += 1;

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.ReplayTargetCertificateMismatch, PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &ctx,
        .transcript = &transcript,
    }));
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "world transcript keeps rejected response events unconsumed" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    (try firstRespondedEvent(&transcript)).target_certificate_fingerprint += 1;

    const key = PortsDecl.replayKey((try firstRespondedEvent(&transcript)).request_fingerprint.?);
    try std.testing.expectError(
        error.ReplayTargetCertificateMismatch,
        transcript.nextResponse(key, fixtures.Ports.Target.Certificate.certificate_fingerprint, .@"resume"),
    );
    try std.testing.expectError(error.ReplayUnusedEvent, transcript.assertReplayComplete());
}

test "world replay and verify reject unused response events" {
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        const response_event = (try firstRespondedEvent(&transcript)).*;
        try transcript.append(.{
            .kind = .port_responded,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
        });

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayUnusedEvent, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        const response_event = (try firstRespondedEvent(&transcript)).*;
        try transcript.append(.{
            .kind = .port_responded,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
        });

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayUnusedEvent, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.verify,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
        try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    }
}

test "world verify rejects missing or corrupt stored replay values" {
    var recorded = world.Transcript.init(std.testing.allocator);
    defer recorded.deinit();
    try recordPortsTranscript(&recorded);
    const response_event = (try firstRespondedEvent(&recorded)).*;

    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try transcript.append(.{
            .kind = .port_responded,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
            .world_port_id = response_event.world_port_id,
            .request_fingerprint = response_event.request_fingerprint,
            .response_fingerprint = response_event.response_fingerprint,
            .response_kind = response_event.response_kind,
            .replay_key = response_event.replay_key,
        });

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayMissing, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.verify,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try transcript.append(.{
            .kind = .port_responded,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
            .world_port_id = response_event.world_port_id,
            .request_fingerprint = response_event.request_fingerprint,
            .response_fingerprint = response_event.response_fingerprint,
            .response_kind = response_event.response_kind,
            .replay_key = response_event.replay_key,
            .value = try world.StoredValue.init(std.testing.allocator, @as(i32, 8)),
        });

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.VerifyDivergence, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.verify,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
    }
}

test "world verify detects changed handler response" {
    var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
    defer fresh_runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var fresh_ctx: PortsCtx = .{ .response = 7 };
    var fresh = try PortsMachine.run(&fresh_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
    });
    defer fresh.deinit(std.testing.allocator);

    var verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer verify_runtime.deinit();
    var verify_ctx: PortsCtx = .{ .response = 8 };
    try std.testing.expectError(error.VerifyDivergence, PortsMachine.run(&verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &verify_ctx,
        .transcript = &transcript,
    }));
}

test "world transcript replay key and summary counts are deterministic" {
    const key_a = world.ReplayKey{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabc,
        .response_kind = .@"resume",
    };
    const key_b = world.ReplayKey{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint + 1,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabc,
        .response_kind = .@"resume",
    };
    const key_c = world.ReplayKey{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = PortsDecl.world_port_id + 1,
        .request_fingerprint = 0xabc,
        .response_kind = .@"resume",
    };
    const key_d = world.ReplayKey{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabd,
        .response_kind = .@"resume",
    };
    try std.testing.expect(key_a.fingerprint() != key_b.fingerprint());
    try std.testing.expect(key_a.fingerprint() != key_c.fingerprint());
    try std.testing.expect(key_a.fingerprint() != key_d.fingerprint());

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
    });
    try transcript.append(.{
        .kind = .run_completed,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
    });
    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.run_started);
    try std.testing.expectEqual(@as(usize, 1), summary.run_completed);
}

test "world transcript stores string-list values for replay" {
    const key = world.ReplayKey{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabc,
        .response_kind = .@"resume",
    };
    const response: []const []const u8 = &.{ "alpha", "beta" };
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .port_responded,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = key.request_fingerprint,
        .response_kind = .@"resume",
        .replay_key = key.fingerprint(),
        .value = try world.StoredValue.init(std.testing.allocator, response),
    });

    const event = try transcript.nextResponse(key, fixtures.Ports.Target.Certificate.certificate_fingerprint, .@"resume");
    const stored = event.value orelse return error.MissingResponseEvent;
    const cloned = try stored.as(std.testing.allocator, []const []const u8);
    defer {
        for (cloned) |item| std.testing.allocator.free(item);
        std.testing.allocator.free(cloned);
    }
    try std.testing.expectEqual(@as(usize, 2), cloned.len);
    try std.testing.expectEqualStrings("alpha", cloned[0]);
    try std.testing.expectEqualStrings("beta", cloned[1]);
}

test "world audit report counts fresh calls and fingerprints" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};
    var result = try PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.audit,
        .audit_source = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(fixtures.Ports.Target.WorldSurface.surface_fingerprint, result.audit.world_surface_fingerprint);
    try std.testing.expectEqual(fixtures.Ports.Target.Certificate.certificate_fingerprint, result.audit.target_certificate_fingerprint);
    try std.testing.expectEqual(world.Mode.audit, result.audit.mode);
    try std.testing.expectEqual(@as(usize, 1), result.audit.port_request_count);
    try std.testing.expectEqual(@as(usize, 1), result.audit.fresh_response_count);
    try std.testing.expectEqual(@as(usize, 1), result.audit.per_port_counts[0]);
}

const AgentCtx = struct {
    allocator: std.mem.Allocator,
    scenario: fixtures.Agent.Scenario,
    model_calls: usize = 0,
    tool_calls: usize = 0,
    event_count: usize = 2,
};

fn decide(ctx: *AgentCtx, observation: []const u8) !fixtures.Agent.Action {
    ctx.model_calls += 1;
    const action = fixtures.Agent.decideAction(ctx.scenario, observation);
    if (action == .tool) ctx.event_count += 2;
    return action;
}

fn tool(ctx: *AgentCtx, command: []const u8) ![]const u8 {
    ctx.tool_calls += 1;
    ctx.event_count += 2;
    return fixtures.Agent.callTool(ctx.allocator, ctx.scenario, command);
}

const AgentDecideDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decide);
const AgentToolDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, tool);
const AgentMachine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ AgentDecideDecl, AgentToolDecl },
    .strict_handler_coverage = true,
});
const AgentArgs = struct { usize, []const u8 };
const AgentOptions = struct {
    allocator: std.mem.Allocator,
    mode: world.Mode,
    ctx: *AgentCtx,
    transcript: *world.Transcript,
};
const AgentResult = AgentMachine.Run(*boundary.Runtime, AgentArgs, AgentOptions).Result;

fn runAgentScenario(allocator: std.mem.Allocator, scenario: fixtures.Agent.Scenario) !struct {
    fresh_result: AgentResult,
    replay_result: AgentResult,
    transcript: world.Transcript,
    fresh_ctx: AgentCtx,
    replay_ctx: AgentCtx,
} {
    if (scenario == .fixture) try fixtures.Agent.prepareFixtureWorkspace();

    var transcript = world.Transcript.init(allocator);
    errdefer transcript.deinit();

    var fresh_runtime = boundary.Runtime.init(allocator);
    defer fresh_runtime.deinit();
    var fresh_ctx: AgentCtx = .{ .allocator = allocator, .scenario = scenario };
    const args: AgentArgs = .{ 3, fixtures.Agent.initialObservation(scenario) };
    var fresh_result = try AgentMachine.run(&fresh_runtime, args, AgentOptions{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
    });
    errdefer fresh_result.deinit(allocator);

    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replay_ctx: AgentCtx = .{ .allocator = allocator, .scenario = scenario };
    var replay_result = try AgentMachine.run(&replay_runtime, args, AgentOptions{
        .allocator = allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript = &transcript,
    });
    errdefer replay_result.deinit(allocator);

    return .{
        .fresh_result = fresh_result,
        .replay_result = replay_result,
        .transcript = transcript,
        .fresh_ctx = fresh_ctx,
        .replay_ctx = replay_ctx,
    };
}

test "agent loop skeleton scenario final text and accounting match" {
    var run = try runAgentScenario(std.testing.allocator, .skeleton);
    defer run.fresh_result.deinit(std.testing.allocator);
    defer run.replay_result.deinit(std.testing.allocator);
    defer run.transcript.deinit();

    try std.testing.expectEqualStrings("final=actuate skeleton complete", run.fresh_result.value);
    try std.testing.expectEqualStrings(run.fresh_result.value, run.replay_result.value);
    try std.testing.expectEqual(@as(usize, 6), run.fresh_ctx.event_count);
    try std.testing.expectEqual(@as(usize, 1), run.fresh_ctx.tool_calls);
    try std.testing.expectEqual(@as(usize, 0), run.replay_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), run.replay_ctx.tool_calls);
    try std.testing.expectEqual(@as(usize, 3), run.transcript.summary().port_responded);
}

test "agent loop fixture scenario final text and accounting match" {
    var run = try runAgentScenario(std.testing.allocator, .fixture);
    defer run.fresh_result.deinit(std.testing.allocator);
    defer run.replay_result.deinit(std.testing.allocator);
    defer run.transcript.deinit();

    try std.testing.expectEqualStrings("final=fixture updated", run.fresh_result.value);
    try std.testing.expectEqualStrings(run.fresh_result.value, run.replay_result.value);
    try std.testing.expectEqual(@as(usize, 10), run.fresh_ctx.event_count);
    try std.testing.expectEqual(@as(usize, 2), run.fresh_ctx.tool_calls);
    try std.testing.expectEqual(@as(usize, 0), run.replay_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), run.replay_ctx.tool_calls);
    try std.testing.expectEqual(@as(usize, 5), run.transcript.summary().port_responded);

    const io = std.Io.Threaded.global_single_threaded.io();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, fixtures.Agent.fixture_output_path, std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("actuate updated the fixture", bytes);
}
