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
const PortsNativeBinding = world.bind(PortsDecl, world.NativeAdapter(approve));
const PortsAltNativeBinding = world.bind(PortsDecl, world.NativeAdapter(approveRequest));
const PortsReplayBinding = world.bind(PortsDecl, world.ReplayAdapter(0x7777_aaaa));
const PortsByteBinding = world.bind(PortsDecl, world.ByteAdapter("test-byte"));
const PortsPendingBinding = world.bind(PortsDecl, struct {
    pub const kind: world.AdapterKind = .pending_stub;
    pub const authority = world.PortAuthority.fixture;
    pub const value_policy = world.ValuePolicy.portable;
});
const PortsRejectBinding = world.bind(PortsDecl, struct {
    pub const kind: world.AdapterKind = .null_reject;
    pub const authority = world.PortAuthority.fixture;
    pub const value_policy = world.ValuePolicy.portable;
});
const PortsEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{PortsNativeBinding},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const PortsReplayEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{PortsReplayBinding},
    .policy = world.EnvironmentPolicy.strict_replay,
});
const PortsByteEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{PortsByteBinding},
    .policy = world.EnvironmentPolicy.test_fixture,
});
const PortsMissingEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{},
    .policy = world.EnvironmentPolicy.strict_fresh,
});
const PortsDuplicateEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{ PortsNativeBinding, PortsAltNativeBinding },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const PortsMachineEnv = world.Machine(fixtures.Ports.Target, .{
    .environment = PortsEnv,
    .strict_handler_coverage = true,
});
const PortsReplayMachineEnv = world.Machine(fixtures.Ports.Target, .{
    .environment = PortsReplayEnv,
});
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

const ResumeFailureProgram = struct {
    pub const contract = fixtures.Ports.Target.Program.contract;
    pub const protocol = fixtures.Ports.Target.Program.protocol;
    pub const Handlers = fixtures.Ports.Target.Program.Handlers;
    const InnerSession = fixtures.Ports.Target.Program.Session;

    pub const Session = struct {
        inner: InnerSession,
        pub const Request = InnerSession.Request;

        pub fn startWithArgs(runtime: anytype, handlers: anytype, args: anytype) !@This() {
            return .{ .inner = try InnerSession.startWithArgs(runtime, handlers, args) };
        }

        pub fn deinit(self: *@This()) void {
            self.inner.deinit();
        }

        pub fn next(self: *@This()) @typeInfo(@TypeOf(InnerSession.next)).@"fn".return_type.? {
            return self.inner.next();
        }

        pub fn resumeTyped(_: *@This(), _: anytype, _: anytype) !void {
            return error.TestResumeFailed;
        }
    };
};

const ResumeFailureTarget = struct {
    pub const Program = ResumeFailureProgram;
    pub const WorldSurface = fixtures.Ports.Target.WorldSurface;
    pub const WorldPortTable = fixtures.Ports.Target.WorldPortTable;
    pub const WorldValueTable = fixtures.Ports.Target.WorldValueTable;
    pub const WorldDispatchTable = fixtures.Ports.Target.WorldDispatchTable;
    pub const Certificate = fixtures.Ports.Target.Certificate;

    pub fn assertWorldSurfaceReady() void {}
    pub fn assertNoSearchHotPath() void {}
};
const ResumeFailureRequest = ResumeFailureProgram.protocol.operationSite("approval", "request", 0);
const ResumeFailureDecl = world.port(ResumeFailureTarget, ResumeFailureRequest, approve);
const ResumeFailureMachine = world.Machine(ResumeFailureTarget, .{
    .ports = .{ResumeFailureDecl},
    .strict_handler_coverage = true,
});

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

fn hashTestBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
    hasher.update(bytes);
}

fn hashTestU64(hasher: *std.hash.Wyhash, value: anytype) void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, @intCast(value), .little);
    hasher.update(&buffer);
}

fn writeLittleU64(bytes: []u8, value: anytype) void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, @intCast(value), .little);
    @memcpy(bytes, &buffer);
}

fn firstDiffAfter(left: []const u8, right: []const u8, start: usize) !usize {
    const limit = @min(left.len, right.len);
    var index = start;
    while (index < limit) : (index += 1) {
        if (left[index] != right[index]) return index;
    }
    return error.MissingDiff;
}

fn nthBytesOffset(haystack: []const u8, needle: []const u8, ordinal: usize) !usize {
    var search_from: usize = 0;
    var seen: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, search_from, needle)) |offset| {
        if (seen == ordinal) return offset;
        seen += 1;
        search_from = offset + 1;
    }
    return error.MissingNeedle;
}

fn testTranscriptImageFingerprint(image: world.TranscriptImage) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashTestBytes(&hasher, "world.transcript.image.fingerprint");
    hashTestU64(&hasher, world.world_transcript_image_fingerprint_version);
    hashTestU64(&hasher, image.world_surface_fingerprint);
    hashTestU64(&hasher, image.target_certificate_fingerprint);
    hashTestU64(&hasher, @intFromEnum(image.final_status));
    hashTestU64(&hasher, image.response_count);
    hashTestU64(&hasher, image.events.len);
    for (image.events) |event| hashTestU64(&hasher, event.event_fingerprint);
    return hasher.final();
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

    var checkpointed = world.Transcript.init(std.testing.allocator);
    defer checkpointed.deinit();
    try checkpointed.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    try checkpointed.append(.{
        .kind = .checkpoint_recorded,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    try checkpointed.append(.{
        .kind = .run_completed,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    var replayed = try Machine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &checkpointed,
    });
    defer replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 1), replayed.value);

    var frame_run = try Machine.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    defer frame_run.deinit();
    const impossible_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .request_fingerprint = 0,
        .response_fingerprint = 0,
        .replay_key = 0,
    });
    try std.testing.expectError(error.UnknownResidualSite, frame_run.resumeFrame(impossible_response));
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

test "world frame step rejects missing port descriptor before exposing request" {
    const MissingMachine = world.Machine(fixtures.Ports.Target, .{ .ports = .{} });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    var run = try MissingMachine.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
    });
    defer run.deinit();

    try std.testing.expectError(error.MissingHandler, run.nextFrame());
    switch (try run.nextFrame()) {
        .failed => {},
        else => return error.ExpectedFailed,
    }
    try std.testing.expectEqual(@as(usize, 1), run.audit.missing_handler_count);
    try std.testing.expectEqual(@as(usize, 1), run.audit.failed_count);

    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 0), summary.port_requested);
    try std.testing.expectEqual(@as(usize, 1), summary.port_failed);
    try std.testing.expectEqual(@as(usize, 0), summary.frame_requested);
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

    const wrong_payload_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, @as([]const u8, "deploy-prod"), .portable);
    var wrong_payload_request = world.Frame.Request.init(.{
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
        .payload_image = wrong_payload_image,
    });
    defer wrong_payload_request.deinit(std.testing.allocator);
    const wrong_payload_encoded = try wrong_payload_request.encode(std.testing.allocator);
    defer std.testing.allocator.free(wrong_payload_encoded);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Request.decode(std.testing.allocator, wrong_payload_encoded));

    var wrong_request_version = testRequestFrame();
    wrong_request_version.format_version += 1;
    var request_version_transcript = world.Transcript.init(std.testing.allocator);
    defer request_version_transcript.deinit();
    try request_version_transcript.append(.{
        .kind = .frame_requested,
        .world_surface_fingerprint = wrong_request_version.world_surface_fingerprint,
        .target_certificate_fingerprint = wrong_request_version.target_certificate_fingerprint,
        .world_port_id = wrong_request_version.world_port_id,
        .request_fingerprint = wrong_request_version.request_fingerprint,
        .turn_index = wrong_request_version.turn_index,
        .residual_site_index = wrong_request_version.residual_site_index,
        .residual_site_fingerprint = wrong_request_version.residual_site_fingerprint,
        .request_frame = wrong_request_version,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, request_version_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));

    const with_junk = try std.testing.allocator.alloc(u8, encoded.len + 1);
    defer std.testing.allocator.free(with_junk);
    @memcpy(with_junk[0..encoded.len], encoded);
    with_junk[encoded.len] = 0;
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Request.decode(std.testing.allocator, with_junk));
}

