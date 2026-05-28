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

fn approveRequest(ctx: *PortsCtx, request: world.PortRequest(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest)) !i32 {
    try request.expectPort(fixtures.Ports.ApprovalRequest);
    try std.testing.expectEqual(@as(u32, 0), request.world_port_id);
    try std.testing.expectEqual(fixtures.Ports.ApprovalRequest.index, request.residual_site_index);
    try std.testing.expectEqual(fixtures.Ports.ApprovalRequest.fingerprint, request.residual_site_fingerprint);
    try std.testing.expectEqual(@as(?u32, 0), request.value_table_payload_id);
    try std.testing.expectEqual(@as(?u32, 1), request.value_table_response_id);
    try std.testing.expectEqualStrings("deploy-prod", try request.payload(fixtures.Ports.ApprovalRequest));
    ctx.calls += 1;
    return ctx.response;
}

const PortsDecl = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);
const PortsByIdDecl = world.portById(fixtures.Ports.Target, 0, fixtures.Ports.ApprovalRequest, approve);
const PortsRequestDecl = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approveRequest);
const PortsMachine = world.Machine(fixtures.Ports.Target, .{
    .ports = .{PortsDecl},
    .strict_handler_coverage = true,
});
const PortsRequestMachine = world.Machine(fixtures.Ports.Target, .{
    .ports = .{PortsRequestDecl},
    .strict_handler_coverage = true,
});

const MissingDispatchTarget = struct {
    pub const Program = fixtures.Ports.Target.Program;
    pub const WorldSurface = fixtures.Ports.Target.WorldSurface;
    pub const WorldPortTable = fixtures.Ports.Target.WorldPortTable;
    pub const WorldValueTable = fixtures.Ports.Target.WorldValueTable;
    pub const Certificate = fixtures.Ports.Target.Certificate;

    pub const WorldDispatchTable = struct {
        pub fn lookup(_: usize) ?u32 {
            return null;
        }
    };

    pub fn assertWorldSurfaceReady() void {}
    pub fn assertNoSearchHotPath() void {}
};
const MissingDispatchMachine = world.Machine(MissingDispatchTarget, .{ .ports = .{} });

const OptionalNullTarget = struct {
    pub const Program = struct {
        pub const Handlers = struct {};
        pub const contract = struct {
            pub const ResultType = ?i32;
        };

        pub const Session = struct {
            value: ?i32,

            pub const Request = struct {
                pub fn trace(_: @This()) struct {
                    operation_site_index: usize,
                    operation_site_fingerprint: u64,
                    fingerprint: u64,
                    turn_index: usize,
                } {
                    return .{
                        .operation_site_index = 0,
                        .operation_site_fingerprint = 0,
                        .fingerprint = 0,
                        .turn_index = 0,
                    };
                }
            };
            const Done = struct {
                value: ?i32,

                pub fn deinit(_: *@This()) void {}
            };

            pub fn startWithArgs(_: anytype, _: Handlers, args: anytype) !@This() {
                return .{ .value = args[0] };
            }

            pub fn deinit(_: *@This()) void {}

            pub fn next(self: *@This()) !union(enum) {
                done: Done,
                after,
                request: Request,
            } {
                return .{ .done = .{ .value = self.value } };
            }
        };
    };

    pub const WorldSurface = struct {
        pub const surface_fingerprint: u64 = 0x7773_6f70_746e_0001;

        pub fn replayScopeRef() struct { fingerprint: u64 } {
            return .{ .fingerprint = surface_fingerprint };
        }
    };
    pub const WorldPortTable = struct {
        pub const entries = &.{};
    };
    pub const WorldValueTable = struct {
        pub const entries = &.{};
    };
    pub const WorldDispatchTable = struct {
        pub fn lookup(_: usize) ?u32 {
            return null;
        }
    };
    pub const Certificate = struct {
        pub const certificate_fingerprint: u64 = 0x7773_6f70_746e_0002;
    };

    pub fn assertWorldSurfaceReady() void {}
    pub fn assertNoSearchHotPath() void {}
};

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

fn firstRunCompletedIndex(transcript: *world.Transcript) !usize {
    for (transcript.events.items, 0..) |event, index| {
        if (event.kind == .run_completed) return index;
    }
    return error.MissingRunCompletedEvent;
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

test "world machine preserves optional null completion values" {
    const Machine = world.Machine(OptionalNullTarget, .{
        .ports = .{},
        .strict_handler_coverage = true,
    });

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    var result = try Machine.run(&runtime, .{@as(?i32, null)}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?i32, null), result.value);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().run_completed);
}

