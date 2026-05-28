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
    UnsupportedValueImage,
    NativeOnlyValue,
    MissingValueImage,
    InvalidFrameEncoding,
    FrameSurfaceMismatch,
    FrameTargetCertificateMismatch,
    FramePortMismatch,
    FrameRequestFingerprintMismatch,
    FrameValueTableMismatch,
    VerifyMissingExpected,
    VerifyResponseKindMismatch,
    VerifyResponseFingerprintMismatch,
    VerifyValueImageMismatch,
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
    frame_requested,
    frame_responded,
    frame_replayed,
    frame_verified,
    frame_rejected,
    frame_failed,
    checkpoint_recorded,
    branch_started,
    branch_joined,
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

pub const world_frame_request_format_version: u32 = 1;
pub const world_frame_request_fingerprint_version: u32 = 1;
pub const world_frame_response_format_version: u32 = 1;
pub const world_frame_response_fingerprint_version: u32 = 1;
pub const world_frame_value_image_format_version: u32 = 1;
pub const world_frame_value_image_fingerprint_version: u32 = 1;
pub const world_transcript_image_format_version: u32 = 1;
pub const world_transcript_image_fingerprint_version: u32 = 1;
pub const world_timeline_event_format_version: u32 = 1;
pub const world_timeline_event_fingerprint_version: u32 = 1;
pub const world_timeline_checkpoint_format_version: u32 = 1;
pub const world_timeline_checkpoint_fingerprint_version: u32 = 1;
pub const world_timeline_branch_format_version: u32 = 1;
pub const world_timeline_branch_fingerprint_version: u32 = 1;
pub const world_audit_image_format_version: u32 = 1;
pub const world_audit_image_fingerprint_version: u32 = 1;

pub const ValuePolicy = struct {
    require_portable_values: bool = false,
    allow_native_only_values: bool = true,
    require_response_images_for_replay: bool = false,
    allow_diagnostic_type_labels: bool = true,
    max_value_image_bytes: ?usize = null,

    pub const portable = ValuePolicy{
        .require_portable_values = true,
        .allow_native_only_values = false,
        .require_response_images_for_replay = true,
        .allow_diagnostic_type_labels = false,
    };

    pub const native_compatible = ValuePolicy{};

    pub const audit_only = ValuePolicy{
        .require_portable_values = false,
        .allow_native_only_values = true,
        .require_response_images_for_replay = false,
        .allow_diagnostic_type_labels = true,
    };
};

