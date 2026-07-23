const std = @import("std");

/// World application protocol v1.
pub const format_version: u32 = 1;
/// World application WASM ABI v1.
pub const abi_version: u32 = 1;
/// SHA-256 content identity used by v1 semantic records.
pub const Digest = [std.crypto.hash.sha2.Sha256.digest_length]u8;
/// All-zero digest used only while computing a self-identifying record.
pub const zero_digest: Digest = [_]u8{0} ** std.crypto.hash.sha2.Sha256.digest_length;

fn isZeroDigest(value: Digest) bool {
    return std.mem.eql(u8, &value, &zero_digest);
}

pub const Error = error{
    ApplicationMismatch,
    DuplicateResultTarget,
    EffectResultMismatch,
    InvalidEncoding,
    InvalidFrame,
    InvalidIdentity,
    InvalidManifest,
    InvalidRequest,
    InvalidResult,
    LimitExceeded,
    OutOfMemory,
    StaleResultTarget,
    TrailingBytes,
    UnexpectedResultTarget,
    UnsupportedVersion,
};

/// Hard decode and application limits. Hosts may impose stricter limits.
pub const Limits = struct {
    maximum_manifest_bytes: u32 = 1 << 20,
    maximum_initial_args_bytes: u32 = 1 << 20,
    maximum_state_bytes: u32 = 1 << 20,
    maximum_payload_bytes: u32 = 1 << 20,
    maximum_result_bytes: u32 = 1 << 20,
    maximum_host_claim_bytes: u32 = 64 << 10,
    maximum_host_metadata_bytes: u32 = 64 << 10,
    maximum_failure_bytes: u32 = 64 << 10,
    maximum_name_bytes: u32 = 4 << 10,
    maximum_internal_handlers: u32 = 256,
    maximum_residual_effects: u32 = 256,
    maximum_fuel_per_step: u64 = 100_000,
    maximum_frame_depth: u32 = 64,
    maximum_provider_depth: u32 = 8,

    pub fn validate(self: @This()) Error!void {
        if (self.maximum_manifest_bytes == 0 or
            self.maximum_initial_args_bytes == 0 or
            self.maximum_state_bytes == 0 or
            self.maximum_payload_bytes == 0 or
            self.maximum_result_bytes == 0 or
            self.maximum_name_bytes == 0 or
            self.maximum_fuel_per_step == 0 or
            self.maximum_frame_depth == 0 or
            self.maximum_provider_depth == 0)
        {
            return error.InvalidManifest;
        }
    }

    fn admits(self: @This(), declared: @This()) bool {
        return declared.maximum_manifest_bytes <= self.maximum_manifest_bytes and
            declared.maximum_initial_args_bytes <= self.maximum_initial_args_bytes and
            declared.maximum_state_bytes <= self.maximum_state_bytes and
            declared.maximum_payload_bytes <= self.maximum_payload_bytes and
            declared.maximum_result_bytes <= self.maximum_result_bytes and
            declared.maximum_host_claim_bytes <= self.maximum_host_claim_bytes and
            declared.maximum_host_metadata_bytes <= self.maximum_host_metadata_bytes and
            declared.maximum_failure_bytes <= self.maximum_failure_bytes and
            declared.maximum_name_bytes <= self.maximum_name_bytes and
            declared.maximum_internal_handlers <= self.maximum_internal_handlers and
            declared.maximum_residual_effects <= self.maximum_residual_effects and
            declared.maximum_fuel_per_step <= self.maximum_fuel_per_step and
            declared.maximum_frame_depth <= self.maximum_frame_depth and
            declared.maximum_provider_depth <= self.maximum_provider_depth;
    }
};

pub const EffectStatus = enum(u8) {
    ok = 0,
    rejected = 1,
    failed = 2,
    deferred = 3,
    cancelled = 4,
};

pub const AllowedStatuses = packed struct(u8) {
    ok: bool = true,
    rejected: bool = true,
    failed: bool = true,
    deferred: bool = false,
    cancelled: bool = true,
    _reserved: u3 = 0,

    pub fn contains(self: @This(), status: EffectStatus) bool {
        return switch (status) {
            .ok => self.ok,
            .rejected => self.rejected,
            .failed => self.failed,
            .deferred => self.deferred,
            .cancelled => self.cancelled,
        };
    }

    fn validate(self: @This()) Error!void {
        if (self._reserved != 0) return error.InvalidEncoding;
        if (!self.ok and !self.rejected and !self.failed and !self.deferred and !self.cancelled) {
            return error.InvalidRequest;
        }
    }
};

/// Receiver-independent deterministic limits attached to one effect request.
pub const EffectLimits = struct {
    maximum_result_bytes: u32,
    maximum_attempts: u32,
};

/// One residual effect emitted by an application Frame.
pub const EffectRequest = struct {
    request_id: Digest = zero_digest,
    application_id: Digest,
    parent_frame_id: Digest,
    sequence: u64,
    ordinal: u32 = 0,
    site_id: u64,
    interface_id: Digest,
    payload_schema_id: Digest,
    result_schema_id: Digest,
    allowed_statuses: AllowedStatuses = .{},
    payload_bytes: []const u8,
    idempotency_key: Digest = zero_digest,
    authority_requirements: u64 = 0,
    limits: EffectLimits,

    pub fn seal(self: *@This(), allocator: std.mem.Allocator, limits: Limits) Error!void {
        _ = allocator;
        self.request_id = zero_digest;
        self.idempotency_key = zero_digest;
        try self.validateShape(limits, false);
        self.request_id = try requestSemanticDigest(self.*);
        self.idempotency_key = deriveIdempotencyKey(self.request_id, self.interface_id, self.application_id);
    }

    fn validateShape(self: @This(), limits: Limits, check_identity: bool) Error!void {
        try self.allowed_statuses.validate();
        if (isZeroDigest(self.application_id) or
            isZeroDigest(self.interface_id) or
            isZeroDigest(self.payload_schema_id) or
            isZeroDigest(self.result_schema_id))
        {
            return error.InvalidRequest;
        }
        if ((self.sequence == 0 and !isZeroDigest(self.parent_frame_id)) or
            (self.sequence != 0 and isZeroDigest(self.parent_frame_id)))
        {
            return error.InvalidRequest;
        }
        if (self.ordinal != 0) return error.InvalidRequest;
        if (self.payload_bytes.len > limits.maximum_payload_bytes) return error.LimitExceeded;
        if (self.limits.maximum_result_bytes == 0 or self.limits.maximum_result_bytes > limits.maximum_result_bytes) {
            return error.InvalidRequest;
        }
        if (self.limits.maximum_attempts == 0) return error.InvalidRequest;
        if (!check_identity) return;
        var candidate = self;
        const actual_request_id = candidate.request_id;
        const actual_idempotency_key = candidate.idempotency_key;
        candidate.request_id = zero_digest;
        candidate.idempotency_key = zero_digest;
        if (!std.mem.eql(u8, &actual_request_id, &try requestSemanticDigest(candidate))) return error.InvalidIdentity;
        const expected_key = deriveIdempotencyKey(actual_request_id, self.interface_id, self.application_id);
        if (!std.mem.eql(u8, &actual_idempotency_key, &expected_key)) return error.InvalidIdentity;
    }

    pub fn validate(self: @This(), limits: Limits) Error!void {
        return self.validateShape(limits, true);
    }

    pub fn encode(self: @This(), allocator: std.mem.Allocator, limits: Limits) Error![]u8 {
        try self.validate(limits);
        return encodeRequestSemantic(allocator, self, true);
    }

    /// Decode a borrowed semantic value whose slice storage belongs to `arena`.
    pub fn decode(arena: *std.heap.ArenaAllocator, bytes: []const u8, limits: Limits) Error!@This() {
        const allocator = arena.allocator();
        if (bytes.len > try aggregateLimit(&.{limits.maximum_payload_bytes}, 512)) return error.LimitExceeded;
        var reader = Reader.init(bytes);
        try reader.expectMagic(request_magic);
        if (try reader.readU32() != format_version) return error.UnsupportedVersion;
        var request: EffectRequest = .{
            .request_id = try reader.readDigest(),
            .application_id = try reader.readDigest(),
            .parent_frame_id = try reader.readDigest(),
            .sequence = try reader.readU64(),
            .ordinal = try reader.readU32(),
            .site_id = try reader.readU64(),
            .interface_id = try reader.readDigest(),
            .payload_schema_id = try reader.readDigest(),
            .result_schema_id = try reader.readDigest(),
            .allowed_statuses = @bitCast(try reader.readU8()),
            .payload_bytes = try reader.readOwnedBytes(allocator, limits.maximum_payload_bytes),
            .idempotency_key = try reader.readDigest(),
            .authority_requirements = try reader.readU64(),
            .limits = .{
                .maximum_result_bytes = try reader.readU32(),
                .maximum_attempts = try reader.readU32(),
            },
        };
        errdefer allocator.free(request.payload_bytes);
        try reader.finish();
        try request.validate(limits);
        return request;
    }
};