test "world step API preserves repeated optional null completion values" {
    const Machine = world.Machine(OptionalNullTarget, .{
        .ports = .{},
        .strict_handler_coverage = true,
    });

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var run = try Machine.start(&runtime, .{@as(?i32, null)}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    defer run.deinit();

    switch (try run.next()) {
        .done => |value| try std.testing.expectEqual(@as(?i32, null), value),
        else => return error.ExpectedDone,
    }
    switch (try run.next()) {
        .done => |value| try std.testing.expectEqual(@as(?i32, null), value),
        else => return error.ExpectedRepeatedDone,
    }
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
    try std.testing.expectEqual(@as(u32, 0), PortsByIdDecl.world_port_id);

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
    const repeated = try run.next();
    switch (repeated) {
        .done => |value| try std.testing.expectEqual(@as(i32, 7), value),
        else => return error.ExpectedRepeatedDone,
    }
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.run_completed);
    try std.testing.expectEqual(@as(usize, 0), summary.run_failed);
}

test "world dispatch uses WorldDispatchTable residual site mapping" {
    const site_index = fixtures.Ports.ApprovalRequest.index;
    const world_port_id = fixtures.Ports.Target.WorldDispatchTable.lookup(site_index) orelse return error.MissingDispatch;
    try std.testing.expectEqual(PortsDecl.world_port_id, world_port_id);
    try std.testing.expectEqual(fixtures.Ports.ApprovalRequest.fingerprint, fixtures.Ports.Target.WorldPortTable.entries[world_port_id].residual_site_fingerprint);
}

test "world handlers can accept constructible PortRequest by site" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{ .response = 11 };

    var result = try PortsRequestMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 11), result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
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

    var second_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer second_replay_runtime.deinit();
    var second_replay_ctx: PortsCtx = .{ .response = 101 };
    var second_replay = try PortsMachine.run(&second_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &second_replay_ctx,
        .transcript = &transcript,
    });
    defer second_replay.deinit(std.testing.allocator);

    try std.testing.expectEqual(fresh.value, second_replay.value);
    try std.testing.expectEqual(@as(usize, 0), second_replay_ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), second_replay.audit.replayed_response_count);

    var verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer verify_runtime.deinit();
    var verify_ctx: PortsCtx = .{ .response = fresh.value };
    var verified = try PortsMachine.run(&verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &verify_ctx,
        .transcript = &transcript,
    });
    defer verified.deinit(std.testing.allocator);

    try std.testing.expectEqual(fresh.value, verified.value);
    try std.testing.expectEqual(@as(usize, 1), verify_ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), verified.audit.fresh_response_count);
    try std.testing.expectEqual(@as(usize, 1), verified.audit.replayed_response_count);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().port_requested);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().port_responded);

    var third_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer third_replay_runtime.deinit();
    var third_replay_ctx: PortsCtx = .{ .response = 103 };
    var third_replay = try PortsMachine.run(&third_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &third_replay_ctx,
        .transcript = &transcript,
    });
    defer third_replay.deinit(std.testing.allocator);

    try std.testing.expectEqual(fresh.value, third_replay.value);
    try std.testing.expectEqual(@as(usize, 0), third_replay_ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), third_replay.audit.replayed_response_count);
}

test "world replay selects the latest completed transcript run" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    {
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{ .response = 7 };
        var result = try PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .ctx = &ctx,
            .transcript = &transcript,
        });
        defer result.deinit(std.testing.allocator);
    }
    {
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{ .response = 9 };
        var result = try PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .ctx = &ctx,
            .transcript = &transcript,
        });
        defer result.deinit(std.testing.allocator);
    }

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    var image_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer image_replay_runtime.deinit();
    var image_replayed = try PortsMachine.run(&image_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &image,
    });
    defer image_replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 9), image_replayed.value);

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

    try std.testing.expectEqual(@as(i32, 9), replayed.value);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.calls);
    try std.testing.expectEqual(@as(usize, 2), transcript.summary().port_responded);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().port_replayed);

    var image_after_replay = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image_after_replay.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), image_after_replay.response_count);
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

test "world malformed dispatch lookup records failed run" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    try std.testing.expectError(error.UnknownResidualSite, MissingDispatchMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
    }));

    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.run_started);
    try std.testing.expectEqual(@as(usize, 1), summary.run_failed);
    try std.testing.expectEqual(@as(usize, 0), summary.run_completed);
}

test "world step dispatch failure is terminal" {
    const MissingMachine = world.Machine(fixtures.Ports.Target, .{ .ports = .{} });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    var run = try MissingMachine.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer run.deinit();

    switch (try run.next()) {
        .port_required => {},
        else => return error.ExpectedPortRequired,
    }
    try std.testing.expectError(error.MissingHandler, run.dispatch());
    switch (try run.next()) {
        .failed => {},
        else => return error.ExpectedFailed,
    }
    try std.testing.expectError(error.HandlerFailed, run.dispatch());

    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.port_requested);
    try std.testing.expectEqual(@as(usize, 1), summary.port_failed);
    try std.testing.expectEqual(@as(usize, 1), summary.run_failed);
    try std.testing.expectEqual(@as(usize, 0), summary.run_completed);
}

