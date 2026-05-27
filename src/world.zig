const std = @import("std");

pub const Mode = enum {
    fresh,
    replay,
    verify,
    audit,
};

pub const Error = error{
    SurfaceMismatch,
    TargetCertificateMismatch,
    MissingHandler,
    ExtraHandler,
    UnknownWorldPort,
    UnknownResidualSite,
    ResidualSiteFingerprintMismatch,
    WrongTarget,
    PortMismatch,
    ReplayMissing,
    ReplayPortMismatch,
    ReplayRequestFingerprintMismatch,
    ReplayResponseKindMismatch,
    ReplayUnusedEvent,
    ReplaySurfaceMismatch,
    VerifyDivergence,
    HandlerRejected,
    HandlerPending,
    HandlerFailed,
    UnsupportedAfterRequest,
    InvalidMode,
    OutOfMemory,
};

pub const ResponseKind = enum {
    @"resume",
    return_now,
};

pub const ResponseStatus = enum {
    responded,
    rejected,
    pending,
    failed,
};

pub const EventKind = enum {
    run_started,
    port_requested,
    port_responded,
    port_replayed,
    port_rejected,
    port_failed,
    run_completed,
    run_failed,
};

pub const ReplayKey = struct {
    world_surface_fingerprint: u64,
    world_port_id: u32,
    request_fingerprint: u64,
    response_kind: ResponseKind,

    pub fn fingerprint(self: @This()) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hashBytes(&hasher, "world.replay.key.v0");
        hashU64(&hasher, self.world_surface_fingerprint);
        hashU64(&hasher, self.world_port_id);
        hashU64(&hasher, self.request_fingerprint);
        hashBytes(&hasher, @tagName(self.response_kind));
        return hasher.final();
    }
};

pub const StoredValue = struct {
    ptr: *anyopaque,
    type_name: []const u8,
    destroy_fn: *const fn (std.mem.Allocator, *anyopaque) void,

    pub fn init(allocator: std.mem.Allocator, value: anytype) !@This() {
        const Value = @TypeOf(value);
        const ptr = try allocator.create(Value);
        ptr.* = value;
        return .{
            .ptr = @ptrCast(ptr),
            .type_name = @typeName(Value),
            .destroy_fn = struct {
                fn destroy(inner_allocator: std.mem.Allocator, erased: *anyopaque) void {
                    const typed: *Value = @ptrCast(@alignCast(erased));
                    inner_allocator.destroy(typed);
                }
            }.destroy,
        };
    }

    pub fn as(self: @This(), comptime Value: type) !Value {
        if (!std.mem.eql(u8, self.type_name, @typeName(Value))) return Error.ReplayResponseKindMismatch;
        const typed: *Value = @ptrCast(@alignCast(self.ptr));
        return typed.*;
    }

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.destroy_fn(allocator, self.ptr);
        self.ptr = undefined;
    }
};