pub const Frame = struct {
    pub const Status = ResponseStatus;
    pub const Error = error{
        UnsupportedValueImage,
        NativeOnlyValue,
        MissingValueImage,
        InvalidFrameEncoding,
        FrameSurfaceMismatch,
        FrameTargetCertificateMismatch,
        FramePortMismatch,
        FrameRequestFingerprintMismatch,
        FrameValueTableMismatch,
        VerifyMissingExpected,
        VerifyResponseKindMismatch,
        VerifyResponseFingerprintMismatch,
        VerifyValueImageMismatch,
        OutOfMemory,
    };

    pub const Codec = struct {
        pub const reject_trailing_junk = true;
    };

    pub const ValueImage = struct {
        format_version: u32 = world_frame_value_image_format_version,
        fingerprint_version: u32 = world_frame_value_image_fingerprint_version,
        value_image_fingerprint: u64,
        value_table_id: ?u32 = null,
        boundary_value_fingerprint: ?u64 = null,
        codec_schema_descriptor_fingerprint: ?u64 = null,
        bytes: []const u8,
        dynamic_size: bool = false,
        diagnostic_type_label: ?[]const u8 = null,

        pub fn fromValue(
            allocator: std.mem.Allocator,
            value_table_id: ?u32,
            boundary_value_fingerprint: ?u64,
            codec_schema_descriptor_fingerprint: ?u64,
            value: anytype,
            policy: ValuePolicy,
        ) !@This() {
            var bytes: std.ArrayList(u8) = .empty;
            errdefer bytes.deinit(allocator);
            if (policy.max_value_image_bytes) |max| {
                if (portableValueDynamicByteLowerBound(@TypeOf(value), value) > max) return error.UnsupportedValueImage;
            }
            try encodePortableValue(@TypeOf(value), allocator, &bytes, value);
            if (policy.max_value_image_bytes) |max| {
                if (bytes.items.len > max) return error.UnsupportedValueImage;
            }
            const owned_bytes = try bytes.toOwnedSlice(allocator);
            errdefer allocator.free(owned_bytes);
            const label = if (policy.allow_diagnostic_type_labels)
                try allocator.dupe(u8, @typeName(@TypeOf(value)))
            else
                null;
            errdefer if (label) |owned_label| allocator.free(owned_label);
            return .{
                .value_image_fingerprint = fingerprintValueImage(
                    value_table_id,
                    boundary_value_fingerprint,
                    codec_schema_descriptor_fingerprint,
                    owned_bytes,
                ),
                .value_table_id = value_table_id,
                .boundary_value_fingerprint = boundary_value_fingerprint,
                .codec_schema_descriptor_fingerprint = codec_schema_descriptor_fingerprint,
                .bytes = owned_bytes,
                .dynamic_size = valueIsDynamic(@TypeOf(value)),
                .diagnostic_type_label = label,
            };
        }

        pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
            const bytes = try allocator.dupe(u8, self.bytes);
            errdefer allocator.free(bytes);
            const label = if (self.diagnostic_type_label) |diagnostic|
                try allocator.dupe(u8, diagnostic)
            else
                null;
            errdefer if (label) |owned| allocator.free(owned);
            var result = self;
            result.bytes = bytes;
            result.diagnostic_type_label = label;
            return result;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.bytes);
            if (self.diagnostic_type_label) |label| allocator.free(label);
            self.* = undefined;
        }

        pub fn decodeValue(self: @This(), allocator: std.mem.Allocator, comptime Value: type) !Value {
            var cursor: usize = 0;
            const value = try decodePortableValue(Value, allocator, self.bytes, &cursor);
            errdefer deinitOwnedValue(allocator, value);
            if (cursor != self.bytes.len) return error.InvalidFrameEncoding;
            return value;
        }

        pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeU32(&out, allocator, self.format_version);
            try writeU32(&out, allocator, self.fingerprint_version);
            try writeU64(&out, allocator, self.value_image_fingerprint);
            try writeOptionalU32(&out, allocator, self.value_table_id);
            try writeOptionalU64(&out, allocator, self.boundary_value_fingerprint);
            try writeOptionalU64(&out, allocator, self.codec_schema_descriptor_fingerprint);
            try writeBool(&out, allocator, self.dynamic_size);
            try writeBytes(&out, allocator, self.bytes);
            try writeOptionalBytes(&out, allocator, self.diagnostic_type_label);
            return out.toOwnedSlice(allocator);
        }

        pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
            var cursor: usize = 0;
            const result = try decodeFrom(allocator, bytes, &cursor);
            errdefer {
                var owned = result;
                owned.deinit(allocator);
            }
            if (cursor != bytes.len) return error.InvalidFrameEncoding;
            return result;
        }

        fn decodeFrom(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !@This() {
            const format_version = try readU32(bytes, cursor);
            if (format_version != world_frame_value_image_format_version) return error.InvalidFrameEncoding;
            const fingerprint_version = try readU32(bytes, cursor);
            if (fingerprint_version != world_frame_value_image_fingerprint_version) return error.InvalidFrameEncoding;
            const value_image_fingerprint = try readU64(bytes, cursor);
            const value_table_id = try readOptionalU32(bytes, cursor);
            const boundary_value_fingerprint = try readOptionalU64(bytes, cursor);
            const codec_schema_descriptor_fingerprint = try readOptionalU64(bytes, cursor);
            const dynamic_size = try readBool(bytes, cursor);
            const image_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(image_bytes);
            const label = try readOptionalBytesOwned(allocator, bytes, cursor);
            errdefer if (label) |owned| allocator.free(owned);
            const expected = fingerprintValueImage(
                value_table_id,
                boundary_value_fingerprint,
                codec_schema_descriptor_fingerprint,
                image_bytes,
            );
            if (expected != value_image_fingerprint) return error.VerifyValueImageMismatch;
            return .{
                .value_image_fingerprint = value_image_fingerprint,
                .value_table_id = value_table_id,
                .boundary_value_fingerprint = boundary_value_fingerprint,
                .codec_schema_descriptor_fingerprint = codec_schema_descriptor_fingerprint,
                .bytes = image_bytes,
                .dynamic_size = dynamic_size,
                .diagnostic_type_label = label,
            };
        }
    };

    pub const Request = struct {
        format_version: u32 = world_frame_request_format_version,
        fingerprint_version: u32 = world_frame_request_fingerprint_version,
        frame_fingerprint: u64,
        world_surface_fingerprint: u64,
        world_surface_replay_scope_fingerprint: ?u64 = null,
        target_certificate_fingerprint: u64,
        world_port_id: u32,
        residual_site_index: usize,
        residual_site_fingerprint: u64,
        request_fingerprint: u64,
        turn_index: usize,
        payload_value_table_id: ?u32 = null,
        expected_response_value_table_id: ?u32 = null,
        payload_value_fingerprint: ?u64 = null,
        payload_image: ?ValueImage = null,
        replay_key_seed: ReplayKeySeed,
        source_effect_shape_fingerprint: ?u64 = null,
        world_port_ref_fingerprint: ?u64 = null,
        trace_ref_fingerprint: ?u64 = null,
        evidence_ref_fingerprint: ?u64 = null,
        flags: u32 = 0,

        pub fn init(args: struct {
            world_surface_fingerprint: u64,
            world_surface_replay_scope_fingerprint: ?u64 = null,
            target_certificate_fingerprint: u64,
            world_port_id: u32,
            residual_site_index: usize,
            residual_site_fingerprint: u64,
            request_fingerprint: u64,
            turn_index: usize,
            payload_value_table_id: ?u32 = null,
            expected_response_value_table_id: ?u32 = null,
            payload_image: ?ValueImage = null,
            flags: u32 = 0,
        }) @This() {
            const replay_scope = args.world_surface_replay_scope_fingerprint orelse args.world_surface_fingerprint;
            var result = @This(){
                .frame_fingerprint = 0,
                .world_surface_fingerprint = args.world_surface_fingerprint,
                .world_surface_replay_scope_fingerprint = args.world_surface_replay_scope_fingerprint,
                .target_certificate_fingerprint = args.target_certificate_fingerprint,
                .world_port_id = args.world_port_id,
                .residual_site_index = args.residual_site_index,
                .residual_site_fingerprint = args.residual_site_fingerprint,
                .request_fingerprint = args.request_fingerprint,
                .turn_index = args.turn_index,
                .payload_value_table_id = args.payload_value_table_id,
                .expected_response_value_table_id = args.expected_response_value_table_id,
                .payload_value_fingerprint = if (args.payload_image) |image| image.value_image_fingerprint else null,
                .payload_image = args.payload_image,
                .replay_key_seed = .{
                    .world_surface_fingerprint = args.world_surface_fingerprint,
                    .world_surface_scope_fingerprint = replay_scope,
                    .world_port_id = args.world_port_id,
                    .request_fingerprint = args.request_fingerprint,
                },
                .flags = args.flags,
            };
            result.frame_fingerprint = fingerprintRequest(result);
            return result;
        }

        pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
            var result = self;
            result.payload_image = if (self.payload_image) |image| try image.clone(allocator) else null;
            return result;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.payload_image) |*image| image.deinit(allocator);
            self.* = undefined;
        }

        pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeU32(&out, allocator, self.format_version);
            try writeU32(&out, allocator, self.fingerprint_version);
            try writeU64(&out, allocator, self.frame_fingerprint);
            try writeU64(&out, allocator, self.world_surface_fingerprint);
            try writeOptionalU64(&out, allocator, self.world_surface_replay_scope_fingerprint);
            try writeU64(&out, allocator, self.target_certificate_fingerprint);
            try writeU32(&out, allocator, self.world_port_id);
            try writeU64(&out, allocator, self.residual_site_index);
            try writeU64(&out, allocator, self.residual_site_fingerprint);
            try writeU64(&out, allocator, self.request_fingerprint);
            try writeU64(&out, allocator, self.turn_index);
            try writeOptionalU32(&out, allocator, self.payload_value_table_id);
            try writeOptionalU32(&out, allocator, self.expected_response_value_table_id);
            try writeOptionalU64(&out, allocator, self.payload_value_fingerprint);
            try writeOptionalValueImage(&out, allocator, self.payload_image);
            try writeU64(&out, allocator, self.replay_key_seed.world_surface_fingerprint);
            try writeU64(&out, allocator, self.replay_key_seed.world_surface_scope_fingerprint);
            try writeU32(&out, allocator, self.replay_key_seed.world_port_id);
            try writeU64(&out, allocator, self.replay_key_seed.request_fingerprint);
            try writeOptionalU64(&out, allocator, self.source_effect_shape_fingerprint);
            try writeOptionalU64(&out, allocator, self.world_port_ref_fingerprint);
            try writeOptionalU64(&out, allocator, self.trace_ref_fingerprint);
            try writeOptionalU64(&out, allocator, self.evidence_ref_fingerprint);
            try writeU32(&out, allocator, self.flags);
            return out.toOwnedSlice(allocator);
        }

        pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
            var cursor: usize = 0;
            const result = try decodeFrom(allocator, bytes, &cursor);
            errdefer {
                var owned = result;
                owned.deinit(allocator);
            }
            if (cursor != bytes.len) return error.InvalidFrameEncoding;
            return result;
        }

        fn decodeFrom(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !@This() {
            const format_version = try readU32(bytes, cursor);
            if (format_version != world_frame_request_format_version) return error.InvalidFrameEncoding;
            const fingerprint_version = try readU32(bytes, cursor);
            if (fingerprint_version != world_frame_request_fingerprint_version) return error.InvalidFrameEncoding;
            var result = @This(){
                .frame_fingerprint = try readU64(bytes, cursor),
                .world_surface_fingerprint = try readU64(bytes, cursor),
                .world_surface_replay_scope_fingerprint = try readOptionalU64(bytes, cursor),
                .target_certificate_fingerprint = try readU64(bytes, cursor),
                .world_port_id = try readU32(bytes, cursor),
                .residual_site_index = try readU64AsUsize(bytes, cursor),
                .residual_site_fingerprint = try readU64(bytes, cursor),
                .request_fingerprint = try readU64(bytes, cursor),
                .turn_index = try readU64AsUsize(bytes, cursor),
                .payload_value_table_id = try readOptionalU32(bytes, cursor),
                .expected_response_value_table_id = try readOptionalU32(bytes, cursor),
                .payload_value_fingerprint = try readOptionalU64(bytes, cursor),
                .payload_image = try readOptionalValueImage(allocator, bytes, cursor),
                .replay_key_seed = .{
                    .world_surface_fingerprint = try readU64(bytes, cursor),
                    .world_surface_scope_fingerprint = try readU64(bytes, cursor),
                    .world_port_id = try readU32(bytes, cursor),
                    .request_fingerprint = try readU64(bytes, cursor),
                },
                .source_effect_shape_fingerprint = try readOptionalU64(bytes, cursor),
                .world_port_ref_fingerprint = try readOptionalU64(bytes, cursor),
                .trace_ref_fingerprint = try readOptionalU64(bytes, cursor),
                .evidence_ref_fingerprint = try readOptionalU64(bytes, cursor),
                .flags = try readU32(bytes, cursor),
            };
            errdefer result.deinit(allocator);
            const expected_payload_value_fingerprint: ?u64 = if (result.payload_image) |image| image.value_image_fingerprint else null;
            if (result.payload_value_fingerprint != expected_payload_value_fingerprint) return error.InvalidFrameEncoding;
            const expected_replay_scope = result.world_surface_replay_scope_fingerprint orelse result.world_surface_fingerprint;
            if (result.replay_key_seed.world_surface_fingerprint != result.world_surface_fingerprint) return error.InvalidFrameEncoding;
            if (result.replay_key_seed.world_surface_scope_fingerprint != expected_replay_scope) return error.InvalidFrameEncoding;
            if (result.replay_key_seed.world_port_id != result.world_port_id) return error.InvalidFrameEncoding;
            if (result.replay_key_seed.request_fingerprint != result.request_fingerprint) return error.InvalidFrameEncoding;
            if (fingerprintRequest(result) != result.frame_fingerprint) return error.InvalidFrameEncoding;
            return result;
        }
    };

    pub const Response = struct {
        format_version: u32 = world_frame_response_format_version,
        fingerprint_version: u32 = world_frame_response_fingerprint_version,
        frame_fingerprint: u64,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        world_port_id: u32,
        request_fingerprint: u64,
        response_kind: ResponseKind = .@"resume",
        response_value_table_id: ?u32 = null,
        response_fingerprint: u64,
        response_value_fingerprint: ?u64 = null,
        response_image: ?ValueImage = null,
        replay_key: u64,
        status: ResponseStatus = .responded,
        error_tag: ?[]const u8 = null,
        reason: ?[]const u8 = null,
        owns_error_tag: bool = false,
        owns_reason: bool = false,
        flags: u32 = 0,

        pub fn fromValue(
            allocator: std.mem.Allocator,
            request: Request,
            response_value_table_id: ?u32,
            response_fingerprint: u64,
            response_kind: ResponseKind,
            value: anytype,
            policy: ValuePolicy,
        ) !@This() {
            var image = try ValueImage.fromValue(
                allocator,
                response_value_table_id,
                response_fingerprint,
                null,
                value,
                policy,
            );
            errdefer image.deinit(allocator);
            return init(.{
                .world_surface_fingerprint = request.world_surface_fingerprint,
                .target_certificate_fingerprint = request.target_certificate_fingerprint,
                .world_port_id = request.world_port_id,
                .request_fingerprint = request.request_fingerprint,
                .response_kind = response_kind,
                .response_value_table_id = response_value_table_id,
                .response_fingerprint = response_fingerprint,
                .response_image = image,
                .replay_key = request.replay_key_seed.withResponse(response_fingerprint).fingerprint(),
                .status = .responded,
            });
        }

        pub fn init(args: struct {
            world_surface_fingerprint: u64,
            target_certificate_fingerprint: u64,
            world_port_id: u32,
            request_fingerprint: u64,
            response_kind: ResponseKind = .@"resume",
            response_value_table_id: ?u32 = null,
            response_fingerprint: u64,
            response_image: ?ValueImage = null,
            replay_key: u64,
            status: ResponseStatus = .responded,
            error_tag: ?[]const u8 = null,
            reason: ?[]const u8 = null,
            flags: u32 = 0,
        }) @This() {
            var result = @This(){
                .frame_fingerprint = 0,
                .world_surface_fingerprint = args.world_surface_fingerprint,
                .target_certificate_fingerprint = args.target_certificate_fingerprint,
                .world_port_id = args.world_port_id,
                .request_fingerprint = args.request_fingerprint,
                .response_kind = args.response_kind,
                .response_value_table_id = args.response_value_table_id,
                .response_fingerprint = args.response_fingerprint,
                .response_value_fingerprint = if (args.response_image) |image| image.value_image_fingerprint else null,
                .response_image = args.response_image,
                .replay_key = args.replay_key,
                .status = args.status,
                .error_tag = args.error_tag,
                .reason = args.reason,
                .owns_error_tag = false,
                .owns_reason = false,
                .flags = args.flags,
            };
            result.frame_fingerprint = fingerprintResponse(result);
            return result;
        }

        pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
            var result = self;
            result.response_image = if (self.response_image) |image| try image.clone(allocator) else null;
            errdefer if (result.response_image) |*image| image.deinit(allocator);
            result.error_tag = if (self.error_tag) |tag| try allocator.dupe(u8, tag) else null;
            result.owns_error_tag = result.error_tag != null;
            errdefer if (result.error_tag) |tag| allocator.free(tag);
            result.reason = if (self.reason) |reason| try allocator.dupe(u8, reason) else null;
            result.owns_reason = result.reason != null;
            errdefer if (result.reason) |reason| allocator.free(reason);
            return result;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.response_image) |*image| image.deinit(allocator);
            if (self.owns_error_tag) if (self.error_tag) |tag| allocator.free(tag);
            if (self.owns_reason) if (self.reason) |reason| allocator.free(reason);
            self.* = undefined;
        }

        pub fn decodeValue(self: @This(), allocator: std.mem.Allocator, comptime Value: type) !Value {
            const image = self.response_image orelse return error.MissingValueImage;
            return image.decodeValue(allocator, Value);
        }

        pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeU32(&out, allocator, self.format_version);
            try writeU32(&out, allocator, self.fingerprint_version);
            try writeU64(&out, allocator, self.frame_fingerprint);
            try writeU64(&out, allocator, self.world_surface_fingerprint);
            try writeU64(&out, allocator, self.target_certificate_fingerprint);
            try writeU32(&out, allocator, self.world_port_id);
            try writeU64(&out, allocator, self.request_fingerprint);
            try writeU8(&out, allocator, @intFromEnum(self.response_kind));
            try writeOptionalU32(&out, allocator, self.response_value_table_id);
            try writeU64(&out, allocator, self.response_fingerprint);
            try writeOptionalU64(&out, allocator, self.response_value_fingerprint);
            try writeOptionalValueImage(&out, allocator, self.response_image);
            try writeU64(&out, allocator, self.replay_key);
            try writeU8(&out, allocator, @intFromEnum(self.status));
            try writeOptionalBytes(&out, allocator, self.error_tag);
            try writeOptionalBytes(&out, allocator, self.reason);
            try writeU32(&out, allocator, self.flags);
            return out.toOwnedSlice(allocator);
        }

        pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
            var cursor: usize = 0;
            const result = try decodeFrom(allocator, bytes, &cursor);
            errdefer {
                var owned = result;
                owned.deinit(allocator);
            }
            if (cursor != bytes.len) return error.InvalidFrameEncoding;
            return result;
        }

        fn decodeFrom(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !@This() {
            const format_version = try readU32(bytes, cursor);
            if (format_version != world_frame_response_format_version) return error.InvalidFrameEncoding;
            const fingerprint_version = try readU32(bytes, cursor);
            if (fingerprint_version != world_frame_response_fingerprint_version) return error.InvalidFrameEncoding;
            const frame_fingerprint = try readU64(bytes, cursor);
            const world_surface_fingerprint = try readU64(bytes, cursor);
            const target_certificate_fingerprint = try readU64(bytes, cursor);
            const world_port_id = try readU32(bytes, cursor);
            const request_fingerprint = try readU64(bytes, cursor);
            const response_kind = try enumFromByte(ResponseKind, try readU8(bytes, cursor));
            const response_value_table_id = try readOptionalU32(bytes, cursor);
            const response_fingerprint = try readU64(bytes, cursor);
            const response_value_fingerprint = try readOptionalU64(bytes, cursor);
            var response_image = try readOptionalValueImage(allocator, bytes, cursor);
            errdefer if (response_image) |*image| image.deinit(allocator);
            const expected_response_value_fingerprint: ?u64 = if (response_image) |image| image.value_image_fingerprint else null;
            if (response_value_fingerprint != expected_response_value_fingerprint) return error.InvalidFrameEncoding;
            if (response_image) |image| {
                if (image.value_table_id != response_value_table_id) return error.InvalidFrameEncoding;
                if (image.boundary_value_fingerprint != response_fingerprint) return error.InvalidFrameEncoding;
            }
            const replay_key = try readU64(bytes, cursor);
            const status = try enumFromByte(ResponseStatus, try readU8(bytes, cursor));
            const error_tag = try readOptionalBytesOwned(allocator, bytes, cursor);
            errdefer if (error_tag) |tag| allocator.free(tag);
            const reason = try readOptionalBytesOwned(allocator, bytes, cursor);
            errdefer if (reason) |owned_reason| allocator.free(owned_reason);
            const flags = try readU32(bytes, cursor);
            var result = init(.{
                .world_surface_fingerprint = world_surface_fingerprint,
                .target_certificate_fingerprint = target_certificate_fingerprint,
                .world_port_id = world_port_id,
                .request_fingerprint = request_fingerprint,
                .response_kind = response_kind,
                .response_value_table_id = response_value_table_id,
                .response_fingerprint = response_fingerprint,
                .response_image = response_image,
                .replay_key = replay_key,
                .status = status,
                .error_tag = error_tag,
                .reason = reason,
                .flags = flags,
            });
            result.owns_error_tag = error_tag != null;
            result.owns_reason = reason != null;
            if (result.frame_fingerprint != frame_fingerprint) return error.InvalidFrameEncoding;
            return result;
        }
    };

    pub const NativeAdapter = struct {};
    pub const ReplayAdapter = struct {};
    pub const VerifyAdapter = struct {};
};