test "response frame status rejected failed and canonical bytes" {
    const request = testRequestFrame();
    const deferred_response_flag: u32 = 1;
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

    const wrong_table_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 0, 0xdec1_5100, null, @as(i32, 7), .portable);
    var wrong_table_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_value_table_id = 1,
        .response_fingerprint = 0xdec1_5100,
        .response_image = wrong_table_image,
        .replay_key = request.replay_key_seed.withResponse(0xdec1_5100).fingerprint(),
    });
    defer wrong_table_response.deinit(std.testing.allocator);
    const wrong_table_encoded = try wrong_table_response.encode(std.testing.allocator);
    defer std.testing.allocator.free(wrong_table_encoded);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Response.decode(std.testing.allocator, wrong_table_encoded));

    const deferred_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, @as(i32, 7), .portable);
    var deferred_with_fingerprint = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_value_table_id = 1,
        .response_fingerprint = 0xdec1_5100,
        .response_image = deferred_image,
        .replay_key = 0,
        .flags = deferred_response_flag,
    });
    defer deferred_with_fingerprint.deinit(std.testing.allocator);
    const deferred_with_fingerprint_encoded = try deferred_with_fingerprint.encode(std.testing.allocator);
    defer std.testing.allocator.free(deferred_with_fingerprint_encoded);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Response.decode(std.testing.allocator, deferred_with_fingerprint_encoded));

    const deferred_rejected_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, @as(i32, 7), .portable);
    var deferred_rejected = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_value_table_id = 1,
        .response_fingerprint = 0,
        .response_image = deferred_rejected_image,
        .replay_key = 0,
        .status = .rejected,
        .flags = deferred_response_flag,
    });
    defer deferred_rejected.deinit(std.testing.allocator);
    const deferred_rejected_encoded = try deferred_rejected.encode(std.testing.allocator);
    defer std.testing.allocator.free(deferred_rejected_encoded);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Response.decode(std.testing.allocator, deferred_rejected_encoded));

    const deferred_without_image = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 0,
        .replay_key = 0,
        .flags = deferred_response_flag,
    });
    const deferred_without_image_encoded = try deferred_without_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(deferred_without_image_encoded);
    try std.testing.expectError(error.MissingValueImage, world.Frame.Response.decode(std.testing.allocator, deferred_without_image_encoded));

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
    const EnumValue = enum(u8) { ok };
    var enum_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, EnumValue.ok, .portable);
    defer enum_image.deinit(std.testing.allocator);
    const enum_value = try enum_image.decodeValue(std.testing.allocator, EnumValue);
    try std.testing.expectEqual(EnumValue.ok, enum_value);
    const SignedEnumValue = enum(i8) { neg = -1 };
    var signed_enum_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, SignedEnumValue.neg, .portable);
    defer signed_enum_image.deinit(std.testing.allocator);
    const signed_enum_value = try signed_enum_image.decodeValue(std.testing.allocator, SignedEnumValue);
    try std.testing.expectEqual(SignedEnumValue.neg, signed_enum_value);
    var labeled_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, null, null, null, @as(i32, 42), world.ValuePolicy.native_compatible);
    defer labeled_image.deinit(std.testing.allocator);
    const dynamic_tampered = try labeled_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(dynamic_tampered);
    @constCast(dynamic_tampered)[19] = 1;
    try std.testing.expectError(error.VerifyValueImageMismatch, world.Frame.ValueImage.decode(std.testing.allocator, dynamic_tampered));
    const label_tampered = try labeled_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(label_tampered);
    @constCast(label_tampered)[label_tampered.len - 1] ^= 1;
    try std.testing.expectError(error.VerifyValueImageMismatch, world.Frame.ValueImage.decode(std.testing.allocator, label_tampered));

    var string = try world.Frame.ValueImage.fromValue(std.testing.allocator, 2, null, null, @as([]const u8, "hello"), .portable);
    defer string.deinit(std.testing.allocator);
    const decoded_string = try string.decodeValue(std.testing.allocator, []const u8);
    defer std.testing.allocator.free(decoded_string);
    try std.testing.expectEqualStrings("hello", decoded_string);
    const mutable_bytes = try std.testing.allocator.dupe(u8, "hello");
    defer std.testing.allocator.free(mutable_bytes);
    var mutable_string = try world.Frame.ValueImage.fromValue(std.testing.allocator, 2, null, null, mutable_bytes, .portable);
    defer mutable_string.deinit(std.testing.allocator);
    const decoded_mutable_string = try mutable_string.decodeValue(std.testing.allocator, []u8);
    defer std.testing.allocator.free(decoded_mutable_string);
    decoded_mutable_string[0] = 'H';
    try std.testing.expectEqualStrings("Hello", decoded_mutable_string);

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
    const Untagged = union { text: []const u8 };
    const forged_untagged = world.Frame.ValueImage{
        .value_image_fingerprint = 0,
        .bytes = &[_]u8{
            0, 0, 0, 0, // field index 0
            3,   0,   0,   0, 0, 0, 0, 0, // byte-slice length
            'b', 'a', 'd',
        },
        .dynamic_size = true,
    };
    try std.testing.expectError(error.UnsupportedValueImage, forged_untagged.decodeValue(std.testing.allocator, Untagged));
    var string_list = try world.Frame.ValueImage.fromValue(std.testing.allocator, 5, null, null, @as([]const []const u8, &.{"alpha"}), .portable);
    defer string_list.deinit(std.testing.allocator);
    std.mem.writeInt(u64, @constCast(string_list.bytes[0..8]), std.math.maxInt(u64), .little);
    try std.testing.expectError(error.InvalidFrameEncoding, string_list.decodeValue(std.testing.allocator, []const []const u8));

    var native_only: i32 = 1;
    try std.testing.expectError(error.UnsupportedValueImage, world.Frame.ValueImage.fromValue(std.testing.allocator, null, null, null, &native_only, .portable));
    try std.testing.expectError(error.UnsupportedValueImage, world.Frame.ValueImage.fromValue(std.testing.allocator, null, null, null, @as([]const u8, "too-big"), .{ .max_value_image_bytes = 1 }));
    const over_decode_cap = try std.testing.allocator.alloc(u8, world.world_max_decoded_byte_field_len + 1);
    defer std.testing.allocator.free(over_decode_cap);
    @memset(over_decode_cap, 0);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.ValueImage.fromValue(std.testing.allocator, null, null, null, over_decode_cap, .{}));
    var stored_over_decode_cap = try world.StoredValue.init(std.testing.allocator, over_decode_cap);
    defer stored_over_decode_cap.deinit(std.testing.allocator);
    try std.testing.expect(stored_over_decode_cap.portable_image == null);
    try std.testing.expectError(error.InvalidFrameEncoding, stored_over_decode_cap.valueImage(std.testing.allocator, null, null, null, .{}));
    var stored_string = try world.StoredValue.init(std.testing.allocator, @as([]const u8, "lazy"));
    defer stored_string.deinit(std.testing.allocator);
    try std.testing.expect(stored_string.portable_image == null);
}