test "world replay validates zero-port run fingerprints" {
    const Machine = world.Machine(fixtures.Strict.Target, .{ .ports = .{} });
    {
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
        defer fresh_runtime.deinit();
        var fresh = try Machine.run(&fresh_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer fresh.deinit(std.testing.allocator);
        transcript.events.items[0].world_surface_fingerprint += 1;

        var replay_runtime = boundary.Runtime.init(std.testing.allocator);
        defer replay_runtime.deinit();
        try std.testing.expectError(error.ReplaySurfaceMismatch, Machine.run(&replay_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
        defer fresh_runtime.deinit();
        var fresh = try Machine.run(&fresh_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer fresh.deinit(std.testing.allocator);
        try transcript.append(.{
            .kind = .run_started,
            .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        });
        try transcript.append(.{
            .kind = .run_failed,
            .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        });

        var replay_runtime = boundary.Runtime.init(std.testing.allocator);
        defer replay_runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&replay_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
        defer fresh_runtime.deinit();
        var fresh = try Machine.run(&fresh_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer fresh.deinit(std.testing.allocator);
        transcript.events.items[1].kind = .run_failed;

        var replay_runtime = boundary.Runtime.init(std.testing.allocator);
        defer replay_runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&replay_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
        defer fresh_runtime.deinit();
        var fresh = try Machine.run(&fresh_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer fresh.deinit(std.testing.allocator);
        transcript.events.items[1].kind = .run_started;

        var replay_runtime = boundary.Runtime.init(std.testing.allocator);
        defer replay_runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&replay_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try transcript.append(.{
            .kind = .run_started,
            .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        });
        try transcript.append(.{
            .kind = .run_started,
            .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        });
        try transcript.append(.{
            .kind = .run_completed,
            .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        });

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
}

test "world replay ignores responses outside validated source run" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    const response_event = (try firstRespondedEvent(&transcript)).*;
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
    var result = try PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 7), result.value);
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
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
        try transcript.events.insert(transcript.allocator, try firstRunCompletedIndex(&transcript), .{
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
        try transcript.events.insert(transcript.allocator, try firstRunCompletedIndex(&transcript), .{
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
            .kind = .run_started,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
        });
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
        try transcript.append(.{
            .kind = .run_completed,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
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
            .kind = .run_started,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
        });
        var corrupt_stored = try world.StoredValue.init(std.testing.allocator, @as(i32, 8));
        defer corrupt_stored.deinit(std.testing.allocator);
        try transcript.append(.{
            .kind = .port_responded,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
            .world_port_id = response_event.world_port_id,
            .request_fingerprint = response_event.request_fingerprint,
            .response_fingerprint = response_event.response_fingerprint,
            .response_kind = response_event.response_kind,
            .replay_key = response_event.replay_key,
            .value = corrupt_stored,
        });
        try transcript.append(.{
            .kind = .run_completed,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
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
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.calls);
}

test "world transcript replay key and summary counts are deterministic" {
    const scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint;
    const key_a = world.ReplayKey{
        .world_surface_scope_fingerprint = scope_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabc,
        .response_fingerprint = 0x123,
    };
    const key_b = world.ReplayKey{
        .world_surface_scope_fingerprint = scope_fingerprint + 1,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabc,
        .response_fingerprint = 0x123,
    };
    const key_c = world.ReplayKey{
        .world_surface_scope_fingerprint = scope_fingerprint,
        .world_port_id = PortsDecl.world_port_id + 1,
        .request_fingerprint = 0xabc,
        .response_fingerprint = 0x123,
    };
    const key_d = world.ReplayKey{
        .world_surface_scope_fingerprint = scope_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabd,
        .response_fingerprint = 0x123,
    };
    const key_e = world.ReplayKey{
        .world_surface_scope_fingerprint = scope_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabc,
        .response_fingerprint = 0x124,
    };
    try std.testing.expect(key_a.fingerprint() != key_b.fingerprint());
    try std.testing.expect(key_a.fingerprint() != key_c.fingerprint());
    try std.testing.expect(key_a.fingerprint() != key_d.fingerprint());
    try std.testing.expect(key_a.fingerprint() != key_e.fingerprint());

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

fn testRequestFrame() world.Frame.Request {
    return world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 0xabc0_ffee,
        .turn_index = 3,
        .payload_value_table_id = 0,
        .expected_response_value_table_id = 1,
    });
}

test "request frame fingerprint stable and encodes canonical bytes" {
    const request = testRequestFrame();
    const again = testRequestFrame();
    try std.testing.expectEqual(request.frame_fingerprint, again.frame_fingerprint);
    try std.testing.expectEqual(fixtures.Ports.Target.WorldSurface.surface_fingerprint, request.world_surface_fingerprint);
    try std.testing.expectEqual(fixtures.Ports.Target.Certificate.certificate_fingerprint, request.target_certificate_fingerprint);
    try std.testing.expectEqual(@as(u32, 0), request.world_port_id);
    try std.testing.expectEqual(@as(u64, 0xabc0_ffee), request.request_fingerprint);

    const encoded = try request.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.Frame.Request.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(request.frame_fingerprint, decoded.frame_fingerprint);

    var wrong_replay_seed = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(wrong_replay_seed);
    const replay_seed_world_surface_offset = 89;
    wrong_replay_seed[replay_seed_world_surface_offset] ^= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Request.decode(std.testing.allocator, wrong_replay_seed));

    const with_junk = try std.testing.allocator.alloc(u8, encoded.len + 1);
    defer std.testing.allocator.free(with_junk);
    @memcpy(with_junk[0..encoded.len], encoded);
    with_junk[encoded.len] = 0;
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Request.decode(std.testing.allocator, with_junk));
}

test "response frame status rejected failed and canonical bytes" {
    const request = testRequestFrame();
    var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, 0xdec1_5100, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.ResponseStatus.responded, response.status);
    try std.testing.expectEqual(request.request_fingerprint, response.request_fingerprint);
    try std.testing.expectEqual(@as(u32, 0), response.world_port_id);

    const encoded = try response.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.Frame.Response.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(response.frame_fingerprint, decoded.frame_fingerprint);
    const decoded_value = try decoded.decodeValue(std.testing.allocator, i32);
    try std.testing.expectEqual(@as(i32, 7), decoded_value);

    var tampered = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(tampered);
    const response_value_fingerprint_offset = 4 + 4 + 8 + 8 + 8 + 4 + 8 + 1 + 1 + 4 + 8 + 1;
    tampered[response_value_fingerprint_offset] ^= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Response.decode(std.testing.allocator, tampered));

    const rejected = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 0,
        .replay_key = request.replay_key_seed.withResponse(0).fingerprint(),
        .status = .rejected,
    });
    try std.testing.expectEqual(world.ResponseStatus.rejected, rejected.status);
    const failed = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 1,
        .replay_key = request.replay_key_seed.withResponse(1).fingerprint(),
        .status = .failed,
    });
    try std.testing.expectEqual(world.ResponseStatus.failed, failed.status);
}