pub const StoredValue = struct {
    ptr: *anyopaque,
    type_name: []const u8,
    portable_image: ?Frame.ValueImage = null,
    clone_fn: *const fn (std.mem.Allocator, *anyopaque) anyerror!StoredValue,
    image_fn: *const fn (std.mem.Allocator, *anyopaque, ?u32, ?u64, ?u64, ValuePolicy) anyerror!Frame.ValueImage,
    destroy_fn: *const fn (std.mem.Allocator, *anyopaque) void,

    pub fn init(allocator: std.mem.Allocator, value: anytype) !@This() {
        const cloned = try cloneOwnedValue(allocator, value);
        errdefer deinitOwnedValue(allocator, cloned);
        return initOwned(allocator, cloned);
    }

    fn initOwned(allocator: std.mem.Allocator, value: anytype) !@This() {
        const Value = @TypeOf(value);
        var portable_image = Frame.ValueImage.fromValue(allocator, null, null, null, value, .native_compatible) catch |err| switch (err) {
            error.UnsupportedValueImage => null,
            else => return err,
        };
        errdefer if (portable_image) |*image| image.deinit(allocator);
        const ptr = try allocator.create(Value);
        errdefer allocator.destroy(ptr);
        ptr.* = value;
        const result = @This(){
            .ptr = @ptrCast(ptr),
            .type_name = @typeName(Value),
            .portable_image = portable_image,
            .clone_fn = struct {
                fn clone(inner_allocator: std.mem.Allocator, erased: *anyopaque) anyerror!StoredValue {
                    const typed: *Value = @ptrCast(@alignCast(erased));
                    return StoredValue.init(inner_allocator, typed.*);
                }
            }.clone,
            .image_fn = struct {
                fn image(
                    inner_allocator: std.mem.Allocator,
                    erased: *anyopaque,
                    value_table_id: ?u32,
                    boundary_value_fingerprint: ?u64,
                    codec_schema_descriptor_fingerprint: ?u64,
                    policy: ValuePolicy,
                ) anyerror!Frame.ValueImage {
                    const typed: *Value = @ptrCast(@alignCast(erased));
                    return Frame.ValueImage.fromValue(
                        inner_allocator,
                        value_table_id,
                        boundary_value_fingerprint,
                        codec_schema_descriptor_fingerprint,
                        typed.*,
                        policy,
                    );
                }
            }.image,
            .destroy_fn = struct {
                fn destroy(inner_allocator: std.mem.Allocator, erased: *anyopaque) void {
                    const typed: *Value = @ptrCast(@alignCast(erased));
                    deinitOwnedValue(inner_allocator, typed.*);
                    inner_allocator.destroy(typed);
                }
            }.destroy,
        };
        return result;
    }

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
        return self.clone_fn(allocator, self.ptr);
    }

    pub fn valueImage(
        self: @This(),
        allocator: std.mem.Allocator,
        value_table_id: ?u32,
        boundary_value_fingerprint: ?u64,
        codec_schema_descriptor_fingerprint: ?u64,
        policy: ValuePolicy,
    ) !Frame.ValueImage {
        return self.image_fn(
            allocator,
            self.ptr,
            value_table_id,
            boundary_value_fingerprint,
            codec_schema_descriptor_fingerprint,
            policy,
        );
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
        if (self.portable_image) |*image| image.deinit(allocator);
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
        world_surface_replay_scope_fingerprint: ?u64 = null,
        payload_value_table_id: ?u32 = null,
        expected_response_value_table_id: ?u32 = null,
        turn_index: ?usize = null,
        residual_site_index: ?usize = null,
        residual_site_fingerprint: ?u64 = null,
        status: ?ResponseStatus = null,
        source_run: bool = true,
        value: ?StoredValue = null,
        request_frame: ?Frame.Request = null,
        response_frame: ?Frame.Response = null,
    };

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *@This()) void {
        for (self.events.items) |*event| {
            if (event.value) |*stored| stored.deinit(self.allocator);
            if (event.request_frame) |*frame| frame.deinit(self.allocator);
            if (event.response_frame) |*frame| frame.deinit(self.allocator);
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
        cloned.request_frame = null;
        if (event.request_frame) |frame| {
            cloned.request_frame = try frame.clone(self.allocator);
        }
        errdefer if (cloned.request_frame) |*frame| frame.deinit(self.allocator);
        cloned.response_frame = null;
        if (event.response_frame) |frame| {
            cloned.response_frame = try frame.clone(self.allocator);
        }
        errdefer if (cloned.response_frame) |*frame| frame.deinit(self.allocator);
        try self.events.append(self.allocator, cloned);
    }

    fn appendOwned(self: *@This(), event: *Event) !void {
        try self.events.append(self.allocator, event.*);
        event.value = null;
        event.request_frame = null;
        event.response_frame = null;
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
            if (event.kind != .port_responded and event.kind != .frame_responded) continue;
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
            if (self.events.items[index].kind == .port_responded or self.events.items[index].kind == .frame_responded) return Error.ReplayUnusedEvent;
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
                .port_responded,
                .frame_responded,
                => {
                    if (active_start != null) {
                        active_has_port_event = true;
                        active_has_source_response = true;
                    }
                },
                .port_requested,
                .port_replayed,
                .port_rejected,
                .port_failed,
                .frame_requested,
                .frame_replayed,
                .frame_verified,
                .frame_rejected,
                .frame_failed,
                .checkpoint_recorded,
                .branch_started,
                .branch_joined,
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
                .frame_requested => result.frame_requested += 1,
                .frame_responded => result.frame_responded += 1,
                .frame_replayed => result.frame_replayed += 1,
                .frame_verified => result.frame_verified += 1,
                .frame_rejected => result.frame_rejected += 1,
                .frame_failed => result.frame_failed += 1,
                .checkpoint_recorded => result.checkpoint_recorded += 1,
                .branch_started => result.branch_started += 1,
                .branch_joined => result.branch_joined += 1,
                .run_completed => result.run_completed += 1,
                .run_failed => result.run_failed += 1,
            }
        }
        return result;
    }

    pub fn toImage(self: *const @This(), allocator: std.mem.Allocator, options: anytype) !TranscriptImage {
        const policy: ValuePolicy = if (@hasField(@TypeOf(options), "value_policy"))
            @field(options, "value_policy")
        else
            .native_compatible;
        return TranscriptImage.fromTranscript(allocator, self, policy);
    }

    pub fn fromImage(allocator: std.mem.Allocator, image: TranscriptImage) !@This() {
        var transcript = Transcript.init(allocator);
        errdefer transcript.deinit();
        for (image.events) |event| {
            try transcript.append(.{
                .kind = event.kind,
                .world_surface_fingerprint = event.world_surface_fingerprint,
                .target_certificate_fingerprint = event.target_certificate_fingerprint,
                .world_port_id = event.world_port_id,
                .request_fingerprint = event.request_fingerprint,
                .response_fingerprint = event.response_fingerprint,
                .response_kind = event.response_kind,
                .replay_key = event.replay_key,
                .world_surface_replay_scope_fingerprint = if (event.request_frame) |frame| frame.world_surface_replay_scope_fingerprint else null,
                .payload_value_table_id = if (event.request_frame) |frame| frame.payload_value_table_id else null,
                .expected_response_value_table_id = if (event.request_frame) |frame| frame.expected_response_value_table_id else null,
                .turn_index = event.turn_index,
                .residual_site_index = event.residual_site_index,
                .residual_site_fingerprint = event.residual_site_fingerprint,
                .status = event.status,
                .source_run = event.source_run,
                .request_frame = event.request_frame,
                .response_frame = event.response_frame,
            });
        }
        return transcript;
    }

    pub const Summary = struct {
        run_started: usize = 0,
        port_requested: usize = 0,
        port_responded: usize = 0,
        port_replayed: usize = 0,
        port_rejected: usize = 0,
        port_failed: usize = 0,
        frame_requested: usize = 0,
        frame_responded: usize = 0,
        frame_replayed: usize = 0,
        frame_verified: usize = 0,
        frame_rejected: usize = 0,
        frame_failed: usize = 0,
        checkpoint_recorded: usize = 0,
        branch_started: usize = 0,
        branch_joined: usize = 0,
        run_completed: usize = 0,
        run_failed: usize = 0,
    };
};

pub const Timeline = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event) = .empty,

    pub const Event = struct {
        format_version: u32 = world_timeline_event_format_version,
        fingerprint_version: u32 = world_timeline_event_fingerprint_version,
        event_fingerprint: u64,
        kind: EventKind,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        request_frame_fingerprint: ?u64 = null,
        response_frame_fingerprint: ?u64 = null,
        replay_key: ?u64 = null,
        checkpoint_fingerprint: ?u64 = null,
        branch_id: ?u64 = null,
        turn_index: usize = 0,
        status: ?ResponseStatus = null,

        pub fn init(args: struct {
            kind: EventKind,
            world_surface_fingerprint: u64,
            target_certificate_fingerprint: u64,
            request_frame_fingerprint: ?u64 = null,
            response_frame_fingerprint: ?u64 = null,
            replay_key: ?u64 = null,
            checkpoint_fingerprint: ?u64 = null,
            branch_id: ?u64 = null,
            turn_index: usize = 0,
            status: ?ResponseStatus = null,
        }) @This() {
            var event = @This(){
                .event_fingerprint = 0,
                .kind = args.kind,
                .world_surface_fingerprint = args.world_surface_fingerprint,
                .target_certificate_fingerprint = args.target_certificate_fingerprint,
                .request_frame_fingerprint = args.request_frame_fingerprint,
                .response_frame_fingerprint = args.response_frame_fingerprint,
                .replay_key = args.replay_key,
                .checkpoint_fingerprint = args.checkpoint_fingerprint,
                .branch_id = args.branch_id,
                .turn_index = args.turn_index,
                .status = args.status,
            };
            event.event_fingerprint = fingerprintTimelineEvent(event);
            return event;
        }
    };

    pub const Checkpoint = struct {
        format_version: u32 = world_timeline_checkpoint_format_version,
        fingerprint_version: u32 = world_timeline_checkpoint_fingerprint_version,
        checkpoint_fingerprint: u64,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        event_index: usize,
        turn_index: usize,
        current_request_fingerprint: ?u64 = null,
        last_response_fingerprint: ?u64 = null,
        capsule_image_fingerprint: ?u64 = null,
        transcript_prefix_fingerprint: u64,
        branch_id: u64,
        status: Status,

        pub const Status = enum {
            running,
            parked_on_port,
            completed,
            failed,
        };

        pub fn init(args: struct {
            world_surface_fingerprint: u64,
            target_certificate_fingerprint: u64,
            event_index: usize,
            turn_index: usize,
            current_request_fingerprint: ?u64 = null,
            last_response_fingerprint: ?u64 = null,
            capsule_image_fingerprint: ?u64 = null,
            transcript_prefix_fingerprint: u64,
            branch_id: u64 = 0,
            status: Status,
        }) @This() {
            var checkpoint = @This(){
                .checkpoint_fingerprint = 0,
                .world_surface_fingerprint = args.world_surface_fingerprint,
                .target_certificate_fingerprint = args.target_certificate_fingerprint,
                .event_index = args.event_index,
                .turn_index = args.turn_index,
                .current_request_fingerprint = args.current_request_fingerprint,
                .last_response_fingerprint = args.last_response_fingerprint,
                .capsule_image_fingerprint = args.capsule_image_fingerprint,
                .transcript_prefix_fingerprint = args.transcript_prefix_fingerprint,
                .branch_id = args.branch_id,
                .status = args.status,
            };
            checkpoint.checkpoint_fingerprint = fingerprintCheckpoint(checkpoint);
            return checkpoint;
        }
    };

    pub const Branch = struct {
        format_version: u32 = world_timeline_branch_format_version,
        fingerprint_version: u32 = world_timeline_branch_fingerprint_version,
        branch_id: u64,
        parent_branch_id: ?u64 = null,
        checkpoint_fingerprint: u64,
        branch_label: []const u8 = "",
        start_event_index: usize,
        final_event_index: ?usize = null,
        final_status: Checkpoint.Status = .running,
        event_count: usize = 0,
        response_count: usize = 0,

        pub fn fingerprint(self: @This()) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.timeline.branch.fingerprint");
            hashU64(&hasher, world_timeline_branch_fingerprint_version);
            hashU64(&hasher, self.branch_id);
            hashOptionalU64(&hasher, self.parent_branch_id);
            hashU64(&hasher, self.checkpoint_fingerprint);
            hashU64(&hasher, self.start_event_index);
            if (self.final_event_index) |index| {
                hashBool(&hasher, true);
                hashU64(&hasher, index);
            } else {
                hashBool(&hasher, false);
            }
            hashU64(&hasher, @intFromEnum(self.final_status));
            hashU64(&hasher, self.event_count);
            hashU64(&hasher, self.response_count);
            hashU64(&hasher, self.branch_label.len);
            hashBytes(&hasher, self.branch_label);
            return hasher.final();
        }
    };

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *@This()) void {
        self.events.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn append(self: *@This(), event: Event) !void {
        try self.events.append(self.allocator, event);
    }
};