test "transcript image encode decode round trip stable and image replay works without handler context" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);

    {
        var mixed_surface = world.Transcript.init(std.testing.allocator);
        defer mixed_surface.deinit();
        try recordPortsTranscript(&mixed_surface);
        try mixed_surface.append(.{
            .kind = .checkpoint_recorded,
            .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint + 1,
            .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        });
        try std.testing.expectError(error.SurfaceMismatch, mixed_surface.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));
    }
    {
        var mixed_target = world.Transcript.init(std.testing.allocator);
        defer mixed_target.deinit();
        try recordPortsTranscript(&mixed_target);
        try mixed_target.append(.{
            .kind = .checkpoint_recorded,
            .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint + 1,
        });
        try std.testing.expectError(error.TargetCertificateMismatch, mixed_target.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));
    }

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    var stale_replay_image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer stale_replay_image.deinit(std.testing.allocator);
    for (stale_replay_image.events) |*event| {
        if (event.response_frame) |*frame| {
            frame.flags = 1;
            break;
        }
    }
    var stale_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer stale_replay_runtime.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, PortsMachine.run(&stale_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &stale_replay_image,
    }));
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
    var forged_status_image = decoded;
    forged_status_image.final_status = .failed;
    forged_status_image.transcript_image_fingerprint = testTranscriptImageFingerprint(forged_status_image);
    const forged_status_encoded = try forged_status_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(forged_status_encoded);
    try std.testing.expectError(error.InvalidFrameEncoding, world.TranscriptImage.decode(std.testing.allocator, forged_status_encoded));
    const decoded_response = for (decoded.events) |event| {
        if (event.response_frame) |response| break response;
    } else return error.ExpectedResponseFrame;
    try std.testing.expectEqual(@as(?u32, 1), decoded_response.response_value_table_id);
    const MissingDescriptorMachine = world.Machine(fixtures.Ports.Target, .{ .ports = .{} });
    var missing_descriptor_runtime = boundary.Runtime.init(std.testing.allocator);
    defer missing_descriptor_runtime.deinit();
    try std.testing.expectError(error.MissingHandler, MissingDescriptorMachine.run(&missing_descriptor_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &decoded,
    }));

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

    var skipped_events = try std.testing.allocator.alloc(world.TranscriptImage.EventImage, 2);
    errdefer std.testing.allocator.free(skipped_events);
    var skipped_bad_response = try decoded_response.clone(std.testing.allocator);
    var skipped_bad_owned = true;
    errdefer if (skipped_bad_owned) skipped_bad_response.deinit(std.testing.allocator);
    skipped_bad_response.status = .failed;
    var skipped_good_response = try decoded_response.clone(std.testing.allocator);
    var skipped_good_owned = true;
    errdefer if (skipped_good_owned) skipped_good_response.deinit(std.testing.allocator);
    skipped_events[0] = .{
        .event_fingerprint = 0,
        .kind = .frame_responded,
        .world_surface_fingerprint = decoded.world_surface_fingerprint,
        .target_certificate_fingerprint = decoded.target_certificate_fingerprint,
        .world_port_id = skipped_bad_response.world_port_id,
        .request_fingerprint = skipped_bad_response.request_fingerprint,
        .response_fingerprint = skipped_bad_response.response_fingerprint,
        .response_kind = skipped_bad_response.response_kind,
        .replay_key = skipped_bad_response.replay_key,
        .response_frame = skipped_bad_response,
    };
    skipped_bad_owned = false;
    skipped_events[1] = skipped_events[0];
    skipped_events[1].response_frame = skipped_good_response;
    skipped_good_owned = false;
    var skipped_image = world.TranscriptImage{
        .transcript_image_fingerprint = 0,
        .world_surface_fingerprint = decoded.world_surface_fingerprint,
        .target_certificate_fingerprint = decoded.target_certificate_fingerprint,
        .events = skipped_events,
        .final_status = .completed,
        .response_count = 2,
    };
    defer skipped_image.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.ReplayMissing,
        skipped_image.nextResponse(image_request.replay_key_seed, fixtures.Ports.Target.Certificate.certificate_fingerprint, .@"resume"),
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

    var capped_event_header = [_]u8{0} ** (49 + 64);
    std.mem.writeInt(u32, capped_event_header[0..4], world.world_transcript_image_format_version, .little);
    std.mem.writeInt(u32, capped_event_header[4..8], world.world_transcript_image_fingerprint_version, .little);
    capped_event_header[32] = @intFromEnum(world.TranscriptImage.FinalStatus.running);
    std.mem.writeInt(u64, capped_event_header[41..49], 64, .little);
    try std.testing.expectError(error.InvalidFrameEncoding, world.TranscriptImage.decode(std.testing.allocator, &capped_event_header));

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

    var wrong_table_transcript = try world.Transcript.fromImage(std.testing.allocator, decoded);
    defer wrong_table_transcript.deinit();
    for (wrong_table_transcript.events.items) |*event| {
        if (event.response_frame) |*frame| {
            frame.response_value_table_id = null;
            break;
        }
    }
    var wrong_table_runtime = boundary.Runtime.init(std.testing.allocator);
    defer wrong_table_runtime.deinit();
    try std.testing.expectError(error.FrameValueTableMismatch, PortsMachine.run(&wrong_table_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &wrong_table_transcript,
    }));

    var failed_response_transcript = try world.Transcript.fromImage(std.testing.allocator, decoded);
    defer failed_response_transcript.deinit();
    for (failed_response_transcript.events.items) |*event| {
        if (event.response_frame) |response| {
            var failed_response_image = if (response.response_image) |response_image|
                try response_image.clone(std.testing.allocator)
            else
                null;
            errdefer if (failed_response_image) |*response_image| response_image.deinit(std.testing.allocator);
            const failed_response = world.Frame.Response.init(.{
                .world_surface_fingerprint = response.world_surface_fingerprint,
                .target_certificate_fingerprint = response.target_certificate_fingerprint,
                .world_port_id = response.world_port_id,
                .request_fingerprint = response.request_fingerprint,
                .response_kind = response.response_kind,
                .response_value_table_id = response.response_value_table_id,
                .response_fingerprint = response.response_fingerprint,
                .response_image = failed_response_image,
                .replay_key = response.replay_key,
                .status = .failed,
            });
            failed_response_image = null;
            event.response_frame.?.deinit(std.testing.allocator);
            event.response_frame = failed_response;
            event.status = .failed;
            break;
        }
    } else return error.ExpectedResponseFrame;
    var failed_response_runtime = boundary.Runtime.init(std.testing.allocator);
    defer failed_response_runtime.deinit();
    try std.testing.expectError(error.ReplayMissing, PortsMachine.run(&failed_response_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &failed_response_transcript,
    }));

    var rebuilt_verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer rebuilt_verify_runtime.deinit();
    var rebuilt_verify_ctx: PortsCtx = .{};
    var rebuilt_verified = try PortsMachine.run(&rebuilt_verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &rebuilt_verify_ctx,
        .transcript = &rebuilt_transcript,
    });
    defer rebuilt_verified.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), rebuilt_verified.value);
    try std.testing.expectEqual(@as(usize, 1), rebuilt_verify_ctx.calls);

    var both_authorities_transcript = try world.Transcript.fromImage(std.testing.allocator, decoded);
    defer both_authorities_transcript.deinit();
    var both_authorities_runtime = boundary.Runtime.init(std.testing.allocator);
    defer both_authorities_runtime.deinit();
    var both_authorities_replayed = try PortsMachine.run(&both_authorities_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &both_authorities_transcript,
        .transcript_image = &decoded,
    });
    defer both_authorities_replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), both_authorities_replayed.value);

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
            const repeated_step = try run.nextFrame();
            switch (repeated_step) {
                .port_request => |again| {
                    var repeated_request = again;
                    defer repeated_request.deinit(std.testing.allocator);
                    try std.testing.expectEqual(request.frame_fingerprint, repeated_request.frame_fingerprint);
                },
                else => return error.ExpectedFrameRequest,
            }
            try std.testing.expectEqual(@as(usize, 1), frame_transcript.summary().frame_requested);
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
            const wrong_nested_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 0, response_fingerprint, null, @as(i32, 7), .portable);
            var wrong_nested_response = world.Frame.Response.init(.{
                .world_surface_fingerprint = request.world_surface_fingerprint,
                .target_certificate_fingerprint = request.target_certificate_fingerprint,
                .world_port_id = request.world_port_id,
                .request_fingerprint = request.request_fingerprint,
                .response_value_table_id = 1,
                .response_fingerprint = response_fingerprint,
                .response_image = wrong_nested_image,
                .replay_key = request.replay_key_seed.withResponse(response_fingerprint).fingerprint(),
            });
            defer wrong_nested_response.deinit(std.testing.allocator);
            try std.testing.expectError(error.InvalidFrameEncoding, run.resumeFrame(wrong_nested_response));
            var wrong_response_version = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer wrong_response_version.deinit(std.testing.allocator);
            wrong_response_version.format_version += 1;
            try std.testing.expectError(error.InvalidFrameEncoding, run.resumeFrame(wrong_response_version));
            var wrong_response_image_version = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer wrong_response_image_version.deinit(std.testing.allocator);
            wrong_response_image_version.response_image.?.format_version += 1;
            try std.testing.expectError(error.InvalidFrameEncoding, run.resumeFrame(wrong_response_image_version));
            var stale_image_response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer stale_image_response.deinit(std.testing.allocator);
            @constCast(stale_image_response.response_image.?.bytes)[0] ^= 1;
            try std.testing.expectError(error.InvalidFrameEncoding, run.resumeFrame(stale_image_response));
            var stale_frame_response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer stale_frame_response.deinit(std.testing.allocator);
            stale_frame_response.flags = 1;
            try std.testing.expectError(error.InvalidFrameEncoding, run.resumeFrame(stale_frame_response));
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
    const image_response_event = for (frame_image.events) |event| {
        if (event.kind == .frame_responded) break event;
    } else return error.ExpectedResponseFrame;
    try std.testing.expectEqual(world.ResponseStatus.responded, image_response_event.status.?);
    try std.testing.expectEqual(expected_response_frame_fingerprint, image_response.frame_fingerprint);
    var replay_frame_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_frame_runtime.deinit();
    var replay_frame_run = try PortsMachine.start(&replay_frame_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &frame_image,
    });
    defer replay_frame_run.deinit();
    switch (try replay_frame_run.nextFrame()) {
        .port_request => |frame| {
            var request = frame;
            defer request.deinit(std.testing.allocator);
            const forged_replay_response = world.Frame.Response.init(.{
                .world_surface_fingerprint = request.world_surface_fingerprint,
                .target_certificate_fingerprint = request.target_certificate_fingerprint,
                .world_port_id = request.world_port_id,
                .request_fingerprint = request.request_fingerprint,
                .response_fingerprint = 0,
                .replay_key = request.replay_key_seed.withResponse(0).fingerprint(),
            });
            try std.testing.expectError(error.InvalidMode, replay_frame_run.resumeFrame(forged_replay_response));
        },
        else => return error.ExpectedFrameRequest,
    }
    var frame_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer frame_replay_runtime.deinit();
    var frame_replayed = try PortsMachine.run(&frame_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &frame_image,
    });
    defer frame_replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), frame_replayed.value);

    var stale_verify_image = try frame_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer stale_verify_image.deinit(std.testing.allocator);
    for (stale_verify_image.events) |*event| {
        if (event.response_frame) |*response_frame| {
            response_frame.flags = 1;
            break;
        }
    }
    var stale_verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer stale_verify_runtime.deinit();
    var stale_verify_ctx: PortsCtx = .{};
    try std.testing.expectError(error.InvalidFrameEncoding, PortsMachine.run(&stale_verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &stale_verify_ctx,
        .transcript_image = &stale_verify_image,
    }));

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

    var native_frame_image = try frame_transcript.toImage(std.testing.allocator, .{});
    defer native_frame_image.deinit(std.testing.allocator);
    var native_frame_verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer native_frame_verify_runtime.deinit();
    var native_frame_verify_ctx: PortsCtx = .{};
    var native_frame_verified = try PortsMachine.run(&native_frame_verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &native_frame_verify_ctx,
        .transcript_image = &native_frame_image,
    });
    defer native_frame_verified.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), native_frame_verified.value);
    try std.testing.expectEqual(@as(usize, 1), native_frame_verify_ctx.calls);

    var frame_verify_transcript = world.Transcript.init(std.testing.allocator);
    defer frame_verify_transcript.deinit();
    var frame_verify_record_runtime = boundary.Runtime.init(std.testing.allocator);
    defer frame_verify_record_runtime.deinit();
    var frame_verify_record_ctx: PortsCtx = .{};
    var frame_verify_recorded = try PortsMachine.run(&frame_verify_record_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &frame_verify_record_ctx,
        .transcript_image = &frame_image,
        .transcript = &frame_verify_transcript,
    });
    defer frame_verify_recorded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), frame_verify_recorded.value);
    try std.testing.expectEqual(@as(usize, 1), frame_verify_transcript.summary().frame_verified);
    var frame_verify_record_image = try frame_verify_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer frame_verify_record_image.deinit(std.testing.allocator);
    const frame_verify_audit = world.AuditImage.fromReport(frame_verify_recorded.audit, frame_verify_record_image);
    try std.testing.expectEqual(@as(usize, 1), frame_verify_audit.response_frame_count);
    try std.testing.expectEqual(@as(usize, 1), frame_verify_audit.replayed_frame_count);
    try std.testing.expectEqual(@as(usize, 1), frame_verify_audit.verified_frame_count);
    try std.testing.expectEqual(@as(usize, 0), frame_verify_audit.failed_frame_count);

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
    const audit = world.AuditImage.fromReport(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .mode = world.Mode.fresh,
        .final_status = .failed,
        .failed_count = 2,
    }, image);
    try std.testing.expectEqual(@as(usize, 2), audit.request_frame_count);
    try std.testing.expectEqual(@as(usize, 2), audit.response_frame_count);
    try std.testing.expectEqual(@as(usize, 1), audit.failed_frame_count);
    try std.testing.expectEqual(@as(usize, 0), audit.missing_portable_value_image_count);
}