pub const Transcript = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event) = .empty,
    replay_cursor: usize = 0,

    pub const Event = struct {
        kind: EventKind,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        world_port_id: ?u32 = null,
        request_fingerprint: ?u64 = null,
        response_fingerprint: ?u64 = null,
        response_kind: ?ResponseKind = null,
        replay_key: ?u64 = null,
        turn_index: ?usize = null,
        residual_site_index: ?usize = null,
        residual_site_fingerprint: ?u64 = null,
        status: ?ResponseStatus = null,
        value: ?StoredValue = null,
    };

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *@This()) void {
        for (self.events.items) |*event| {
            if (event.value) |*stored| stored.deinit(self.allocator);
        }
        self.events.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn append(self: *@This(), event: Event) !void {
        try self.events.append(self.allocator, event);
    }

    pub fn resetReplay(self: *@This()) void {
        self.replay_cursor = 0;
    }

    pub fn nextResponse(
        self: *@This(),
        key: ReplayKey,
        expected_response_kind: ResponseKind,
    ) !*const Event {
        const key_fingerprint = key.fingerprint();
        while (self.replay_cursor < self.events.items.len) : (self.replay_cursor += 1) {
            const index = self.replay_cursor;
            const event = &self.events.items[index];
            if (event.kind != .port_responded) continue;
            self.replay_cursor += 1;
            if (event.world_surface_fingerprint != key.world_surface_fingerprint) return Error.ReplaySurfaceMismatch;
            if ((event.world_port_id orelse return Error.ReplayPortMismatch) != key.world_port_id) return Error.ReplayPortMismatch;
            if ((event.request_fingerprint orelse return Error.ReplayRequestFingerprintMismatch) != key.request_fingerprint) return Error.ReplayRequestFingerprintMismatch;
            if ((event.response_kind orelse return Error.ReplayResponseKindMismatch) != expected_response_kind) return Error.ReplayResponseKindMismatch;
            if ((event.replay_key orelse return Error.ReplayMissing) != key_fingerprint) return Error.ReplayMissing;
            return event;
        }
        return Error.ReplayMissing;
    }

    pub fn assertReplayComplete(self: *const @This()) !void {
        var index = self.replay_cursor;
        while (index < self.events.items.len) : (index += 1) {
            if (self.events.items[index].kind == .port_responded) return Error.ReplayUnusedEvent;
        }
    }

    pub fn summary(self: *const @This()) Summary {
        var result: Summary = .{};
        for (self.events.items) |event| {
            switch (event.kind) {
                .run_started => result.run_started += 1,
                .port_requested => result.port_requested += 1,
                .port_responded => result.port_responded += 1,
                .port_replayed => result.port_replayed += 1,
                .port_rejected => result.port_rejected += 1,
                .port_failed => result.port_failed += 1,
                .run_completed => result.run_completed += 1,
                .run_failed => result.run_failed += 1,
            }
        }
        return result;
    }

    pub const Summary = struct {
        run_started: usize = 0,
        port_requested: usize = 0,
        port_responded: usize = 0,
        port_replayed: usize = 0,
        port_rejected: usize = 0,
        port_failed: usize = 0,
        run_completed: usize = 0,
        run_failed: usize = 0,
    };
};

pub const AuditReport = struct {
    world_surface_fingerprint: u64,
    target_certificate_fingerprint: u64,
    mode: Mode,
    final_status: Status = .running,
    port_request_count: usize = 0,
    fresh_response_count: usize = 0,
    replayed_response_count: usize = 0,
    rejected_count: usize = 0,
    failed_count: usize = 0,
    missing_handler_count: usize = 0,
    replay_mismatch_count: usize = 0,
    per_port_counts: []usize = &.{},

    pub const Status = enum {
        running,
        completed,
        failed,
        parked,
    };
};

pub fn PortRequest(comptime Target: type, comptime Descriptor: type) type {
    return struct {
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        world_port_id: u32,
        residual_site_index: usize,
        residual_site_fingerprint: u64,
        request_fingerprint: u64,
        replay_key: ReplayKey,
        turn_index: usize,
        value_table_payload_id: ?u32,
        value_table_response_id: ?u32,
        source_ref: @TypeOf(Target.WorldPortTable.entries[Descriptor.world_port_id].source_ref),
        world_port_ref: @TypeOf(Target.WorldPortTable.entries[Descriptor.world_port_id].world_port_ref),
        payload_value: Descriptor.Payload,

        pub fn payload(self: @This(), comptime Expected: type) !Expected.Payload {
            if (Expected.world_port_id != self.world_port_id) return Error.PortMismatch;
            return self.payload_value;
        }

        pub fn expectPort(self: @This(), comptime Expected: type) !void {
            if (Expected.world_port_id != self.world_port_id) return Error.PortMismatch;
        }

        pub fn summary(self: @This(), writer: anytype) !void {
            try writer.print(
                "surface={x} target={x} port={d} site={d} request={x} replay={x}",
                .{
                    self.world_surface_fingerprint,
                    self.target_certificate_fingerprint,
                    self.world_port_id,
                    self.residual_site_index,
                    self.request_fingerprint,
                    self.replay_key.fingerprint(),
                },
            );
        }
    };
}

pub fn PortResponse(comptime Target: type, comptime Descriptor: type) type {
    _ = Target;
    return struct {
        world_port_id: u32 = Descriptor.world_port_id,
        request_fingerprint: u64,
        response_kind: ResponseKind = .@"resume",
        value: ?Descriptor.Response = null,
        response_fingerprint: ?u64 = null,
        replay_key: ReplayKey,
        status: ResponseStatus = .responded,
    };
}