pub const TranscriptImage = struct {
    format_version: u32 = world_transcript_image_format_version,
    fingerprint_version: u32 = world_transcript_image_fingerprint_version,
    transcript_image_fingerprint: u64,
    world_surface_fingerprint: u64,
    target_certificate_fingerprint: u64,
    events: []EventImage,
    final_status: FinalStatus,
    response_count: usize = 0,
    replay_cursor: usize = 0,
    replay_limit: ?usize = null,

    pub const FinalStatus = enum {
        running,
        completed,
        failed,
    };

    pub const EventImage = struct {
        event_fingerprint: u64,
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
        request_frame: ?Frame.Request = null,
        response_frame: ?Frame.Response = null,

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.request_frame) |*frame| frame.deinit(allocator);
            if (self.response_frame) |*frame| frame.deinit(allocator);
            self.* = undefined;
        }
    };

    pub fn fromTranscript(allocator: std.mem.Allocator, transcript: *const Transcript, policy: ValuePolicy) !@This() {
        const events = try allocator.alloc(EventImage, transcript.events.items.len);
        errdefer allocator.free(events);
        var initialized: usize = 0;
        errdefer {
            for (events[0..initialized]) |*event| event.deinit(allocator);
        }
        var response_count: usize = 0;
        for (transcript.events.items, 0..) |event, index| {
            events[index] = try eventImageFromTranscriptEvent(allocator, event, policy);
            initialized += 1;
            if (events[index].response_frame != null) response_count += 1;
        }
        var image = @This(){
            .transcript_image_fingerprint = 0,
            .world_surface_fingerprint = if (events.len > 0) events[0].world_surface_fingerprint else 0,
            .target_certificate_fingerprint = if (events.len > 0) events[0].target_certificate_fingerprint else 0,
            .events = events,
            .final_status = finalStatusFromEvents(events),
            .response_count = response_count,
        };
        image.transcript_image_fingerprint = fingerprintTranscriptImage(image);
        return image;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (self.events) |*event| event.deinit(allocator);
        allocator.free(self.events);
        self.* = undefined;
    }

    pub fn resetReplay(self: *@This()) void {
        self.replay_cursor = 0;
        self.replay_limit = null;
    }

    pub fn validateReplayRun(self: *@This(), expected_world_surface_fingerprint: u64, expected_target_certificate_fingerprint: u64) !void {
        if (self.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
        if (self.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
        var active_start: ?usize = null;
        var selected_start: ?usize = null;
        var selected_limit: ?usize = null;
        var active_is_source_run = false;
        var active_has_port_event = false;
        var active_has_source_response = false;
        var latest_run_failed = false;
        for (self.events, 0..) |event, index| {
            switch (event.kind) {
                .run_started => {
                    if (active_start != null) return error.ReplayMissing;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
                    active_start = index;
                    active_is_source_run = event.source_run;
                    active_has_port_event = false;
                    active_has_source_response = false;
                    latest_run_failed = true;
                },
                .run_completed => {
                    const start = active_start orelse continue;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
                    if (active_is_source_run and (!active_has_port_event or active_has_source_response)) {
                        selected_start = start;
                        selected_limit = index;
                    }
                    active_start = null;
                    latest_run_failed = false;
                },
                .run_failed => {
                    if (active_start == null) continue;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
                    const failed_source_run = active_is_source_run;
                    active_start = null;
                    active_is_source_run = false;
                    if (failed_source_run) {
                        selected_start = null;
                        selected_limit = null;
                    }
                    latest_run_failed = failed_source_run;
                },
                .port_responded,
                .frame_responded,
                => {
                    if (active_start != null) {
                        active_has_port_event = true;
                        active_has_source_response = true;
                    }
                },
                .port_requested,
                .port_replayed,
                .port_rejected,
                .port_failed,
                .frame_requested,
                .frame_replayed,
                .frame_verified,
                .frame_rejected,
                .frame_failed,
                .checkpoint_recorded,
                .branch_started,
                .branch_joined,
                => {
                    if (active_start != null) active_has_port_event = true;
                },
            }
        }
        if (active_start != null or latest_run_failed) return error.ReplayMissing;
        self.replay_cursor = (selected_start orelse return error.ReplayMissing) + 1;
        self.replay_limit = selected_limit orelse return error.ReplayMissing;
    }

    pub fn nextResponse(
        self: *@This(),
        key: ReplayKeySeed,
        expected_target_certificate_fingerprint: u64,
        expected_response_kind: ResponseKind,
    ) !*const Frame.Response {
        const replay_limit = self.replay_limit orelse self.events.len;
        while (self.replay_cursor < replay_limit) : (self.replay_cursor += 1) {
            const index = self.replay_cursor;
            const event = &self.events[index];
            if (!eventKindIsSourceResponse(event.kind)) continue;
            const frame = if (event.response_frame) |*response_frame| response_frame else continue;
            if (frame.status != .responded) continue;
            if (frame.world_surface_fingerprint != key.world_surface_fingerprint) return error.ReplaySurfaceMismatch;
            if (frame.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
            if (frame.world_port_id != key.world_port_id) return error.ReplayPortMismatch;
            if (frame.request_fingerprint != key.request_fingerprint) return error.ReplayRequestFingerprintMismatch;
            if (frame.response_kind != expected_response_kind) return error.ReplayResponseKindMismatch;
            const expected_key = key.withResponse(frame.response_fingerprint).fingerprint();
            if (frame.replay_key != expected_key) return error.ReplayMissing;
            self.replay_cursor = index + 1;
            return frame;
        }
        return error.ReplayMissing;
    }

    pub fn assertReplayComplete(self: *const @This()) !void {
        const replay_limit = self.replay_limit orelse self.events.len;
        var index = self.replay_cursor;
        while (index < replay_limit) : (index += 1) {
            if (eventKindIsSourceResponse(self.events[index].kind) and self.events[index].response_frame != null) return error.ReplayUnusedEvent;
        }
    }

    pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        try writeU32(&out, allocator, self.format_version);
        try writeU32(&out, allocator, self.fingerprint_version);
        try writeU64(&out, allocator, self.transcript_image_fingerprint);
        try writeU64(&out, allocator, self.world_surface_fingerprint);
        try writeU64(&out, allocator, self.target_certificate_fingerprint);
        try writeU8(&out, allocator, @intFromEnum(self.final_status));
        try writeU64(&out, allocator, self.response_count);
        try writeU64(&out, allocator, self.events.len);
        for (self.events) |event| try encodeTranscriptEventImage(&out, allocator, event);
        return out.toOwnedSlice(allocator);
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
        var cursor: usize = 0;
        const format_version = try readU32(bytes, &cursor);
        if (format_version != world_transcript_image_format_version) return error.InvalidFrameEncoding;
        const fingerprint_version = try readU32(bytes, &cursor);
        if (fingerprint_version != world_transcript_image_fingerprint_version) return error.InvalidFrameEncoding;
        const transcript_image_fingerprint = try readU64(bytes, &cursor);
        const world_surface_fingerprint = try readU64(bytes, &cursor);
        const target_certificate_fingerprint = try readU64(bytes, &cursor);
        const final_status = try enumFromByte(FinalStatus, try readU8(bytes, &cursor));
        const response_count = try readU64AsUsize(bytes, &cursor);
        const event_count = try readU64AsUsize(bytes, &cursor);
        if (event_count > bytes.len - cursor) return error.InvalidFrameEncoding;
        const events = try allocator.alloc(EventImage, event_count);
        errdefer allocator.free(events);
        var initialized: usize = 0;
        errdefer for (events[0..initialized]) |*event| event.deinit(allocator);
        for (events) |*event| {
            event.* = try decodeTranscriptEventImage(allocator, bytes, &cursor);
            initialized += 1;
        }
        if (cursor != bytes.len) return error.InvalidFrameEncoding;
        var decoded_response_count: usize = 0;
        for (events) |event| {
            if (event.response_frame != null) decoded_response_count += 1;
        }
        if (decoded_response_count != response_count) return error.InvalidFrameEncoding;
        const image = @This(){
            .transcript_image_fingerprint = transcript_image_fingerprint,
            .world_surface_fingerprint = world_surface_fingerprint,
            .target_certificate_fingerprint = target_certificate_fingerprint,
            .events = events,
            .final_status = final_status,
            .response_count = response_count,
        };
        if (fingerprintTranscriptImage(image) != transcript_image_fingerprint) return error.InvalidFrameEncoding;
        return image;
    }
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

pub const AuditImage = struct {
    format_version: u32 = world_audit_image_format_version,
    fingerprint_version: u32 = world_audit_image_fingerprint_version,
    audit_fingerprint: u64,
    world_surface_fingerprint: u64,
    target_certificate_fingerprint: u64,
    mode: Mode,
    final_status: AuditReport.Status,
    request_frame_count: usize = 0,
    response_frame_count: usize = 0,
    replayed_frame_count: usize = 0,
    verified_frame_count: usize = 0,
    failed_frame_count: usize = 0,
    branch_count: usize = 0,
    checkpoint_count: usize = 0,
    missing_portable_value_image_count: usize = 0,
    native_only_value_count: usize = 0,
    transcript_image_fingerprint: ?u64 = null,

    pub fn fromReport(report: AuditReport, transcript_image: ?TranscriptImage) @This() {
        var image = @This(){
            .audit_fingerprint = 0,
            .world_surface_fingerprint = report.world_surface_fingerprint,
            .target_certificate_fingerprint = report.target_certificate_fingerprint,
            .mode = report.mode,
            .final_status = report.final_status,
            .request_frame_count = report.port_request_count,
            .response_frame_count = report.fresh_response_count + report.replayed_response_count,
            .replayed_frame_count = report.replayed_response_count,
            .failed_frame_count = report.failed_count,
            .transcript_image_fingerprint = if (transcript_image) |image_source| image_source.transcript_image_fingerprint else null,
        };
        if (transcript_image) |image_source| {
            for (image_source.events) |event| {
                if (event.kind == .frame_verified) image.verified_frame_count += 1;
                if (event.kind == .checkpoint_recorded) image.checkpoint_count += 1;
                if (event.kind == .branch_started) image.branch_count += 1;
                if (event.response_frame != null and event.response_frame.?.response_image == null) {
                    image.missing_portable_value_image_count += 1;
                }
            }
        }
        image.audit_fingerprint = fingerprintAuditImage(image);
        return image;
    }
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
                frame_step_request: bool = false,
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
                    if (modeConsumesTranscript(effective) and
                        !@hasField(Options, "transcript") and
                        !@hasField(Options, "transcript_image"))
                    {
                        return Error.ReplayMissing;
                    }
                    var session = try Program.Session.startWithArgs(runtime, Program.Handlers{}, args);
                    errdefer session.deinit();
                    if (@hasField(Options, "transcript_image") and modeConsumesTranscript(effective)) {
                        @field(options, "transcript_image").resetReplay();
                        try @field(options, "transcript_image").validateReplayRun(
                            Target.WorldSurface.surface_fingerprint,
                            Target.Certificate.certificate_fingerprint,
                        );
                    }
                    if (@hasField(Options, "transcript")) {
                        if (modeConsumesTranscript(effective) and !@hasField(Options, "transcript_image")) {
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
                            if (modeConsumesTranscript(self.effective_mode) and @hasField(Options, "transcript") and !@hasField(Options, "transcript_image")) {
                                @field(self.options, "transcript").assertReplayComplete() catch |err| {
                                    self.audit.replay_mismatch_count += 1;
                                    try self.markRunFailed();
                                    return err;
                                };
                            }
                            if (modeConsumesTranscript(self.effective_mode) and @hasField(Options, "transcript_image")) {
                                @field(self.options, "transcript_image").assertReplayComplete() catch |err| {
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
                                if (!self.frame_step_request) {
                                    try appendPortEvent(Target, self.options, .port_requested, world_port_id, trace, null, null, null, null, null);
                                }
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
                                    try appendPortEvent(Target, self.options, .port_failed, world_port_id, trace, null, null, null, null, null);
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

                pub const FrameStep = union(enum) {
                    done: Value,
                    port_request: Frame.Request,
                    failed,
                };

                pub fn nextFrame(self: *Self) !FrameStep {
                    self.frame_step_request = true;
                    defer self.frame_step_request = false;
                    const step = try self.next();
                    return switch (step) {
                        .done => |value| .{ .done = value },
                        .failed => .failed,
                        .parked => error.HandlerPending,
                        .port_required => .{ .port_request = try self.pendingRequestFrame(true) },
                    };
                }

                pub fn resumeFrame(self: *Self, response_frame: Frame.Response) !void {
                    if (response_frame.status == .pending) return error.HandlerPending;
                    const request = self.pending_request orelse return error.UnknownResidualSite;
                    const world_port_id = self.pending_port_id orelse return error.UnknownWorldPort;
                    var frame = try self.pendingRequestFrame(false);
                    defer frame.deinit(self.allocator);
                    if (response_frame.world_surface_fingerprint != frame.world_surface_fingerprint) return error.FrameSurfaceMismatch;
                    if (response_frame.target_certificate_fingerprint != frame.target_certificate_fingerprint) return error.FrameTargetCertificateMismatch;
                    if (response_frame.world_port_id != world_port_id) return error.FramePortMismatch;
                    if (response_frame.request_fingerprint != frame.request_fingerprint) return error.FrameRequestFingerprintMismatch;
                    if (response_frame.status == .responded and response_frame.response_value_table_id != frame.expected_response_value_table_id) return error.FrameValueTableMismatch;
                    if (response_frame.replay_key != frame.replay_key_seed.withResponse(response_frame.response_fingerprint).fingerprint()) return error.ReplayMissing;
                    if (response_frame.status == .rejected) {
                        self.audit.rejected_count += 1;
                        try appendPortEvent(Target, self.options, .frame_rejected, world_port_id, request.trace(), response_frame.response_fingerprint, response_frame.response_kind, null, null, response_frame);
                        try self.markRunFailed();
                        return error.HandlerRejected;
                    }
                    if (response_frame.status == .failed) {
                        self.audit.failed_count += 1;
                        try appendPortEvent(Target, self.options, .frame_failed, world_port_id, request.trace(), response_frame.response_fingerprint, response_frame.response_kind, null, null, response_frame);
                        try self.markRunFailed();
                        return error.HandlerFailed;
                    }
                    switch (world_port_id) {
                        inline 0...Target.WorldPortTable.entries.len - 1 => |id| {
                            const Handler = comptime handlerForWorldPortId(Target, Config, @intCast(id));
                            if (Handler) |Decl| {
                                try self.resumeFrameDecl(Decl, request, response_frame);
                                self.pending_request = null;
                                self.pending_port_id = null;
                                return;
                            }
                            return self.markMissingHandler(world_port_id, request.trace());
                        },
                        else => return error.UnknownWorldPort,
                    }
                }

                fn pendingRequestFrame(self: *Self, record_event: bool) !Frame.Request {
                    const request = self.pending_request orelse return error.UnknownResidualSite;
                    const world_port_id = self.pending_port_id orelse return error.UnknownWorldPort;
                    if (Target.WorldPortTable.entries.len != 0) {
                        switch (world_port_id) {
                            inline 0...Target.WorldPortTable.entries.len - 1 => |id| {
                                const Handler = comptime handlerForWorldPortId(Target, Config, @intCast(id));
                                if (Handler) |Decl| return try self.pendingRequestFrameDecl(Decl, request, world_port_id, record_event);
                            },
                            else => {},
                        }
                    }
                    const trace = request.trace();
                    var frame = Frame.Request.init(.{
                        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                        .world_surface_replay_scope_fingerprint = Target.WorldSurface.replayScopeRef().fingerprint,
                        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
                        .world_port_id = world_port_id,
                        .residual_site_index = trace.operation_site_index,
                        .residual_site_fingerprint = trace.operation_site_fingerprint,
                        .request_fingerprint = trace.fingerprint,
                        .turn_index = trace.turn_index,
                        .payload_value_table_id = valueIdForRuntime(Target, world_port_id, .payload),
                        .expected_response_value_table_id = valueIdForRuntime(Target, world_port_id, .@"resume"),
                    });
                    errdefer frame.deinit(self.allocator);
                    if (record_event and self.effective_mode == .fresh) {
                        try appendPortEvent(Target, self.options, .frame_requested, world_port_id, trace, null, null, null, frame, null);
                    }
                    return frame;
                }

                fn pendingRequestFrameDecl(self: *Self, comptime Decl: type, request: Request, world_port_id: u32, record_event: bool) !Frame.Request {
                    const typed_request = try request.as(Decl.SiteType);
                    const payload = try typed_request.payload();
                    var payload_image: ?Frame.ValueImage = try Frame.ValueImage.fromValue(
                        self.allocator,
                        valueIdForRuntime(Target, world_port_id, .payload),
                        null,
                        null,
                        payload,
                        .portable,
                    );
                    errdefer if (payload_image) |*image| image.deinit(self.allocator);
                    const trace = request.trace();
                    var frame = Frame.Request.init(.{
                        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                        .world_surface_replay_scope_fingerprint = Target.WorldSurface.replayScopeRef().fingerprint,
                        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
                        .world_port_id = world_port_id,
                        .residual_site_index = trace.operation_site_index,
                        .residual_site_fingerprint = trace.operation_site_fingerprint,
                        .request_fingerprint = trace.fingerprint,
                        .turn_index = trace.turn_index,
                        .payload_value_table_id = valueIdForRuntime(Target, world_port_id, .payload),
                        .expected_response_value_table_id = valueIdForRuntime(Target, world_port_id, .@"resume"),
                        .payload_image = payload_image,
                    });
                    payload_image = null;
                    errdefer frame.deinit(self.allocator);
                    if (record_event and self.effective_mode == .fresh) {
                        try appendPortEvent(Target, self.options, .frame_requested, world_port_id, trace, null, null, null, frame, null);
                    }
                    return frame;
                }

                fn resumeFrameDecl(self: *Self, comptime Decl: type, request: Request, response_frame: Frame.Response) !void {
                    const typed_request = try request.as(Decl.SiteType);
                    if (response_frame.response_kind != .@"resume") return error.VerifyResponseKindMismatch;
                    const value = try response_frame.decodeValue(self.allocator, Decl.Response);
                    defer deinitOwnedValue(self.allocator, value);
                    const response_trace = try typed_request.responseTrace(.@"resume", value);
                    if (response_trace.fingerprint != response_frame.response_fingerprint) return error.VerifyResponseFingerprintMismatch;
                    var stored: ?StoredValue = null;
                    if (comptime @hasField(Options, "transcript")) {
                        stored = try StoredValue.init(@field(self.options, "transcript").allocator, value);
                    }
                    defer if (stored) |*owned| {
                        if (comptime @hasField(Options, "transcript")) {
                            owned.deinit(@field(self.options, "transcript").allocator);
                        }
                    };
                    var run_value = try StoredValue.init(self.allocator, value);
                    var run_value_owned = true;
                    errdefer if (run_value_owned) run_value.deinit(self.allocator);
                    try self.retained_values.append(self.allocator, run_value);
                    run_value_owned = false;
                    var retained_committed = false;
                    errdefer if (!retained_committed) {
                        var retained = self.retained_values.pop().?;
                        retained.deinit(self.allocator);
                    };
                    const retained_value = try self.retained_values.items[self.retained_values.items.len - 1].borrow(Decl.Response);
                    try appendPortEvent(Target, self.options, .frame_responded, Decl.world_port_id, request.trace(), response_trace.fingerprint, response_frame.response_kind, stored, null, response_frame);
                    stored = null;
                    self.audit.fresh_response_count += 1;
                    try self.session.resumeTyped(typed_request, retained_value);
                    retained_committed = true;
                }

                fn markMissingHandler(self: *Self, world_port_id: u32, trace: anytype) !void {
                    self.audit.missing_handler_count += 1;
                    self.audit.failed_count += 1;
                    try appendPortEvent(Target, self.options, .port_failed, world_port_id, trace, null, null, null, null, null);
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
                        null,
                        null,
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
                    if (comptime @hasField(Options, "transcript_image")) {
                        const image = @field(self.options, "transcript_image");
                        const frame = image.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                            self.audit.replay_mismatch_count += 1;
                            return err;
                        };
                        if (frame.response_value_table_id != valueIdForRuntime(Target, Decl.world_port_id, .@"resume")) return error.FrameValueTableMismatch;
                        const value = try frame.decodeValue(self.allocator, Decl.Response);
                        var value_owned = true;
                        errdefer if (value_owned) deinitOwnedValue(self.allocator, value);
                        const response_trace = try typed_request.responseTrace(.@"resume", value);
                        if (response_trace.fingerprint != frame.response_fingerprint) {
                            self.audit.replay_mismatch_count += 1;
                            return error.VerifyResponseFingerprintMismatch;
                        }
                        try appendPortEvent(Target, self.options, .frame_replayed, Decl.world_port_id, trace, response_trace.fingerprint, .@"resume", null, null, frame.*);
                        self.audit.replayed_response_count += 1;
                        var run_value = try StoredValue.initOwned(self.allocator, value);
                        value_owned = false;
                        var run_value_owned = true;
                        errdefer if (run_value_owned) run_value.deinit(self.allocator);
                        try self.retained_values.append(self.allocator, run_value);
                        run_value_owned = false;
                        return self.retained_values.items[self.retained_values.items.len - 1].borrow(Decl.Response);
                    }
                    if (!@hasField(Options, "transcript")) return Error.ReplayMissing;
                    const transcript = @field(self.options, "transcript");
                    const event = transcript.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                        self.audit.replay_mismatch_count += 1;
                        return err;
                    };
                    const value = if (event.value) |stored|
                        try stored.as(self.allocator, Decl.Response)
                    else if (event.response_frame) |frame|
                        try frame.decodeValue(self.allocator, Decl.Response)
                    else
                        return Error.ReplayMissing;
                    var value_owned = true;
                    errdefer if (value_owned) deinitOwnedValue(self.allocator, value);
                    const response_trace = try typed_request.responseTrace(.@"resume", value);
                    if (response_trace.fingerprint != (event.response_fingerprint orelse return Error.ReplayMissing)) {
                        self.audit.replay_mismatch_count += 1;
                        return Error.ReplayResponseKindMismatch;
                    }
                    try appendPortEvent(Target, self.options, .port_replayed, Decl.world_port_id, trace, response_trace.fingerprint, .@"resume", null, null, if (event.response_frame) |frame| frame else null);
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
                    var expected_response_fingerprint: u64 = undefined;
                    var expected_value_image_fingerprint: ?u64 = null;
                    var expected_value_table_id: ?u32 = null;
                    var expected_boundary_value_fingerprint: ?u64 = null;
                    var expected_codec_schema_descriptor_fingerprint: ?u64 = null;
                    if (comptime @hasField(Options, "transcript_image")) {
                        const image = @field(self.options, "transcript_image");
                        const frame = image.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                            self.audit.replay_mismatch_count += 1;
                            return err;
                        };
                        expected_response_fingerprint = frame.response_fingerprint;
                        if (frame.response_value_table_id != valueIdForRuntime(Target, Decl.world_port_id, .@"resume")) return error.FrameValueTableMismatch;
                        if (frame.response_image) |response_image| {
                            expected_value_image_fingerprint = response_image.value_image_fingerprint;
                            expected_value_table_id = response_image.value_table_id;
                            expected_boundary_value_fingerprint = response_image.boundary_value_fingerprint;
                            expected_codec_schema_descriptor_fingerprint = response_image.codec_schema_descriptor_fingerprint;
                        } else {
                            expected_value_image_fingerprint = frame.response_value_fingerprint;
                        }
                        const replay_value = try frame.decodeValue(self.allocator, Decl.Response);
                        defer deinitOwnedValue(self.allocator, replay_value);
                        const replay_trace = try typed_request.responseTrace(.@"resume", replay_value);
                        if (replay_trace.fingerprint != expected_response_fingerprint) {
                            self.audit.replay_mismatch_count += 1;
                            return error.VerifyDivergence;
                        }
                    } else {
                        if (!@hasField(Options, "transcript")) return Error.ReplayMissing;
                        const transcript = @field(self.options, "transcript");
                        const event = transcript.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                            self.audit.replay_mismatch_count += 1;
                            return err;
                        };
                        expected_response_fingerprint = event.response_fingerprint orelse return Error.ReplayMissing;
                        const replay_value = if (event.value) |stored|
                            stored.as(self.allocator, Decl.Response) catch |err| {
                                self.audit.replay_mismatch_count += 1;
                                return err;
                            }
                        else if (event.response_frame) |frame| value: {
                            if (frame.response_value_table_id != valueIdForRuntime(Target, Decl.world_port_id, .@"resume")) return error.FrameValueTableMismatch;
                            if (frame.response_image) |response_image| {
                                expected_value_image_fingerprint = response_image.value_image_fingerprint;
                                expected_value_table_id = response_image.value_table_id;
                                expected_boundary_value_fingerprint = response_image.boundary_value_fingerprint;
                                expected_codec_schema_descriptor_fingerprint = response_image.codec_schema_descriptor_fingerprint;
                            } else {
                                expected_value_image_fingerprint = frame.response_value_fingerprint;
                            }
                            break :value frame.decodeValue(self.allocator, Decl.Response) catch |err| {
                                self.audit.replay_mismatch_count += 1;
                                return err;
                            };
                        } else return Error.ReplayMissing;
                        defer deinitOwnedValue(self.allocator, replay_value);
                        const replay_trace = try typed_request.responseTrace(.@"resume", replay_value);
                        if (replay_trace.fingerprint != expected_response_fingerprint) {
                            self.audit.replay_mismatch_count += 1;
                            return Error.VerifyDivergence;
                        }
                    }
                    self.audit.replayed_response_count += 1;
                    const fresh = try callHandler(Decl, @field(self.options, "ctx"), request);
                    defer Decl.response_deinit(@field(self.options, "ctx"), fresh);
                    const response_trace = try typed_request.responseTrace(.@"resume", fresh);
                    if (response_trace.fingerprint != expected_response_fingerprint) {
                        self.audit.replay_mismatch_count += 1;
                        return Error.VerifyDivergence;
                    }
                    if (expected_value_image_fingerprint) |expected_image_fingerprint| {
                        var fresh_image = try Frame.ValueImage.fromValue(
                            self.allocator,
                            expected_value_table_id,
                            expected_boundary_value_fingerprint,
                            expected_codec_schema_descriptor_fingerprint,
                            fresh,
                            .portable,
                        );
                        defer fresh_image.deinit(self.allocator);
                        if (fresh_image.value_image_fingerprint != expected_image_fingerprint) return error.VerifyValueImageMismatch;
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

fn valueIdForRuntime(comptime Target: type, world_port_id: u32, comptime kind: anytype) ?u32 {
    for (Target.WorldValueTable.entries) |entry| {
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

fn eventKindIsSourceResponse(kind: EventKind) bool {
    return kind == .port_responded or kind == .frame_responded;
}

fn eventKindAllowsResponseFrame(kind: EventKind) bool {
    return switch (kind) {
        .port_responded,
        .port_replayed,
        .port_rejected,
        .port_failed,
        .frame_responded,
        .frame_replayed,
        .frame_rejected,
        .frame_failed,
        => true,
        else => false,
    };
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
    request_frame: ?Frame.Request,
    response_frame: ?Frame.Response,
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
        .world_surface_replay_scope_fingerprint = Target.WorldSurface.replayScopeRef().fingerprint,
        .payload_value_table_id = valueIdForRuntime(Target, world_port_id, .payload),
        .expected_response_value_table_id = valueIdForRuntime(Target, world_port_id, .@"resume"),
        .turn_index = trace.turn_index,
        .residual_site_index = trace.operation_site_index,
        .residual_site_fingerprint = trace.operation_site_fingerprint,
        .status = if (kind == .port_responded) .responded else null,
        .value = value,
        .request_frame = if (request_frame) |frame| try frame.clone(transcript.allocator) else null,
        .response_frame = if (response_frame) |frame| try frame.clone(transcript.allocator) else null,
    };
    errdefer if (event.request_frame) |*frame| frame.deinit(transcript.allocator);
    errdefer if (event.response_frame) |*frame| frame.deinit(transcript.allocator);
    try transcript.appendOwned(&event);
}

fn eventImageFromTranscriptEvent(allocator: std.mem.Allocator, event: Transcript.Event, policy: ValuePolicy) !TranscriptImage.EventImage {
    var request_frame: ?Frame.Request = if (event.request_frame) |frame|
        try frame.clone(allocator)
    else
        null;
    if (request_frame == null) {
        if (event.world_port_id) |world_port_id| {
            if (event.request_fingerprint) |request_fingerprint| {
                if (event.residual_site_index != null and event.residual_site_fingerprint != null and event.turn_index != null) {
                    request_frame = Frame.Request.init(.{
                        .world_surface_fingerprint = event.world_surface_fingerprint,
                        .world_surface_replay_scope_fingerprint = event.world_surface_replay_scope_fingerprint,
                        .target_certificate_fingerprint = event.target_certificate_fingerprint,
                        .world_port_id = world_port_id,
                        .residual_site_index = event.residual_site_index.?,
                        .residual_site_fingerprint = event.residual_site_fingerprint.?,
                        .request_fingerprint = request_fingerprint,
                        .turn_index = event.turn_index.?,
                        .payload_value_table_id = event.payload_value_table_id,
                        .expected_response_value_table_id = event.expected_response_value_table_id,
                    });
                }
            }
        }
    }
    errdefer if (request_frame) |*frame| frame.deinit(allocator);

    var response_frame: ?Frame.Response = if (event.response_frame) |frame|
        try frame.clone(allocator)
    else
        null;
    const response_status = event.status orelse if (event.kind == .port_rejected or event.kind == .frame_rejected)
        ResponseStatus.rejected
    else if (event.kind == .port_failed or event.kind == .frame_failed)
        ResponseStatus.failed
    else
        null;
    if (response_frame) |frame| {
        if (frame.status == .responded and frame.response_image == null) {
            if (policy.require_response_images_for_replay) return error.MissingValueImage;
            if (policy.require_portable_values and !policy.allow_native_only_values) return error.NativeOnlyValue;
        }
    }
    const source_response_event = switch (event.kind) {
        .port_responded,
        .frame_responded,
        .port_rejected,
        .frame_rejected,
        .port_failed,
        .frame_failed,
        => true,
        else => false,
    };
    if (response_frame == null and source_response_event and event.world_port_id != null and event.request_fingerprint != null and event.response_fingerprint != null and event.response_kind != null and event.replay_key != null) {
        const frame_status = response_status orelse .responded;
        var response_image: ?Frame.ValueImage = null;
        if (event.value) |stored| {
            response_image = try stored.valueImage(
                allocator,
                event.expected_response_value_table_id,
                event.response_fingerprint,
                null,
                policy,
            );
        }
        errdefer if (response_image) |*image| image.deinit(allocator);
        if (frame_status == .responded) {
            if (response_image == null and policy.require_response_images_for_replay) return error.MissingValueImage;
            if (response_image == null and policy.require_portable_values and !policy.allow_native_only_values) return error.NativeOnlyValue;
        }
        response_frame = Frame.Response.init(.{
            .world_surface_fingerprint = event.world_surface_fingerprint,
            .target_certificate_fingerprint = event.target_certificate_fingerprint,
            .world_port_id = event.world_port_id.?,
            .request_fingerprint = event.request_fingerprint.?,
            .response_kind = event.response_kind.?,
            .response_value_table_id = event.expected_response_value_table_id,
            .response_fingerprint = event.response_fingerprint.?,
            .response_image = response_image,
            .replay_key = event.replay_key.?,
            .status = frame_status,
        });
        response_image = null;
    }
    errdefer if (response_frame) |*frame| frame.deinit(allocator);

    var image = TranscriptImage.EventImage{
        .event_fingerprint = 0,
        .kind = event.kind,
        .world_surface_fingerprint = event.world_surface_fingerprint,
        .target_certificate_fingerprint = event.target_certificate_fingerprint,
        .world_port_id = event.world_port_id,
        .request_fingerprint = event.request_fingerprint,
        .response_fingerprint = event.response_fingerprint,
        .response_kind = event.response_kind,
        .replay_key = event.replay_key,
        .turn_index = event.turn_index,
        .residual_site_index = event.residual_site_index,
        .residual_site_fingerprint = event.residual_site_fingerprint,
        .status = response_status,
        .source_run = event.source_run,
        .request_frame = request_frame,
        .response_frame = response_frame,
    };
    image.event_fingerprint = fingerprintTranscriptEventImage(image);
    return image;
}

fn finalStatusFromEvents(events: []const TranscriptImage.EventImage) TranscriptImage.FinalStatus {
    var status: TranscriptImage.FinalStatus = .running;
    for (events) |event| {
        switch (event.kind) {
            .run_completed => status = .completed,
            .run_failed => status = .failed,
            else => {},
        }
    }
    return status;
}

fn encodeTranscriptEventImage(out: *std.ArrayList(u8), allocator: std.mem.Allocator, event: TranscriptImage.EventImage) !void {
    try writeU64(out, allocator, event.event_fingerprint);
    try writeU8(out, allocator, @intFromEnum(event.kind));
    try writeU64(out, allocator, event.world_surface_fingerprint);
    try writeU64(out, allocator, event.target_certificate_fingerprint);
    try writeOptionalU32(out, allocator, event.world_port_id);
    try writeOptionalU64(out, allocator, event.request_fingerprint);
    try writeOptionalU64(out, allocator, event.response_fingerprint);
    if (event.response_kind) |kind| {
        try writeBool(out, allocator, true);
        try writeU8(out, allocator, @intFromEnum(kind));
    } else {
        try writeBool(out, allocator, false);
    }
    try writeOptionalU64(out, allocator, event.replay_key);
    try writeOptionalU64(out, allocator, event.turn_index);
    try writeOptionalU64(out, allocator, event.residual_site_index);
    try writeOptionalU64(out, allocator, event.residual_site_fingerprint);
    if (event.status) |status| {
        try writeBool(out, allocator, true);
        try writeU8(out, allocator, @intFromEnum(status));
    } else {
        try writeBool(out, allocator, false);
    }
    try writeBool(out, allocator, event.source_run);
    if (event.request_frame) |frame| {
        try writeBool(out, allocator, true);
        const encoded = try frame.encode(allocator);
        defer allocator.free(encoded);
        try writeBytes(out, allocator, encoded);
    } else {
        try writeBool(out, allocator, false);
    }
    if (event.response_frame) |frame| {
        try writeBool(out, allocator, true);
        const encoded = try frame.encode(allocator);
        defer allocator.free(encoded);
        try writeBytes(out, allocator, encoded);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn decodeTranscriptEventImage(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !TranscriptImage.EventImage {
    var event = TranscriptImage.EventImage{
        .event_fingerprint = try readU64(bytes, cursor),
        .kind = try enumFromByte(EventKind, try readU8(bytes, cursor)),
        .world_surface_fingerprint = try readU64(bytes, cursor),
        .target_certificate_fingerprint = try readU64(bytes, cursor),
        .world_port_id = try readOptionalU32(bytes, cursor),
        .request_fingerprint = try readOptionalU64(bytes, cursor),
        .response_fingerprint = try readOptionalU64(bytes, cursor),
        .response_kind = if (try readBool(bytes, cursor)) try enumFromByte(ResponseKind, try readU8(bytes, cursor)) else null,
        .replay_key = try readOptionalU64(bytes, cursor),
        .turn_index = try readOptionalUsize(bytes, cursor),
        .residual_site_index = try readOptionalUsize(bytes, cursor),
        .residual_site_fingerprint = try readOptionalU64(bytes, cursor),
        .status = if (try readBool(bytes, cursor)) try enumFromByte(ResponseStatus, try readU8(bytes, cursor)) else null,
        .source_run = try readBool(bytes, cursor),
        .request_frame = null,
        .response_frame = null,
    };
    errdefer event.deinit(allocator);
    if (try readBool(bytes, cursor)) {
        const encoded = try readBytesOwned(allocator, bytes, cursor);
        defer allocator.free(encoded);
        event.request_frame = try Frame.Request.decode(allocator, encoded);
    }
    if (try readBool(bytes, cursor)) {
        const encoded = try readBytesOwned(allocator, bytes, cursor);
        defer allocator.free(encoded);
        event.response_frame = try Frame.Response.decode(allocator, encoded);
    }
    if (event.response_frame != null and !eventKindAllowsResponseFrame(event.kind)) return error.InvalidFrameEncoding;
    if (fingerprintTranscriptEventImage(event) != event.event_fingerprint) return error.InvalidFrameEncoding;
    return event;
}

fn fingerprintValueImage(
    value_table_id: ?u32,
    boundary_value_fingerprint: ?u64,
    codec_schema_descriptor_fingerprint: ?u64,
    bytes: []const u8,
) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.frame.value_image.fingerprint");
    hashU64(&hasher, world_frame_value_image_fingerprint_version);
    hashOptionalU32(&hasher, value_table_id);
    hashOptionalU64(&hasher, boundary_value_fingerprint);
    hashOptionalU64(&hasher, codec_schema_descriptor_fingerprint);
    hashU64(&hasher, bytes.len);
    hashBytes(&hasher, bytes);
    return hasher.final();
}

fn fingerprintTranscriptEventImage(event: TranscriptImage.EventImage) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.transcript.event_image.fingerprint");
    hashU64(&hasher, world_timeline_event_fingerprint_version);
    hashU64(&hasher, @intFromEnum(event.kind));
    hashU64(&hasher, event.world_surface_fingerprint);
    hashU64(&hasher, event.target_certificate_fingerprint);
    hashOptionalU32(&hasher, event.world_port_id);
    hashOptionalU64(&hasher, event.request_fingerprint);
    hashOptionalU64(&hasher, event.response_fingerprint);
    if (event.response_kind) |kind| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(kind));
    } else {
        hashBool(&hasher, false);
    }
    hashOptionalU64(&hasher, event.replay_key);
    if (event.turn_index) |turn| {
        hashBool(&hasher, true);
        hashU64(&hasher, turn);
    } else {
        hashBool(&hasher, false);
    }
    if (event.residual_site_index) |site| {
        hashBool(&hasher, true);
        hashU64(&hasher, site);
    } else {
        hashBool(&hasher, false);
    }
    hashOptionalU64(&hasher, event.residual_site_fingerprint);
    if (event.status) |status| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(status));
    } else {
        hashBool(&hasher, false);
    }
    hashBool(&hasher, event.source_run);
    if (event.request_frame) |frame| {
        hashBool(&hasher, true);
        hashU64(&hasher, frame.frame_fingerprint);
    } else {
        hashBool(&hasher, false);
    }
    if (event.response_frame) |frame| {
        hashBool(&hasher, true);
        hashU64(&hasher, frame.frame_fingerprint);
    } else {
        hashBool(&hasher, false);
    }
    return hasher.final();
}

fn fingerprintTranscriptImage(image: TranscriptImage) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.transcript.image.fingerprint");
    hashU64(&hasher, world_transcript_image_fingerprint_version);
    hashU64(&hasher, image.world_surface_fingerprint);
    hashU64(&hasher, image.target_certificate_fingerprint);
    hashU64(&hasher, @intFromEnum(image.final_status));
    hashU64(&hasher, image.response_count);
    hashU64(&hasher, image.events.len);
    for (image.events) |event| hashU64(&hasher, event.event_fingerprint);
    return hasher.final();
}

fn fingerprintTimelineEvent(event: Timeline.Event) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.timeline.event.fingerprint");
    hashU64(&hasher, world_timeline_event_fingerprint_version);
    hashU64(&hasher, @intFromEnum(event.kind));
    hashU64(&hasher, event.world_surface_fingerprint);
    hashU64(&hasher, event.target_certificate_fingerprint);
    hashOptionalU64(&hasher, event.request_frame_fingerprint);
    hashOptionalU64(&hasher, event.response_frame_fingerprint);
    hashOptionalU64(&hasher, event.replay_key);
    hashOptionalU64(&hasher, event.checkpoint_fingerprint);
    hashOptionalU64(&hasher, event.branch_id);
    hashU64(&hasher, event.turn_index);
    if (event.status) |status| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(status));
    } else {
        hashBool(&hasher, false);
    }
    return hasher.final();
}