test "resume frame terminally fails when session rejects accepted response" {
    var seed_transcript = world.Transcript.init(std.testing.allocator);
    defer seed_transcript.deinit();
    try recordPortsTranscript(&seed_transcript);
    const response_fingerprint = (try firstRespondedEvent(&seed_transcript)).response_fingerprint.?;

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var run = try ResumeFailureMachine.start(&runtime, .{}, .{
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

    var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);

    try std.testing.expectError(error.TestResumeFailed, run.resumeFrame(response));
    try std.testing.expectEqual(@as(usize, 1), run.audit.failed_count);
    switch (try run.nextFrame()) {
        .failed => {},
        else => return error.ExpectedFailed,
    }

    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.frame_responded);
    try std.testing.expectEqual(@as(usize, 1), summary.frame_failed);
    try std.testing.expectEqual(@as(usize, 1), summary.run_failed);
    const failed_event = for (transcript.events.items) |event| {
        if (event.kind == .frame_failed) break event;
    } else return error.ExpectedFrameFailure;
    try std.testing.expectEqual(world.ResponseStatus.failed, failed_event.status.?);
    try std.testing.expectEqual(world.ResponseStatus.failed, failed_event.response_frame.?.status);

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const failed_image_event = for (image.events) |event| {
        if (event.kind == .frame_failed) break event;
    } else return error.ExpectedFrameFailure;
    try std.testing.expectEqual(world.ResponseStatus.failed, failed_image_event.status.?);
    try std.testing.expectEqual(world.ResponseStatus.failed, failed_image_event.response_frame.?.status);
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
    try std.testing.expectError(error.NativeOnlyValue, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy{ .allow_native_only_values = false } }));
}