test "value image scalar string product sum and policy failures" {
    var scalar = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, @as(i32, 42), .portable);
    defer scalar.deinit(std.testing.allocator);
    const scalar_value = try scalar.decodeValue(std.testing.allocator, i32);
    try std.testing.expectEqual(@as(i32, 42), scalar_value);
    var literal = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, 42, .portable);
    defer literal.deinit(std.testing.allocator);
    const literal_value = try literal.decodeValue(std.testing.allocator, i32);
    try std.testing.expectEqual(@as(i32, 42), literal_value);

    var string = try world.Frame.ValueImage.fromValue(std.testing.allocator, 2, null, null, @as([]const u8, "hello"), .portable);
    defer string.deinit(std.testing.allocator);
    const decoded_string = try string.decodeValue(std.testing.allocator, []const u8);
    defer std.testing.allocator.free(decoded_string);
    try std.testing.expectEqualStrings("hello", decoded_string);

    const Product = struct { count: i32, label: []const u8 };
    var product = try world.Frame.ValueImage.fromValue(std.testing.allocator, 3, null, null, Product{ .count = 2, .label = @as([]const u8, "ok") }, .portable);
    defer product.deinit(std.testing.allocator);
    const decoded_product = try product.decodeValue(std.testing.allocator, Product);
    defer std.testing.allocator.free(decoded_product.label);
    try std.testing.expectEqual(@as(i32, 2), decoded_product.count);
    try std.testing.expectEqualStrings("ok", decoded_product.label);

    var sum = try world.Frame.ValueImage.fromValue(std.testing.allocator, 4, null, null, fixtures.Agent.Action{ .tool = @as([]const u8, "read") }, .portable);
    defer sum.deinit(std.testing.allocator);
    const decoded_sum = try sum.decodeValue(std.testing.allocator, fixtures.Agent.Action);
    switch (decoded_sum) {
        .tool => |tool_name| {
            defer std.testing.allocator.free(tool_name);
            try std.testing.expectEqualStrings("read", tool_name);
        },
        else => return error.ExpectedToolAction,
    }

    var native_only: i32 = 1;
    try std.testing.expectError(error.UnsupportedValueImage, world.Frame.ValueImage.fromValue(std.testing.allocator, null, null, null, &native_only, .portable));
    try std.testing.expectError(error.UnsupportedValueImage, world.Frame.ValueImage.fromValue(std.testing.allocator, null, null, null, @as([]const u8, "too-big"), .{ .max_value_image_bytes = 1 }));
}