fn fingerprintCheckpoint(checkpoint: Timeline.Checkpoint) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.timeline.checkpoint.fingerprint");
    hashU64(&hasher, world_timeline_checkpoint_fingerprint_version);
    hashU64(&hasher, checkpoint.world_surface_fingerprint);
    hashU64(&hasher, checkpoint.target_certificate_fingerprint);
    hashU64(&hasher, checkpoint.event_index);
    hashU64(&hasher, checkpoint.turn_index);
    hashOptionalU64(&hasher, checkpoint.current_request_fingerprint);
    hashOptionalU64(&hasher, checkpoint.last_response_fingerprint);
    hashOptionalU64(&hasher, checkpoint.capsule_image_fingerprint);
    hashU64(&hasher, checkpoint.transcript_prefix_fingerprint);
    hashU64(&hasher, checkpoint.branch_id);
    hashU64(&hasher, @intFromEnum(checkpoint.status));
    return hasher.final();
}

fn fingerprintAuditImage(image: AuditImage) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.audit.image.fingerprint");
    hashU64(&hasher, world_audit_image_fingerprint_version);
    hashU64(&hasher, image.world_surface_fingerprint);
    hashU64(&hasher, image.target_certificate_fingerprint);
    hashU64(&hasher, @intFromEnum(image.mode));
    hashU64(&hasher, @intFromEnum(image.final_status));
    hashU64(&hasher, image.request_frame_count);
    hashU64(&hasher, image.response_frame_count);
    hashU64(&hasher, image.replayed_frame_count);
    hashU64(&hasher, image.verified_frame_count);
    hashU64(&hasher, image.failed_frame_count);
    hashU64(&hasher, image.branch_count);
    hashU64(&hasher, image.checkpoint_count);
    hashU64(&hasher, image.missing_portable_value_image_count);
    hashU64(&hasher, image.native_only_value_count);
    hashOptionalU64(&hasher, image.transcript_image_fingerprint);
    return hasher.final();
}