pub fn port(comptime Target: type, comptime Site: type, comptime handler_fn: anytype) type {
    const id = comptime worldPortIdForSite(Target, Site) orelse
        @compileError("World port descriptor does not match target WorldPortTable");
    const entry = Target.WorldPortTable.entries[id];
    if (entry.residual_site_fingerprint != Site.fingerprint) {
        @compileError("World port site fingerprint mismatch");
    }
    return struct {
        pub const TargetType = Target;
        pub const SiteType = Site;
        pub const Payload = Site.Payload;
        pub const Response = Site.Resume;
        pub const Result = Site.Result;
        pub const world_port_id: u32 = id;
        pub const residual_site_index: usize = Site.index;
        pub const residual_site_fingerprint: u64 = Site.fingerprint;
        pub const payload_ref = Site.payload_ref;
        pub const response_ref = Site.resume_ref;
        pub const result_ref = Site.result_ref;
        pub const source_ref = entry.source_ref;
        pub const world_port_ref = entry.world_port_ref;
        pub const suggested_name = if (entry.semantic_label) |label| label else entry.op_name;
        pub const handler = handler_fn;

        pub fn replayKey(request_fingerprint: u64) ReplayKey {
            return .{
                .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                .world_port_id = world_port_id,
                .request_fingerprint = request_fingerprint,
                .response_kind = .@"resume",
            };
        }
    };
}

pub fn portById(comptime Target: type, comptime id: u32, comptime Site: type, comptime handler_fn: anytype) type {
    if (id >= Target.WorldPortTable.entries.len) @compileError("world_port_id out of range");
    if (Target.WorldPortTable.entries[id].residual_site_index != Site.index) {
        @compileError("world_port_id does not point at Site");
    }
    return port(Target, Site, handler_fn);
}