/// Untrusted outcome for one pending EffectRequest.
pub const EffectResult = struct {
    result_id: Digest = zero_digest,
    request_id: Digest,
    status: EffectStatus,
    result_schema_id: Digest,
    result_bytes: ?[]const u8 = null,
    host_claims: []const u8 = &.{},
    attempt: u32,

    pub fn seal(self: *@This(), allocator: std.mem.Allocator, limits: Limits) Error!void {
        _ = allocator;
        self.result_id = zero_digest;
        try self.validateShape(limits, false);
        self.result_id = try resultSemanticDigest(self.*);
    }

    fn validateShape(self: @This(), limits: Limits, check_identity: bool) Error!void {
        if (isZeroDigest(self.request_id) or isZeroDigest(self.result_schema_id)) {
            return error.InvalidResult;
        }
        if (self.attempt == 0) return error.InvalidResult;
        if (self.result_bytes) |value| {
            if (value.len > limits.maximum_result_bytes) return error.LimitExceeded;
        }
        if (self.host_claims.len > limits.maximum_host_claim_bytes) return error.LimitExceeded;
        if (self.status == .ok and self.result_bytes == null) return error.InvalidResult;
        if (self.status == .deferred and self.result_bytes != null) return error.InvalidResult;
        if (!check_identity) return;
        var candidate = self;
        const actual_id = candidate.result_id;
        candidate.result_id = zero_digest;
        if (!std.mem.eql(u8, &actual_id, &try resultSemanticDigest(candidate))) return error.InvalidIdentity;
    }

    pub fn validate(self: @This(), limits: Limits) Error!void {
        return self.validateShape(limits, true);
    }

    pub fn encode(self: @This(), allocator: std.mem.Allocator, limits: Limits) Error![]u8 {
        try self.validate(limits);
        return encodeResultSemantic(allocator, self, true);
    }

    /// Decode a borrowed semantic value whose slice storage belongs to `arena`.
    pub fn decode(arena: *std.heap.ArenaAllocator, bytes: []const u8, limits: Limits) Error!@This() {
        const allocator = arena.allocator();
        if (bytes.len > try aggregateLimit(&.{ limits.maximum_result_bytes, limits.maximum_host_claim_bytes }, 256)) {
            return error.LimitExceeded;
        }
        var reader = Reader.init(bytes);
        try reader.expectMagic(result_magic);
        if (try reader.readU32() != format_version) return error.UnsupportedVersion;
        const result_id = try reader.readDigest();
        const request_id = try reader.readDigest();
        const status = try readEffectStatus(&reader);
        const result_schema_id = try reader.readDigest();
        const result_bytes = try reader.readOptionalOwnedBytes(allocator, limits.maximum_result_bytes);
        errdefer if (result_bytes) |value| allocator.free(value);
        const host_claims = try reader.readOwnedBytes(allocator, limits.maximum_host_claim_bytes);
        errdefer allocator.free(host_claims);
        const attempt = try reader.readU32();
        try reader.finish();
        const result: EffectResult = .{
            .result_id = result_id,
            .request_id = request_id,
            .status = status,
            .result_schema_id = result_schema_id,
            .result_bytes = result_bytes,
            .host_claims = host_claims,
            .attempt = attempt,
        };
        try result.validate(limits);
        return result;
    }
};

pub const FrameStatus = enum(u8) {
    needs_effect = 0,
    completed = 1,
    failed = 2,
    yielded_fuel = 3,
    cancelled = 4,
};

pub const ResourceCounters = struct {
    instructions: u64 = 0,
    continuation_operations: u64 = 0,
    internal_handler_calls: u64 = 0,
    external_effects: u64 = 0,
    value_bytes: u64 = 0,
};

/// Sole authoritative portable process and causal transition record.
pub const Frame = struct {
    frame_id: Digest = zero_digest,
    application_id: Digest,
    parent_frame_id: ?Digest = null,
    sequence: u64,
    state_bytes: []const u8,
    pending_effect: ?EffectRequest = null,
    accepted_effect_result_id: ?Digest = null,
    status: FrameStatus,
    final_result_schema_id: ?Digest = null,
    final_result_bytes: ?[]const u8 = null,
    failure: ?[]const u8 = null,
    resource_counters: ResourceCounters = .{},
    semantic_warnings: u64 = 0,

    pub fn seal(self: *@This(), allocator: std.mem.Allocator, limits: Limits) Error!void {
        _ = allocator;
        self.frame_id = zero_digest;
        try self.validateShape(limits, false);
        self.frame_id = try frameSemanticDigest(self.*);
    }

    fn validateShape(self: @This(), limits: Limits, check_identity: bool) Error!void {
        if (isZeroDigest(self.application_id)) return error.InvalidFrame;
        if (self.state_bytes.len > limits.maximum_state_bytes) return error.LimitExceeded;
        if (self.final_result_bytes) |value| {
            if (value.len > limits.maximum_result_bytes) return error.LimitExceeded;
        }
        if (self.failure) |value| {
            if (value.len > limits.maximum_failure_bytes) return error.LimitExceeded;
        }
        if (self.sequence == 0) {
            if (self.parent_frame_id != null or self.accepted_effect_result_id != null) return error.InvalidFrame;
        } else {
            const parent_id = self.parent_frame_id orelse return error.InvalidFrame;
            if (isZeroDigest(parent_id)) return error.InvalidFrame;
        }
        if (self.accepted_effect_result_id) |result_id| {
            if (isZeroDigest(result_id)) return error.InvalidFrame;
        }
        if (self.final_result_schema_id) |schema_id| {
            if (isZeroDigest(schema_id)) return error.InvalidFrame;
        }
        switch (self.status) {
            .needs_effect => {
                const request = self.pending_effect orelse return error.InvalidFrame;
                if (self.final_result_schema_id != null or self.final_result_bytes != null or self.failure != null) return error.InvalidFrame;
                if (self.state_bytes.len == 0) return error.InvalidFrame;
                if (request.ordinal != 0 or request.sequence != self.sequence) return error.InvalidFrame;
                if (!std.mem.eql(u8, &request.application_id, &self.application_id)) return error.ApplicationMismatch;
                const expected_parent = self.parent_frame_id orelse zero_digest;
                if (!std.mem.eql(u8, &request.parent_frame_id, &expected_parent)) return error.InvalidFrame;
                try request.validate(limits);
            },
            .completed => {
                if (self.pending_effect != null or self.failure != null) return error.InvalidFrame;
                if (self.final_result_schema_id == null or self.final_result_bytes == null) return error.InvalidFrame;
            },
            .failed => {
                if (self.pending_effect != null or self.final_result_schema_id != null or self.final_result_bytes != null or self.failure == null) {
                    return error.InvalidFrame;
                }
            },
            .yielded_fuel => {
                if (self.pending_effect != null or self.final_result_schema_id != null or self.final_result_bytes != null or self.failure != null) {
                    return error.InvalidFrame;
                }
                if (self.state_bytes.len == 0) return error.InvalidFrame;
            },
            .cancelled => {
                if (self.pending_effect != null or self.final_result_schema_id != null or self.final_result_bytes != null) return error.InvalidFrame;
            },
        }
        if (!check_identity) return;
        var candidate = self;
        const actual_id = candidate.frame_id;
        candidate.frame_id = zero_digest;
        if (!std.mem.eql(u8, &actual_id, &try frameSemanticDigest(candidate))) return error.InvalidIdentity;
    }

    pub fn validate(self: @This(), limits: Limits) Error!void {
        return self.validateShape(limits, true);
    }

    pub fn encode(self: @This(), allocator: std.mem.Allocator, limits: Limits) Error![]u8 {
        try self.validate(limits);
        return encodeFrameSemantic(allocator, self, true);
    }

    /// Decode a borrowed semantic value whose slice storage belongs to `arena`.
    pub fn decode(arena: *std.heap.ArenaAllocator, bytes: []const u8, limits: Limits) Error!@This() {
        const allocator = arena.allocator();
        if (bytes.len > try aggregateLimit(&.{ limits.maximum_state_bytes, limits.maximum_payload_bytes, limits.maximum_result_bytes, limits.maximum_failure_bytes }, 1024)) {
            return error.LimitExceeded;
        }
        var reader = Reader.init(bytes);
        try reader.expectMagic(frame_magic);
        if (try reader.readU32() != format_version) return error.UnsupportedVersion;
        const frame_id = try reader.readDigest();
        const application_id = try reader.readDigest();
        const parent_frame_id = try reader.readOptionalDigest();
        const sequence = try reader.readU64();
        const state_bytes = try reader.readOwnedBytes(allocator, limits.maximum_state_bytes);
        errdefer allocator.free(state_bytes);
        const pending_effect = if (try reader.readBool()) blk: {
            const request_bytes = try reader.readBytes(try aggregateLimitU32(&.{limits.maximum_payload_bytes}, 512));
            break :blk try EffectRequest.decode(arena, request_bytes, limits);
        } else null;
        const accepted_effect_result_id = try reader.readOptionalDigest();
        const status = try readFrameStatus(&reader);
        const final_result_schema_id = try reader.readOptionalDigest();
        const final_result_bytes = try reader.readOptionalOwnedBytes(allocator, limits.maximum_result_bytes);
        errdefer if (final_result_bytes) |value| allocator.free(value);
        const failure = try reader.readOptionalOwnedBytes(allocator, limits.maximum_failure_bytes);
        errdefer if (failure) |value| allocator.free(value);
        const resource_counters: ResourceCounters = .{
            .instructions = try reader.readU64(),
            .continuation_operations = try reader.readU64(),
            .internal_handler_calls = try reader.readU64(),
            .external_effects = try reader.readU64(),
            .value_bytes = try reader.readU64(),
        };
        const semantic_warnings = try reader.readU64();
        try reader.finish();
        const frame: Frame = .{
            .frame_id = frame_id,
            .application_id = application_id,
            .parent_frame_id = parent_frame_id,
            .sequence = sequence,
            .state_bytes = state_bytes,
            .pending_effect = pending_effect,
            .accepted_effect_result_id = accepted_effect_result_id,
            .status = status,
            .final_result_schema_id = final_result_schema_id,
            .final_result_bytes = final_result_bytes,
            .failure = failure,
            .resource_counters = resource_counters,
            .semantic_warnings = semantic_warnings,
        };
        try frame.validate(limits);
        return frame;
    }
};