fn fingerprintRequest(frame: Frame.Request) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.frame.request.fingerprint");
    hashU64(&hasher, world_frame_request_fingerprint_version);
    hashU64(&hasher, frame.world_surface_fingerprint);
    hashOptionalU64(&hasher, frame.world_surface_replay_scope_fingerprint);
    hashU64(&hasher, frame.target_certificate_fingerprint);
    hashU64(&hasher, frame.world_port_id);
    hashU64(&hasher, frame.residual_site_index);
    hashU64(&hasher, frame.residual_site_fingerprint);
    hashU64(&hasher, frame.request_fingerprint);
    hashU64(&hasher, frame.turn_index);
    hashOptionalU32(&hasher, frame.payload_value_table_id);
    hashOptionalU32(&hasher, frame.expected_response_value_table_id);
    hashOptionalU64(&hasher, frame.payload_value_fingerprint);
    if (frame.payload_image) |image| {
        hashBool(&hasher, true);
        hashU64(&hasher, image.value_image_fingerprint);
    } else {
        hashBool(&hasher, false);
    }
    hashU64(&hasher, frame.replay_key_seed.world_surface_fingerprint);
    hashU64(&hasher, frame.replay_key_seed.world_surface_scope_fingerprint);
    hashU64(&hasher, frame.replay_key_seed.world_port_id);
    hashU64(&hasher, frame.replay_key_seed.request_fingerprint);
    hashOptionalU64(&hasher, frame.source_effect_shape_fingerprint);
    hashOptionalU64(&hasher, frame.world_port_ref_fingerprint);
    hashOptionalU64(&hasher, frame.trace_ref_fingerprint);
    hashOptionalU64(&hasher, frame.evidence_ref_fingerprint);
    hashU64(&hasher, frame.flags);
    return hasher.final();
}