test "transcript image encode decode round trip stable and image replay works without handlers" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const image_request = for (image.events) |event| {
        if (event.request_frame) |request| break request;
    } else return error.ExpectedFrameRequest;
    try std.testing.expectEqual(fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint, image_request.world_surface_replay_scope_fingerprint.?);
    try std.testing.expectEqual(@as(?u32, 0), image_request.payload_value_table_id);
    try std.testing.expectEqual(@as(?u32, 1), image_request.expected_response_value_table_id);
    const encoded = try image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.TranscriptImage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(image.transcript_image_fingerprint, decoded.transcript_image_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), decoded.response_count);
    const decoded_response = for (decoded.events) |event| {
        if (event.response_frame) |response| break response;
    } else return error.ExpectedResponseFrame;
    try std.testing.expectEqual(@as(?u32, 1), decoded_response.response_value_table_id);

    var forged_events = try std.testing.allocator.alloc(world.TranscriptImage.EventImage, 1);
    var forged_events_owned = true;
    errdefer if (forged_events_owned) std.testing.allocator.free(forged_events);
    var forged_response = try decoded_response.clone(std.testing.allocator);
    var forged_response_owned = true;
    errdefer if (forged_response_owned) forged_response.deinit(std.testing.allocator);
    forged_events[0] = .{
        .event_fingerprint = 0,
        .kind = .run_started,
        .world_surface_fingerprint = decoded.world_surface_fingerprint,
        .target_certificate_fingerprint = decoded.target_certificate_fingerprint,
        .source_run = true,
        .response_frame = forged_response,
    };
    forged_response_owned = false;
    var forged_image = world.TranscriptImage{
        .transcript_image_fingerprint = 0,
        .world_surface_fingerprint = decoded.world_surface_fingerprint,
        .target_certificate_fingerprint = decoded.target_certificate_fingerprint,
        .events = forged_events,
        .final_status = .completed,
        .response_count = 1,
    };
    forged_events_owned = false;
    defer forged_image.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.ReplayMissing,
        forged_image.nextResponse(image_request.replay_key_seed, fixtures.Ports.Target.Certificate.certificate_fingerprint, .@"resume"),
    );

    var forged_header: [49]u8 = undefined;
    std.mem.writeInt(u32, forged_header[0..4], world.world_transcript_image_format_version, .little);
    std.mem.writeInt(u32, forged_header[4..8], world.world_transcript_image_fingerprint_version, .little);
    std.mem.writeInt(u64, forged_header[8..16], 0, .little);
    std.mem.writeInt(u64, forged_header[16..24], fixtures.Ports.Target.WorldSurface.surface_fingerprint, .little);
    std.mem.writeInt(u64, forged_header[24..32], fixtures.Ports.Target.Certificate.certificate_fingerprint, .little);
    forged_header[32] = @intFromEnum(world.TranscriptImage.FinalStatus.completed);
    std.mem.writeInt(u64, forged_header[33..41], 0, .little);
    std.mem.writeInt(u64, forged_header[41..49], 1, .little);
    try std.testing.expectError(error.InvalidFrameEncoding, world.TranscriptImage.decode(std.testing.allocator, &forged_header));

    var rebuilt_transcript = try world.Transcript.fromImage(std.testing.allocator, decoded);
    defer rebuilt_transcript.deinit();
    var rebuilt_runtime = boundary.Runtime.init(std.testing.allocator);
    defer rebuilt_runtime.deinit();
    var rebuilt_replayed = try PortsMachine.run(&rebuilt_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &rebuilt_transcript,
    });
    defer rebuilt_replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), rebuilt_replayed.value);

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replayed = try PortsMachine.run(&replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &decoded,
    });
    defer replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), replayed.value);
    try std.testing.expectEqual(@as(usize, 1), replayed.audit.replayed_response_count);
}

test "step frame nextFrame resumeFrame and verify adapter image path work" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    const response_fingerprint = (try firstRespondedEvent(&transcript)).response_fingerprint.?;

    var frame_transcript = world.Transcript.init(std.testing.allocator);
    defer frame_transcript.deinit();

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var run = try PortsMachine.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &frame_transcript,
    });
    defer run.deinit();
    var expected_response_frame_fingerprint: u64 = 0;
    const step = try run.nextFrame();
    switch (step) {
        .port_request => |frame| {
            var request = frame;
            defer request.deinit(std.testing.allocator);
            try std.testing.expect(request.payload_image != null);
            const payload = try request.payload_image.?.decodeValue(std.testing.allocator, []const u8);
            defer std.testing.allocator.free(payload);
            try std.testing.expectEqualStrings("deploy-prod", payload);
            const encoded_request = try request.encode(std.testing.allocator);
            defer std.testing.allocator.free(encoded_request);
            var tampered_request = try std.testing.allocator.dupe(u8, encoded_request);
            defer std.testing.allocator.free(tampered_request);
            const payload_value_fingerprint_offset = 4 + 4 + 8 + 8 + 1 + 8 + 8 + 4 + 8 + 8 + 8 + 8 + 1 + 4 + 1 + 4 + 1;
            tampered_request[payload_value_fingerprint_offset] ^= 1;
            try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Request.decode(std.testing.allocator, tampered_request));
            var wrong_value_table_response = try world.Frame.Response.fromValue(std.testing.allocator, request, null, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer wrong_value_table_response.deinit(std.testing.allocator);
            try std.testing.expectError(error.FrameValueTableMismatch, run.resumeFrame(wrong_value_table_response));
            var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer response.deinit(std.testing.allocator);
            expected_response_frame_fingerprint = response.frame_fingerprint;
            try run.resumeFrame(response);
        },
        else => return error.ExpectedFrameRequest,
    }
    switch (try run.nextFrame()) {
        .done => |value| try std.testing.expectEqual(@as(i32, 7), value),
        else => return error.ExpectedDone,
    }
    try std.testing.expectEqual(@as(usize, 1), run.audit.fresh_response_count);
    try std.testing.expectEqual(@as(usize, 0), run.audit.replayed_response_count);
    const frame_summary = frame_transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), frame_summary.frame_requested);
    try std.testing.expectEqual(@as(usize, 1), frame_summary.frame_responded);

    var frame_image = try frame_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer frame_image.deinit(std.testing.allocator);
    const image_response = for (frame_image.events) |event| {
        if (event.response_frame) |response| break response;
    } else return error.ExpectedResponseFrame;
    try std.testing.expectEqual(expected_response_frame_fingerprint, image_response.frame_fingerprint);
    var frame_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer frame_replay_runtime.deinit();
    var frame_replayed = try PortsMachine.run(&frame_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &frame_image,
    });
    defer frame_replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), frame_replayed.value);

    var frame_verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer frame_verify_runtime.deinit();
    var frame_verify_ctx: PortsCtx = .{};
    var frame_verified = try PortsMachine.run(&frame_verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &frame_verify_ctx,
        .transcript_image = &frame_image,
    });
    defer frame_verified.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), frame_verified.value);
    try std.testing.expectEqual(@as(usize, 1), frame_verify_ctx.calls);

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    var verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer verify_runtime.deinit();
    var verify_ctx: PortsCtx = .{};
    var verified = try PortsMachine.run(&verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &verify_ctx,
        .transcript_image = &image,
    });
    defer verified.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), verified.value);
    try std.testing.expectEqual(@as(usize, 1), verify_ctx.calls);
}