/// Transient input to one application step. Host metadata is deliberately non-semantic.
pub const StepInput = struct {
    application_id: Digest,
    expected_parent_frame_id: ?Digest = null,
    prior_frame_bytes: ?[]const u8 = null,
    initial_args_bytes: ?[]const u8 = null,
    effect_result: ?EffectResult = null,
    fuel: u64,
    host_metadata: []const u8 = &.{},

    pub fn validate(self: @This(), limits: Limits) Error!void {
        if (self.fuel == 0 or self.fuel > limits.maximum_fuel_per_step) return error.LimitExceeded;
        if (self.host_metadata.len > limits.maximum_host_metadata_bytes) return error.LimitExceeded;
        const genesis = self.prior_frame_bytes == null;
        if (genesis) {
            if (self.expected_parent_frame_id != null or self.initial_args_bytes == null or self.effect_result != null) return error.InvalidFrame;
        } else {
            if (self.expected_parent_frame_id == null or self.initial_args_bytes != null) return error.InvalidFrame;
        }
        if (self.prior_frame_bytes) |value| {
            if (value.len > try aggregateLimit(&.{ limits.maximum_state_bytes, limits.maximum_payload_bytes, limits.maximum_result_bytes, limits.maximum_failure_bytes }, 1024)) {
                return error.LimitExceeded;
            }
        }
        if (self.initial_args_bytes) |value| {
            if (value.len > limits.maximum_initial_args_bytes) return error.LimitExceeded;
        }
        if (self.effect_result) |value| try value.validate(limits);
    }

    pub fn encode(self: @This(), allocator: std.mem.Allocator, limits: Limits) Error![]u8 {
        try self.validate(limits);
        var writer = Writer.init(allocator);
        errdefer writer.deinit();
        try writer.writeBytes(input_magic);
        try writer.writeU32(format_version);
        try writer.writeDigest(self.application_id);
        try writer.writeOptionalDigest(self.expected_parent_frame_id);
        try writer.writeOptionalBytes(self.prior_frame_bytes);
        try writer.writeOptionalBytes(self.initial_args_bytes);
        try writer.writeBool(self.effect_result != null);
        if (self.effect_result) |result| {
            const result_bytes = try result.encode(allocator, limits);
            defer allocator.free(result_bytes);
            try writer.writeLenBytes(result_bytes);
        }
        try writer.writeU64(self.fuel);
        try writer.writeLenBytes(self.host_metadata);
        return writer.toOwnedSlice();
    }

    /// Decode a borrowed semantic value whose slice storage belongs to `arena`.
    pub fn decode(arena: *std.heap.ArenaAllocator, bytes: []const u8, limits: Limits) Error!@This() {
        const allocator = arena.allocator();
        if (bytes.len > try aggregateLimit(&.{
            limits.maximum_state_bytes,
            limits.maximum_payload_bytes,
            limits.maximum_result_bytes,
            limits.maximum_failure_bytes,
            limits.maximum_initial_args_bytes,
            limits.maximum_result_bytes,
            limits.maximum_host_claim_bytes,
            limits.maximum_host_metadata_bytes,
        }, 4096)) return error.LimitExceeded;
        var reader = Reader.init(bytes);
        try reader.expectMagic(input_magic);
        if (try reader.readU32() != format_version) return error.UnsupportedVersion;
        const application_id = try reader.readDigest();
        const expected_parent_frame_id = try reader.readOptionalDigest();
        const prior_limit = try aggregateLimitU32(&.{ limits.maximum_state_bytes, limits.maximum_payload_bytes, limits.maximum_result_bytes, limits.maximum_failure_bytes }, 1024);
        const prior_frame_bytes = try reader.readOptionalOwnedBytes(allocator, prior_limit);
        errdefer if (prior_frame_bytes) |value| allocator.free(value);
        const initial_args_bytes = try reader.readOptionalOwnedBytes(allocator, limits.maximum_initial_args_bytes);
        errdefer if (initial_args_bytes) |value| allocator.free(value);
        const effect_result = if (try reader.readBool()) blk: {
            const result_limit = try aggregateLimitU32(&.{ limits.maximum_result_bytes, limits.maximum_host_claim_bytes }, 256);
            break :blk try EffectResult.decode(arena, try reader.readBytes(result_limit), limits);
        } else null;
        const fuel = try reader.readU64();
        const host_metadata = try reader.readOwnedBytes(allocator, limits.maximum_host_metadata_bytes);
        errdefer allocator.free(host_metadata);
        try reader.finish();
        const input: StepInput = .{
            .application_id = application_id,
            .expected_parent_frame_id = expected_parent_frame_id,
            .prior_frame_bytes = prior_frame_bytes,
            .initial_args_bytes = initial_args_bytes,
            .effect_result = effect_result,
            .fuel = fuel,
            .host_metadata = host_metadata,
        };
        try input.validate(limits);
        return input;
    }
};

pub const ResidualEffect = struct {
    interface_id: Digest,
    site_id: u64,
    payload_schema_id: Digest,
    result_schema_id: Digest,
    allowed_statuses: AllowedStatuses,
    authority_requirements: u64,
};