test "transcript image applies value policy to stored response frames" {
    const request = testRequestFrame();
    var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, 0xdec1_5100, .@"resume", @as(i32, 7), world.ValuePolicy.native_compatible);
    defer response.deinit(std.testing.allocator);
    try std.testing.expect(response.response_image.?.diagnostic_type_label != null);

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
    try std.testing.expectError(error.UnsupportedValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));
    try std.testing.expectError(error.UnsupportedValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy{ .max_value_image_bytes = 1 } }));
}

test "transcript image applies value policy to stored request frames" {
    var payload_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 0, null, null, @as([]const u8, "deploy-prod"), world.ValuePolicy.native_compatible);
    var request = world.Frame.Request.init(.{
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
        .payload_image = payload_image,
    });
    payload_image = undefined;
    defer request.deinit(std.testing.allocator);
    try std.testing.expect(request.payload_image.?.diagnostic_type_label != null);

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .frame_requested,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .request_frame = request,
    });
    try std.testing.expectError(error.UnsupportedValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));
    try std.testing.expectError(error.UnsupportedValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy{ .max_value_image_bytes = 1 } }));
}

test "native compatible transcript image omits unsupported response value images" {
    const request = testRequestFrame();
    var stored = try world.StoredValue.init(std.testing.allocator, @as(f16, 1.5));
    defer stored.deinit(std.testing.allocator);
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 0xdec1_5100,
        .response_kind = .@"resume",
        .replay_key = request.replay_key_seed.withResponse(0xdec1_5100).fingerprint(),
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .status = .responded,
        .value = stored,
    });
    var image = try transcript.toImage(std.testing.allocator, .{});
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), image.response_count);
    const response_frame = image.events[0].response_frame orelse return error.ExpectedResponseFrame;
    try std.testing.expect(response_frame.response_image == null);
    const audit = world.AuditImage.fromReport(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .mode = world.Mode.fresh,
        .final_status = .completed,
        .fresh_response_count = 1,
    }, image);
    try std.testing.expectEqual(@as(usize, 0), audit.missing_portable_value_image_count);
    try std.testing.expectEqual(@as(usize, 1), audit.native_only_value_count);
}

test "transcript image enforces byte caps on stored response values" {
    const request = testRequestFrame();
    var stored = try world.StoredValue.init(std.testing.allocator, @as([]const u8, "too-big"));
    defer stored.deinit(std.testing.allocator);
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 0xdec1_5100,
        .response_kind = .@"resume",
        .replay_key = request.replay_key_seed.withResponse(0xdec1_5100).fingerprint(),
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .status = .responded,
        .value = stored,
    });
    try std.testing.expectError(error.UnsupportedValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy{ .max_value_image_bytes = 1 } }));
}