test "rejected and failed frame responses record terminal transcript state" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    {
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var run = try PortsMachine.start(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer run.deinit();

        var request = switch (try run.nextFrame()) {
            .port_request => |frame| frame,
            else => return error.ExpectedFrameRequest,
        };
        defer request.deinit(std.testing.allocator);
        const rejected = world.Frame.Response.init(.{
            .world_surface_fingerprint = request.world_surface_fingerprint,
            .target_certificate_fingerprint = request.target_certificate_fingerprint,
            .world_port_id = request.world_port_id,
            .request_fingerprint = request.request_fingerprint,
            .response_fingerprint = 0,
            .replay_key = request.replay_key_seed.withResponse(0).fingerprint(),
            .status = .rejected,
        });

        try std.testing.expectError(error.HandlerRejected, run.resumeFrame(rejected));
        try std.testing.expectEqual(@as(usize, 1), run.audit.rejected_count);
        switch (try run.nextFrame()) {
            .failed => {},
            else => return error.ExpectedFailed,
        }
    }
    {
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var run = try PortsMachine.start(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer run.deinit();

        var request = switch (try run.nextFrame()) {
            .port_request => |frame| frame,
            else => return error.ExpectedFrameRequest,
        };
        defer request.deinit(std.testing.allocator);
        const failed = world.Frame.Response.init(.{
            .world_surface_fingerprint = request.world_surface_fingerprint,
            .target_certificate_fingerprint = request.target_certificate_fingerprint,
            .world_port_id = request.world_port_id,
            .request_fingerprint = request.request_fingerprint,
            .response_fingerprint = 1,
            .replay_key = request.replay_key_seed.withResponse(1).fingerprint(),
            .status = .failed,
        });

        try std.testing.expectError(error.HandlerFailed, run.resumeFrame(failed));
        try std.testing.expectEqual(@as(usize, 1), run.audit.failed_count);
        switch (try run.nextFrame()) {
            .failed => {},
            else => return error.ExpectedFailed,
        }
    }
    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.frame_rejected);
    try std.testing.expectEqual(@as(usize, 1), summary.frame_failed);
    try std.testing.expectEqual(@as(usize, 2), summary.run_failed);

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), image.response_count);
}

test "portable transcript image rejects responded frames without value images" {
    const request = testRequestFrame();
    const response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 1,
        .replay_key = request.replay_key_seed.withResponse(1).fingerprint(),
        .status = .responded,
    });
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = response.response_fingerprint,
        .response_kind = response.response_kind,
        .replay_key = response.replay_key,
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .status = .responded,
        .response_frame = response,
    });
    try std.testing.expectError(error.MissingValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));
}

