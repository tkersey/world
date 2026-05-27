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
    ReplayTargetCertificateMismatch,
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
    world_surface_scope_fingerprint: u64,
    world_port_id: u32,
    request_fingerprint: u64,
    response_fingerprint: u64,

    pub fn fingerprint(self: @This()) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hashBytes(&hasher, "world.replay.key.v0");
        hashU64(&hasher, self.world_surface_scope_fingerprint);
        hashU64(&hasher, self.world_port_id);
        hashU64(&hasher, self.request_fingerprint);
        hashU64(&hasher, self.response_fingerprint);
        return hasher.final();
    }
};

pub const ReplayKeySeed = struct {
    world_surface_fingerprint: u64,
    world_surface_scope_fingerprint: u64,
    world_port_id: u32,
    request_fingerprint: u64,

    pub fn withResponse(self: @This(), response_fingerprint: u64) ReplayKey {
        return .{
            .world_surface_scope_fingerprint = self.world_surface_scope_fingerprint,
            .world_port_id = self.world_port_id,
            .request_fingerprint = self.request_fingerprint,
            .response_fingerprint = response_fingerprint,
        };
    }
};

pub const StoredValue = struct {
    ptr: *anyopaque,
    type_name: []const u8,
    clone_fn: *const fn (std.mem.Allocator, *anyopaque) anyerror!StoredValue,
    destroy_fn: *const fn (std.mem.Allocator, *anyopaque) void,

    pub fn init(allocator: std.mem.Allocator, value: anytype) !@This() {
        const cloned = try cloneOwnedValue(allocator, value);
        errdefer deinitOwnedValue(allocator, cloned);
        return initOwned(allocator, cloned);
    }

    fn initOwned(allocator: std.mem.Allocator, value: anytype) !@This() {
        const Value = @TypeOf(value);
        const ptr = try allocator.create(Value);
        errdefer allocator.destroy(ptr);
        ptr.* = value;
        return .{
            .ptr = @ptrCast(ptr),
            .type_name = @typeName(Value),
            .clone_fn = struct {
                fn clone(inner_allocator: std.mem.Allocator, erased: *anyopaque) anyerror!StoredValue {
                    const typed: *Value = @ptrCast(@alignCast(erased));
                    return StoredValue.init(inner_allocator, typed.*);
                }
            }.clone,
            .destroy_fn = struct {
                fn destroy(inner_allocator: std.mem.Allocator, erased: *anyopaque) void {
                    const typed: *Value = @ptrCast(@alignCast(erased));
                    deinitOwnedValue(inner_allocator, typed.*);
                    inner_allocator.destroy(typed);
                }
            }.destroy,
        };
    }

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
        return self.clone_fn(allocator, self.ptr);
    }

    pub fn as(self: @This(), allocator: std.mem.Allocator, comptime Value: type) !Value {
        if (!std.mem.eql(u8, self.type_name, @typeName(Value))) return Error.ReplayResponseKindMismatch;
        const typed: *Value = @ptrCast(@alignCast(self.ptr));
        return cloneOwnedValue(allocator, typed.*);
    }

    fn borrow(self: @This(), comptime Value: type) !Value {
        if (!std.mem.eql(u8, self.type_name, @typeName(Value))) return Error.ReplayResponseKindMismatch;
        const typed: *Value = @ptrCast(@alignCast(self.ptr));
        return typed.*;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.destroy_fn(allocator, self.ptr);
        self.ptr = undefined;
    }
};