pub fn Machine(comptime Target: type, comptime Config: anytype) type {
    comptime validateTarget(Target);
    comptime validateConfig(Target, Config);
    return struct {
        pub const target_world_surface_fingerprint = Target.WorldSurface.surface_fingerprint;
        pub const target_certificate_fingerprint = Target.Certificate.certificate_fingerprint;
        pub const port_count = Target.WorldPortTable.entries.len;

        pub fn assertAllPortsHandled() void {
            comptime assertAllPortsHandledFor(Target, Config);
        }

        pub fn assertNoExtraHandlers() void {
            comptime validateConfig(Target, Config);
        }

        pub fn assertSurfaceMatches(comptime expected: u64) void {
            if (expected != Target.WorldSurface.surface_fingerprint) @compileError("WorldSurface fingerprint mismatch");
        }

        pub fn assertNoSearchHotPath() void {
            Target.assertNoSearchHotPath();
        }

        pub fn assertReplayComplete(transcript: *const Transcript) !void {
            try transcript.assertReplayComplete();
        }

        pub fn start(runtime: anytype, args: anytype, options: anytype) !Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
            return Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)).start(runtime, args, options);
        }

        pub fn run(runtime: anytype, args: anytype, options: anytype) !Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)).Result {
            var run_state = try start(runtime, args, options);
            defer run_state.deinit();
            while (true) {
                const step = try run_state.next();
                switch (step) {
                    .done => |value| return .{ .value = value, .audit = try run_state.snapshotAudit() },
                    .port_required => try run_state.dispatch(),
                    .parked => return Error.HandlerPending,
                    .failed => return Error.HandlerFailed,
                }
            }
        }

        pub fn Run(comptime RuntimePtr: type, comptime Args: type, comptime Options: type) type {
            _ = Args;
            return struct {
                const Self = @This();
                const Program = Target.Program;
                const Session = Program.Session;
                const Request = Session.Request;
                const Value = Program.contract.ResultType;

                runtime: RuntimePtr,
                session: Session,
                allocator: std.mem.Allocator,
                mode: Mode,
                effective_mode: Mode,
                options: Options,
                pending_request: ?Request = null,
                pending_port_id: ?u32 = null,
                audit: AuditReport,
                per_port_counts: []usize,
                done_value: ?Value = null,

                pub const Result = struct {
                    value: Value,
                    audit: AuditReport,

                    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                        deinitRunValue(allocator, self.value);
                        allocator.free(self.audit.per_port_counts);
                        self.audit.per_port_counts = &.{};
                    }
                };

                pub const Step = union(enum) {
                    done: Value,
                    port_required,
                    parked,
                    failed,
                };

                fn snapshotAudit(self: *const Self) !AuditReport {
                    const counts = try self.allocator.dupe(usize, self.audit.per_port_counts);
                    var audit = self.audit;
                    audit.per_port_counts = counts;
                    return audit;
                }

                fn start(runtime: RuntimePtr, args: anytype, options: Options) !Self {
                    const allocator = @field(options, "allocator");
                    const mode_value: Mode = if (@hasField(Options, "mode")) @field(options, "mode") else .fresh;
                    const effective = if (mode_value == .audit and @hasField(Options, "audit_source"))
                        @field(options, "audit_source")
                    else if (mode_value == .audit)
                        Mode.fresh
                    else
                        mode_value;
                    const per_port_counts = try allocator.alloc(usize, Target.WorldPortTable.entries.len);
                    @memset(per_port_counts, 0);
                    errdefer allocator.free(per_port_counts);
                    try validateRuntimeSurfaceOptions(Target, options);
                    if (@hasField(Options, "transcript")) {
                        if (effective == .replay) @field(options, "transcript").resetReplay();
                        try appendRunEvent(Target, options, .run_started, null);
                    }
                    var session = try Program.Session.startWithArgs(runtime, Program.Handlers{}, args);
                    errdefer session.deinit();
                    return .{
                        .runtime = runtime,
                        .session = session,
                        .allocator = allocator,
                        .mode = mode_value,
                        .effective_mode = effective,
                        .options = options,
                        .audit = .{
                            .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                            .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
                            .mode = mode_value,
                            .per_port_counts = per_port_counts,
                        },
                        .per_port_counts = per_port_counts,
                    };
                }

                pub fn deinit(self: *Self) void {
                    self.session.deinit();
                    self.allocator.free(self.per_port_counts);
                }

                pub fn next(self: *Self) !Step {
                    if (self.pending_request != null) return .port_required;
                    switch (try self.session.next()) {
                        .done => |done| {
                            var result = done;
                            defer result.deinit();
                            self.done_value = try cloneRunValue(self.allocator, result.value);
                            self.audit.final_status = .completed;
                            try appendRunEvent(Target, self.options, .run_completed, null);
                            if (self.effective_mode == .replay and @hasField(Options, "transcript")) {
                                try @field(self.options, "transcript").assertReplayComplete();
                            }
                            return .{ .done = self.done_value.? };
                        },
                        .after => {
                            self.audit.final_status = .failed;
                            try appendRunEvent(Target, self.options, .run_failed, null);
                            return Error.UnsupportedAfterRequest;
                        },
                        .request => |request| {
                            const trace = request.trace();
                            const world_port_id = Target.WorldDispatchTable.lookup(trace.operation_site_index) orelse return Error.UnknownResidualSite;
                            if (world_port_id >= Target.WorldPortTable.entries.len) return Error.UnknownWorldPort;
                            const entry = Target.WorldPortTable.entries[world_port_id];
                            if (entry.residual_site_fingerprint != trace.operation_site_fingerprint) return Error.ResidualSiteFingerprintMismatch;
                            self.pending_request = request;
                            self.pending_port_id = world_port_id;
                            self.audit.port_request_count += 1;
                            self.per_port_counts[world_port_id] += 1;
                            if (self.effective_mode != .replay) {
                                try appendPortEvent(Target, self.options, .port_requested, world_port_id, trace, null, null, null);
                            }
                            return .port_required;
                        },
                    }
                }

                pub fn dispatch(self: *Self) !void {
                    const request = self.pending_request orelse return Error.UnknownResidualSite;
                    const world_port_id = self.pending_port_id orelse return Error.UnknownWorldPort;
                    inline for (Config.ports) |Decl| {
                        if (Decl.world_port_id == world_port_id) {
                            try self.dispatchDecl(Decl, request);
                            self.pending_request = null;
                            self.pending_port_id = null;
                            return;
                        }
                    }
                    self.audit.missing_handler_count += 1;
                    return Error.MissingHandler;
                }

                fn dispatchDecl(self: *Self, comptime Decl: type, request: Request) !void {
                    const typed_request = try request.as(Decl.SiteType);
                    const payload = try typed_request.payload();
                    const trace = request.trace();
                    const replay_key = Decl.replayKey(trace.fingerprint);
                    const public_request = PortRequest(Target, Decl){
                        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
                        .world_port_id = Decl.world_port_id,
                        .residual_site_index = trace.operation_site_index,
                        .residual_site_fingerprint = trace.operation_site_fingerprint,
                        .request_fingerprint = trace.fingerprint,
                        .replay_key = replay_key,
                        .turn_index = trace.turn_index,
                        .value_table_payload_id = valueIdFor(Target, Decl.world_port_id, .payload),
                        .value_table_response_id = valueIdFor(Target, Decl.world_port_id, .@"resume"),
                        .source_ref = Decl.source_ref,
                        .world_port_ref = Decl.world_port_ref,
                        .payload_value = payload,
                    };
                    const value = switch (self.effective_mode) {
                        .fresh, .audit => try self.callFresh(Decl, public_request),
                        .verify => try self.callVerify(Decl, public_request, typed_request, replay_key),
                        .replay => try self.callReplay(Decl, typed_request, replay_key, trace),
                    };
                    try self.session.resumeTyped(typed_request, value);
                }

                fn callFresh(self: *Self, comptime Decl: type, request: PortRequest(Target, Decl)) !Decl.Response {
                    const response = try callHandler(Decl, @field(self.options, "ctx"), request);
                    const typed = try (self.pending_request orelse return Error.UnknownResidualSite).as(Decl.SiteType);
                    const response_trace = try typed.responseTrace(.@"resume", response);
                    const stored = try StoredValue.init(self.allocator, response);
                    try appendPortEvent(
                        Target,
                        self.options,
                        .port_responded,
                        Decl.world_port_id,
                        (self.pending_request orelse return Error.UnknownResidualSite).trace(),
                        response_trace.fingerprint,
                        .@"resume",
                        stored,
                    );
                    self.audit.fresh_response_count += 1;
                    return response;
                }

                fn callReplay(
                    self: *Self,
                    comptime Decl: type,
                    typed_request: anytype,
                    replay_key: ReplayKey,
                    trace: anytype,
                ) !Decl.Response {
                    const transcript = @field(self.options, "transcript");
                    const event = transcript.nextResponse(replay_key, .@"resume") catch |err| {
                        self.audit.replay_mismatch_count += 1;
                        return err;
                    };
                    const stored = event.value orelse return Error.ReplayMissing;
                    const value = try stored.as(Decl.Response);
                    const response_trace = try typed_request.responseTrace(.@"resume", value);
                    if (response_trace.fingerprint != (event.response_fingerprint orelse return Error.ReplayMissing)) {
                        self.audit.replay_mismatch_count += 1;
                        return Error.ReplayResponseKindMismatch;
                    }
                    try appendPortEvent(Target, self.options, .port_replayed, Decl.world_port_id, trace, response_trace.fingerprint, .@"resume", null);
                    self.audit.replayed_response_count += 1;
                    return value;
                }

                fn callVerify(
                    self: *Self,
                    comptime Decl: type,
                    request: PortRequest(Target, Decl),
                    typed_request: anytype,
                    replay_key: ReplayKey,
                ) !Decl.Response {
                    const fresh = try callHandler(Decl, @field(self.options, "ctx"), request);
                    const response_trace = try typed_request.responseTrace(.@"resume", fresh);
                    const transcript = @field(self.options, "transcript");
                    const event = transcript.nextResponse(replay_key, .@"resume") catch |err| {
                        self.audit.replay_mismatch_count += 1;
                        return err;
                    };
                    if (response_trace.fingerprint != (event.response_fingerprint orelse return Error.ReplayMissing)) {
                        self.audit.replay_mismatch_count += 1;
                        return Error.VerifyDivergence;
                    }
                    self.audit.fresh_response_count += 1;
                    return fresh;
                }
            };
        }
    };
}