test "timeline event checkpoint branch and audit image fingerprints are stable" {
    const request = testRequestFrame();
    var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, 0xdec1_5100, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);

    const event = world.Timeline.Event.init(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .request_frame_fingerprint = request.frame_fingerprint,
        .response_frame_fingerprint = response.frame_fingerprint,
        .replay_key = response.replay_key,
        .turn_index = request.turn_index,
        .status = .responded,
    });
    const same_event = world.Timeline.Event.init(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .request_frame_fingerprint = request.frame_fingerprint,
        .response_frame_fingerprint = response.frame_fingerprint,
        .replay_key = response.replay_key,
        .turn_index = request.turn_index,
        .status = .responded,
    });
    try std.testing.expectEqual(event.event_fingerprint, same_event.event_fingerprint);

    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .event_index = 1,
        .turn_index = request.turn_index,
        .current_request_fingerprint = request.request_fingerprint,
        .last_response_fingerprint = response.response_fingerprint,
        .transcript_prefix_fingerprint = event.event_fingerprint,
        .branch_id = 10,
        .status = .parked_on_port,
    });
    const branch = world.Timeline.Branch{
        .branch_id = 11,
        .parent_branch_id = 10,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .branch_label = "alternate approval",
        .start_event_index = 1,
        .final_event_index = 3,
        .final_status = .completed,
        .event_count = 2,
        .response_count = 1,
    };
    try std.testing.expect(branch.fingerprint() != checkpoint.checkpoint_fingerprint);

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);

    const audit = world.AuditReport{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .mode = .fresh,
        .final_status = .completed,
        .port_request_count = 1,
        .fresh_response_count = 1,
    };
    const audit_image = world.AuditImage.fromReport(audit, image);
    try std.testing.expectEqual(image.transcript_image_fingerprint, audit_image.transcript_image_fingerprint.?);
    try std.testing.expectEqual(@as(usize, 1), audit_image.request_frame_count);
    try std.testing.expect(audit_image.audit_fingerprint != 0);
}

test "world timeline port frame byte adapter native adapter replay adapter agent timeline agent branch audit counts" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    const response_fingerprint = (try firstRespondedEvent(&transcript)).response_fingerprint.?;

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    try std.testing.expect(image.transcript_image_fingerprint != 0);

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replayed = try PortsMachine.run(&replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &image,
    });
    defer replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), replayed.value);

    const request = testRequestFrame();
    const request_bytes = try request.encode(std.testing.allocator);
    defer std.testing.allocator.free(request_bytes);
    var decoded_request = try world.Frame.Request.decode(std.testing.allocator, request_bytes);
    defer decoded_request.deinit(std.testing.allocator);
    var response = try world.Frame.Response.fromValue(std.testing.allocator, decoded_request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);
    const response_bytes = try response.encode(std.testing.allocator);
    defer std.testing.allocator.free(response_bytes);
    var decoded_response = try world.Frame.Response.decode(std.testing.allocator, response_bytes);
    defer decoded_response.deinit(std.testing.allocator);
    try std.testing.expectEqual(response.frame_fingerprint, decoded_response.frame_fingerprint);

    const audit_image = world.AuditImage.fromReport(replayed.audit, image);
    try std.testing.expectEqual(@as(usize, 1), audit_image.replayed_frame_count);
    try std.testing.expect(audit_image.audit_fingerprint != 0);
}

test "world transcript stores string-list values for replay" {
    const response_fingerprint = @as(u64, 0x123);
    const key = world.ReplayKeySeed{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabc,
    };
    const response: []const []const u8 = &.{ "alpha", "beta" };
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var stored = try world.StoredValue.init(std.testing.allocator, response);
    defer stored.deinit(std.testing.allocator);
    try transcript.append(.{
        .kind = .port_responded,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = key.request_fingerprint,
        .response_fingerprint = response_fingerprint,
        .response_kind = .@"resume",
        .replay_key = key.withResponse(response_fingerprint).fingerprint(),
        .value = stored,
    });

    const event = try transcript.nextResponse(key, fixtures.Ports.Target.Certificate.certificate_fingerprint, .@"resume");
    const event_stored = event.value orelse return error.MissingResponseEvent;
    const cloned = try event_stored.as(std.testing.allocator, []const []const u8);
    defer {
        for (cloned) |item| std.testing.allocator.free(item);
        std.testing.allocator.free(cloned);
    }
    try std.testing.expectEqual(@as(usize, 2), cloned.len);
    try std.testing.expectEqualStrings("alpha", cloned[0]);
    try std.testing.expectEqualStrings("beta", cloned[1]);
}

test "world transcript append clones stored values" {
    const response_fingerprint = @as(u64, 0x456);
    const key = world.ReplayKeySeed{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xdef,
    };
    var source = world.Transcript.init(std.testing.allocator);
    var stored = try world.StoredValue.init(std.testing.allocator, @as(i32, 9));
    defer stored.deinit(std.testing.allocator);
    try source.append(.{
        .kind = .port_responded,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = key.request_fingerprint,
        .response_fingerprint = response_fingerprint,
        .response_kind = .@"resume",
        .replay_key = key.withResponse(response_fingerprint).fingerprint(),
        .value = stored,
    });

    var cloned = world.Transcript.init(std.testing.allocator);
    defer cloned.deinit();
    try cloned.append(source.events.items[0]);
    source.deinit();

    const event = try cloned.nextResponse(key, fixtures.Ports.Target.Certificate.certificate_fingerprint, .@"resume");
    const cloned_value = try (event.value orelse return error.MissingResponseEvent).as(std.testing.allocator, i32);
    try std.testing.expectEqual(@as(i32, 9), cloned_value);
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

test "world audit mode rejects self-referential audit source" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    try std.testing.expectError(error.InvalidMode, PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.audit,
        .audit_source = world.Mode.audit,
        .ctx = &ctx,
        .transcript = &transcript,
    }));
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