fn fingerprintResponse(frame: Frame.Response) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.frame.response.fingerprint");
    hashU64(&hasher, world_frame_response_fingerprint_version);
    hashU64(&hasher, frame.world_surface_fingerprint);
    hashU64(&hasher, frame.target_certificate_fingerprint);
    hashU64(&hasher, frame.world_port_id);
    hashU64(&hasher, frame.request_fingerprint);
    hashU64(&hasher, @intFromEnum(frame.response_kind));
    hashOptionalU32(&hasher, frame.response_value_table_id);
    hashU64(&hasher, frame.response_fingerprint);
    hashOptionalU64(&hasher, frame.response_value_fingerprint);
    if (frame.response_image) |image| {
        hashBool(&hasher, true);
        hashU64(&hasher, image.value_image_fingerprint);
    } else {
        hashBool(&hasher, false);
    }
    hashU64(&hasher, frame.replay_key);
    hashU64(&hasher, @intFromEnum(frame.status));
    hashOptionalBytes(&hasher, frame.error_tag);
    hashOptionalBytes(&hasher, frame.reason);
    hashU64(&hasher, frame.flags);
    return hasher.final();
}

fn portableValueDynamicByteLowerBound(comptime Value: type, value: Value) usize {
    return switch (@typeInfo(Value)) {
        .pointer => |pointer| blk: {
            if (comptime pointer.size == .slice and pointer.child == u8) break :blk value.len;
            if (comptime isStringList(Value)) {
                var total: usize = 0;
                for (value) |item| total += item.len;
                break :blk total;
            }
            break :blk 0;
        },
        .optional => |optional| if (value) |payload|
            portableValueDynamicByteLowerBound(optional.child, payload)
        else
            0,
        .@"struct" => |info| blk: {
            var total: usize = 0;
            inline for (info.fields) |field| {
                total += portableValueDynamicByteLowerBound(field.type, @field(value, field.name));
            }
            break :blk total;
        },
        .@"union" => |union_info| blk: {
            const Tag = union_info.tag_type orelse break :blk 0;
            const active_tag = std.meta.activeTag(value);
            inline for (union_info.fields) |field| {
                if (active_tag == @field(Tag, field.name)) {
                    if (field.type == void) break :blk 0;
                    break :blk portableValueDynamicByteLowerBound(field.type, @field(value, field.name));
                }
            }
            break :blk 0;
        },
        else => 0,
    };
}