fn validateTarget(comptime Target: type) void {
    const required = .{
        "Program",
        "WorldSurface",
        "WorldPortTable",
        "WorldValueTable",
        "WorldDispatchTable",
        "Certificate",
    };
    inline for (required) |decl| {
        if (!@hasDecl(Target, decl)) @compileError("Boundary Target missing " ++ decl);
    }
    Target.assertWorldSurfaceReady();
    Target.assertNoSearchHotPath();
}

fn validateConfig(comptime Target: type, comptime Config: anytype) void {
    if (!@hasField(@TypeOf(Config), "ports")) @compileError("world.Machine config requires .ports");
    inline for (Config.ports) |Decl| {
        if (Decl.TargetType != Target) @compileError("World port handler bound to wrong Target");
        if (Decl.world_port_id >= Target.WorldPortTable.entries.len) @compileError("World port handler id out of range");
    }
    if (comptime @hasField(@TypeOf(Config), "strict_handler_coverage") and Config.strict_handler_coverage) {
        assertAllPortsHandledFor(Target, Config);
    }
}

fn assertAllPortsHandledFor(comptime Target: type, comptime Config: anytype) void {
    inline for (Target.WorldPortTable.entries) |entry| {
        comptime var found = false;
        inline for (Config.ports) |Decl| {
            if (Decl.world_port_id == entry.world_port_id) found = true;
        }
        if (!found) @compileError("World port missing handler");
    }
}