pub const Transcript = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event) = .empty,
    replay_cursor: usize = 0,
    replay_limit: ?usize = null,

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
        source_run: bool = true,
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
        var cloned = event;
        cloned.value = null;
        if (event.value) |stored| {
            cloned.value = try stored.clone(self.allocator);
        }
        errdefer if (cloned.value) |*stored| stored.deinit(self.allocator);
        try self.events.append(self.allocator, cloned);
    }

    fn appendOwned(self: *@This(), event: *Event) !void {
        try self.events.append(self.allocator, event.*);
        event.value = null;
    }

    pub fn resetReplay(self: *@This()) void {
        self.replay_cursor = 0;
        self.replay_limit = null;
    }

    pub fn nextResponse(
        self: *@This(),
        key: ReplayKeySeed,
        expected_target_certificate_fingerprint: u64,
        expected_response_kind: ResponseKind,
    ) !*const Event {
        const replay_limit = self.replay_limit orelse self.events.items.len;
        while (self.replay_cursor < replay_limit) : (self.replay_cursor += 1) {
            const index = self.replay_cursor;
            const event = &self.events.items[index];
            if (event.kind != .port_responded) continue;
            if (event.world_surface_fingerprint != key.world_surface_fingerprint) return Error.ReplaySurfaceMismatch;
            if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return Error.ReplayTargetCertificateMismatch;
            if ((event.world_port_id orelse return Error.ReplayPortMismatch) != key.world_port_id) return Error.ReplayPortMismatch;
            if ((event.request_fingerprint orelse return Error.ReplayRequestFingerprintMismatch) != key.request_fingerprint) return Error.ReplayRequestFingerprintMismatch;
            if ((event.response_kind orelse return Error.ReplayResponseKindMismatch) != expected_response_kind) return Error.ReplayResponseKindMismatch;
            const response_fingerprint = event.response_fingerprint orelse return Error.ReplayMissing;
            const key_fingerprint = key.withResponse(response_fingerprint).fingerprint();
            if ((event.replay_key orelse return Error.ReplayMissing) != key_fingerprint) return Error.ReplayMissing;
            self.replay_cursor = index + 1;
            return event;
        }
        return Error.ReplayMissing;
    }

    pub fn assertReplayComplete(self: *const @This()) !void {
        const replay_limit = self.replay_limit orelse self.events.items.len;
        var index = self.replay_cursor;
        while (index < replay_limit) : (index += 1) {
            if (self.events.items[index].kind == .port_responded) return Error.ReplayUnusedEvent;
        }
    }

    pub fn validateReplayRun(
        self: *@This(),
        expected_world_surface_fingerprint: u64,
        expected_target_certificate_fingerprint: u64,
    ) !void {
        var active_start: ?usize = null;
        var selected_start: ?usize = null;
        var selected_limit: ?usize = null;
        var active_is_source_run = false;
        var active_has_port_event = false;
        var active_has_source_response = false;
        var latest_run_failed = false;
        for (self.events.items, 0..) |event, index| {
            switch (event.kind) {
                .run_started => {
                    if (active_start != null) return Error.ReplayMissing;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return Error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return Error.ReplayTargetCertificateMismatch;
                    active_start = index;
                    active_is_source_run = event.source_run;
                    active_has_port_event = false;
                    active_has_source_response = false;
                    latest_run_failed = true;
                },
                .run_completed => {
                    const start = active_start orelse continue;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return Error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return Error.ReplayTargetCertificateMismatch;
                    if (active_is_source_run and (!active_has_port_event or active_has_source_response)) {
                        selected_start = start;
                        selected_limit = index;
                    }
                    active_start = null;
                    latest_run_failed = false;
                },
                .run_failed => {
                    if (active_start == null) continue;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return Error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return Error.ReplayTargetCertificateMismatch;
                    const failed_source_run = active_is_source_run;
                    active_start = null;
                    active_is_source_run = false;
                    if (failed_source_run) {
                        selected_start = null;
                        selected_limit = null;
                    }
                    latest_run_failed = failed_source_run;
                },
                .port_responded => {
                    if (active_start != null) {
                        active_has_port_event = true;
                        active_has_source_response = true;
                    }
                },
                .port_requested,
                .port_replayed,
                .port_rejected,
                .port_failed,
                => {
                    if (active_start != null) active_has_port_event = true;
                },
            }
        }
        if (active_start != null or latest_run_failed) return Error.ReplayMissing;
        self.replay_cursor = (selected_start orelse return Error.ReplayMissing) + 1;
        self.replay_limit = selected_limit orelse return Error.ReplayMissing;
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
    const world_port_id = descriptorWorldPortId(Target, Descriptor);
    return struct {
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        world_port_id: u32,
        residual_site_index: usize,
        residual_site_fingerprint: u64,
        request_fingerprint: u64,
        replay_key: ReplayKeySeed,
        turn_index: usize,
        value_table_payload_id: ?u32,
        value_table_response_id: ?u32,
        source_ref: @TypeOf(Target.WorldPortTable.entries[world_port_id].source_ref),
        world_port_ref: @TypeOf(Target.WorldPortTable.entries[world_port_id].world_port_ref),
        payload_value: Descriptor.Payload,

        pub fn payload(self: @This(), comptime Expected: type) !Expected.Payload {
            if (descriptorWorldPortId(Target, Expected) != self.world_port_id) return Error.PortMismatch;
            return self.payload_value;
        }

        pub fn expectPort(self: @This(), comptime Expected: type) !void {
            if (descriptorWorldPortId(Target, Expected) != self.world_port_id) return Error.PortMismatch;
        }

        pub fn summary(self: @This(), writer: anytype) !void {
            try writer.print(
                "surface={x} target={x} port={d} site={d} request={x} replay_scope={x}",
                .{
                    self.world_surface_fingerprint,
                    self.target_certificate_fingerprint,
                    self.world_port_id,
                    self.residual_site_index,
                    self.request_fingerprint,
                    self.replay_key.world_surface_scope_fingerprint,
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
    return portWithOptions(Target, Site, handler_fn, .{});
}

pub fn portWithOptions(comptime Target: type, comptime Site: type, comptime handler_fn: anytype, comptime options: anytype) type {
    const id = comptime worldPortIdForSite(Target, Site) orelse
        @compileError("World port descriptor does not match target WorldPortTable");
    const entry = Target.WorldPortTable.entries[id];
    if (entry.residual_site_fingerprint != Site.fingerprint) {
        @compileError("World port site fingerprint mismatch");
    }
    if (!Site.may_resume) {
        @compileError("World v0 only supports resumable world ports");
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
        pub const response_deinit = if (@hasField(@TypeOf(options), "response_deinit"))
            options.response_deinit
        else
            noopResponseDeinit;

        pub fn replayKey(request_fingerprint: u64) ReplayKeySeed {
            return .{
                .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                .world_surface_scope_fingerprint = Target.WorldSurface.replayScopeRef().fingerprint,
                .world_port_id = world_port_id,
                .request_fingerprint = request_fingerprint,
            };
        }
    };
}

pub fn portById(comptime Target: type, comptime id: u32, comptime Site: type, comptime handler_fn: anytype) type {
    return portByIdWithOptions(Target, id, Site, handler_fn, .{});
}

pub fn portByIdWithOptions(comptime Target: type, comptime id: u32, comptime Site: type, comptime handler_fn: anytype, comptime options: anytype) type {
    if (id >= Target.WorldPortTable.entries.len) @compileError("world_port_id out of range");
    const entry = Target.WorldPortTable.entries[id];
    if (entry.residual_site_index != Site.index or entry.residual_site_fingerprint != Site.fingerprint) {
        @compileError("world_port_id does not point at Site");
    }
    const Descriptor = portWithOptions(Target, Site, handler_fn, options);
    if (Descriptor.world_port_id != id) @compileError("world_port_id does not point at Site");
    return Descriptor;
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
                    .done => |value| {
                        const audit = try run_state.snapshotAudit();
                        run_state.done_value_present = false;
                        return .{ .value = value, .audit = audit };
                    },
                    .port_required => run_state.dispatch() catch |err| {
                        try run_state.markRunFailed();
                        return err;
                    },
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
                done_value: Value = undefined,
                done_value_present: bool = false,
                retained_values: std.ArrayList(StoredValue) = .empty,

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

                fn markRunFailed(self: *Self) !void {
                    if (self.audit.final_status == .failed) return;
                    if (self.audit.final_status == .completed) return;
                    self.pending_request = null;
                    self.pending_port_id = null;
                    self.audit.final_status = .failed;
                    try appendRunEvent(Target, self.options, .run_failed, null, false);
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
                    if (effective == .audit) return Error.InvalidMode;
                    const per_port_counts = try allocator.alloc(usize, Target.WorldPortTable.entries.len);
                    @memset(per_port_counts, 0);
                    errdefer allocator.free(per_port_counts);
                    try validateRuntimeSurfaceOptions(Target, options);
                    if (modeConsumesTranscript(effective) and !@hasField(Options, "transcript")) return Error.ReplayMissing;
                    var session = try Program.Session.startWithArgs(runtime, Program.Handlers{}, args);
                    errdefer session.deinit();
                    if (@hasField(Options, "transcript")) {
                        if (modeConsumesTranscript(effective)) {
                            @field(options, "transcript").resetReplay();
                            try @field(options, "transcript").validateReplayRun(
                                Target.WorldSurface.surface_fingerprint,
                                Target.Certificate.certificate_fingerprint,
                            );
                        }
                        try appendRunEvent(Target, options, .run_started, null, effective == .fresh);
                    }
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
                    if (self.done_value_present) {
                        deinitRunValue(self.allocator, self.done_value);
                        self.done_value_present = false;
                    }
                    self.session.deinit();
                    for (self.retained_values.items) |*value| value.deinit(self.allocator);
                    self.retained_values.deinit(self.allocator);
                    self.allocator.free(self.per_port_counts);
                }

                pub fn next(self: *Self) !Step {
                    if (self.audit.final_status == .completed) {
                        if (!self.done_value_present) return Error.HandlerFailed;
                        return .{ .done = self.done_value };
                    }
                    if (self.audit.final_status == .failed) return .failed;
                    if (self.pending_request != null) return .port_required;
                    const session_step = self.session.next() catch |err| {
                        self.audit.failed_count += 1;
                        try self.markRunFailed();
                        return err;
                    };
                    switch (session_step) {
                        .done => |done| {
                            var result = done;
                            defer result.deinit();
                            self.done_value = try cloneRunValue(self.allocator, result.value);
                            self.done_value_present = true;
                            if (modeConsumesTranscript(self.effective_mode) and @hasField(Options, "transcript")) {
                                @field(self.options, "transcript").assertReplayComplete() catch |err| {
                                    self.audit.replay_mismatch_count += 1;
                                    try self.markRunFailed();
                                    return err;
                                };
                            }
                            self.audit.final_status = .completed;
                            try appendRunEvent(Target, self.options, .run_completed, null, self.effective_mode == .fresh);
                            return .{ .done = self.done_value };
                        },
                        .after => {
                            try self.markRunFailed();
                            return Error.UnsupportedAfterRequest;
                        },
                        .request => |request| {
                            const trace = request.trace();
                            const world_port_id = Target.WorldDispatchTable.lookup(trace.operation_site_index) orelse {
                                self.audit.failed_count += 1;
                                try self.markRunFailed();
                                return Error.UnknownResidualSite;
                            };
                            if (world_port_id >= Target.WorldPortTable.entries.len) {
                                self.audit.failed_count += 1;
                                try self.markRunFailed();
                                return Error.UnknownWorldPort;
                            }
                            const entry = Target.WorldPortTable.entries[world_port_id];
                            if (entry.residual_site_fingerprint != trace.operation_site_fingerprint) {
                                self.audit.failed_count += 1;
                                try self.markRunFailed();
                                return Error.ResidualSiteFingerprintMismatch;
                            }
                            self.pending_request = request;
                            self.pending_port_id = world_port_id;
                            self.audit.port_request_count += 1;
                            self.per_port_counts[world_port_id] += 1;
                            if (self.effective_mode == .fresh) {
                                try appendPortEvent(Target, self.options, .port_requested, world_port_id, trace, null, null, null);
                            }
                            return .port_required;
                        },
                    }
                }

                pub fn dispatch(self: *Self) !void {
                    if (self.audit.final_status == .failed) return Error.HandlerFailed;
                    const request = self.pending_request orelse return Error.UnknownResidualSite;
                    const world_port_id = self.pending_port_id orelse return Error.UnknownWorldPort;
                    const trace = request.trace();
                    if (Target.WorldPortTable.entries.len == 0) return self.markMissingHandler(world_port_id, trace);
                    switch (world_port_id) {
                        inline 0...Target.WorldPortTable.entries.len - 1 => |id| {
                            const Handler = comptime handlerForWorldPortId(Target, Config, @intCast(id));
                            if (Handler) |Decl| {
                                self.dispatchDecl(Decl, request) catch |err| {
                                    self.audit.failed_count += 1;
                                    try appendPortEvent(Target, self.options, .port_failed, world_port_id, trace, null, null, null);
                                    try self.markRunFailed();
                                    return err;
                                };
                                self.pending_request = null;
                                self.pending_port_id = null;
                                return;
                            }
                            return self.markMissingHandler(world_port_id, trace);
                        },
                        else => return Error.UnknownWorldPort,
                    }
                }

                fn markMissingHandler(self: *Self, world_port_id: u32, trace: anytype) !void {
                    self.audit.missing_handler_count += 1;
                    self.audit.failed_count += 1;
                    try appendPortEvent(Target, self.options, .port_failed, world_port_id, trace, null, null, null);
                    try self.markRunFailed();
                    return Error.MissingHandler;
                }

                fn dispatchDecl(self: *Self, comptime Decl: type, request: Request) !void {
                    const typed_request = try request.as(Decl.SiteType);
                    const payload = try typed_request.payload();
                    const trace = request.trace();
                    const replay_key = Decl.replayKey(trace.fingerprint);
                    const public_request = PortRequest(Target, Decl.SiteType){
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
                    switch (self.effective_mode) {
                        .fresh, .audit => {
                            const value = try self.callFresh(Decl, public_request);
                            try self.session.resumeTyped(typed_request, value);
                        },
                        .verify => {
                            const value = try self.callVerify(Decl, public_request, typed_request, replay_key);
                            try self.session.resumeTyped(typed_request, value);
                        },
                        .replay => {
                            const value = try self.callReplay(Decl, typed_request, replay_key, trace);
                            try self.session.resumeTyped(typed_request, value);
                        },
                    }
                }

                fn callFresh(self: *Self, comptime Decl: type, request: PortRequest(Target, Decl.SiteType)) !Decl.Response {
                    if (!@hasField(Options, "ctx")) return Error.MissingHandler;
                    const response = try callHandler(Decl, @field(self.options, "ctx"), request);
                    defer Decl.response_deinit(@field(self.options, "ctx"), response);
                    const typed = try (self.pending_request orelse return Error.UnknownResidualSite).as(Decl.SiteType);
                    const response_trace = try typed.responseTrace(.@"resume", response);
                    var stored: ?StoredValue = null;
                    if (comptime @hasField(Options, "transcript")) {
                        stored = try StoredValue.init(@field(self.options, "transcript").allocator, response);
                    }
                    defer if (stored) |*owned| {
                        if (comptime @hasField(Options, "transcript")) {
                            owned.deinit(@field(self.options, "transcript").allocator);
                        }
                    };
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
                    stored = null;
                    self.audit.fresh_response_count += 1;
                    return try self.retainResponse(Decl.Response, response);
                }

                fn callReplay(
                    self: *Self,
                    comptime Decl: type,
                    typed_request: anytype,
                    replay_key: ReplayKeySeed,
                    trace: anytype,
                ) !Decl.Response {
                    if (!@hasField(Options, "transcript")) return Error.ReplayMissing;
                    const transcript = @field(self.options, "transcript");
                    const event = transcript.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                        self.audit.replay_mismatch_count += 1;
                        return err;
                    };
                    const stored = event.value orelse return Error.ReplayMissing;
                    const value = try stored.as(self.allocator, Decl.Response);
                    var value_owned = true;
                    errdefer if (value_owned) deinitOwnedValue(self.allocator, value);
                    const response_trace = try typed_request.responseTrace(.@"resume", value);
                    if (response_trace.fingerprint != (event.response_fingerprint orelse return Error.ReplayMissing)) {
                        self.audit.replay_mismatch_count += 1;
                        return Error.ReplayResponseKindMismatch;
                    }
                    try appendPortEvent(Target, self.options, .port_replayed, Decl.world_port_id, trace, response_trace.fingerprint, .@"resume", null);
                    self.audit.replayed_response_count += 1;
                    var run_value = try StoredValue.initOwned(self.allocator, value);
                    value_owned = false;
                    var run_value_owned = true;
                    errdefer if (run_value_owned) run_value.deinit(self.allocator);
                    try self.retained_values.append(self.allocator, run_value);
                    run_value_owned = false;
                    return self.retained_values.items[self.retained_values.items.len - 1].borrow(Decl.Response);
                }

                fn callVerify(
                    self: *Self,
                    comptime Decl: type,
                    request: PortRequest(Target, Decl.SiteType),
                    typed_request: anytype,
                    replay_key: ReplayKeySeed,
                ) !Decl.Response {
                    if (!@hasField(Options, "ctx")) return Error.MissingHandler;
                    if (!@hasField(Options, "transcript")) return Error.ReplayMissing;
                    const transcript = @field(self.options, "transcript");
                    const event = transcript.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                        self.audit.replay_mismatch_count += 1;
                        return err;
                    };
                    const expected_response_fingerprint = event.response_fingerprint orelse return Error.ReplayMissing;
                    const stored = event.value orelse return Error.ReplayMissing;
                    const replay_value = stored.as(self.allocator, Decl.Response) catch |err| {
                        self.audit.replay_mismatch_count += 1;
                        return err;
                    };
                    defer deinitOwnedValue(self.allocator, replay_value);
                    const replay_trace = try typed_request.responseTrace(.@"resume", replay_value);
                    if (replay_trace.fingerprint != expected_response_fingerprint) {
                        self.audit.replay_mismatch_count += 1;
                        return Error.VerifyDivergence;
                    }
                    self.audit.replayed_response_count += 1;
                    const fresh = try callHandler(Decl, @field(self.options, "ctx"), request);
                    defer Decl.response_deinit(@field(self.options, "ctx"), fresh);
                    const response_trace = try typed_request.responseTrace(.@"resume", fresh);
                    if (response_trace.fingerprint != expected_response_fingerprint) {
                        self.audit.replay_mismatch_count += 1;
                        return Error.VerifyDivergence;
                    }
                    self.audit.fresh_response_count += 1;
                    return try self.retainResponse(Decl.Response, fresh);
                }

                fn retainResponse(self: *Self, comptime Response: type, value: Response) !Response {
                    var retained = try StoredValue.init(self.allocator, value);
                    var retained_owned = true;
                    errdefer if (retained_owned) retained.deinit(self.allocator);
                    try self.retained_values.append(self.allocator, retained);
                    retained_owned = false;
                    return self.retained_values.items[self.retained_values.items.len - 1].borrow(Response);
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
    inline for (Config.ports, 0..) |Decl, index| {
        if (Decl.TargetType != Target) @compileError("World port handler bound to wrong Target");
        if (Decl.world_port_id >= Target.WorldPortTable.entries.len) @compileError("World port handler id out of range");
        validatePortDescriptorMetadata(Target, Decl);
        inline for (Config.ports, 0..) |Other, other_index| {
            if (other_index > index and Decl.world_port_id == Other.world_port_id) {
                @compileError("World port handler id duplicated");
            }
        }
    }
    if (comptime @hasField(@TypeOf(Config), "strict_handler_coverage") and Config.strict_handler_coverage) {
        assertAllPortsHandledFor(Target, Config);
    }
}

fn validatePortDescriptorMetadata(comptime Target: type, comptime Decl: type) void {
    const entry = Target.WorldPortTable.entries[Decl.world_port_id];
    if (Decl.residual_site_index != entry.residual_site_index or
        Decl.residual_site_fingerprint != entry.residual_site_fingerprint or
        !boundaryValueRefMatches(Decl.payload_ref, entry.payload_ref) or
        !boundaryValueRefMatches(Decl.response_ref, entry.resume_ref) or
        !boundaryValueRefMatches(Decl.result_ref, entry.result_ref) or
        !Decl.source_ref.eql(entry.source_ref) or
        !Decl.world_port_ref.eql(entry.world_port_ref))
    {
        @compileError("World port descriptor metadata does not match target WorldPortTable");
    }
}

fn boundaryValueRefMatches(comptime descriptor_ref: anytype, comptime target_ref: anytype) bool {
    return std.mem.eql(u8, @tagName(descriptor_ref.codec), target_ref.codec) and
        descriptor_ref.schema_index == target_ref.schema_index;
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

fn handlerForWorldPortId(comptime Target: type, comptime Config: anytype, comptime world_port_id: u32) ?type {
    _ = Target;
    inline for (Config.ports) |Decl| {
        if (Decl.world_port_id == world_port_id) return Decl;
    }
    return null;
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

fn descriptorWorldPortId(comptime Target: type, comptime Descriptor: type) u32 {
    if (comptime @hasDecl(Descriptor, "world_port_id")) return Descriptor.world_port_id;
    return comptime worldPortIdForSite(Target, Descriptor) orelse
        @compileError("World port request type does not match target WorldPortTable");
}

fn callHandler(comptime Decl: type, ctx: anytype, request_value: PortRequest(Decl.TargetType, Decl.SiteType)) !Decl.Response {
    const Handler = @TypeOf(Decl.handler);
    const info = @typeInfo(Handler).@"fn";
    if (info.params.len != 2) @compileError("World port handler must take ctx plus payload or PortRequest");
    const Second = info.params[1].type orelse @compileError("World port handler second parameter must be typed");
    if (Second == @TypeOf(request_value)) {
        return Decl.handler(ctx, request_value);
    }
    return Decl.handler(ctx, request_value.payload_value);
}

fn noopResponseDeinit(_: anytype, _: anytype) void {}

fn cloneOwnedValue(allocator: std.mem.Allocator, value: anytype) !@TypeOf(value) {
    const Value = @TypeOf(value);
    return switch (@typeInfo(Value)) {
        .void,
        .bool,
        .int,
        .float,
        .comptime_float,
        .comptime_int,
        .@"enum",
        .error_set,
        => value,
        .pointer => |pointer| blk: {
            if (comptime pointer.size == .slice and pointer.child == u8) {
                break :blk try allocator.dupe(u8, value);
            }
            if (comptime isStringList(Value)) {
                break :blk try cloneOwnedStringList(allocator, value);
            }
            @compileError("World transcript/result storage only supports owned cloning for byte slices and string lists");
        },
        .optional => |optional| if (value) |payload|
            try cloneOwnedValue(allocator, @as(optional.child, payload))
        else
            null,
        .@"struct" => |info| blk: {
            var result: Value = undefined;
            var initialized_fields: usize = 0;
            errdefer inline for (info.fields, 0..) |field, field_index| {
                if (field_index < initialized_fields) {
                    deinitOwnedValue(allocator, @field(result, field.name));
                }
            };
            inline for (info.fields) |field| {
                @field(result, field.name) = try cloneOwnedValue(allocator, @field(value, field.name));
                initialized_fields += 1;
            }
            break :blk result;
        },
        .@"union" => |union_info| blk: {
            const Tag = union_info.tag_type orelse
                @compileError("World transcript/result storage requires tagged unions");
            const active_tag = std.meta.activeTag(value);
            inline for (union_info.fields) |field| {
                if (active_tag == @field(Tag, field.name)) {
                    if (field.type == void) break :blk @unionInit(Value, field.name, {});
                    const cloned = try cloneOwnedValue(allocator, @field(value, field.name));
                    break :blk @unionInit(Value, field.name, cloned);
                }
            }
            unreachable;
        },
        else => @compileError("World transcript/result storage cannot own-clone " ++ @typeName(Value)),
    };
}

fn deinitOwnedValue(allocator: std.mem.Allocator, value: anytype) void {
    const Value = @TypeOf(value);
    switch (@typeInfo(Value)) {
        .void,
        .bool,
        .int,
        .float,
        .comptime_float,
        .comptime_int,
        .@"enum",
        .error_set,
        => {},
        .pointer => |pointer| {
            if (comptime pointer.size == .slice and pointer.child == u8) {
                allocator.free(@constCast(value));
                return;
            }
            if (comptime isStringList(Value)) {
                for (value) |item| allocator.free(@constCast(item));
                allocator.free(@constCast(value));
                return;
            }
        },
        .optional => if (value) |payload| deinitOwnedValue(allocator, payload),
        .@"struct" => |info| inline for (info.fields) |field| {
            deinitOwnedValue(allocator, @field(value, field.name));
        },
        .@"union" => |union_info| {
            const Tag = union_info.tag_type orelse return;
            const active_tag = std.meta.activeTag(value);
            inline for (union_info.fields) |field| {
                if (active_tag == @field(Tag, field.name)) {
                    if (field.type != void) deinitOwnedValue(allocator, @field(value, field.name));
                    return;
                }
            }
        },
        else => {},
    }
}

fn isByteSlice(comptime Value: type) bool {
    return switch (@typeInfo(Value)) {
        .pointer => |pointer| pointer.size == .slice and pointer.child == u8,
        else => false,
    };
}

fn isStringList(comptime Value: type) bool {
    return switch (@typeInfo(Value)) {
        .pointer => |pointer| pointer.size == .slice and isByteSlice(pointer.child),
        else => false,
    };
}

fn cloneOwnedStringList(allocator: std.mem.Allocator, value: anytype) !@TypeOf(value) {
    const Value = @TypeOf(value);
    const Child = @typeInfo(Value).pointer.child;
    const result = try allocator.alloc(Child, value.len);
    errdefer allocator.free(result);
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |item| allocator.free(@constCast(item));
    for (value, 0..) |item, index| {
        result[index] = try allocator.dupe(u8, item);
        initialized += 1;
    }
    return result;
}

fn cloneRunValue(allocator: std.mem.Allocator, value: anytype) !@TypeOf(value) {
    return cloneOwnedValue(allocator, value);
}

fn deinitRunValue(allocator: std.mem.Allocator, value: anytype) void {
    deinitOwnedValue(allocator, value);
}

fn validateRuntimeSurfaceOptions(comptime Target: type, options: anytype) !void {
    if (@hasField(@TypeOf(options), "expected_world_surface_fingerprint")) {
        if (options.expected_world_surface_fingerprint != Target.WorldSurface.surface_fingerprint) return Error.SurfaceMismatch;
    }
    if (@hasField(@TypeOf(options), "expected_target_certificate_fingerprint")) {
        if (options.expected_target_certificate_fingerprint != Target.Certificate.certificate_fingerprint) return Error.TargetCertificateMismatch;
    }
}

fn modeConsumesTranscript(mode: Mode) bool {
    return mode == .replay or mode == .verify;
}

fn appendRunEvent(comptime Target: type, options: anytype, kind: EventKind, status: ?ResponseStatus, source_run: bool) !void {
    if (!@hasField(@TypeOf(options), "transcript")) return;
    try @field(options, "transcript").append(.{
        .kind = kind,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
        .status = status,
        .source_run = source_run,
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
    const transcript = @field(options, "transcript");
    const replay_key = if (response_fingerprint) |fingerprint| ReplayKey{
        .world_surface_scope_fingerprint = Target.WorldSurface.replayScopeRef().fingerprint,
        .world_port_id = world_port_id,
        .request_fingerprint = trace.fingerprint,
        .response_fingerprint = fingerprint,
    } else null;
    var event = Transcript.Event{
        .kind = kind,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
        .world_port_id = world_port_id,
        .request_fingerprint = trace.fingerprint,
        .response_fingerprint = response_fingerprint,
        .response_kind = response_kind,
        .replay_key = if (replay_key) |key| key.fingerprint() else null,
        .turn_index = trace.turn_index,
        .residual_site_index = trace.operation_site_index,
        .residual_site_fingerprint = trace.operation_site_fingerprint,
        .status = if (kind == .port_responded) .responded else null,
        .value = value,
    };
    try transcript.appendOwned(&event);
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