test "transcript image final status resets on later run start" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
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
    try transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.TranscriptImage.FinalStatus.running, image.final_status);

    const encoded = try image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.TranscriptImage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.TranscriptImage.FinalStatus.running, decoded.final_status);
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
    var response = try world.Frame.Response.fromPortableValue(std.testing.allocator, decoded_request, 1, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);
    try std.testing.expect(response.responseFingerprintDeferred());
    const response_bytes = try response.encode(std.testing.allocator);
    defer std.testing.allocator.free(response_bytes);
    var decoded_response = try world.Frame.Response.decode(std.testing.allocator, response_bytes);
    defer decoded_response.deinit(std.testing.allocator);
    try std.testing.expectEqual(response.frame_fingerprint, decoded_response.frame_fingerprint);

    var deferred_transcript = world.Transcript.init(std.testing.allocator);
    defer deferred_transcript.deinit();
    try deferred_transcript.append(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = response.world_surface_fingerprint,
        .target_certificate_fingerprint = response.target_certificate_fingerprint,
        .world_port_id = response.world_port_id,
        .request_fingerprint = response.request_fingerprint,
        .response_fingerprint = response.response_fingerprint,
        .response_kind = response.response_kind,
        .replay_key = response.replay_key,
        .status = response.status,
        .response_frame = response,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, deferred_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));

    var frame_runtime = boundary.Runtime.init(std.testing.allocator);
    defer frame_runtime.deinit();
    var frame_run = try PortsMachine.start(&frame_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    defer frame_run.deinit();
    var live_request = switch (try frame_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer live_request.deinit(std.testing.allocator);
    var live_response = try world.Frame.Response.fromPortableValue(std.testing.allocator, live_request, 1, .@"resume", @as(i32, 7), .portable);
    defer live_response.deinit(std.testing.allocator);
    try frame_run.resumeFrame(live_response);
    const frame_result = switch (try frame_run.nextFrame()) {
        .done => |value| value,
        else => return error.ExpectedDone,
    };
    try std.testing.expectEqual(@as(i32, 7), frame_result);

    const audit_image = world.AuditImage.fromReport(replayed.audit, image);
    try std.testing.expectEqual(@as(usize, 1), audit_image.response_frame_count);
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
const AgentEnv = world.Environment(fixtures.Agent.Target, .{
    .bindings = .{
        world.bind(AgentDecideDecl, world.NativeAdapter(decide)),
        world.bind(AgentToolDecl, world.NativeAdapter(tool)),
    },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const AgentMachine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ AgentDecideDecl, AgentToolDecl },
    .strict_handler_coverage = true,
});
const AgentMachineEnv = world.Machine(fixtures.Agent.Target, .{
    .environment = AgentEnv,
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

test "target ref fingerprint stable and rejects wrong WorldSurface or TargetCertificate" {
    const ref_a = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const ref_b = world.TargetRef.fromTarget(fixtures.Ports.Target);
    try std.testing.expectEqual(ref_a.target_ref_fingerprint, ref_b.target_ref_fingerprint);
    try std.testing.expect(ref_a.matchesTarget(fixtures.Ports.Target));

    var wrong_surface = ref_a;
    wrong_surface.world_surface_fingerprint += 1;
    wrong_surface.target_ref_fingerprint += 1;
    try std.testing.expect(!wrong_surface.matchesTarget(fixtures.Ports.Target));

    var wrong_certificate = ref_a;
    wrong_certificate.target_certificate_fingerprint += 1;
    wrong_certificate.target_ref_fingerprint += 1;
    try std.testing.expect(!wrong_certificate.matchesTarget(fixtures.Ports.Target));
    try std.testing.expect(ref_a.residual_program_plan_hash != null);
}

test "import requirement and import set preserve world_port_id scope" {
    const requirement = world.ImportRequirement.fromTargetPort(fixtures.Ports.Target, 0);
    const again = world.ImportRequirement.fromTargetPort(fixtures.Ports.Target, 0);
    try std.testing.expectEqual(requirement.requirement_fingerprint, again.requirement_fingerprint);
    try std.testing.expectEqual(@as(u32, 0), requirement.world_port_id);
    try std.testing.expectEqual(@as(?u32, 0), requirement.payload_value_table_id);
    try std.testing.expectEqual(@as(?u32, 1), requirement.response_value_table_id);

    const set = world.ImportSet.fromTarget(fixtures.Ports.Target);
    const ids = try set.requiredPortIds(std.testing.allocator);
    defer std.testing.allocator.free(ids);
    try std.testing.expectEqual(@as(usize, 1), ids.len);
    try std.testing.expectEqual(@as(u32, 0), ids[0]);
    try std.testing.expectEqual(requirement.requirement_fingerprint, set.requirementForPort(fixtures.Ports.Target, 0).requirement_fingerprint);
}

test "world environment accepts bindings and reports missing duplicate and replay-only coverage" {
    const fresh_report = PortsEnv.acceptanceReport(.fresh, false);
    try std.testing.expect(fresh_report.accepted);
    try std.testing.expectEqual(@as(usize, 1), fresh_report.required_port_count);
    try std.testing.expectEqual(@as(usize, 1), fresh_report.bound_port_count);

    const missing_report = PortsMissingEnv.acceptanceReport(.fresh, false);
    try std.testing.expect(!missing_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.MissingBinding, missing_report.blockers[0]);

    const duplicate_report = PortsDuplicateEnv.acceptanceReport(.fresh, false);
    try std.testing.expect(!duplicate_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.ExtraBinding, duplicate_report.blockers[0]);

    const replay_missing_bindings = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{},
        .policy = world.EnvironmentPolicy.strict_replay,
    }).acceptanceReport(.replay, true);
    try std.testing.expect(!replay_missing_bindings.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.MissingBinding, replay_missing_bindings.blockers[0]);

    const replay_fresh_report = PortsReplayEnv.acceptanceReport(.fresh, false);
    try std.testing.expect(!replay_fresh_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, replay_fresh_report.blockers[0]);

    const replay_verify_report = PortsReplayEnv.acceptanceReport(.verify, true);
    try std.testing.expect(!replay_verify_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, replay_verify_report.blockers[0]);

    const replay_report = PortsReplayEnv.acceptanceReport(.replay, true);
    try std.testing.expect(replay_report.accepted);

    const pending_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsPendingBinding},
        .policy = world.EnvironmentPolicy.fresh_and_replay,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!pending_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, pending_report.blockers[0]);

    const reject_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsRejectBinding},
        .policy = world.EnvironmentPolicy.fresh_and_replay,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!reject_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, reject_report.blockers[0]);
}

test "binding plan and binding descriptors exclude native function pointer identity" {
    const native_record = PortsNativeBinding.bindingRecord();
    const alternate_native_record = PortsAltNativeBinding.bindingRecord();
    try std.testing.expectEqual(native_record.binding_fingerprint, alternate_native_record.binding_fingerprint);
    try std.testing.expectEqual(native_record.adapter_descriptor_fingerprint, alternate_native_record.adapter_descriptor_fingerprint);

    const replay_record = PortsReplayBinding.bindingRecord();
    try std.testing.expect(native_record.binding_fingerprint != replay_record.binding_fingerprint);
    try std.testing.expectEqual(world.AdapterKind.replay, replay_record.adapter_kind);

    const plan = PortsEnv.bindingPlan();
    try std.testing.expect(plan.accepted);
    try std.testing.expectEqual(@as(?usize, 0), plan.lookup(0));
    try std.testing.expectEqual(@as(?usize, null), plan.lookup(99));
}

test "acceptance report port authority adapter descriptor and environment certificate fingerprints are stable" {
    const authority = world.PortAuthority.fixture;
    const same_authority = world.PortAuthority.fixture;
    try std.testing.expectEqual(authority.authority_fingerprint, same_authority.authority_fingerprint);
    try std.testing.expect(authority.allows_fresh_calls);
    try std.testing.expect(world.PortAuthority.replay_source.allows_replay);
    try std.testing.expect(!world.PortAuthority.replay_source.allows_fresh_calls);

    const record = PortsByteBinding.bindingRecord();
    try std.testing.expectEqual(world.AdapterKind.byte, record.adapter_kind);
    const native_record = PortsNativeBinding.bindingRecord();
    try std.testing.expect(native_record.adapter_descriptor_fingerprint != record.adapter_descriptor_fingerprint);

    const report = PortsEnv.acceptanceReport(.fresh, false);
    const report_again = PortsEnv.acceptanceReport(.fresh, false);
    try std.testing.expectEqual(report.report_fingerprint, report_again.report_fingerprint);

    const cert = PortsEnv.certificate(.fresh, false);
    const cert_again = PortsEnv.certificate(.fresh, false);
    try std.testing.expectEqual(cert.certificate_fingerprint, cert_again.certificate_fingerprint);
    try std.testing.expectEqual(PortsEnv.bindingPlan().plan_fingerprint, cert.binding_plan_fingerprint);
    try std.testing.expectEqual(world.EnvironmentCertificate.ModeMask.fresh, cert.accepted_modes);

    const missing_cert = PortsMissingEnv.certificate(.fresh, false);
    try std.testing.expectEqual(world.EnvironmentCertificate.ModeMask.none, missing_cert.accepted_modes);

    const replay_cert = PortsReplayEnv.certificate(.replay, true);
    try std.testing.expectEqual(world.EnvironmentCertificate.ModeMask.replay, replay_cert.accepted_modes);

    const replay_fresh_cert = PortsReplayEnv.certificate(.fresh, false);
    try std.testing.expectEqual(world.EnvironmentCertificate.ModeMask.none, replay_fresh_cert.accepted_modes);
}

test "Machine accepts Environment while legacy ports config remains valid" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var result = try PortsMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);

    const legacy_plan = PortsMachine.port_count;
    try std.testing.expectEqual(@as(usize, 1), legacy_plan);
}

test "run state fingerprints bind parked and completed state without runtime pointers" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const parked = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = testRequestFrame().frame_fingerprint,
        .turn_index = 3,
        .status = .parked_on_port,
    });
    const parked_again = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = testRequestFrame().frame_fingerprint,
        .turn_index = 3,
        .status = .parked_on_port,
    });
    try std.testing.expectEqual(parked.run_state_fingerprint, parked_again.run_state_fingerprint);

    const completed = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .final_value_image_fingerprint = 0x1234,
        .status = .completed,
    });
    try std.testing.expect(parked.run_state_fingerprint != completed.run_state_fingerprint);
}