const BorrowedAgentCtx = struct {
    final_storage: [32]u8 = undefined,
    calls: usize = 0,

    fn init() @This() {
        var ctx: @This() = .{};
        @memcpy(ctx.final_storage[0.."final=borrowed".len], "final=borrowed");
        return ctx;
    }
};

fn decideBorrowed(ctx: *BorrowedAgentCtx, _: []const u8) !fixtures.Agent.Action {
    ctx.calls += 1;
    return .{ .final = ctx.final_storage[0.."final=borrowed".len] };
}

fn unusedTool(_: *BorrowedAgentCtx, _: []const u8) ![]const u8 {
    return error.UnexpectedToolCall;
}

const BorrowedDecideDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decideBorrowed);
const BorrowedToolDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, unusedTool);
const BorrowedMachine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ BorrowedDecideDecl, BorrowedToolDecl },
    .strict_handler_coverage = true,
});
const BorrowedOptions = struct {
    allocator: std.mem.Allocator,
    mode: world.Mode,
    ctx: *BorrowedAgentCtx,
    transcript: *world.Transcript,
};

const OwnedResponseCtx = struct {
    allocator: std.mem.Allocator,
    cleanup_calls: usize = 0,
};

fn ownedTool(ctx: *OwnedResponseCtx, _: []const u8) ![]const u8 {
    return try ctx.allocator.dupe(u8, "owned-response");
}

fn deinitOwnedToolResponse(ctx: *OwnedResponseCtx, response: []const u8) void {
    ctx.cleanup_calls += 1;
    ctx.allocator.free(@constCast(response));
}

fn ownedDecide(_: *OwnedResponseCtx, observation: []const u8) !fixtures.Agent.Action {
    if (std.mem.eql(u8, observation, "start")) return .{ .tool = "owned" };
    return .{ .final = observation };
}

const OwnedDecideDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, ownedDecide);
const OwnedToolDecl = world.portWithOptions(fixtures.Agent.Target, fixtures.Agent.Tool, ownedTool, .{
    .response_deinit = deinitOwnedToolResponse,
});
const OwnedMachine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ OwnedDecideDecl, OwnedToolDecl },
    .strict_handler_coverage = true,
});
const OwnedOptions = struct {
    allocator: std.mem.Allocator,
    mode: world.Mode,
    ctx: *OwnedResponseCtx,
    transcript: *world.Transcript,
};

test "world retains fresh handler responses before resuming boundary" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx = BorrowedAgentCtx.init();

    var run = try BorrowedMachine.start(&runtime, AgentArgs{ @as(usize, 1), "ignored" }, BorrowedOptions{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer run.deinit();

    switch (try run.next()) {
        .port_required => {},
        else => return error.ExpectedPortRequired,
    }
    try run.dispatch();
    @memcpy(ctx.final_storage[0.."final=mutated!".len], "final=mutated!");

    switch (try run.next()) {
        .done => |value| try std.testing.expectEqualStrings("final=borrowed", value),
        else => return error.ExpectedDone,
    }
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
}

test "world stores transcript values with the transcript allocator" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var run_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer _ = run_arena.deinit();
    var ctx = BorrowedAgentCtx.init();

    var result = try BorrowedMachine.run(&runtime, AgentArgs{ @as(usize, 1), "ignored" }, BorrowedOptions{
        .allocator = run_arena.allocator(),
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(run_arena.allocator());

    try std.testing.expectEqualStrings("final=borrowed", result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
}

test "world deinitializes owned handler responses after retaining them" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: OwnedResponseCtx = .{ .allocator = std.testing.allocator };

    var result = try OwnedMachine.run(&runtime, AgentArgs{ @as(usize, 2), "start" }, OwnedOptions{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("owned-response", result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.cleanup_calls);
}

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

test "world replay selects latest zero-port source run after ported run" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    var ported_runtime = boundary.Runtime.init(std.testing.allocator);
    defer ported_runtime.deinit();
    var ported_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var ported = try AgentMachine.run(&ported_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, AgentOptions{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ported_ctx,
        .transcript = &transcript,
    });
    defer ported.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), transcript.summary().port_responded);

    var zero_runtime = boundary.Runtime.init(std.testing.allocator);
    defer zero_runtime.deinit();
    var zero_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var zero = try AgentMachine.run(&zero_runtime, AgentArgs{ @as(usize, 0), "ignored" }, AgentOptions{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &zero_ctx,
        .transcript = &transcript,
    });
    defer zero.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("budget exhausted", zero.value);

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replay_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var replay = try AgentMachine.run(&replay_runtime, AgentArgs{ @as(usize, 0), "ignored" }, AgentOptions{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript = &transcript,
    });
    defer replay.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("budget exhausted", replay.value);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.tool_calls);
}