fn encodePortableValue(comptime Value: type, allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void {
    switch (@typeInfo(Value)) {
        .void => {},
        .bool => try writeBool(out, allocator, value),
        .int => {
            const info = @typeInfo(Value).int;
            if (info.bits > 64) return error.UnsupportedValueImage;
            if (info.signedness == .signed) {
                try writeI64(out, allocator, @intCast(value));
            } else {
                try writeU64(out, allocator, @intCast(value));
            }
        },
        .comptime_int => {
            if (value < 0) {
                try writeI64(out, allocator, @as(i64, value));
            } else {
                try writeU64(out, allocator, @as(u64, value));
            }
        },
        .float, .comptime_float => {
            if (Value == f32) {
                try writeU32(out, allocator, @as(u32, @bitCast(value)));
            } else if (Value == f64) {
                try writeU64(out, allocator, @as(u64, @bitCast(value)));
            } else {
                return error.UnsupportedValueImage;
            }
        },
        .@"enum" => |info| {
            if (info.tag_type) |Tag| {
                if (@bitSizeOf(Tag) > 64) return error.UnsupportedValueImage;
            }
            try writeU64(out, allocator, @intCast(@intFromEnum(value)));
        },
        .pointer => |pointer| {
            if (comptime pointer.size == .slice and pointer.child == u8) {
                try writeBytes(out, allocator, value);
                return;
            }
            if (comptime isStringList(Value)) {
                try writeU64(out, allocator, value.len);
                for (value) |item| try writeBytes(out, allocator, item);
                return;
            }
            return error.UnsupportedValueImage;
        },
        .optional => |optional| {
            if (value) |payload| {
                try writeBool(out, allocator, true);
                try encodePortableValue(optional.child, allocator, out, payload);
            } else {
                try writeBool(out, allocator, false);
            }
        },
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                try encodePortableValue(field.type, allocator, out, @field(value, field.name));
            }
        },
        .@"union" => |union_info| {
            const Tag = union_info.tag_type orelse return error.UnsupportedValueImage;
            const active_tag = std.meta.activeTag(value);
            inline for (union_info.fields, 0..) |field, field_index| {
                if (active_tag == @field(Tag, field.name)) {
                    try writeU32(out, allocator, @as(u32, @intCast(field_index)));
                    if (field.type != void) {
                        try encodePortableValue(field.type, allocator, out, @field(value, field.name));
                    }
                    return;
                }
            }
            unreachable;
        },
        else => return error.UnsupportedValueImage,
    }
}

fn decodePortableValue(comptime Value: type, allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !Value {
    return switch (@typeInfo(Value)) {
        .void => {},
        .bool => try readBool(bytes, cursor),
        .int => blk: {
            const info = @typeInfo(Value).int;
            if (info.bits > 64) return error.UnsupportedValueImage;
            if (info.signedness == .signed) {
                const raw = try readI64(bytes, cursor);
                break :blk std.math.cast(Value, raw) orelse return error.InvalidFrameEncoding;
            }
            const raw = try readU64(bytes, cursor);
            break :blk std.math.cast(Value, raw) orelse return error.InvalidFrameEncoding;
        },
        .comptime_int => return error.UnsupportedValueImage,
        .float, .comptime_float => blk: {
            if (Value == f32) {
                break :blk @as(f32, @bitCast(try readU32(bytes, cursor)));
            } else if (Value == f64) {
                break :blk @as(f64, @bitCast(try readU64(bytes, cursor)));
            }
            return error.UnsupportedValueImage;
        },
        .@"enum" => |info| blk: {
            const raw = try readU64(bytes, cursor);
            inline for (info.fields) |field| {
                if (field.value == raw) break :blk @as(Value, @enumFromInt(raw));
            }
            return error.InvalidFrameEncoding;
        },
        .pointer => |pointer| blk: {
            if (comptime pointer.size == .slice and pointer.child == u8) {
                break :blk try readBytesOwned(allocator, bytes, cursor);
            }
            if (comptime isStringList(Value)) {
                const len = try readU64AsUsize(bytes, cursor);
                const Child = @typeInfo(Value).pointer.child;
                const result = try allocator.alloc(Child, len);
                errdefer allocator.free(result);
                var initialized: usize = 0;
                errdefer for (result[0..initialized]) |item| allocator.free(@constCast(item));
                for (result) |*item| {
                    item.* = try readBytesOwned(allocator, bytes, cursor);
                    initialized += 1;
                }
                break :blk result;
            }
            return error.UnsupportedValueImage;
        },
        .optional => |optional| blk: {
            if (!try readBool(bytes, cursor)) break :blk null;
            const payload = try decodePortableValue(optional.child, allocator, bytes, cursor);
            break :blk payload;
        },
        .@"struct" => |info| blk: {
            var result: Value = undefined;
            var initialized_fields: usize = 0;
            errdefer inline for (info.fields, 0..) |field, field_index| {
                if (field_index < initialized_fields) {
                    deinitOwnedValue(allocator, @field(result, field.name));
                }
            };
            inline for (info.fields) |field| {
                @field(result, field.name) = try decodePortableValue(field.type, allocator, bytes, cursor);
                initialized_fields += 1;
            }
            break :blk result;
        },
        .@"union" => |union_info| blk: {
            const field_index = try readU32(bytes, cursor);
            inline for (union_info.fields, 0..) |field, index| {
                if (field_index == index) {
                    if (field.type == void) break :blk @unionInit(Value, field.name, {});
                    const payload = try decodePortableValue(field.type, allocator, bytes, cursor);
                    errdefer deinitOwnedValue(allocator, payload);
                    break :blk @unionInit(Value, field.name, payload);
                }
            }
            return error.InvalidFrameEncoding;
        },
        else => return error.UnsupportedValueImage,
    };
}

fn valueIsDynamic(comptime Value: type) bool {
    return switch (@typeInfo(Value)) {
        .pointer => |pointer| pointer.size == .slice,
        .optional => |optional| valueIsDynamic(optional.child),
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                if (valueIsDynamic(field.type)) return true;
            }
            return false;
        },
        .@"union" => |info| {
            inline for (info.fields) |field| {
                if (valueIsDynamic(field.type)) return true;
            }
            return false;
        },
        else => false,
    };
}

fn writeU8(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u8) !void {
    try out.append(allocator, value);
}

fn writeBool(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: bool) !void {
    try writeU8(out, allocator, if (value) 1 else 0);
}

fn writeU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: anytype) !void {
    var buffer: [4]u8 = undefined;
    std.mem.writeInt(u32, &buffer, @intCast(value), .little);
    try out.appendSlice(allocator, &buffer);
}

fn writeU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: anytype) !void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, @intCast(value), .little);
    try out.appendSlice(allocator, &buffer);
}

fn writeI64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: i64) !void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(i64, &buffer, value, .little);
    try out.appendSlice(allocator, &buffer);
}

fn writeOptionalU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?u32) !void {
    if (value) |present| {
        try writeBool(out, allocator, true);
        try writeU32(out, allocator, present);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn writeOptionalU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: anytype) !void {
    if (value) |present| {
        try writeBool(out, allocator, true);
        try writeU64(out, allocator, present);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn writeBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) !void {
    try writeU64(out, allocator, bytes.len);
    try out.appendSlice(allocator, bytes);
}

fn writeOptionalBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: ?[]const u8) !void {
    if (bytes) |present| {
        try writeBool(out, allocator, true);
        try writeBytes(out, allocator, present);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn writeOptionalValueImage(out: *std.ArrayList(u8), allocator: std.mem.Allocator, image: ?Frame.ValueImage) !void {
    if (image) |present| {
        try writeBool(out, allocator, true);
        const encoded = try present.encode(allocator);
        defer allocator.free(encoded);
        try writeBytes(out, allocator, encoded);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn readU8(bytes: []const u8, cursor: *usize) !u8 {
    if (cursor.* >= bytes.len) return error.InvalidFrameEncoding;
    const value = bytes[cursor.*];
    cursor.* += 1;
    return value;
}

fn readBool(bytes: []const u8, cursor: *usize) !bool {
    return switch (try readU8(bytes, cursor)) {
        0 => false,
        1 => true,
        else => error.InvalidFrameEncoding,
    };
}

fn readU32(bytes: []const u8, cursor: *usize) !u32 {
    if (bytes.len - cursor.* < 4) return error.InvalidFrameEncoding;
    const value = std.mem.readInt(u32, bytes[cursor.*..][0..4], .little);
    cursor.* += 4;
    return value;
}

fn readU64(bytes: []const u8, cursor: *usize) !u64 {
    if (bytes.len - cursor.* < 8) return error.InvalidFrameEncoding;
    const value = std.mem.readInt(u64, bytes[cursor.*..][0..8], .little);
    cursor.* += 8;
    return value;
}

fn readI64(bytes: []const u8, cursor: *usize) !i64 {
    if (bytes.len - cursor.* < 8) return error.InvalidFrameEncoding;
    const value = std.mem.readInt(i64, bytes[cursor.*..][0..8], .little);
    cursor.* += 8;
    return value;
}

fn readU64AsUsize(bytes: []const u8, cursor: *usize) !usize {
    return std.math.cast(usize, try readU64(bytes, cursor)) orelse error.InvalidFrameEncoding;
}

fn readOptionalU32(bytes: []const u8, cursor: *usize) !?u32 {
    if (!try readBool(bytes, cursor)) return null;
    return try readU32(bytes, cursor);
}

fn readOptionalU64(bytes: []const u8, cursor: *usize) !?u64 {
    if (!try readBool(bytes, cursor)) return null;
    return try readU64(bytes, cursor);
}

fn readOptionalUsize(bytes: []const u8, cursor: *usize) !?usize {
    if (!try readBool(bytes, cursor)) return null;
    return try readU64AsUsize(bytes, cursor);
}

fn readBytesOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ![]const u8 {
    const len = try readU64AsUsize(bytes, cursor);
    if (len > bytes.len - cursor.*) return error.InvalidFrameEncoding;
    const result = try allocator.dupe(u8, bytes[cursor.* .. cursor.* + len]);
    cursor.* += len;
    return result;
}

fn readOptionalBytesOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?[]const u8 {
    if (!try readBool(bytes, cursor)) return null;
    return try readBytesOwned(allocator, bytes, cursor);
}

fn readOptionalValueImage(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?Frame.ValueImage {
    if (!try readBool(bytes, cursor)) return null;
    const encoded = try readBytesOwned(allocator, bytes, cursor);
    defer allocator.free(encoded);
    return try Frame.ValueImage.decode(allocator, encoded);
}

fn enumFromByte(comptime Enum: type, value: u8) !Enum {
    inline for (@typeInfo(Enum).@"enum".fields) |field| {
        if (field.value == value) return @as(Enum, @enumFromInt(value));
    }
    return error.InvalidFrameEncoding;
}

fn hashBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
    hasher.update(bytes);
}

fn hashU64(hasher: *std.hash.Wyhash, value: anytype) void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, @intCast(value), .little);
    hasher.update(&buffer);
}

fn hashBool(hasher: *std.hash.Wyhash, value: bool) void {
    hashU64(hasher, @as(u8, if (value) 1 else 0));
}

fn hashOptionalU32(hasher: *std.hash.Wyhash, value: ?u32) void {
    if (value) |present| {
        hashBool(hasher, true);
        hashU64(hasher, present);
    } else {
        hashBool(hasher, false);
    }
}

fn hashOptionalU64(hasher: *std.hash.Wyhash, value: ?u64) void {
    if (value) |present| {
        hashBool(hasher, true);
        hashU64(hasher, present);
    } else {
        hashBool(hasher, false);
    }
}

fn hashOptionalBytes(hasher: *std.hash.Wyhash, bytes: ?[]const u8) void {
    if (bytes) |present| {
        hashBool(hasher, true);
        hashU64(hasher, present.len);
        hashBytes(hasher, present);
    } else {
        hashBool(hasher, false);
    }
}

test {
    _ = Mode;
    _ = Transcript;
    _ = Machine;
}