test "run image encode decode roundtrip includes TargetRef TranscriptImage branches checkpoints and pending frame" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const import_set = world.ImportSet.fromTarget(fixtures.Ports.Target);
    const request = testRequestFrame();
    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .event_index = 1,
        .turn_index = request.turn_index,
        .current_request_fingerprint = request.frame_fingerprint,
        .transcript_prefix_fingerprint = image.events[0].event_fingerprint,
        .branch_id = 1,
        .status = .parked_on_port,
    });
    const branch = world.Timeline.Branch{
        .branch_id = 2,
        .parent_branch_id = 1,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .branch_label = "receiver",
        .start_event_index = 1,
        .final_event_index = image.events.len,
        .final_status = .running,
        .event_count = image.events.len,
        .response_count = image.response_count,
    };
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .branch_id = 2,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .pending_request_fingerprint = request.frame_fingerprint,
        .turn_index = request.turn_index,
        .status = .parked_on_port,
    });
    const run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .transcript_image = image,
        .current_state = state,
        .checkpoints = &.{checkpoint},
        .branches = @constCast(&[_]world.Timeline.Branch{branch}),
        .pending_request_frame = request,
        .environment_certificate_fingerprint = PortsEnv.certificate(.fresh, false).certificate_fingerprint,
        .acceptance_report_fingerprint = PortsEnv.acceptanceReport(.fresh, false).report_fingerprint,
    });

    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.RunImage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(run_image.run_image_fingerprint, decoded.run_image_fingerprint);
    try std.testing.expectEqual(target_ref.target_ref_fingerprint, decoded.target_ref.target_ref_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), decoded.checkpoints.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.branches.len);
    try std.testing.expect(decoded.pending_request_frame != null);

    var malformed = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(malformed);
    malformed[8] +%= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, world.RunImage.decode(std.testing.allocator, malformed));

    var malformed_target_ref = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(malformed_target_ref);
    malformed_target_ref[25] +%= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, world.RunImage.decode(std.testing.allocator, malformed_target_ref));

    var transcript_fingerprint_bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &transcript_fingerprint_bytes, image.transcript_image_fingerprint, .little);
    const encoded_transcript_fingerprint_offset = try nthBytesOffset(encoded, &transcript_fingerprint_bytes, 1);
    var malformed_transcript_fingerprint = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(malformed_transcript_fingerprint);
    malformed_transcript_fingerprint[encoded_transcript_fingerprint_offset] +%= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, world.RunImage.decode(std.testing.allocator, malformed_transcript_fingerprint));

    const stale_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const stale_transcript_binding = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .transcript_image = image,
        .current_state = stale_state,
    });
    try std.testing.expectError(error.HandoffTargetMismatch, stale_transcript_binding.validate(.{}));

    var final_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, @as(i32, 7), .portable);
    defer final_image.deinit(std.testing.allocator);
    const borrowed_final_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .final_value_image_fingerprint = final_image.value_image_fingerprint,
        .status = .completed,
    });
    var borrowed_final_owner = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = borrowed_final_state,
        .final_result_image = final_image,
    });
    borrowed_final_owner.deinit(std.testing.allocator);
    const mismatched_final_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .final_value_image_fingerprint = final_image.value_image_fingerprint + 1,
        .status = .completed,
    });
    const mismatched_final_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = mismatched_final_state,
        .final_result_image = final_image,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_final_image.validate(.{}));

    const wrong_target_checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = target_ref.world_surface_fingerprint + 1,
        .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
        .event_index = 1,
        .turn_index = request.turn_index,
        .current_request_fingerprint = request.frame_fingerprint,
        .transcript_prefix_fingerprint = image.events[0].event_fingerprint,
        .branch_id = 1,
        .status = .parked_on_port,
    });
    const wrong_checkpoint_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .checkpoint_fingerprint = wrong_target_checkpoint.checkpoint_fingerprint,
        .status = .parked_on_port,
    });
    const wrong_target_checkpoint_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = wrong_checkpoint_state,
        .checkpoints = &.{wrong_target_checkpoint},
        .pending_request_frame = request,
    });
    try std.testing.expectError(error.HandoffCheckpointMismatch, wrong_target_checkpoint_image.validate(.{}));
}

test "run image decode rejects oversized timeline counts before allocation" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const import_set = world.ImportSet.fromTarget(fixtures.Ports.Target);
    const base_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .not_started,
    });
    const base_image = world.RunImage.init(.{
        .kind = .reference_target_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = base_state,
    });
    const base_encoded = try base_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(base_encoded);

    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = target_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
        .event_index = 1,
        .turn_index = 1,
        .transcript_prefix_fingerprint = 0,
        .branch_id = 0,
        .status = .running,
    });
    const checkpoint_image = world.RunImage.init(.{
        .kind = .reference_target_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = base_state,
        .checkpoints = &.{checkpoint},
    });
    const checkpoint_encoded = try checkpoint_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(checkpoint_encoded);

    const checkpoint_count_offset = try firstDiffAfter(base_encoded, checkpoint_encoded, 17);

    var oversized_checkpoints = try std.testing.allocator.dupe(u8, base_encoded);
    defer std.testing.allocator.free(oversized_checkpoints);
    writeLittleU64(
        oversized_checkpoints[checkpoint_count_offset..][0..8],
        (world.RunImage.ValidateOptions{}).max_checkpoints + 1,
    );
    var fixed_buffer: [1024]u8 = undefined;
    var fixed_allocator = std.heap.FixedBufferAllocator.init(&fixed_buffer);
    try std.testing.expectError(error.InvalidFrameEncoding, world.RunImage.decode(fixed_allocator.allocator(), oversized_checkpoints));

    var oversized_branches = try std.testing.allocator.dupe(u8, base_encoded);
    defer std.testing.allocator.free(oversized_branches);
    writeLittleU64(
        oversized_branches[checkpoint_count_offset + 8 ..][0..8],
        (world.RunImage.ValidateOptions{}).max_branches + 1,
    );
    var fixed_allocator_again = std.heap.FixedBufferAllocator.init(&fixed_buffer);
    try std.testing.expectError(error.InvalidFrameEncoding, world.RunImage.decode(fixed_allocator_again.allocator(), oversized_branches));
}

test "handoff preflight rejects target mismatch and accepts replay handoff with transcript image" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .replay_only_run);
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var borrowed_image_owner = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .replay_only_run);
    borrowed_image_owner.deinit(std.testing.allocator);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();

    const replay_report = handoff.preflight(fixtures.Ports.Target, PortsReplayEnv, .accept_replay);
    try std.testing.expect(replay_report.accepted);

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const forged_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .not_started,
    });
    const forged_import_set = world.RunImage.init(.{
        .kind = .reference_target_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint + 1,
        .current_state = forged_state,
    });
    const forged_encoded = try forged_import_set.encode(std.testing.allocator);
    defer std.testing.allocator.free(forged_encoded);
    var forged_handoff = try world.Handoff.fromRunImage(std.testing.allocator, forged_encoded);
    defer forged_handoff.deinit();
    const import_mismatch = forged_handoff.preflight(fixtures.Ports.Target, PortsEnv, .inspect_only);
    try std.testing.expect(!import_mismatch.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.HandoffTargetMismatch, import_mismatch.blockers[0]);

    const EmptyEnv = world.Environment(OptionalNullTarget, .{ .bindings = .{}, .policy = world.EnvironmentPolicy.audit_only });
    const mismatch = handoff.preflight(OptionalNullTarget, EmptyEnv, .inspect_only);
    try std.testing.expect(!mismatch.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.HandoffTargetMismatch, mismatch.blockers[0]);
}