/// Immutable application preflight contract exported by each application WASM.
pub const ApplicationManifest = struct {
    application_id: Digest = zero_digest,
    application_name: []const u8,
    application_version: []const u8,
    boundary_package_version: []const u8,
    boundary_static_machine_abi_version: u32,
    world_package_version: []const u8,
    world_application_abi_version: u32 = abi_version,
    root_program_id: Digest,
    internal_handler_ids: []const Digest = &.{},
    residual_effects: []const ResidualEffect = &.{},
    limits: Limits = .{},
    required_host_capabilities: u64 = 0,

    pub fn seal(self: *@This(), allocator: std.mem.Allocator) Error!void {
        _ = allocator;
        self.application_id = zero_digest;
        try self.validateShape(false);
        if (try manifestEncodedLength(self.*) > self.limits.maximum_manifest_bytes) return error.LimitExceeded;
        self.application_id = try manifestSemanticDigest(self.*);
    }

    fn validateShape(self: @This(), check_identity: bool) Error!void {
        try self.limits.validate();
        if (self.world_application_abi_version != abi_version or self.boundary_static_machine_abi_version == 0) return error.InvalidManifest;
        if (isZeroDigest(self.root_program_id)) return error.InvalidManifest;
        if (self.application_name.len == 0 or self.application_name.len > self.limits.maximum_name_bytes or
            self.application_version.len == 0 or self.application_version.len > self.limits.maximum_name_bytes or
            self.boundary_package_version.len == 0 or self.boundary_package_version.len > self.limits.maximum_name_bytes or
            self.world_package_version.len == 0 or self.world_package_version.len > self.limits.maximum_name_bytes)
        {
            return error.InvalidManifest;
        }
        if (self.internal_handler_ids.len > self.limits.maximum_internal_handlers or self.residual_effects.len > self.limits.maximum_residual_effects) {
            return error.LimitExceeded;
        }
        for (self.internal_handler_ids, 0..) |handler_id, index| {
            if (isZeroDigest(handler_id)) return error.InvalidManifest;
            if (index != 0 and std.mem.order(u8, &self.internal_handler_ids[index - 1], &handler_id) != .lt) {
                return error.InvalidManifest;
            }
        }
        var derived_host_capabilities: u64 = 0;
        for (self.residual_effects, 0..) |effect, index| {
            if (isZeroDigest(effect.interface_id) or
                isZeroDigest(effect.payload_schema_id) or
                isZeroDigest(effect.result_schema_id))
            {
                return error.InvalidManifest;
            }
            try effect.allowed_statuses.validate();
            derived_host_capabilities |= effect.authority_requirements;
            if (index != 0) {
                const previous = self.residual_effects[index - 1];
                if (compareResidualEffect(previous, effect) != .lt) return error.InvalidManifest;
            }
        }
        if (self.required_host_capabilities != derived_host_capabilities) return error.InvalidManifest;
        if (!check_identity) return;
        var candidate = self;
        const actual_id = candidate.application_id;
        candidate.application_id = zero_digest;
        if (!std.mem.eql(u8, &actual_id, &try manifestSemanticDigest(candidate))) return error.InvalidIdentity;
    }

    pub fn validate(self: @This()) Error!void {
        try self.validateShape(true);
        if (try manifestEncodedLength(self) > self.limits.maximum_manifest_bytes) return error.LimitExceeded;
    }

    pub fn encode(self: @This(), allocator: std.mem.Allocator) Error![]u8 {
        try self.validate();
        const bytes = try encodeManifestSemantic(allocator, self, true);
        if (bytes.len > self.limits.maximum_manifest_bytes) {
            allocator.free(bytes);
            return error.LimitExceeded;
        }
        return bytes;
    }

    /// Decode a borrowed semantic value whose slice storage belongs to `arena`.
    pub fn decode(arena: *std.heap.ArenaAllocator, bytes: []const u8, admission_limits: Limits) Error!@This() {
        const allocator = arena.allocator();
        try admission_limits.validate();
        if (bytes.len > admission_limits.maximum_manifest_bytes) return error.LimitExceeded;
        var reader = Reader.init(bytes);
        try reader.expectMagic(manifest_magic);
        if (try reader.readU32() != format_version) return error.UnsupportedVersion;
        const application_id = try reader.readDigest();
        const application_name = try reader.readOwnedBytes(allocator, admission_limits.maximum_name_bytes);
        errdefer allocator.free(application_name);
        const application_version = try reader.readOwnedBytes(allocator, admission_limits.maximum_name_bytes);
        errdefer allocator.free(application_version);
        const boundary_package_version = try reader.readOwnedBytes(allocator, admission_limits.maximum_name_bytes);
        errdefer allocator.free(boundary_package_version);
        const boundary_static_machine_abi_version = try reader.readU32();
        const world_package_version = try reader.readOwnedBytes(allocator, admission_limits.maximum_name_bytes);
        errdefer allocator.free(world_package_version);
        const world_application_abi_version = try reader.readU32();
        const root_program_id = try reader.readDigest();
        const handler_count = try reader.readCount(admission_limits.maximum_internal_handlers);
        try reader.requireItems(handler_count, zero_digest.len, manifest_tail_after_handlers);
        const internal_handler_ids = try allocator.alloc(Digest, handler_count);
        errdefer allocator.free(internal_handler_ids);
        for (internal_handler_ids) |*value| value.* = try reader.readDigest();
        const residual_count = try reader.readCount(admission_limits.maximum_residual_effects);
        try reader.requireItems(residual_count, residual_effect_encoded_length, manifest_tail_after_residuals);
        const residual_effects = try allocator.alloc(ResidualEffect, residual_count);
        errdefer allocator.free(residual_effects);
        for (residual_effects) |*effect| {
            effect.* = .{
                .interface_id = try reader.readDigest(),
                .site_id = try reader.readU64(),
                .payload_schema_id = try reader.readDigest(),
                .result_schema_id = try reader.readDigest(),
                .allowed_statuses = @bitCast(try reader.readU8()),
                .authority_requirements = try reader.readU64(),
            };
        }
        const declared_limits = try readLimits(&reader);
        try declared_limits.validate();
        if (bytes.len > declared_limits.maximum_manifest_bytes) return error.LimitExceeded;
        if (!admission_limits.admits(declared_limits)) return error.LimitExceeded;
        const required_host_capabilities = try reader.readU64();
        try reader.finish();
        const manifest: ApplicationManifest = .{
            .application_id = application_id,
            .application_name = application_name,
            .application_version = application_version,
            .boundary_package_version = boundary_package_version,
            .boundary_static_machine_abi_version = boundary_static_machine_abi_version,
            .world_package_version = world_package_version,
            .world_application_abi_version = world_application_abi_version,
            .root_program_id = root_program_id,
            .internal_handler_ids = internal_handler_ids,
            .residual_effects = residual_effects,
            .limits = declared_limits,
            .required_host_capabilities = required_host_capabilities,
        };
        try manifest.validate();
        return manifest;
    }
};

pub fn digestLabel(domain: []const u8, label: []const u8) Digest {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(domain);
    hasher.update(&.{0});
    hasher.update(label);
    var digest: Digest = undefined;
    hasher.final(&digest);
    return digest;
}

/// Validate one untrusted result against the sole pending request before reduction.
pub fn validateResultForRequest(request: EffectRequest, result: EffectResult, limits: Limits) Error!void {
    try request.validate(limits);
    try result.validate(limits);
    if (!std.mem.eql(u8, &request.request_id, &result.request_id)) return error.UnexpectedResultTarget;
    if (!request.allowed_statuses.contains(result.status)) return error.EffectResultMismatch;
    if (!std.mem.eql(u8, &request.result_schema_id, &result.result_schema_id)) return error.EffectResultMismatch;
    if (result.attempt > request.limits.maximum_attempts) return error.EffectResultMismatch;
    if (result.result_bytes) |value| {
        if (value.len > request.limits.maximum_result_bytes) return error.LimitExceeded;
    }
}

fn aggregateLimit(values: []const u32, extra: usize) Error!usize {
    var total = extra;
    for (values) |value| {
        total = std.math.add(usize, total, value) catch return error.LimitExceeded;
    }
    return total;
}

fn aggregateLimitU32(values: []const u32, extra: usize) Error!u32 {
    const total = try aggregateLimit(values, extra);
    if (total > std.math.maxInt(u32)) return error.LimitExceeded;
    return @intCast(total);
}

fn deriveIdempotencyKey(request_id: Digest, interface_id: Digest, application_id: Digest) Digest {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("world.idempotency-key.v1");
    hasher.update(&.{0});
    hasher.update(&request_id);
    hasher.update(&interface_id);
    hasher.update(&application_id);
    var digest: Digest = undefined;
    hasher.final(&digest);
    return digest;
}

const request_magic = "WRLDERQ1";
const result_magic = "WRLDERS1";
const frame_magic = "WRLDFRM1";
const input_magic = "WRLDSTP1";
const manifest_magic = "WRLDMNF1";
const residual_effect_encoded_length = zero_digest.len * 3 + 8 + 1 + 8;
const limits_encoded_length = 13 * @sizeOf(u32) + @sizeOf(u64);
const manifest_tail_after_residuals = limits_encoded_length + @sizeOf(u64);
const manifest_tail_after_handlers = @sizeOf(u32) + manifest_tail_after_residuals;

fn encodeRequestSemantic(allocator: std.mem.Allocator, request: EffectRequest, include_id: bool) Error![]u8 {
    var writer = Writer.init(allocator);
    errdefer writer.deinit();
    try writeRequestCanonical(&writer, request, include_id);
    return writer.toOwnedSlice();
}

fn writeRequestCanonical(writer: anytype, request: EffectRequest, include_id: bool) Error!void {
    try writer.writeBytes(request_magic);
    try writer.writeU32(format_version);
    try writer.writeDigest(if (include_id) request.request_id else zero_digest);
    try writer.writeDigest(request.application_id);
    try writer.writeDigest(request.parent_frame_id);
    try writer.writeU64(request.sequence);
    try writer.writeU32(request.ordinal);
    try writer.writeU64(request.site_id);
    try writer.writeDigest(request.interface_id);
    try writer.writeDigest(request.payload_schema_id);
    try writer.writeDigest(request.result_schema_id);
    try writer.writeU8(@bitCast(request.allowed_statuses));
    try writer.writeLenBytes(request.payload_bytes);
    try writer.writeDigest(if (include_id) request.idempotency_key else zero_digest);
    try writer.writeU64(request.authority_requirements);
    try writer.writeU32(request.limits.maximum_result_bytes);
    try writer.writeU32(request.limits.maximum_attempts);
}

fn encodeResultSemantic(allocator: std.mem.Allocator, result: EffectResult, include_id: bool) Error![]u8 {
    var writer = Writer.init(allocator);
    errdefer writer.deinit();
    try writeResultCanonical(&writer, result, include_id);
    return writer.toOwnedSlice();
}

fn writeResultCanonical(writer: anytype, result: EffectResult, include_id: bool) Error!void {
    try writer.writeBytes(result_magic);
    try writer.writeU32(format_version);
    try writer.writeDigest(if (include_id) result.result_id else zero_digest);
    try writer.writeDigest(result.request_id);
    try writer.writeU8(@intFromEnum(result.status));
    try writer.writeDigest(result.result_schema_id);
    try writer.writeOptionalBytes(result.result_bytes);
    try writer.writeLenBytes(result.host_claims);
    try writer.writeU32(result.attempt);
}

fn encodeFrameSemantic(allocator: std.mem.Allocator, frame: Frame, include_id: bool) Error![]u8 {
    var writer = Writer.init(allocator);
    errdefer writer.deinit();
    try writeFrameCanonical(&writer, frame, include_id);
    return writer.toOwnedSlice();
}

fn writeFrameCanonical(writer: anytype, frame: Frame, include_id: bool) Error!void {
    try writer.writeBytes(frame_magic);
    try writer.writeU32(format_version);
    try writer.writeDigest(if (include_id) frame.frame_id else zero_digest);
    try writer.writeDigest(frame.application_id);
    try writer.writeOptionalDigest(frame.parent_frame_id);
    try writer.writeU64(frame.sequence);
    try writer.writeLenBytes(frame.state_bytes);
    try writer.writeBool(frame.pending_effect != null);
    if (frame.pending_effect) |request| {
        try writer.writeU32(try requestEncodedLength(request));
        try writeRequestCanonical(writer, request, true);
    }
    try writer.writeOptionalDigest(frame.accepted_effect_result_id);
    try writer.writeU8(@intFromEnum(frame.status));
    try writer.writeOptionalDigest(frame.final_result_schema_id);
    try writer.writeOptionalBytes(frame.final_result_bytes);
    try writer.writeOptionalBytes(frame.failure);
    try writer.writeU64(frame.resource_counters.instructions);
    try writer.writeU64(frame.resource_counters.continuation_operations);
    try writer.writeU64(frame.resource_counters.internal_handler_calls);
    try writer.writeU64(frame.resource_counters.external_effects);
    try writer.writeU64(frame.resource_counters.value_bytes);
    try writer.writeU64(frame.semantic_warnings);
}