fn worldPortIdForSite(comptime Target: type, comptime Site: type) ?u32 {
    for (Target.WorldPortTable.entries) |entry| {
        if (entry.residual_site_index == Site.index and entry.residual_site_fingerprint == Site.fingerprint) {
            return entry.world_port_id;
        }
    }
    return null;
}

fn valueIdFor(comptime Target: type, comptime world_port_id: u32, comptime kind: anytype) ?u32 {
    inline for (Target.WorldValueTable.entries) |entry| {
        if (entry.world_port_id == world_port_id and entry.kind == kind) return entry.value_id;
    }
    return null;
}

fn callHandler(comptime Decl: type, ctx: anytype, request_value: PortRequest(Decl.TargetType, Decl)) !Decl.Response {
    const Handler = @TypeOf(Decl.handler);
    const info = @typeInfo(Handler).@"fn";
    if (info.params.len != 2) @compileError("World port handler must take ctx plus payload or PortRequest");
    const Second = info.params[1].type orelse @compileError("World port handler second parameter must be typed");
    if (Second == @TypeOf(request_value)) {
        return Decl.handler(ctx, request_value);
    }
    return Decl.handler(ctx, request_value.payload_value);
}

fn cloneRunValue(allocator: std.mem.Allocator, value: anytype) !@TypeOf(value) {
    const Value = @TypeOf(value);
    if (comptime Value == []const u8) {
        return try allocator.dupe(u8, value);
    }
    return value;
}

fn deinitRunValue(allocator: std.mem.Allocator, value: anytype) void {
    const Value = @TypeOf(value);
    if (comptime Value == []const u8) {
        allocator.free(@constCast(value));
    }
}

fn validateRuntimeSurfaceOptions(comptime Target: type, options: anytype) !void {
    if (@hasField(@TypeOf(options), "expected_world_surface_fingerprint")) {
        if (options.expected_world_surface_fingerprint != Target.WorldSurface.surface_fingerprint) return Error.SurfaceMismatch;
    }
    if (@hasField(@TypeOf(options), "expected_target_certificate_fingerprint")) {
        if (options.expected_target_certificate_fingerprint != Target.Certificate.certificate_fingerprint) return Error.TargetCertificateMismatch;
    }
}

fn appendRunEvent(comptime Target: type, options: anytype, kind: EventKind, status: ?ResponseStatus) !void {
    if (!@hasField(@TypeOf(options), "transcript")) return;
    try @field(options, "transcript").append(.{
        .kind = kind,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
        .status = status,
    });
}

fn appendPortEvent(
    comptime Target: type,
    options: anytype,
    kind: EventKind,
    world_port_id: u32,
    trace: anytype,
    response_fingerprint: ?u64,
    response_kind: ?ResponseKind,
    value: ?StoredValue,
) !void {
    if (!@hasField(@TypeOf(options), "transcript")) return;
    const replay_key = ReplayKey{
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .world_port_id = world_port_id,
        .request_fingerprint = trace.fingerprint,
        .response_kind = response_kind orelse .@"resume",
    };
    try @field(options, "transcript").append(.{
        .kind = kind,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
        .world_port_id = world_port_id,
        .request_fingerprint = trace.fingerprint,
        .response_fingerprint = response_fingerprint,
        .response_kind = response_kind,
        .replay_key = replay_key.fingerprint(),
        .turn_index = trace.turn_index,
        .residual_site_index = trace.operation_site_index,
        .residual_site_fingerprint = trace.operation_site_fingerprint,
        .status = if (kind == .port_responded) .responded else null,
        .value = value,
    });
}

fn hashBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
    hasher.update(bytes);
}

fn hashU64(hasher: *std.hash.Wyhash, value: u64) void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, value, .little);
    hasher.update(&buffer);
}

test {
    _ = Mode;
    _ = Transcript;
    _ = Machine;
}