test "parked handoff resumes selected pending request on receiver environment" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var run = try PortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    defer run.deinit();
    var request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer request.deinit(std.testing.allocator);

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = request.frame_fingerprint,
        .turn_index = request.turn_index,
        .status = .parked_on_port,
    });
    const run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .pending_request_frame = request,
    });
    var borrowed_frame_owner = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .pending_request_frame = request,
    });
    borrowed_frame_owner.deinit(std.testing.allocator);
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();

    var receiver_runtime = boundary.Runtime.init(std.testing.allocator);
    defer receiver_runtime.deinit();
    var receiver_ctx: PortsCtx = .{};
    var receiver_run = try handoff.@"resume"(fixtures.Ports.Target, PortsEnv, &receiver_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &receiver_ctx,
    }, .accept_fresh);
    defer receiver_run.deinit();
    var receiver_request = switch (try receiver_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer receiver_request.deinit(std.testing.allocator);
    try std.testing.expectEqual(request.frame_fingerprint, receiver_request.frame_fingerprint);
    try receiver_run.dispatch();
    const done = try receiver_run.nextFrame();
    try std.testing.expectEqual(@as(i32, 7), switch (done) {
        .done => |value| value,
        else => return error.ExpectedDone,
    });
}

test "parked handoff replays transcript prefix before selected pending request" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var run = try AgentMachineEnv.start(&runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer run.deinit();
    var model_request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer model_request.deinit(std.testing.allocator);
    try run.dispatch();
    var tool_request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer tool_request.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), ctx.tool_calls);

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .pending_request_fingerprint = tool_request.frame_fingerprint,
        .turn_index = tool_request.turn_index,
        .status = .parked_on_port,
    });
    const run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .transcript_image = image,
        .current_state = state,
        .pending_request_frame = tool_request,
    });
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();

    var receiver_runtime = boundary.Runtime.init(std.testing.allocator);
    defer receiver_runtime.deinit();
    var receiver_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var receiver_run = try handoff.@"resume"(fixtures.Agent.Target, AgentEnv, &receiver_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &receiver_ctx,
    }, .accept_fresh);
    defer receiver_run.deinit();
    try std.testing.expectEqual(@as(usize, 0), receiver_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), receiver_ctx.tool_calls);

    var receiver_request = switch (try receiver_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer receiver_request.deinit(std.testing.allocator);
    try std.testing.expectEqual(tool_request.frame_fingerprint, receiver_request.frame_fingerprint);
    try receiver_run.dispatch();
    var final_model_request = switch (try receiver_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer final_model_request.deinit(std.testing.allocator);
    try receiver_run.dispatch();
    const done = try receiver_run.nextFrame();
    try std.testing.expectEqualStrings("final=actuate skeleton complete", switch (done) {
        .done => |value| value,
        else => return error.ExpectedDone,
    });
    try std.testing.expectEqual(@as(usize, 1), receiver_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 1), receiver_ctx.tool_calls);
}

test "replay handoff replays completed run without native handler calls" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .completed_run);
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();

    const report = handoff.preflight(fixtures.Ports.Target, PortsReplayEnv, .accept_replay);
    try std.testing.expect(report.accepted);
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var replayed = try PortsReplayMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &handoff.run_image.transcript_image.?,
    });
    defer replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), replayed.value);
    try std.testing.expectEqual(@as(usize, 1), replayed.audit.replayed_response_count);
}

test "verify handoff detects changed fixture handler behavior" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .completed_run);
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();
    try std.testing.expect(handoff.preflight(fixtures.Ports.Target, PortsEnv, .accept_verify).accepted);

    var ok_runtime = boundary.Runtime.init(std.testing.allocator);
    defer ok_runtime.deinit();
    var ok_ctx: PortsCtx = .{};
    var verified = try PortsMachineEnv.run(&ok_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &ok_ctx,
        .transcript_image = &handoff.run_image.transcript_image.?,
    });
    defer verified.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), verified.value);

    handoff.run_image.transcript_image.?.resetReplay();
    var bad_runtime = boundary.Runtime.init(std.testing.allocator);
    defer bad_runtime.deinit();
    var bad_ctx: PortsCtx = .{ .response = 99 };
    try std.testing.expectError(error.VerifyDivergence, PortsMachineEnv.run(&bad_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &bad_ctx,
        .transcript_image = &handoff.run_image.transcript_image.?,
    }));
}

test "branch handoff metadata roundtrips and parent transcript is not mutated" {
    var baseline = try runAgentScenario(std.testing.allocator, .skeleton);
    defer baseline.fresh_result.deinit(std.testing.allocator);
    defer baseline.replay_result.deinit(std.testing.allocator);
    defer baseline.transcript.deinit();
    var image = try baseline.transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const original_event_count = baseline.transcript.events.items.len;
    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = fixtures.Agent.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Agent.Target.Certificate.certificate_fingerprint,
        .event_index = 2,
        .turn_index = image.events[1].turn_index orelse 0,
        .current_request_fingerprint = image.events[1].request_fingerprint,
        .transcript_prefix_fingerprint = image.events[1].event_fingerprint,
        .branch_id = 1,
        .status = .parked_on_port,
    });
    const branch = world.Timeline.Branch{
        .branch_id = 2,
        .parent_branch_id = 1,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .branch_label = "agent-branch",
        .start_event_index = checkpoint.event_index,
        .final_event_index = image.events.len,
        .final_status = .completed,
        .event_count = image.events.len - checkpoint.event_index,
        .response_count = image.response_count,
    };
    const target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .branch_id = branch.branch_id,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .status = .completed,
    });
    const run_image = world.RunImage.init(.{
        .kind = .branched_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .transcript_image = image,
        .current_state = state,
        .checkpoints = &.{checkpoint},
        .branches = @constCast(&[_]world.Timeline.Branch{branch}),
    });
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.RunImage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), decoded.branches.len);
    try std.testing.expectEqual(branch.fingerprint(), decoded.branches[0].fingerprint());
    try std.testing.expectEqual(original_event_count, baseline.transcript.events.items.len);

    const invalid_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .branch_id = 99,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint + 1,
        .status = .completed,
    });
    const invalid_branch_image = world.RunImage.init(.{
        .kind = .branched_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .transcript_image = image,
        .current_state = invalid_state,
        .checkpoints = &.{checkpoint},
        .branches = @constCast(&[_]world.Timeline.Branch{branch}),
    });
    try std.testing.expectError(error.HandoffCheckpointMismatch, invalid_branch_image.validate(.{}));
}

test "agent handoff replay works without model or tool handler calls" {
    var run = try runAgentScenario(std.testing.allocator, .skeleton);
    defer run.fresh_result.deinit(std.testing.allocator);
    defer run.replay_result.deinit(std.testing.allocator);
    defer run.transcript.deinit();
    var image = try run.transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Agent.Target, image, .replay_only_run);
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replay_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var replay = try AgentMachine.run(&replay_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript_image = &handoff.run_image.transcript_image.?,
    });
    defer replay.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("final=actuate skeleton complete", replay.value);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.tool_calls);
}