fn encodeManifestSemantic(allocator: std.mem.Allocator, manifest: ApplicationManifest, include_id: bool) Error![]u8 {
    var writer = Writer.init(allocator);
    errdefer writer.deinit();
    try writeManifestCanonical(&writer, manifest, include_id);
    return writer.toOwnedSlice();
}

fn writeManifestCanonical(writer: anytype, manifest: ApplicationManifest, include_id: bool) Error!void {
    try writer.writeBytes(manifest_magic);
    try writer.writeU32(format_version);
    try writer.writeDigest(if (include_id) manifest.application_id else zero_digest);
    try writer.writeLenBytes(manifest.application_name);
    try writer.writeLenBytes(manifest.application_version);
    try writer.writeLenBytes(manifest.boundary_package_version);
    try writer.writeU32(manifest.boundary_static_machine_abi_version);
    try writer.writeLenBytes(manifest.world_package_version);
    try writer.writeU32(manifest.world_application_abi_version);
    try writer.writeDigest(manifest.root_program_id);
    try writer.writeU32(@intCast(manifest.internal_handler_ids.len));
    for (manifest.internal_handler_ids) |value| try writer.writeDigest(value);
    try writer.writeU32(@intCast(manifest.residual_effects.len));
    for (manifest.residual_effects) |effect| {
        try writer.writeDigest(effect.interface_id);
        try writer.writeU64(effect.site_id);
        try writer.writeDigest(effect.payload_schema_id);
        try writer.writeDigest(effect.result_schema_id);
        try writer.writeU8(@bitCast(effect.allowed_statuses));
        try writer.writeU64(effect.authority_requirements);
    }
    try writeLimits(writer, manifest.limits);
    try writer.writeU64(manifest.required_host_capabilities);
}

fn requestSemanticDigest(request: EffectRequest) Error!Digest {
    var writer = HashWriter.init("world.effect-request.v1");
    try writeRequestCanonical(&writer, request, false);
    return writer.final();
}

fn resultSemanticDigest(result: EffectResult) Error!Digest {
    var writer = HashWriter.init("world.effect-result.v1");
    try writeResultCanonical(&writer, result, false);
    return writer.final();
}

fn frameSemanticDigest(frame: Frame) Error!Digest {
    var writer = HashWriter.init("world.frame.v1");
    try writeFrameCanonical(&writer, frame, false);
    return writer.final();
}

fn manifestSemanticDigest(manifest: ApplicationManifest) Error!Digest {
    var writer = HashWriter.init("world.application-manifest.v1");
    try writeManifestCanonical(&writer, manifest, false);
    return writer.final();
}

fn requestEncodedLength(request: EffectRequest) Error!u32 {
    const fixed = request_magic.len + 4 + zero_digest.len * 7 + 8 + 4 + 8 + 1 + 4 + 8 + 4 + 4;
    const total = std.math.add(usize, fixed, request.payload_bytes.len) catch return error.LimitExceeded;
    if (total > std.math.maxInt(u32)) return error.LimitExceeded;
    return @intCast(total);
}

fn manifestEncodedLength(manifest: ApplicationManifest) Error!u32 {
    const fixed = manifest_magic.len +
        @sizeOf(u32) +
        zero_digest.len +
        4 * @sizeOf(u32) +
        2 * @sizeOf(u32) +
        zero_digest.len +
        2 * @sizeOf(u32) +
        limits_encoded_length +
        @sizeOf(u64);
    var total: usize = fixed;
    for ([_][]const u8{
        manifest.application_name,
        manifest.application_version,
        manifest.boundary_package_version,
        manifest.world_package_version,
    }) |value| {
        total = std.math.add(usize, total, value.len) catch return error.LimitExceeded;
    }
    const handler_bytes = std.math.mul(usize, manifest.internal_handler_ids.len, zero_digest.len) catch
        return error.LimitExceeded;
    total = std.math.add(usize, total, handler_bytes) catch return error.LimitExceeded;
    const residual_bytes = std.math.mul(usize, manifest.residual_effects.len, residual_effect_encoded_length) catch
        return error.LimitExceeded;
    total = std.math.add(usize, total, residual_bytes) catch return error.LimitExceeded;
    if (total > std.math.maxInt(u32)) return error.LimitExceeded;
    return @intCast(total);
}

fn compareResidualEffect(lhs: ResidualEffect, rhs: ResidualEffect) std.math.Order {
    const interface_order = std.mem.order(u8, &lhs.interface_id, &rhs.interface_id);
    if (interface_order != .eq) return interface_order;
    return std.math.order(lhs.site_id, rhs.site_id);
}

fn readEffectStatus(reader: *Reader) Error!EffectStatus {
    return switch (try reader.readU8()) {
        0 => .ok,
        1 => .rejected,
        2 => .failed,
        3 => .deferred,
        4 => .cancelled,
        else => error.InvalidEncoding,
    };
}

fn readFrameStatus(reader: *Reader) Error!FrameStatus {
    return switch (try reader.readU8()) {
        0 => .needs_effect,
        1 => .completed,
        2 => .failed,
        3 => .yielded_fuel,
        4 => .cancelled,
        else => error.InvalidEncoding,
    };
}

fn writeLimits(writer: anytype, limits: Limits) Error!void {
    try writer.writeU32(limits.maximum_manifest_bytes);
    try writer.writeU32(limits.maximum_initial_args_bytes);
    try writer.writeU32(limits.maximum_state_bytes);
    try writer.writeU32(limits.maximum_payload_bytes);
    try writer.writeU32(limits.maximum_result_bytes);
    try writer.writeU32(limits.maximum_host_claim_bytes);
    try writer.writeU32(limits.maximum_host_metadata_bytes);
    try writer.writeU32(limits.maximum_failure_bytes);
    try writer.writeU32(limits.maximum_name_bytes);
    try writer.writeU32(limits.maximum_internal_handlers);
    try writer.writeU32(limits.maximum_residual_effects);
    try writer.writeU64(limits.maximum_fuel_per_step);
    try writer.writeU32(limits.maximum_frame_depth);
    try writer.writeU32(limits.maximum_provider_depth);
}

fn readLimits(reader: *Reader) Error!Limits {
    return .{
        .maximum_manifest_bytes = try reader.readU32(),
        .maximum_initial_args_bytes = try reader.readU32(),
        .maximum_state_bytes = try reader.readU32(),
        .maximum_payload_bytes = try reader.readU32(),
        .maximum_result_bytes = try reader.readU32(),
        .maximum_host_claim_bytes = try reader.readU32(),
        .maximum_host_metadata_bytes = try reader.readU32(),
        .maximum_failure_bytes = try reader.readU32(),
        .maximum_name_bytes = try reader.readU32(),
        .maximum_internal_handlers = try reader.readU32(),
        .maximum_residual_effects = try reader.readU32(),
        .maximum_fuel_per_step = try reader.readU64(),
        .maximum_frame_depth = try reader.readU32(),
        .maximum_provider_depth = try reader.readU32(),
    };
}

const Writer = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,

    fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *@This()) void {
        self.bytes.deinit(self.allocator);
    }

    fn toOwnedSlice(self: *@This()) Error![]u8 {
        return self.bytes.toOwnedSlice(self.allocator) catch return error.OutOfMemory;
    }

    fn writeBytes(self: *@This(), value: []const u8) Error!void {
        self.bytes.appendSlice(self.allocator, value) catch return error.OutOfMemory;
    }

    fn writeLenBytes(self: *@This(), value: []const u8) Error!void {
        if (value.len > std.math.maxInt(u32)) return error.LimitExceeded;
        try self.writeU32(@intCast(value.len));
        try self.writeBytes(value);
    }

    fn writeOptionalBytes(self: *@This(), value: ?[]const u8) Error!void {
        try self.writeBool(value != null);
        if (value) |actual| try self.writeLenBytes(actual);
    }

    fn writeBool(self: *@This(), value: bool) Error!void {
        try self.writeU8(@intFromBool(value));
    }

    fn writeU8(self: *@This(), value: u8) Error!void {
        self.bytes.append(self.allocator, value) catch return error.OutOfMemory;
    }

    fn writeU32(self: *@This(), value: u32) Error!void {
        var buffer: [4]u8 = undefined;
        std.mem.writeInt(u32, &buffer, value, .little);
        try self.writeBytes(&buffer);
    }

    fn writeU64(self: *@This(), value: u64) Error!void {
        var buffer: [8]u8 = undefined;
        std.mem.writeInt(u64, &buffer, value, .little);
        try self.writeBytes(&buffer);
    }

    fn writeDigest(self: *@This(), value: Digest) Error!void {
        try self.writeBytes(&value);
    }

    fn writeOptionalDigest(self: *@This(), value: ?Digest) Error!void {
        try self.writeBool(value != null);
        if (value) |actual| try self.writeDigest(actual);
    }
};

const HashWriter = struct {
    hasher: std.crypto.hash.sha2.Sha256,

    fn init(domain: []const u8) @This() {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(domain);
        hasher.update(&.{0});
        return .{ .hasher = hasher };
    }

    fn final(self: *@This()) Digest {
        var digest: Digest = undefined;
        self.hasher.final(&digest);
        return digest;
    }

    fn writeBytes(self: *@This(), value: []const u8) Error!void {
        self.hasher.update(value);
    }

    fn writeLenBytes(self: *@This(), value: []const u8) Error!void {
        if (value.len > std.math.maxInt(u32)) return error.LimitExceeded;
        try self.writeU32(@intCast(value.len));
        try self.writeBytes(value);
    }

    fn writeOptionalBytes(self: *@This(), value: ?[]const u8) Error!void {
        try self.writeBool(value != null);
        if (value) |actual| try self.writeLenBytes(actual);
    }

    fn writeBool(self: *@This(), value: bool) Error!void {
        try self.writeU8(@intFromBool(value));
    }

    fn writeU8(self: *@This(), value: u8) Error!void {
        self.hasher.update(&.{value});
    }

    fn writeU32(self: *@This(), value: u32) Error!void {
        var buffer: [4]u8 = undefined;
        std.mem.writeInt(u32, &buffer, value, .little);
        self.hasher.update(&buffer);
    }

    fn writeU64(self: *@This(), value: u64) Error!void {
        var buffer: [8]u8 = undefined;
        std.mem.writeInt(u64, &buffer, value, .little);
        self.hasher.update(&buffer);
    }

    fn writeDigest(self: *@This(), value: Digest) Error!void {
        self.hasher.update(&value);
    }

    fn writeOptionalDigest(self: *@This(), value: ?Digest) Error!void {
        try self.writeBool(value != null);
        if (value) |actual| try self.writeDigest(actual);
    }
};

const Reader = struct {
    bytes: []const u8,
    cursor: usize = 0,

    fn init(bytes: []const u8) @This() {
        return .{ .bytes = bytes };
    }

    fn finish(self: @This()) Error!void {
        if (self.cursor != self.bytes.len) return error.TrailingBytes;
    }

    fn expectMagic(self: *@This(), magic: []const u8) Error!void {
        if (!std.mem.eql(u8, try self.readExact(magic.len), magic)) return error.InvalidEncoding;
    }

    fn readExact(self: *@This(), length: usize) Error![]const u8 {
        const end = std.math.add(usize, self.cursor, length) catch return error.InvalidEncoding;
        if (end > self.bytes.len) return error.InvalidEncoding;
        const value = self.bytes[self.cursor..end];
        self.cursor = end;
        return value;
    }

    fn readBytes(self: *@This(), maximum: u32) Error![]const u8 {
        const length = try self.readU32();
        if (length > maximum) return error.LimitExceeded;
        return self.readExact(length);
    }

    fn readOwnedBytes(self: *@This(), allocator: std.mem.Allocator, maximum: u32) Error![]const u8 {
        return allocator.dupe(u8, try self.readBytes(maximum)) catch return error.OutOfMemory;
    }

    fn readOptionalOwnedBytes(self: *@This(), allocator: std.mem.Allocator, maximum: u32) Error!?[]const u8 {
        if (!try self.readBool()) return null;
        return try self.readOwnedBytes(allocator, maximum);
    }

    fn readBool(self: *@This()) Error!bool {
        return switch (try self.readU8()) {
            0 => false,
            1 => true,
            else => error.InvalidEncoding,
        };
    }

    fn readU8(self: *@This()) Error!u8 {
        return (try self.readExact(1))[0];
    }

    fn readU32(self: *@This()) Error!u32 {
        return std.mem.readInt(u32, (try self.readExact(4))[0..4], .little);
    }

    fn readU64(self: *@This()) Error!u64 {
        return std.mem.readInt(u64, (try self.readExact(8))[0..8], .little);
    }

    fn readDigest(self: *@This()) Error!Digest {
        return (try self.readExact(zero_digest.len))[0..zero_digest.len].*;
    }

    fn readOptionalDigest(self: *@This()) Error!?Digest {
        if (!try self.readBool()) return null;
        return try self.readDigest();
    }

    fn readCount(self: *@This(), maximum: u32) Error!usize {
        const count = try self.readU32();
        if (count > maximum) return error.LimitExceeded;
        return count;
    }

    fn requireItems(self: @This(), count: usize, encoded_length: usize, minimum_tail: usize) Error!void {
        const item_bytes = std.math.mul(usize, count, encoded_length) catch return error.InvalidEncoding;
        const required = std.math.add(usize, item_bytes, minimum_tail) catch return error.InvalidEncoding;
        const remaining = self.bytes.len - self.cursor;
        if (required > remaining) return error.InvalidEncoding;
    }
};

test "world application v1 records round trip canonically" {
    const allocator = std.testing.allocator;
    var decode_arena = std.heap.ArenaAllocator.init(allocator);
    defer decode_arena.deinit();
    const limits: Limits = .{};
    const application_id = digestLabel("test", "application");
    const parent_frame_id = digestLabel("test", "parent");
    const result_schema_id = digestLabel("test", "result-schema");

    var request: EffectRequest = .{
        .application_id = application_id,
        .parent_frame_id = parent_frame_id,
        .sequence = 1,
        .site_id = 9,
        .interface_id = digestLabel("test", "interface"),
        .payload_schema_id = digestLabel("test", "payload-schema"),
        .result_schema_id = result_schema_id,
        .payload_bytes = "request",
        .authority_requirements = 4,
        .limits = .{ .maximum_result_bytes = 1024, .maximum_attempts = 3 },
    };
    try request.seal(allocator, limits);
    const request_bytes = try request.encode(allocator, limits);
    defer allocator.free(request_bytes);
    const decoded_request = try EffectRequest.decode(&decode_arena, request_bytes, limits);
    const request_bytes_again = try decoded_request.encode(allocator, limits);
    defer allocator.free(request_bytes_again);
    try std.testing.expectEqualSlices(u8, request_bytes, request_bytes_again);

    var result: EffectResult = .{
        .request_id = request.request_id,
        .status = .ok,
        .result_schema_id = result_schema_id,
        .result_bytes = "response",
        .host_claims = "fixture",
        .attempt = 1,
    };
    try result.seal(allocator, limits);
    const result_bytes = try result.encode(allocator, limits);
    defer allocator.free(result_bytes);
    const decoded_result = try EffectResult.decode(&decode_arena, result_bytes, limits);
    const result_bytes_again = try decoded_result.encode(allocator, limits);
    defer allocator.free(result_bytes_again);
    try std.testing.expectEqualSlices(u8, result_bytes, result_bytes_again);

    var frame: Frame = .{
        .application_id = application_id,
        .parent_frame_id = parent_frame_id,
        .sequence = 1,
        .state_bytes = "state",
        .pending_effect = request,
        .accepted_effect_result_id = result.result_id,
        .status = .needs_effect,
        .resource_counters = .{ .instructions = 3, .external_effects = 1 },
    };
    try frame.seal(allocator, limits);
    const frame_bytes = try frame.encode(allocator, limits);
    defer allocator.free(frame_bytes);
    const decoded_frame = try Frame.decode(&decode_arena, frame_bytes, limits);
    const frame_bytes_again = try decoded_frame.encode(allocator, limits);
    defer allocator.free(frame_bytes_again);
    try std.testing.expectEqualSlices(u8, frame_bytes, frame_bytes_again);
}

test "world application v1 decode lifetime belongs to the caller arena" {
    const allocator = std.testing.allocator;
    try std.testing.expect(!@hasDecl(EffectRequest, "deinit"));
    try std.testing.expect(!@hasDecl(EffectResult, "deinit"));
    try std.testing.expect(!@hasDecl(Frame, "deinit"));
    try std.testing.expect(!@hasDecl(StepInput, "deinit"));
    try std.testing.expect(!@hasDecl(ApplicationManifest, "deinit"));

    var request: EffectRequest = .{
        .application_id = digestLabel("test", "application"),
        .parent_frame_id = digestLabel("test", "parent"),
        .sequence = 1,
        .site_id = 1,
        .interface_id = digestLabel("test", "interface"),
        .payload_schema_id = digestLabel("test", "payload"),
        .result_schema_id = digestLabel("test", "result"),
        .payload_bytes = "decoded allocation",
        .limits = .{ .maximum_result_bytes = 32, .maximum_attempts = 1 },
    };
    try request.seal(allocator, .{});
    const bytes = try request.encode(allocator, .{});
    defer allocator.free(bytes);

    var decode_arena = std.heap.ArenaAllocator.init(allocator);
    defer decode_arena.deinit();
    var decoded = try EffectRequest.decode(&decode_arena, bytes, .{});
    const copied = decoded;
    decoded.payload_bytes = "borrowed replacement";
    try copied.validate(.{});
}

test "world application v1 seal rejects invalid shapes before stamping identity" {
    const allocator = std.testing.allocator;
    var request: EffectRequest = .{
        .application_id = digestLabel("test", "application"),
        .parent_frame_id = digestLabel("test", "parent"),
        .sequence = 1,
        .ordinal = 1,
        .site_id = 1,
        .interface_id = digestLabel("test", "interface"),
        .payload_schema_id = digestLabel("test", "payload"),
        .result_schema_id = digestLabel("test", "result"),
        .payload_bytes = "payload",
        .limits = .{ .maximum_result_bytes = 32, .maximum_attempts = 1 },
    };
    try std.testing.expectError(error.InvalidRequest, request.seal(allocator, .{}));
    try std.testing.expectEqualSlices(u8, &zero_digest, &request.request_id);
    try std.testing.expectEqualSlices(u8, &zero_digest, &request.idempotency_key);

    var result: EffectResult = .{
        .request_id = digestLabel("test", "request"),
        .status = .ok,
        .result_schema_id = digestLabel("test", "result"),
        .result_bytes = "result",
        .attempt = 0,
    };
    try std.testing.expectError(error.InvalidResult, result.seal(allocator, .{}));
    try std.testing.expectEqualSlices(u8, &zero_digest, &result.result_id);
}

test "world application v1 rejects reserved zero semantic references" {
    const allocator = std.testing.allocator;
    var request: EffectRequest = .{
        .application_id = zero_digest,
        .parent_frame_id = zero_digest,
        .sequence = 0,
        .site_id = 1,
        .interface_id = digestLabel("test", "interface"),
        .payload_schema_id = digestLabel("test", "payload"),
        .result_schema_id = digestLabel("test", "result"),
        .payload_bytes = "payload",
        .limits = .{ .maximum_result_bytes = 32, .maximum_attempts = 1 },
    };
    try std.testing.expectError(error.InvalidRequest, request.seal(allocator, .{}));
    request.application_id = digestLabel("test", "application");
    request.sequence = 1;
    try std.testing.expectError(error.InvalidRequest, request.seal(allocator, .{}));
    request.sequence = 0;
    request.parent_frame_id = digestLabel("test", "parent");
    try std.testing.expectError(error.InvalidRequest, request.seal(allocator, .{}));

    var result: EffectResult = .{
        .request_id = zero_digest,
        .status = .ok,
        .result_schema_id = digestLabel("test", "result"),
        .result_bytes = "result",
        .attempt = 1,
    };
    try std.testing.expectError(error.InvalidResult, result.seal(allocator, .{}));
    result.request_id = digestLabel("test", "request");
    result.result_schema_id = zero_digest;
    try std.testing.expectError(error.InvalidResult, result.seal(allocator, .{}));

    var manifest: ApplicationManifest = .{
        .application_name = "zero-reference",
        .application_version = "1.0.0",
        .boundary_package_version = "1.0.0-rc.1",
        .boundary_static_machine_abi_version = 1,
        .world_package_version = "1.0.0-rc.1",
        .root_program_id = zero_digest,
    };
    try std.testing.expectError(error.InvalidManifest, manifest.seal(allocator));
    const zero_handler = [_]Digest{zero_digest};
    manifest.root_program_id = digestLabel("test", "root");
    manifest.internal_handler_ids = &zero_handler;
    try std.testing.expectError(error.InvalidManifest, manifest.seal(allocator));
    const zero_residual = [_]ResidualEffect{.{
        .interface_id = zero_digest,
        .site_id = 1,
        .payload_schema_id = digestLabel("test", "payload"),
        .result_schema_id = digestLabel("test", "result"),
        .allowed_statuses = .{},
        .authority_requirements = 0,
    }};
    manifest.internal_handler_ids = &.{};
    manifest.residual_effects = &zero_residual;
    try std.testing.expectError(error.InvalidManifest, manifest.seal(allocator));
}

test "world application v1 frame identity ignores no hidden metadata" {
    const allocator = std.testing.allocator;
    const application_id = digestLabel("test", "application");
    var first: Frame = .{
        .application_id = application_id,
        .sequence = 0,
        .state_bytes = "state",
        .status = .yielded_fuel,
    };
    var second = first;
    try first.seal(allocator, .{});
    try second.seal(allocator, .{});
    try std.testing.expectEqualSlices(u8, &first.frame_id, &second.frame_id);
}

test "world application v1 rejects impossible Frame causal sentinels" {
    const allocator = std.testing.allocator;
    var genesis: Frame = .{
        .application_id = digestLabel("test", "application"),
        .sequence = 0,
        .state_bytes = "state",
        .accepted_effect_result_id = digestLabel("test", "result"),
        .status = .yielded_fuel,
    };
    try std.testing.expectError(error.InvalidFrame, genesis.seal(allocator, .{}));
    try std.testing.expectEqualSlices(u8, &zero_digest, &genesis.frame_id);

    var later: Frame = .{
        .application_id = digestLabel("test", "application"),
        .parent_frame_id = zero_digest,
        .sequence = 1,
        .state_bytes = "state",
        .status = .yielded_fuel,
    };
    try std.testing.expectError(error.InvalidFrame, later.seal(allocator, .{}));
    try std.testing.expectEqualSlices(u8, &zero_digest, &later.frame_id);
}

test "world application v1 yielded Frame golden bytes are frozen" {
    const allocator = std.testing.allocator;
    var frame: Frame = .{
        .application_id = digestLabel("test", "golden-application"),
        .sequence = 0,
        .state_bytes = "s",
        .status = .yielded_fuel,
    };
    try frame.seal(allocator, .{});
    const encoded = try frame.encode(allocator, .{});
    defer allocator.free(encoded);

    const golden_hex = "57524c4446524d31010000005bb5b45accd208eb78336b1af03f37cd18b22689d49699d210d59b4b1aee06eef2f06d30cf415f76d57d9f19ed8464d49c125ba7f3796bab009cdd37371a2d080000000000000000000100000073000003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    var golden: [golden_hex.len / 2]u8 = undefined;
    _ = try std.fmt.hexToBytes(&golden, golden_hex);
    try std.testing.expectEqualSlices(u8, &golden, encoded);
}

test "world application v1 rejects a second pending effect by construction" {
    try std.testing.expect(!@hasField(Frame, "pending_effects"));
    try std.testing.expect(@hasField(Frame, "pending_effect"));
}

test "world application v1 admission limits bound declared manifest limits" {
    const allocator = std.testing.allocator;
    var decode_arena = std.heap.ArenaAllocator.init(allocator);
    defer decode_arena.deinit();
    const admission: Limits = .{};
    var declared = admission;
    declared.maximum_state_bytes += 1;
    var manifest: ApplicationManifest = .{
        .application_name = "oversized",
        .application_version = "1.0.0",
        .boundary_package_version = "1.0.0-rc.1",
        .boundary_static_machine_abi_version = 1,
        .world_package_version = "1.0.0-rc.1",
        .root_program_id = digestLabel("test", "root"),
        .limits = declared,
    };
    try manifest.seal(allocator);
    const encoded = try manifest.encode(allocator);
    defer allocator.free(encoded);
    try std.testing.expectError(
        error.LimitExceeded,
        ApplicationManifest.decode(&decode_arena, encoded, admission),
    );
}

test "world application v1 manifest enforces its own byte limit" {
    const allocator = std.testing.allocator;
    var decode_arena = std.heap.ArenaAllocator.init(allocator);
    defer decode_arena.deinit();
    var manifest: ApplicationManifest = .{
        .application_name = "self-limited",
        .application_version = "1.0.0",
        .boundary_package_version = "1.0.0-rc.1",
        .boundary_static_machine_abi_version = 1,
        .world_package_version = "1.0.0-rc.1",
        .root_program_id = digestLabel("test", "root"),
        .limits = .{ .maximum_manifest_bytes = 128 },
    };
    try std.testing.expectError(error.LimitExceeded, manifest.seal(allocator));
    try std.testing.expectEqualSlices(u8, &zero_digest, &manifest.application_id);

    manifest.application_id = try manifestSemanticDigest(manifest);
    const encoded = try encodeManifestSemantic(allocator, manifest, true);
    defer allocator.free(encoded);
    try std.testing.expect(encoded.len > manifest.limits.maximum_manifest_bytes);
    try std.testing.expectError(error.LimitExceeded, manifest.validate());
    try std.testing.expectError(error.LimitExceeded, ApplicationManifest.decode(&decode_arena, encoded, .{}));
}

test "world application v1 manifest proves collection bytes before allocation" {
    const allocator = std.testing.allocator;
    var writer = Writer.init(allocator);
    defer writer.deinit();
    try writer.writeBytes(manifest_magic);
    try writer.writeU32(format_version);
    try writer.writeDigest(digestLabel("test", "manifest"));
    try writer.writeLenBytes("manifest");
    try writer.writeLenBytes("1.0.0");
    try writer.writeLenBytes("1.0.0-rc.1");
    try writer.writeU32(1);
    try writer.writeLenBytes("1.0.0-rc.1");
    try writer.writeU32(abi_version);
    try writer.writeDigest(digestLabel("test", "root"));
    try writer.writeU32(1);
    try writer.writeDigest(zero_digest);
    const truncated_handlers = try writer.toOwnedSlice();
    defer allocator.free(truncated_handlers);

    var failing_allocator = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 4 });
    var failing_arena = std.heap.ArenaAllocator.init(failing_allocator.allocator());
    defer failing_arena.deinit();
    try std.testing.expectError(
        error.InvalidEncoding,
        ApplicationManifest.decode(&failing_arena, truncated_handlers, .{}),
    );
    try std.testing.expect(!failing_allocator.has_induced_failure);

    var residual_writer = Writer.init(allocator);
    defer residual_writer.deinit();
    try residual_writer.writeBytes(manifest_magic);
    try residual_writer.writeU32(format_version);
    try residual_writer.writeDigest(digestLabel("test", "manifest"));
    try residual_writer.writeLenBytes("manifest");
    try residual_writer.writeLenBytes("1.0.0");
    try residual_writer.writeLenBytes("1.0.0-rc.1");
    try residual_writer.writeU32(1);
    try residual_writer.writeLenBytes("1.0.0-rc.1");
    try residual_writer.writeU32(abi_version);
    try residual_writer.writeDigest(digestLabel("test", "root"));
    try residual_writer.writeU32(0);
    try residual_writer.writeU32(1);
    try residual_writer.writeDigest(digestLabel("test", "interface"));
    try residual_writer.writeU64(1);
    try residual_writer.writeDigest(digestLabel("test", "payload"));
    try residual_writer.writeDigest(digestLabel("test", "result"));
    try residual_writer.writeU8(@bitCast(AllowedStatuses{}));
    try residual_writer.writeU64(0);
    const truncated_residuals = try residual_writer.toOwnedSlice();
    defer allocator.free(truncated_residuals);

    var residual_failing_allocator = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 4 });
    var residual_failing_arena = std.heap.ArenaAllocator.init(residual_failing_allocator.allocator());
    defer residual_failing_arena.deinit();
    try std.testing.expectError(
        error.InvalidEncoding,
        ApplicationManifest.decode(&residual_failing_arena, truncated_residuals, .{}),
    );
    try std.testing.expect(!residual_failing_allocator.has_induced_failure);
}

test "world application v1 needs-effect Frame requires portable state" {
    const allocator = std.testing.allocator;
    var request: EffectRequest = .{
        .application_id = digestLabel("test", "application"),
        .parent_frame_id = zero_digest,
        .sequence = 0,
        .site_id = 1,
        .interface_id = digestLabel("test", "interface"),
        .payload_schema_id = digestLabel("test", "payload"),
        .result_schema_id = digestLabel("test", "result"),
        .payload_bytes = "payload",
        .limits = .{ .maximum_result_bytes = 32, .maximum_attempts = 1 },
    };
    try request.seal(allocator, .{});
    var frame: Frame = .{
        .application_id = request.application_id,
        .sequence = 0,
        .state_bytes = "",
        .pending_effect = request,
        .status = .needs_effect,
    };
    try std.testing.expectError(error.InvalidFrame, frame.seal(allocator, .{}));
}

test "world application v1 StepInput and manifest round trip" {
    const allocator = std.testing.allocator;
    var decode_arena = std.heap.ArenaAllocator.init(allocator);
    defer decode_arena.deinit();
    const limits: Limits = .{};
    const handler_ids = [_]Digest{
        digestLabel("test", "handler-a"),
        digestLabel("test", "handler-b"),
    };
    const ordered_handler_ids = if (std.mem.order(u8, &handler_ids[0], &handler_ids[1]) == .lt)
        handler_ids
    else
        [_]Digest{ handler_ids[1], handler_ids[0] };
    const residual_effects = [_]ResidualEffect{
        .{
            .interface_id = digestLabel("test", "interface"),
            .site_id = 7,
            .payload_schema_id = digestLabel("test", "payload"),
            .result_schema_id = digestLabel("test", "result"),
            .allowed_statuses = .{},
            .authority_requirements = 1,
        },
    };
    var manifest: ApplicationManifest = .{
        .application_name = "fixture",
        .application_version = "1.0.0",
        .boundary_package_version = "1.0.0-rc.1",
        .boundary_static_machine_abi_version = 1,
        .world_package_version = "1.0.0-rc.1",
        .root_program_id = digestLabel("test", "root"),
        .internal_handler_ids = &ordered_handler_ids,
        .residual_effects = &residual_effects,
        .limits = limits,
        .required_host_capabilities = 1,
    };
    try manifest.seal(allocator);
    const manifest_bytes = try manifest.encode(allocator);
    defer allocator.free(manifest_bytes);
    const decoded_manifest = try ApplicationManifest.decode(&decode_arena, manifest_bytes, limits);
    const manifest_bytes_again = try decoded_manifest.encode(allocator);
    defer allocator.free(manifest_bytes_again);
    try std.testing.expectEqualSlices(u8, manifest_bytes, manifest_bytes_again);

    const input: StepInput = .{
        .application_id = manifest.application_id,
        .initial_args_bytes = "goal=fixture",
        .fuel = 100,
        .host_metadata = "ignored-by-application-semantics",
    };
    const input_bytes = try input.encode(allocator, limits);
    defer allocator.free(input_bytes);
    const decoded_input = try StepInput.decode(&decode_arena, input_bytes, limits);
    const input_bytes_again = try decoded_input.encode(allocator, limits);
    defer allocator.free(input_bytes_again);
    try std.testing.expectEqualSlices(u8, input_bytes, input_bytes_again);
}

test "world application v1 manifest capabilities are derived exactly from residual effects" {
    const allocator = std.testing.allocator;
    const residual_effects = [_]ResidualEffect{
        .{
            .interface_id = digestLabel("test", "interface"),
            .site_id = 7,
            .payload_schema_id = digestLabel("test", "payload"),
            .result_schema_id = digestLabel("test", "result"),
            .allowed_statuses = .{},
            .authority_requirements = 0b0101,
        },
    };
    var manifest: ApplicationManifest = .{
        .application_name = "capability-drift",
        .application_version = "1.0.0",
        .boundary_package_version = "1.0.0-rc.1",
        .boundary_static_machine_abi_version = 1,
        .world_package_version = "1.0.0-rc.1",
        .root_program_id = digestLabel("test", "root"),
        .residual_effects = &residual_effects,
        .required_host_capabilities = 0b0001,
    };
    try std.testing.expectError(error.InvalidManifest, manifest.seal(allocator));
    manifest.required_host_capabilities = 0b1101;
    try std.testing.expectError(error.InvalidManifest, manifest.seal(allocator));
    manifest.required_host_capabilities = 0b0101;
    try manifest.seal(allocator);
    try manifest.validate();
}

test "world application v1 StepInput rejects aggregate over-limit bytes before decode" {
    const allocator = std.testing.allocator;
    var decode_arena = std.heap.ArenaAllocator.init(allocator);
    defer decode_arena.deinit();
    const limits: Limits = .{};
    const maximum = try aggregateLimit(&.{
        limits.maximum_state_bytes,
        limits.maximum_payload_bytes,
        limits.maximum_result_bytes,
        limits.maximum_failure_bytes,
        limits.maximum_initial_args_bytes,
        limits.maximum_result_bytes,
        limits.maximum_host_claim_bytes,
        limits.maximum_host_metadata_bytes,
    }, 4096);
    const oversized = try allocator.alloc(u8, maximum + 1);
    defer allocator.free(oversized);
    @memset(oversized, 0);
    try std.testing.expectError(error.LimitExceeded, StepInput.decode(&decode_arena, oversized, limits));
}

test "world application v1 malformed records fail closed" {
    const allocator = std.testing.allocator;
    var decode_arena = std.heap.ArenaAllocator.init(allocator);
    defer decode_arena.deinit();
    const limits: Limits = .{};
    var request: EffectRequest = .{
        .application_id = digestLabel("test", "application"),
        .parent_frame_id = digestLabel("test", "parent"),
        .sequence = 1,
        .site_id = 1,
        .interface_id = digestLabel("test", "interface"),
        .payload_schema_id = digestLabel("test", "payload"),
        .result_schema_id = digestLabel("test", "result"),
        .payload_bytes = "payload",
        .limits = .{ .maximum_result_bytes = 32, .maximum_attempts = 2 },
    };
    try request.seal(allocator, limits);
    const encoded = try request.encode(allocator, limits);
    defer allocator.free(encoded);

    const identity_tamper = try allocator.dupe(u8, encoded);
    defer allocator.free(identity_tamper);
    identity_tamper[request_magic.len + 4] ^= 1;
    try std.testing.expectError(error.InvalidIdentity, EffectRequest.decode(&decode_arena, identity_tamper, limits));

    const with_trailing = try allocator.alloc(u8, encoded.len + 1);
    defer allocator.free(with_trailing);
    @memcpy(with_trailing[0..encoded.len], encoded);
    with_trailing[encoded.len] = 0;
    try std.testing.expectError(error.TrailingBytes, EffectRequest.decode(&decode_arena, with_trailing, limits));

    const length_tamper = try allocator.dupe(u8, encoded);
    defer allocator.free(length_tamper);
    const payload_length_offset = request_magic.len + 4 + zero_digest.len * 6 + 8 + 4 + 8 + 1;
    std.mem.writeInt(u32, length_tamper[payload_length_offset..][0..4], std.math.maxInt(u32), .little);
    try std.testing.expectError(error.LimitExceeded, EffectRequest.decode(&decode_arena, length_tamper, limits));

    var wrong_result: EffectResult = .{
        .request_id = request.request_id,
        .status = .ok,
        .result_schema_id = digestLabel("test", "wrong-result"),
        .result_bytes = "response",
        .attempt = 1,
    };
    try wrong_result.seal(allocator, limits);
    try std.testing.expectError(error.EffectResultMismatch, validateResultForRequest(request, wrong_result, limits));
}
