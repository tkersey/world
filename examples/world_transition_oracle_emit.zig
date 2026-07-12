// zlinter-disable declaration_naming field_ordering no_inferred_error_unions no_swallow_error require_doc_comment require_errdefer_dealloc
const boundary = @import("boundary");
const builtin = @import("builtin");
const common = @import("world_appliance_common.zig");
const fixtures = @import("world_fixtures");
const std = @import("std");
const universal = @import("world_universal_appliance_wasm.zig");
const world = @import("world");
const world_transition_oracle_sources = @import("world_transition_oracle_sources");

const corpus_path = "conformance/world-image-v1/v0/world";
const checksum_prefix = corpus_path ++ "/";
const canonical_output_suffix = "conformance/world-image-v1/v0/world";

fn canonicalizePathSeparators(path_bytes: []u8, native_separator: u8) void {
    if (native_separator == '/') return;
    for (path_bytes) |*byte| {
        if (byte.* == native_separator) byte.* = '/';
    }
}

fn isAllowedIsolatedOutputPath(path_bytes: []const u8) bool {
    return std.mem.eql(u8, path_bytes, "./bundle");
}

fn appendJsonString(allocator: std.mem.Allocator, output: *std.ArrayList(u8), value: []const u8) !void {
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidJsonString;
    var encoded: std.Io.Writer.Allocating = .init(allocator);
    defer encoded.deinit();
    try std.json.Stringify.value(value, .{}, &encoded.writer);
    try output.appendSlice(allocator, encoded.written());
}

test "manifest JSON strings round trip source path bytes" {
    const source_path = "src/quote\"\\line\ncontrol\x01.zig";
    var encoded: std.ArrayList(u8) = .empty;
    defer encoded.deinit(std.testing.allocator);
    try appendJsonString(std.testing.allocator, &encoded, source_path);
    try std.testing.expectEqualStrings("\"src/quote\\\"\\\\line\\ncontrol\\u0001.zig\"", encoded.items);

    const parsed = try std.json.parseFromSlice([]const u8, std.testing.allocator, encoded.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(source_path, parsed.value);

    try std.testing.expectError(
        error.InvalidJsonString,
        appendJsonString(std.testing.allocator, &encoded, &.{0xff}),
    );
}

comptime {
    var windows_isolated = ".\\bundle".*;
    canonicalizePathSeparators(windows_isolated[0..], '\\');
    if (!isAllowedIsolatedOutputPath(windows_isolated[0..])) {
        @compileError("native isolated oracle path must be admitted");
    }

    var windows_nested = "artifacts\\states\\checkpoint.bin".*;
    canonicalizePathSeparators(windows_nested[0..], '\\');
    if (!std.mem.eql(u8, windows_nested[0..], "artifacts/states/checkpoint.bin")) {
        @compileError("native walked paths must have portable identities");
    }

    var windows_unrelated = "C:\\repo\\bundle".*;
    canonicalizePathSeparators(windows_unrelated[0..], '\\');
    if (isAllowedIsolatedOutputPath(windows_unrelated[0..])) {
        @compileError("unrelated native output path must remain rejected");
    }
}

const Case = struct {
    id: []const u8,
    transcript: []const u8,
};

const cases = [_]Case{
    .{ .id = "one-port-execution", .transcript = "cases/one-port-execution.txt" },
    .{ .id = "internal-provider-execution", .transcript = "cases/internal-provider-execution.txt" },
    .{ .id = "provider-parked-externally", .transcript = "cases/provider-parked-externally.txt" },
    .{ .id = "active-provider-restore", .transcript = "cases/active-provider-restore.txt" },
    .{ .id = "replay-without-fresh-effect", .transcript = "cases/replay-without-fresh-effect.txt" },
    .{ .id = "lost-output-retry", .transcript = "cases/lost-output-retry.txt" },
    .{ .id = "migration", .transcript = "cases/migration.txt" },
    .{ .id = "branching", .transcript = "cases/branching.txt" },
    .{ .id = "partial-response-batch", .transcript = "cases/partial-response-batch.txt" },
    .{ .id = "deterministic-failure", .transcript = "cases/deterministic-failure.txt" },
    .{ .id = "capacity-exhaustion", .transcript = "cases/capacity-exhaustion.txt" },
    .{ .id = "malformed-records", .transcript = "cases/malformed-records.txt" },
};

const generator_source_identity_algorithm = "sha256-domain-u32le-path-u64le-canonical-lf-bytes-v1";
const generator_source_normalization = "crlf-to-lf;bare-cr-reject";
const generator_source_identity_domain = "world.oracle.generator-source-identity.v1\x00";
const candidate_admission_identity_domain = "world.oracle.candidate-admission.v1\x00";
const compiled_generator_sources = world_transition_oracle_sources.sources;
const generator_source_package_paths = world_transition_oracle_sources.package_paths;
const generator_source_excluded_prefix = world_transition_oracle_sources.excluded_prefix;

comptime {
    @setEvalBranchQuota(100_000);
    if (compiled_generator_sources.len == 0) @compileError("compiled generator source inventory must not be empty");
    for (compiled_generator_sources[1..], compiled_generator_sources[0 .. compiled_generator_sources.len - 1]) |current, previous| {
        if (!std.mem.lessThan(u8, previous.path, current.path)) {
            @compileError("compiled generator source inventory must be unique and preserve canonical order");
        }
    }
}

fn compiledGeneratorSourceBytes(relative_path: []const u8) ![]const u8 {
    for (compiled_generator_sources) |source| {
        if (std.mem.eql(u8, source.path, relative_path)) return source.bytes;
    }
    return error.MissingCompiledGeneratorSource;
}

fn packageVersionFromZon(allocator: std.mem.Allocator, zon_bytes: []const u8) ![]const u8 {
    const source = try allocator.dupeZ(u8, zon_bytes);
    defer allocator.free(source);
    const PackageProjection = struct { version: []const u8 };
    const projection = std.zon.parse.fromSliceAlloc(
        PackageProjection,
        allocator,
        source,
        null,
        .{ .ignore_unknown_fields = true },
    ) catch return error.InvalidPackageManifest;
    defer std.zon.parse.free(allocator, projection);
    if (projection.version.len == 0) return error.InvalidPackageVersionField;
    return allocator.dupe(u8, projection.version);
}

fn compiledPackageVersion(allocator: std.mem.Allocator) ![]const u8 {
    return packageVersionFromZon(allocator, try compiledGeneratorSourceBytes("build.zig.zon"));
}

const BoundaryDependencyProjection = struct {
    url: []const u8,
    hash: []const u8,
};

const BoundaryPackageManifestProjection = struct {
    dependencies: struct {
        boundary: BoundaryDependencyProjection,
    },
};

const BoundaryPackage = struct {
    version: []u8,
    hash: []u8,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.version);
        allocator.free(self.hash);
        self.* = undefined;
    }
};

fn boundaryPackageFromZon(allocator: std.mem.Allocator, zon_bytes: []const u8) !BoundaryPackage {
    const source = try allocator.dupeZ(u8, zon_bytes);
    defer allocator.free(source);
    const projection = std.zon.parse.fromSliceAlloc(
        BoundaryPackageManifestProjection,
        allocator,
        source,
        null,
        .{ .ignore_unknown_fields = true },
    ) catch return error.InvalidPackageManifest;
    defer std.zon.parse.free(allocator, projection);

    const url_prefix = "https://github.com/tkersey/boundary/archive/refs/tags/v";
    const url_suffix = ".tar.gz";
    if (!std.mem.startsWith(u8, projection.dependencies.boundary.url, url_prefix) or
        !std.mem.endsWith(u8, projection.dependencies.boundary.url, url_suffix))
    {
        return error.InvalidBoundaryPackageIdentity;
    }
    const version_end = projection.dependencies.boundary.url.len - url_suffix.len;
    if (version_end <= url_prefix.len) return error.InvalidBoundaryPackageIdentity;
    const version = projection.dependencies.boundary.url[url_prefix.len..version_end];
    if (std.mem.indexOfScalar(u8, version, '/') != null) return error.InvalidBoundaryPackageIdentity;
    const hash_prefix = try std.fmt.allocPrint(allocator, "boundary-{s}-", .{version});
    defer allocator.free(hash_prefix);
    if (!std.mem.startsWith(u8, projection.dependencies.boundary.hash, hash_prefix) or
        projection.dependencies.boundary.hash.len == hash_prefix.len)
    {
        return error.InvalidBoundaryPackageIdentity;
    }

    const owned_version = try allocator.dupe(u8, version);
    errdefer allocator.free(owned_version);
    return .{
        .version = owned_version,
        .hash = try allocator.dupe(u8, projection.dependencies.boundary.hash),
    };
}

fn compiledBoundaryPackage(allocator: std.mem.Allocator) !BoundaryPackage {
    return boundaryPackageFromZon(allocator, try compiledGeneratorSourceBytes("build.zig.zon"));
}

test "package version projection accepts valid ZON whitespace and comments" {
    const zon =
        \\.{
        \\    .name = .world,
        \\    // owner field
        \\    .version   =   "1.2.3", // retained provenance
        \\    .paths = .{"src"},
        \\}
    ;
    const version = try packageVersionFromZon(std.testing.allocator, zon);
    defer std.testing.allocator.free(version);
    try std.testing.expectEqualStrings("1.2.3", version);
    const escaped_version = try packageVersionFromZon(std.testing.allocator, ".{ .@\"version\" = \"2.0.0\" }");
    defer std.testing.allocator.free(escaped_version);
    try std.testing.expectEqualStrings("2.0.0", escaped_version);

    const multiline_zon =
        \\.{
        \\    .note =
        \\        \\literal { } // not a comment
        \\        \\.version = "not a field"
        \\    ,
        \\    .version =
        \\        \\3.0.0
        \\    ,
        \\}
    ;
    const multiline_version = try packageVersionFromZon(std.testing.allocator, multiline_zon);
    defer std.testing.allocator.free(multiline_version);
    try std.testing.expectEqualStrings("3.0.0", multiline_version);
}

test "boundary dependency provenance projects one pinned package owner" {
    const zon =
        \\.{
        \\    .name = .world,
        \\    .dependencies = .{
        \\        .boundary = .{
        \\            // selected package owner
        \\            .url = "https://github.com/tkersey/boundary/archive/refs/tags/v1.2.3.tar.gz",
        \\            .hash = "boundary-1.2.3-fixture",
        \\        },
        \\    },
        \\}
    ;
    var package = try boundaryPackageFromZon(std.testing.allocator, zon);
    defer package.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("1.2.3", package.version);
    try std.testing.expectEqualStrings("boundary-1.2.3-fixture", package.hash);

    const escaped =
        \\.{
        \\    .@"dependencies" = .{
        \\        .@"boundary" = .{
        \\            .@"url" = "https://github.com/tkersey/boundary/archive/refs/tags/v1.2.3.tar.gz",
        \\            .@"hash" = "boundary-1.2.3-fixture"
        \\        }
        \\    },
        \\}
    ;
    var escaped_package = try boundaryPackageFromZon(std.testing.allocator, escaped);
    defer escaped_package.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(package.version, escaped_package.version);
    try std.testing.expectEqualStrings(package.hash, escaped_package.hash);

    const multiline =
        \\.{
        \\    .dependencies = .{
        \\        .boundary = .{
        \\            .url =
        \\                \\https://github.com/tkersey/boundary/archive/refs/tags/v1.2.3.tar.gz
        \\            ,
        \\            .hash =
        \\                \\boundary-1.2.3-fixture
        \\            ,
        \\        },
        \\    },
        \\}
    ;
    var multiline_package = try boundaryPackageFromZon(std.testing.allocator, multiline);
    defer multiline_package.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(package.version, multiline_package.version);
    try std.testing.expectEqualStrings(package.hash, multiline_package.hash);

    const mismatched =
        \\.{
        \\    .dependencies = .{
        \\        .boundary = .{
        \\            .url = "https://github.com/tkersey/boundary/archive/refs/tags/v1.2.4.tar.gz",
        \\            .hash = "boundary-1.2.3-fixture",
        \\        },
        \\    },
        \\}
    ;
    try std.testing.expectError(
        error.InvalidBoundaryPackageIdentity,
        boundaryPackageFromZon(std.testing.allocator, mismatched),
    );
}

const Writer = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    root: []const u8,
    paths: std.ArrayList([]const u8) = .empty,

    fn write(self: *@This(), relative_path: []const u8, data: []const u8) !void {
        for (self.paths.items) |existing| {
            if (std.mem.eql(u8, existing, relative_path)) return error.DuplicateArtifactPath;
        }
        const full_path = try std.fs.path.join(self.allocator, &.{ self.root, relative_path });
        if (std.fs.path.dirname(full_path)) |parent| try std.Io.Dir.cwd().createDirPath(self.io, parent);
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = full_path, .data = data });
        try self.paths.append(self.allocator, try self.allocator.dupe(u8, relative_path));
    }
};

const OwnedPaths = struct {
    allocator: std.mem.Allocator,
    items: [][]u8,

    fn deinit(self: *@This()) void {
        for (self.items) |item| self.allocator.free(item);
        self.allocator.free(self.items);
        self.items = &.{};
    }
};

const PublicationTarget = union(enum) {
    isolated: []const u8,
    trusted_prefix: []const u8,
};

const ReplayCtx = struct { calls: usize = 0 };

fn replayApprove(ctx: *ReplayCtx, payload: []const u8) !i32 {
    if (!std.mem.eql(u8, payload, "deploy-prod")) return error.UnexpectedPayload;
    ctx.calls += 1;
    return 7;
}

const ReplayApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, replayApprove);
const ReplayMachine = world.Machine(fixtures.Ports.Target, .{
    .ports = .{ReplayApprovalPort},
    .strict_handler_coverage = true,
});

const BranchCtx = struct {
    allocator: std.mem.Allocator,
    alternate: bool = false,
};

fn branchDecide(ctx: *BranchCtx, observation: []const u8) !fixtures.Agent.Action {
    if (ctx.alternate) return .{ .final = "final=branch alternate" };
    return fixtures.Agent.decideAction(.skeleton, observation);
}

fn branchTool(ctx: *BranchCtx, command: []const u8) ![]const u8 {
    return fixtures.Agent.callTool(ctx.allocator, .skeleton, command);
}

const BranchDecidePort = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, branchDecide);
const BranchToolPort = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, branchTool);
const BranchMachine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ BranchDecidePort, BranchToolPort },
    .strict_handler_coverage = true,
});

const BatchCtx = struct {};

fn batchDecide(_: *BatchCtx, _: []const u8) !fixtures.Agent.Action {
    return .{ .final = "final=actuate skeleton complete" };
}

fn batchTool(_: *BatchCtx, _: []const u8) ![]const u8 {
    return "tool";
}

const BatchDecideDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, batchDecide);
const BatchToolDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, batchTool);
const BatchActuator = world.actuator(.{
    .kind = .fixture,
    .class = .deterministic_fixture,
    .label = "world-image-v1-oracle.batch",
    .supported_response_statuses = world.Actuation.ResponseStatusSet.all,
    .value_policy = world.ValuePolicy.portable,
});
const BatchAppliance = world.Appliance.Define(fixtures.Agent.Target, .{
    .profile = world.Appliance.Profile.wasm_agent,
    .capacity = world.Appliance.Capacity.wasm_agent,
    .actuation_bindings = .{
        world.bindActuator(BatchDecideDecl, BatchActuator),
        world.bindActuator(BatchToolDecl, BatchActuator),
    },
});

pub fn main(init: std.process.Init) !void {
    comptime {
        if (world.world_executable_image_format_version != 2) @compileError("update World Image v1 oracle executable image format binding");
        if (world.world_executable_image_fingerprint_version != 2) @compileError("update World Image v1 oracle executable image fingerprint binding");
        if (world.world_executable_image_codec_version != 1) @compileError("update World Image v1 oracle executable image codec binding");
        if (world.world_appliance_manifest_format_version != 3) @compileError("update World Image v1 oracle Appliance Manifest format binding");
        if (world.world_appliance_manifest_fingerprint_version != 3) @compileError("update World Image v1 oracle Appliance Manifest fingerprint binding");
        if (world.world_appliance_command_format_version != 1) @compileError("update World Image v1 oracle Appliance Command format binding");
        if (world.world_appliance_command_fingerprint_version != 1) @compileError("update World Image v1 oracle Appliance Command fingerprint binding");
        if (world.world_appliance_wire_turn_input_format_version != 2) @compileError("update World Image v1 oracle Wire.TurnInput format binding");
        if (world.world_appliance_wire_resolution_input_format_version != 1) @compileError("update World Image v1 oracle Wire.ResolutionInput format binding");
        if (world.world_appliance_turn_output_format_version != 3) @compileError("update World Image v1 oracle TurnOutput format binding");
        if (world.world_appliance_turn_output_fingerprint_version != 2) @compileError("update World Image v1 oracle TurnOutput fingerprint binding");
        if (world.world_appliance_turn_closure_format_version != 1) @compileError("update World Image v1 oracle TurnClosure format binding");
        if (world.world_appliance_turn_closure_fingerprint_version != 1) @compileError("update World Image v1 oracle TurnClosure fingerprint binding");
        if (world.world_appliance_checkpoint_format_version != 1) @compileError("update World Image v1 oracle Checkpoint format binding");
        if (world.world_appliance_checkpoint_fingerprint_version != 1) @compileError("update World Image v1 oracle Checkpoint fingerprint binding");
        if (world.world_capsule_image_format_version != 3) @compileError("update World Image v1 oracle Capsule Image format binding");
        if (world.world_capsule_image_fingerprint_version != 1) @compileError("update World Image v1 oracle Capsule Image fingerprint binding");
        if (world.world_appliance_host_request_format_version != 4) @compileError("update World Image v1 oracle HostRequest format binding");
        if (world.world_appliance_host_request_fingerprint_version != 4) @compileError("update World Image v1 oracle HostRequest fingerprint binding");
        if (world.world_frame_request_format_version != 1) @compileError("update World Image v1 oracle Frame.Request format binding");
        if (world.world_frame_request_fingerprint_version != 1) @compileError("update World Image v1 oracle Frame.Request fingerprint binding");
        if (world.Archive.world_archive_append_batch_format_version != 1) @compileError("update World Image v1 oracle Archive.AppendBatch format binding");
        if (world.Archive.world_archive_append_batch_fingerprint_version != 1) @compileError("update World Image v1 oracle Archive.AppendBatch fingerprint binding");
        if (world.world_run_image_format_version != 3) @compileError("update World Image v1 oracle RunImage format binding");
        if (world.world_run_image_fingerprint_version != 1) @compileError("update World Image v1 oracle RunImage fingerprint binding");
        if (world.world_transcript_image_format_version != 3) @compileError("update World Image v1 oracle TranscriptImage format binding");
        if (world.world_transcript_image_fingerprint_version != 1) @compileError("update World Image v1 oracle TranscriptImage fingerprint binding");
        if (world.world_appliance_abi_version != 4) @compileError("update World Image v1 oracle Appliance ABI binding");
    }
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const command = args.next() orelse return error.InvalidArguments;
    if (std.mem.eql(u8, command, "publish")) {
        const source_flag = args.next() orelse return error.InvalidArguments;
        const source_dir = args.next() orelse return error.InvalidArguments;
        const admission_flag = args.next() orelse return error.InvalidArguments;
        const admission_digest_path = args.next() orelse return error.InvalidArguments;
        const target_flag = args.next() orelse return error.InvalidArguments;
        const trusted_prefix = args.next() orelse return error.InvalidArguments;
        if (args.next() != null or
            !std.mem.eql(u8, source_flag, "--source-dir") or
            source_dir.len == 0 or
            !std.mem.eql(u8, admission_flag, "--admission-digest") or
            admission_digest_path.len == 0 or
            !std.mem.eql(u8, target_flag, "--trusted-prefix") or
            !std.fs.path.isAbsolute(trusted_prefix))
        {
            return error.InvalidArguments;
        }
        try publishCandidate(
            init.io,
            allocator,
            source_dir,
            admission_digest_path,
            trusted_prefix,
            "./world-transition-oracle-publish-staging",
        );
        return;
    }
    if (!std.mem.eql(u8, command, "generate")) return error.InvalidArguments;
    const target_flag = args.next() orelse return error.InvalidArguments;
    const target_path = args.next() orelse return error.InvalidArguments;
    const source_flag = args.next() orelse return error.InvalidArguments;
    const source_root = args.next() orelse return error.InvalidArguments;
    if (args.next() != null) return error.InvalidArguments;
    if (!std.mem.eql(u8, source_flag, "--source-root") or !std.fs.path.isAbsolute(source_root)) return error.InvalidSourceRoot;

    const publication_target: PublicationTarget = if (std.mem.eql(u8, target_flag, "--out-dir")) blk: {
        const portable_output_dir = try allocator.dupe(u8, target_path);
        canonicalizePathSeparators(portable_output_dir, std.fs.path.sep);
        if (!isAllowedIsolatedOutputPath(portable_output_dir)) return error.InvalidOutputDirectory;
        break :blk .{ .isolated = target_path };
    } else if (std.mem.eql(u8, target_flag, "--trusted-prefix")) blk: {
        if (!std.fs.path.isAbsolute(target_path)) return error.InvalidTrustedPrefix;
        break :blk .{ .trusted_prefix = target_path };
    } else return error.InvalidArguments;
    const generator_source_identity = try validatedGeneratorSourceIdentity(init.io, allocator, source_root);

    const staging_dir = "./world-transition-oracle-staging";
    try std.Io.Dir.cwd().deleteTree(init.io, staging_dir);
    try std.Io.Dir.cwd().createDirPath(init.io, staging_dir);
    defer std.Io.Dir.cwd().deleteTree(init.io, staging_dir) catch {};
    var writer = Writer{ .io = init.io, .allocator = allocator, .root = staging_dir };

    try emitOnePort(allocator, &writer);
    try emitInternalProvider(allocator, &writer);
    try emitActiveProvider(allocator, &writer);
    try emitReplay(allocator, &writer);
    try emitRetry(allocator, &writer);
    try emitBranching(allocator, &writer);
    try emitPartialBatch(allocator, &writer);
    try emitDeterministicFailure(allocator, &writer);
    try emitCapacityExhaustion(allocator, &writer);
    try emitMalformed(allocator, &writer);
    try writeManifest(allocator, &writer, generator_source_identity);
    try writeChecksums(allocator, &writer);
    try promoteCorpus(allocator, &writer, publication_target);
}

fn publishCandidate(
    io: std.Io,
    allocator: std.mem.Allocator,
    source_root: []const u8,
    admission_digest_path: []const u8,
    trusted_prefix: []const u8,
    staging_root: []const u8,
) !void {
    try std.Io.Dir.cwd().deleteTree(io, staging_root);
    try std.Io.Dir.cwd().createDirPath(io, staging_root);
    defer std.Io.Dir.cwd().deleteTree(io, staging_root) catch {};

    var source_dir = try std.Io.Dir.cwd().openDir(io, source_root, .{
        .follow_symlinks = false,
        .iterate = true,
    });
    defer source_dir.close(io);
    if ((try source_dir.stat(io)).kind != .directory) return error.InvalidCandidateDirectory;

    var candidate_paths = try listFiles(io, allocator, source_dir);
    defer candidate_paths.deinit();
    if (candidate_paths.items.len == 0) return error.EmptyCandidateCorpus;

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_root };
    defer writer.paths.deinit(allocator);
    const candidate_identity = try candidateTreeIdentity(
        io,
        allocator,
        source_dir,
        candidate_paths.items,
        &writer,
    );
    try validateCandidateAdmissionDigest(io, allocator, admission_digest_path, candidate_identity);
    try promoteCorpus(allocator, &writer, .{ .trusted_prefix = trusted_prefix });
}

fn candidateTreeIdentity(
    io: std.Io,
    allocator: std.mem.Allocator,
    source_dir: std.Io.Dir,
    candidate_paths: []const []u8,
    snapshot_writer: ?*Writer,
) ![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(candidate_admission_identity_domain);
    for (candidate_paths) |relative_path| {
        var file = source_dir.openFile(io, relative_path, .{
            .mode = .read_only,
            .follow_symlinks = false,
            .resolve_beneath = true,
        }) catch |err| switch (err) {
            error.SymLinkLoop => return error.InvalidCandidateEntry,
            else => |other| return other,
        };
        defer file.close(io);
        if ((try file.stat(io)).kind != .file) return error.InvalidCandidateEntry;
        var read_buffer: [4096]u8 = undefined;
        var reader = file.reader(io, &read_buffer);
        const bytes = try reader.interface.allocRemaining(allocator, .limited(64 * 1024 * 1024));
        defer allocator.free(bytes);
        if (snapshot_writer) |writer| try writer.write(relative_path, bytes);

        var path_length = [_]u8{0} ** 4;
        std.mem.writeInt(u32, &path_length, @intCast(relative_path.len), .little);
        var content_length = [_]u8{0} ** 8;
        std.mem.writeInt(u64, &content_length, @intCast(bytes.len), .little);
        hasher.update(&path_length);
        hasher.update(relative_path);
        hasher.update(&content_length);
        hasher.update(bytes);
    }
    var digest = [_]u8{0} ** 32;
    hasher.final(&digest);
    return digest;
}

fn candidateAdmissionDigestText(digest: [32]u8) [65]u8 {
    const hex = "0123456789abcdef";
    var text: [65]u8 = undefined;
    for (digest, 0..) |byte, index| {
        text[index * 2] = hex[byte >> 4];
        text[index * 2 + 1] = hex[byte & 0x0f];
    }
    text[64] = '\n';
    return text;
}

fn validateCandidateAdmissionDigest(
    io: std.Io,
    allocator: std.mem.Allocator,
    admission_digest_path: []const u8,
    candidate_identity: [32]u8,
) !void {
    var file = std.Io.Dir.cwd().openFile(io, admission_digest_path, .{
        .mode = .read_only,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.SymLinkLoop => return error.InvalidCandidateAdmissionDigest,
        else => |other| return other,
    };
    defer file.close(io);
    if ((try file.stat(io)).kind != .file) return error.InvalidCandidateAdmissionDigest;
    var read_buffer: [66]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    const admission_bytes = try reader.interface.allocRemaining(allocator, .limited(66));
    defer allocator.free(admission_bytes);
    const expected = candidateAdmissionDigestText(candidate_identity);
    if (!std.mem.eql(u8, admission_bytes, &expected)) return error.CandidateAdmissionMismatch;
}

fn writeCandidateAdmissionDigestForTest(
    io: std.Io,
    allocator: std.mem.Allocator,
    source_root: []const u8,
    admission_digest_path: []const u8,
) !void {
    var source_dir = try std.Io.Dir.cwd().openDir(io, source_root, .{
        .follow_symlinks = false,
        .iterate = true,
    });
    defer source_dir.close(io);
    var candidate_paths = try listFiles(io, allocator, source_dir);
    defer candidate_paths.deinit();
    const identity = try candidateTreeIdentity(io, allocator, source_dir, candidate_paths.items, null);
    const text = candidateAdmissionDigestText(identity);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = admission_digest_path, .data = &text });
}

fn validateStandaloneResolutionInput(
    allocator: std.mem.Allocator,
    resolution_bytes: []const u8,
    turn_input_bytes: []const u8,
    limits: world.Appliance.TurnClosureLimits,
) !void {
    if (std.mem.indexOf(u8, turn_input_bytes, resolution_bytes) == null) {
        return error.ResolutionMemberMismatch;
    }
    var decoded_turn = try world.Appliance.Wire.TurnInput.decodeWithLimits(allocator, turn_input_bytes, limits);
    defer decoded_turn.deinit(allocator);
    if (decoded_turn.resolutions.len != 1) return error.ResolutionMemberMismatch;
    try decoded_turn.resolutions[0].validate(limits);
    var roundtrip_bytes: std.ArrayList(u8) = .empty;
    defer roundtrip_bytes.deinit(allocator);
    try decoded_turn.resolutions[0].encode(&roundtrip_bytes, allocator);
    if (!std.mem.eql(u8, resolution_bytes, roundtrip_bytes.items)) {
        return error.ResolutionMemberMismatch;
    }
}

fn writeValidatedApplianceManifest(
    allocator: std.mem.Allocator,
    writer: *Writer,
    relative_path: []const u8,
    expected_manifest_fingerprint: u64,
    manifest_bytes: []const u8,
) !void {
    var decoded = try world.Appliance.Manifest.decode(allocator, manifest_bytes);
    defer decoded.deinit(allocator);
    try decoded.validate();
    if (decoded.manifest_fingerprint != expected_manifest_fingerprint) return error.ManifestIdentityMismatch;
    const canonical_bytes = try decoded.encode(allocator);
    defer allocator.free(canonical_bytes);
    if (!std.mem.eql(u8, manifest_bytes, canonical_bytes)) return error.ManifestEncodingMismatch;
    try writer.write(relative_path, canonical_bytes);
}

test "manifest bytes require owner validation before publication" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const manifest = common.PortsAppliance.manifest();
    const canonical_bytes = try manifest.encode(allocator);
    const malformed_bytes = try allocator.dupe(u8, canonical_bytes);
    malformed_bytes[0] ^= 0xff;
    var writer = Writer{ .io = io, .allocator = allocator, .root = root };
    const relative_path = "artifacts/manifests/rejected.appliance-manifest";

    try std.testing.expectError(
        error.InvalidFrameEncoding,
        writeValidatedApplianceManifest(allocator, &writer, relative_path, manifest.manifest_fingerprint, malformed_bytes),
    );
    try std.testing.expectEqual(@as(usize, 0), writer.paths.items.len);
    const destination_path = try std.fs.path.join(allocator, &.{ root, relative_path });
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, destination_path, .{}));
}

fn emitOnePort(allocator: std.mem.Allocator, writer: *Writer) !void {
    const executable_image_fingerprint: u64 = 0xA100_0000_0000_0001;
    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    const manifest_bytes = try manifest.encode(allocator);
    defer allocator.free(manifest_bytes);
    try writeValidatedApplianceManifest(allocator, writer, "artifacts/manifests/one-port.appliance-manifest", manifest.manifest_fingerprint, manifest_bytes);

    var core = world.Appliance.Core.initWithCapacity(allocator, manifest, common.PortsAppliance.memoryPlan(), capacity);
    core.executable_image_fingerprint = executable_image_fingerprint;
    var native = world.Appliance.Native.init(core);
    defer native.deinit();

    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    try writer.write("artifacts/inputs/one-port.boot.turn-input", boot_bytes);
    if (native.submitTurn(boot_bytes) != .needs_host) return error.ExpectedNeedsHost;
    const waiting_output_bytes = try common.readOutputOwned(allocator, &native);
    const waiting_closure_bytes = try common.readClosureOwned(allocator, &native);
    var waiting_output = try world.Appliance.TurnOutput.decode(allocator, waiting_output_bytes, manifest.manifest_fingerprint, capacity);
    defer waiting_output.deinit(allocator);
    var waiting_closure = try world.Appliance.TurnClosure.decode(allocator, waiting_closure_bytes);
    defer waiting_closure.deinit(allocator);
    try validateOracleTurnClosure(allocator, waiting_closure, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, null);
    if (waiting_output.host_requests.len != 1) return error.ExpectedOneHostRequest;
    try writer.write("artifacts/outputs/one-port.waiting.turn-output", waiting_output_bytes);
    try writer.write("artifacts/transitions/one-port.waiting.turn-closure", waiting_closure_bytes);
    try writer.write("artifacts/states/one-port.waiting.checkpoint", waiting_closure.checkpoint_bytes);
    try writer.write("artifacts/states/one-port.waiting.capsule", waiting_closure.capsule_bytes);
    try writer.write("artifacts/effects/one-port.pending.host-requests", waiting_closure.pending_host_request_bytes);

    const resolution = try common.wireResolutionFor(allocator, waiting_output.host_requests[0], .responded, 0xA100_0002);
    var resolution_bytes: std.ArrayList(u8) = .empty;
    try resolution.encode(&resolution_bytes, allocator);
    const continue_turn = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = waiting_closure.closure_fingerprint,
        .previous_turn_receipt_fingerprint = waiting_output.turn_receipt.receipt_fingerprint,
        .turn_sequence_number = 1,
        .resolutions = &.{resolution},
    });
    const continue_bytes = try continue_turn.encode(allocator);
    try validateStandaloneResolutionInput(allocator, resolution_bytes.items, continue_bytes, world.Appliance.TurnClosureLimits.fromCapacity(capacity));
    try writer.write("artifacts/effects/one-port.responded.resolution-input", resolution_bytes.items);
    try writer.write("artifacts/inputs/one-port.continue.turn-input", continue_bytes);
    if (native.submitTurn(continue_bytes) != .completed) return error.ExpectedCompleted;
    const completed_output_bytes = try common.readOutputOwned(allocator, &native);
    const completed_closure_bytes = try common.readClosureOwned(allocator, &native);
    var completed_output = try world.Appliance.TurnOutput.decode(allocator, completed_output_bytes, manifest.manifest_fingerprint, capacity);
    defer completed_output.deinit(allocator);
    var completed_closure = try world.Appliance.TurnClosure.decode(allocator, completed_closure_bytes);
    defer completed_closure.deinit(allocator);
    try validateOracleTurnClosure(allocator, completed_closure, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, &waiting_closure);
    try writer.write("artifacts/outputs/one-port.completed.turn-output", completed_output_bytes);
    try writer.write("artifacts/transitions/one-port.completed.turn-closure", completed_closure_bytes);
    try writer.write("artifacts/states/one-port.completed.checkpoint", completed_closure.checkpoint_bytes);
    try writer.write("artifacts/states/one-port.completed.capsule", completed_closure.capsule_bytes);
    try writer.write("artifacts/results/one-port.root-result", completed_closure.root_result_bytes);
    try writer.write("artifacts/history/one-port.archive-append-batch", completed_closure.archive_append_batch_bytes);

    const transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: one-port-execution\n" ++
            "owner_surface: Appliance/TurnClosure\n" ++
            "result_transport_owner: Wire.TurnInput\n" ++
            "waiting_status: {s}\n" ++
            "completed_status: {s}\n" ++
            "request_count: {d}\n" ++
            "parent_closure_fingerprint: 0x{x:0>16}\n" ++
            "completed_closure_fingerprint: 0x{x:0>16}\n" ++
            "result_bytes_present: true\n" ++
            "archive_append_present: true\n",
        .{
            @tagName(waiting_output.status),
            @tagName(completed_output.status),
            waiting_output.host_requests.len,
            waiting_closure.closure_fingerprint,
            completed_closure.closure_fingerprint,
        },
    );
    try writer.write("cases/one-port-execution.txt", transcript);
}

fn buildLoadedProviderImage(allocator: std.mem.Allocator) !world.Executable.Image {
    const root_bytes = try fixtures.ProviderPorts.Target.Module.fullImage(allocator);
    const provider_bytes = try fixtures.Strict.Target.Module.fullImage(allocator);
    var builder = world.Executable.Builder.init(allocator, .{
        .runtime_profile = universal.executable_runtime_profile,
        .linker_policy = .strict_closed,
        .metadata = "world-image-v1-oracle.internal-provider",
    });
    defer builder.deinit();
    try builder.addRootModule(root_bytes);
    try builder.addProviderModule(provider_bytes);
    var prepared = try builder.prepare();
    defer prepared.deinit();
    return prepared.seal();
}

fn emitInternalProvider(allocator: std.mem.Allocator, writer: *Writer) !void {
    var image = try buildLoadedProviderImage(allocator);
    defer image.deinit(allocator);
    const image_bytes = try image.encode(allocator);
    try writer.write("artifacts/images/internal-provider.executable-image", image_bytes);
    var loaded_image = try world.Executable.Image.decode(allocator, image_bytes, .{
        .max_image_bytes = image_bytes.len,
    });
    defer loaded_image.deinit(allocator);

    const capacity = universal.abi_capacity;
    const core = try world.Appliance.Core.initExecutable(allocator, loaded_image, .{
        .profile = .wasm_small,
        .capacity = capacity,
        .supported_runtime_profile = universal.executable_runtime_profile,
        .metadata = "world-image-v1-oracle.internal-provider",
    });
    var native = world.Appliance.Native.init(core);
    defer native.deinit();
    const manifest = native.core.readManifest();
    const manifest_bytes = try manifest.encode(allocator);
    defer allocator.free(manifest_bytes);
    try writeValidatedApplianceManifest(allocator, writer, "artifacts/manifests/internal-provider.appliance-manifest", manifest.manifest_fingerprint, manifest_bytes);

    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    try writer.write("artifacts/inputs/internal-provider.boot.turn-input", boot_bytes);
    if (native.submitTurn(boot_bytes) != .completed) return error.ExpectedCompleted;
    const output_bytes = try common.readOutputOwned(allocator, &native);
    const closure_bytes = try common.readClosureOwned(allocator, &native);
    var output = try world.Appliance.TurnOutput.decode(allocator, output_bytes, manifest.manifest_fingerprint, capacity);
    defer output.deinit(allocator);
    var closure = try world.Appliance.TurnClosure.decode(allocator, closure_bytes);
    defer closure.deinit(allocator);
    try validateOracleTurnClosure(
        allocator,
        closure,
        capacity,
        loaded_image.image_fingerprint,
        manifest.manifest_fingerprint,
        null,
    );
    if (output.host_requests.len != 0) return error.UnexpectedHostRequest;
    try writer.write("artifacts/outputs/internal-provider.completed.turn-output", output_bytes);
    try writer.write("artifacts/transitions/internal-provider.completed.turn-closure", closure_bytes);
    try writer.write("artifacts/states/internal-provider.completed.capsule", closure.capsule_bytes);
    try writer.write("artifacts/results/internal-provider.root-result", closure.root_result_bytes);

    const transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: internal-provider-execution\n" ++
            "owner_surface: Executable/Runspace/Fabric/TurnClosure\n" ++
            "status: {s}\n" ++
            "module_count: {d}\n" ++
            "provider_module_count: 1\n" ++
            "route_count: {d}\n" ++
            "external_request_count: {d}\n" ++
            "image_fingerprint: 0x{x:0>16}\n" ++
            "closure_fingerprint: 0x{x:0>16}\n",
        .{
            @tagName(output.status),
            loaded_image.module_set.modules.len,
            loaded_image.dispatch_image.route_ids.len,
            output.host_requests.len,
            loaded_image.image_fingerprint,
            closure.closure_fingerprint,
        },
    );
    try writer.write("cases/internal-provider-execution.txt", transcript);
}

fn activeProviderRequest(target_ref: world.TargetRef, world_port_id: u32, seed: u64) world.Frame.Request {
    return world.Frame.Request.init(.{
        .world_surface_fingerprint = target_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
        .world_port_id = world_port_id,
        .residual_site_index = world_port_id,
        .residual_site_fingerprint = seed,
        .request_fingerprint = seed ^ 0x5150,
        .turn_index = 0,
        .expected_response_value_table_id = 1,
    });
}

fn emitActiveProvider(allocator: std.mem.Allocator, writer: *Writer) !void {
    const parent_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    var source = world.Runspace.init(allocator, .{});
    var source_destroyed = false;
    defer if (!source_destroyed) source.deinit();

    const parent_handle = world.RunHandle.init(.{
        .runspace_fingerprint = source.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
    });
    const provider_handle = world.RunHandle.init(.{
        .runspace_fingerprint = source.runspace_fingerprint,
        .local_run_id = 1,
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
    });
    const parent_request = activeProviderRequest(parent_ref, 0, 0xA103_0001);
    const provider_request = activeProviderRequest(provider_ref, 0, 0xA103_0002);
    const parent_state = world.RunState.init(.{
        .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
        .pending_request_fingerprint = parent_request.frame_fingerprint,
        .turn_index = parent_request.turn_index,
        .status = .parked_on_port,
    });
    const provider_state = world.RunState.init(.{
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .pending_request_fingerprint = provider_request.frame_fingerprint,
        .turn_index = provider_request.turn_index,
        .status = .parked_on_port,
    });
    const parent_run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = parent_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = parent_state,
        .pending_request_frame = parent_request,
    });
    const provider_run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = provider_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
        .current_state = provider_state,
        .pending_request_frame = provider_request,
    });
    try source.slots.append(allocator, world.Runspace.RunSlot.fromState(.{
        .handle = parent_handle,
        .target_ref = parent_ref,
        .current_state = parent_state,
        .status = .parked_on_port,
        .pending_mailbox_id = 0,
        .installed_run_image = parent_run_image,
        .owns_installed_run_image = true,
    }));
    try source.slots.append(allocator, world.Runspace.RunSlot.fromState(.{
        .handle = provider_handle,
        .target_ref = provider_ref,
        .current_state = provider_state,
        .status = .parked_on_port,
        .pending_mailbox_id = 1,
        .parent_run_handle_fingerprint = parent_handle.handle_fingerprint,
        .installed_run_image = provider_run_image,
        .owns_installed_run_image = true,
    }));
    const parent_pending = try source.mailbox.push(.{
        .run_handle = parent_handle,
        .mailbox_id = 0,
        .request = parent_request,
        .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
        .inserted_event_index = 0,
    });
    const provider_pending = try source.mailbox.push(.{
        .run_handle = provider_handle,
        .mailbox_id = 1,
        .request = provider_request,
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .inserted_event_index = 1,
    });
    source.next_mailbox_id = 2;
    const root_import = world.ImportRequirement.fromTargetPort(fixtures.Ports.Target, 0);
    const mapping = world.Fabric.ValueMapping.init(.{
        .kind = .provider_result_to_parent_response,
        .parent_response_value_table_id = root_import.response_value_table_id,
        .provider_result_value_table_id = root_import.response_value_table_id,
    });
    const route = world.Fabric.Route.init(.{
        .route_id = 0xA103_0003,
        .kind = .target_export,
        .parent_world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .parent_target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .parent_world_port_id = 0,
        .provider_target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .provider_world_surface_fingerprint = provider_ref.world_surface_fingerprint,
        .provider_target_certificate_fingerprint = provider_ref.target_certificate_fingerprint,
        .response_value_mapping_fingerprint = mapping.mapping_fingerprint,
        .metadata = "world-image-v1-oracle.active-provider",
    });
    const plan = world.Fabric.Plan.init(.{
        .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
        .world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .routes = &.{route},
        .value_mappings = &.{mapping},
    });
    try source.fabric_plan_fingerprints.append(allocator, plan.plan_fingerprint);
    try source.fabric_routes.append(allocator, route);
    try source.fabric_route_plan_fingerprints.append(allocator, plan.plan_fingerprint);
    try source.fabric_value_mappings.append(allocator, mapping);
    const invocation = world.Fabric.Invocation.init(.{
        .plan_fingerprint = plan.plan_fingerprint,
        .route_fingerprint = route.route_fingerprint,
        .parent_run_handle_fingerprint = parent_handle.handle_fingerprint,
        .parent_pending_port_fingerprint = parent_pending.pending_port_fingerprint,
        .parent_mailbox_id = 0,
        .request_frame_fingerprint = parent_request.frame_fingerprint,
        .provider_run_handle_fingerprint = provider_handle.handle_fingerprint,
        .depth = 1,
        .sequence = 0,
        .status = .provider_parked,
    });
    try source.fabric_invocations.append(allocator, invocation);

    var source_capsule = try world.Capsule.freezeRunspace(&source, .{ .allow_active_fabric_parked = true });
    defer source_capsule.deinit(allocator);
    const source_capsule_bytes = try source_capsule.encode(allocator);
    var decoded_source_capsule = try world.Capsule.Image.decode(allocator, source_capsule_bytes);
    defer decoded_source_capsule.deinit(allocator);
    try decoded_source_capsule.validate(.{});
    const provider_request_bytes = try provider_request.encode(allocator);
    var decoded_provider_request = try world.Frame.Request.decode(allocator, provider_request_bytes);
    defer decoded_provider_request.deinit(allocator);
    const roundtrip_provider_request_bytes = try decoded_provider_request.encode(allocator);
    defer allocator.free(roundtrip_provider_request_bytes);
    if (!std.mem.eql(u8, provider_request_bytes, roundtrip_provider_request_bytes) or
        decoded_provider_request.frame_fingerprint != provider_request.frame_fingerprint)
    {
        return error.RequestFrameMismatch;
    }
    try writer.write("artifacts/states/active-provider.source.capsule", source_capsule_bytes);
    try writer.write("artifacts/effects/active-provider.external.request-frame", provider_request_bytes);
    source.deinit();
    source_destroyed = true;

    var receiver = world.Runspace.init(allocator, .{});
    defer receiver.deinit();
    const restore_options: world.Capsule.ThawOptions = .{
        .mode = .restore_parked,
        .require_local_permit = false,
        .require_link_match = false,
    };
    var thaw_plan = try world.Capsule.planThaw(decoded_source_capsule, parent_ref.target_ref_fingerprint, 0, 0xA103_0004, restore_options);
    defer thaw_plan.deinit(allocator);
    try thaw_plan.validate();
    var restore = try world.Capsule.thawIntoRunspace(decoded_source_capsule, &receiver, parent_ref.target_ref_fingerprint, 0, 0xA103_0004, restore_options);
    defer restore.deinit(allocator);
    try restore.validate();
    if (!restore.accepted) return error.ExpectedRestoreAccepted;
    if (thaw_plan.require_local_permit or thaw_plan.require_link_match) return error.UnexpectedRestoreAuthorityRequirement;
    if (restore.thaw_plan_fingerprint != thaw_plan.thaw_plan_fingerprint) return error.RestorePlanMismatch;
    if (restore.warnings.len != 1 or restore.warnings[0] != .metadata_only) return error.ExpectedMetadataOnlyRestoreWarning;
    var migrated_capsule = try world.Capsule.freezeRunspace(&receiver, .{ .allow_active_fabric_parked = true });
    defer migrated_capsule.deinit(allocator);
    const migrated_capsule_bytes = try migrated_capsule.encode(allocator);
    var decoded_migrated_capsule = try world.Capsule.Image.decode(allocator, migrated_capsule_bytes);
    defer decoded_migrated_capsule.deinit(allocator);
    try decoded_migrated_capsule.validate(.{});
    try writer.write("artifacts/states/active-provider.migrated.capsule", migrated_capsule_bytes);

    var restored_provider_mailbox_id: ?u64 = null;
    for (receiver.slots.items) |slot| {
        if (slot.parent_run_handle_fingerprint != null) {
            restored_provider_mailbox_id = slot.pending_mailbox_id;
            break;
        }
    }
    const provider_event = try receiver.respondActiveFabricProviderValue(restored_provider_mailbox_id orelse return error.ExpectedPendingRequestFrame, @as(i32, 1));
    const restored_invocation = receiver.fabric_invocations.items[0];
    const root_event = try receiver.respondFromFabric(restored_invocation);
    var completed_capsule = try world.Capsule.freezeRunspace(&receiver, .{});
    defer completed_capsule.deinit(allocator);
    const completed_capsule_bytes = try completed_capsule.encode(allocator);
    var decoded_completed_capsule = try world.Capsule.Image.decode(allocator, completed_capsule_bytes);
    defer decoded_completed_capsule.deinit(allocator);
    try decoded_completed_capsule.validate(.{});
    try writer.write("artifacts/states/active-provider.completed.capsule", completed_capsule_bytes);

    const parked_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: provider-parked-externally\n" ++
            "owner_surface: Runspace/Fabric/Capsule\n" ++
            "fixture_provenance: synthetic-owner-state\n" ++
            "parent_status: parked_on_port\n" ++
            "provider_status: parked_on_port\n" ++
            "fabric_invocation_status: provider_parked\n" ++
            "pending_port_fingerprint: 0x{x:0>16}\n" ++
            "capsule_fingerprint: 0x{x:0>16}\n",
        .{ provider_pending.pending_port_fingerprint, source_capsule.image_fingerprint },
    );
    try writer.write("cases/provider-parked-externally.txt", parked_transcript);

    const restore_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: active-provider-restore\n" ++
            "owner_surface: Capsule/Runspace/Fabric\n" ++
            "fixture_provenance: synthetic-owner-state\n" ++
            "restore_accepted: true\n" ++
            "restore_evidence_scope: metadata_relocation_only\n" ++
            "restore_warning: {s}\n" ++
            "require_local_permit: {}\n" ++
            "require_link_match: {}\n" ++
            "receiver_authority_claimed: false\n" ++
            "restored_route_count: {d}\n" ++
            "restored_invocation_count: {d}\n" ++
            "provider_completed: {}\n" ++
            "root_completed: {}\n" ++
            "completed_capsule_fingerprint: 0x{x:0>16}\n" ++
            "completed_state_artifact: artifacts/states/active-provider.completed.capsule\n",
        .{
            @tagName(restore.warnings[0]),
            thaw_plan.require_local_permit,
            thaw_plan.require_link_match,
            receiver.fabric_routes.items.len,
            receiver.fabric_invocations.items.len,
            provider_event.kind == .run_completed,
            root_event.kind == .run_completed,
            completed_capsule.image_fingerprint,
        },
    );
    try writer.write("cases/active-provider-restore.txt", restore_transcript);

    const migration_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: migration\n" ++
            "owner_surface: Capsule/Runspace/Fabric\n" ++
            "fixture_provenance: synthetic-owner-state\n" ++
            "source_destroyed: {}\n" ++
            "receiver_fresh_instance: true\n" ++
            "restore_accepted: true\n" ++
            "migration_evidence_scope: metadata_relocation_only\n" ++
            "restore_warning: {s}\n" ++
            "require_local_permit: {}\n" ++
            "require_link_match: {}\n" ++
            "receiver_authority_claimed: false\n" ++
            "source_capsule_fingerprint: 0x{x:0>16}\n" ++
            "migrated_capsule_fingerprint: 0x{x:0>16}\n" ++
            "completed_after_migration: {}\n" ++
            "completed_capsule_fingerprint: 0x{x:0>16}\n" ++
            "completed_state_artifact: artifacts/states/active-provider.completed.capsule\n",
        .{
            source_destroyed,
            @tagName(restore.warnings[0]),
            thaw_plan.require_local_permit,
            thaw_plan.require_link_match,
            source_capsule.image_fingerprint,
            migrated_capsule.image_fingerprint,
            provider_event.kind == .run_completed and root_event.kind == .run_completed,
            completed_capsule.image_fingerprint,
        },
    );
    try writer.write("cases/migration.txt", migration_transcript);
}

const RetryParent = struct {
    closure_bytes: []const u8,
    closure: world.Appliance.TurnClosure,
};

const RetryEffectFixture = struct {
    call_count: usize = 0,

    fn resolve(
        self: *@This(),
        allocator: std.mem.Allocator,
        request: world.Appliance.HostRequest,
    ) ![]const u8 {
        if (self.call_count != 0) return error.DuplicateRetryEffectExecution;
        const response_bytes = try common.responseValueImageBytes(allocator, request, 0xA106_0002);
        self.call_count += 1;
        return response_bytes;
    }
};

fn validateOracleTurnClosure(
    allocator: std.mem.Allocator,
    closure: world.Appliance.TurnClosure,
    capacity: world.Appliance.Capacity,
    executable_image_fingerprint: u64,
    manifest_fingerprint: u64,
    parent: ?*const world.Appliance.TurnClosure,
) !void {
    var options: world.Appliance.TurnClosureValidation = .{
        .expected_executable_image_fingerprint = executable_image_fingerprint,
        .expected_manifest_fingerprint = manifest_fingerprint,
        .limits = world.Appliance.TurnClosureLimits.fromCapacity(capacity),
        .bundle_options = .{ .allow_external_dependencies = true },
    };
    if (parent) |parent_closure| {
        try world.Appliance.validateTurnClosureParentContinuity(closure, parent_closure.*);
        options.expected_parent_closure_fingerprint = parent_closure.closure_fingerprint;
        options.expected_parent_state_fingerprint = parent_closure.resulting_state_fingerprint;
        options.expected_parent_chronicle_cursor_fingerprint = parent_closure.chronicle_resulting_cursor_fingerprint;
        options.expected_archive_parent_moment_fingerprint = parent_closure.archive_resulting_moment_fingerprint;
        options.expected_archive_parent_seal_fingerprint = parent_closure.archive_resulting_seal_fingerprint;
    } else {
        if (closure.parent_closure_fingerprint != null or
            closure.archive_parent_moment_fingerprint != null or
            closure.archive_parent_seal_fingerprint != null)
        {
            return error.InvalidClosureParent;
        }
    }
    try closure.validate(allocator, options);
}

fn makeRetryParent(
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    capacity: world.Appliance.Capacity,
    executable_image_fingerprint: u64,
) !RetryParent {
    var core = world.Appliance.Core.initWithCapacity(allocator, manifest, common.PortsAppliance.memoryPlan(), capacity);
    core.executable_image_fingerprint = executable_image_fingerprint;
    var native = world.Appliance.Native.init(core);
    defer native.deinit();
    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    if (native.submitTurn(boot_bytes) != .needs_host) return error.ExpectedNeedsHost;
    const closure_bytes = try common.readClosureOwned(allocator, &native);
    var closure = try world.Appliance.TurnClosure.decode(allocator, closure_bytes);
    errdefer closure.deinit(allocator);
    try validateOracleTurnClosure(allocator, closure, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, null);
    return .{
        .closure_bytes = closure_bytes,
        .closure = closure,
    };
}

fn nativeFromClosure(
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    capacity: world.Appliance.Capacity,
    executable_image_fingerprint: u64,
    closure_bytes: []const u8,
) !world.Appliance.Native {
    var closure = try world.Appliance.TurnClosure.decode(allocator, closure_bytes);
    defer closure.deinit(allocator);
    const checkpoint_bytes = try closure.materializeCheckpoint(allocator);
    var checkpoint = try world.Appliance.Checkpoint.decode(allocator, checkpoint_bytes, manifest.manifest_fingerprint, capacity);
    defer checkpoint.deinit(allocator);
    var core = world.Appliance.Core.initWithCapacity(allocator, manifest, common.PortsAppliance.memoryPlan(), capacity);
    core.executable_image_fingerprint = executable_image_fingerprint;
    errdefer core.deinit();
    try core.restore(checkpoint);
    var native = world.Appliance.Native.init(core);
    native.last_closure_bytes = try allocator.dupe(u8, closure_bytes);
    native.last_closure_owned = true;
    return native;
}

test "oracle child closure requires its parent witness" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const executable_image_fingerprint: u64 = 0xA106_0000_0000_1001;
    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    var parent = try makeRetryParent(allocator, manifest, capacity, executable_image_fingerprint);
    defer parent.closure.deinit(allocator);

    var native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer native.deinit();
    const request = native.core.outstanding_host_requests[0];
    const resolution = try common.wireResolutionFor(allocator, request, .responded, 0xA106_0002);
    const continue_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent.closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = native.core.previous_turn_receipt_fingerprint,
        .turn_sequence_number = native.core.current_turn_sequence_number + 1,
        .resolutions = &.{resolution},
    });
    const continue_bytes = try continue_input.encode(allocator);
    if (native.submitTurn(continue_bytes) != .completed) return error.ExpectedCompleted;
    const child_bytes = try common.readClosureOwned(allocator, &native);
    var child = try world.Appliance.TurnClosure.decode(allocator, child_bytes);
    defer child.deinit(allocator);

    try validateOracleTurnClosure(allocator, child, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, &parent.closure);
    try std.testing.expectError(
        error.InvalidClosureParent,
        validateOracleTurnClosure(allocator, child, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, null),
    );
}

fn emitRetry(allocator: std.mem.Allocator, writer: *Writer) !void {
    const executable_image_fingerprint: u64 = 0xA106_0000_0000_0001;
    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    var parent = try makeRetryParent(allocator, manifest, capacity, executable_image_fingerprint);
    defer parent.closure.deinit(allocator);
    try writer.write("artifacts/transitions/retry.parent.turn-closure", parent.closure_bytes);
    try writer.write("artifacts/states/retry.parent.checkpoint", parent.closure.checkpoint_bytes);

    var first_native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer first_native.deinit();
    if (first_native.core.outstanding_host_requests.len != 1) return error.ExpectedOneHostRequest;
    const request = first_native.core.outstanding_host_requests[0];
    var effect_fixture: RetryEffectFixture = .{};
    const response_bytes = try effect_fixture.resolve(allocator, request);
    const resolution = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .status = .responded,
        .response_value_image_bytes = response_bytes,
        .host_claim_bytes = "world-image-v1-oracle.effect-called-once",
        .attempt_number = 1,
        .metadata = "persisted-before-world-submission",
    });
    var resolution_bytes: std.ArrayList(u8) = .empty;
    try resolution.encode(&resolution_bytes, allocator);
    const continue_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent.closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = first_native.core.previous_turn_receipt_fingerprint,
        .turn_sequence_number = first_native.core.current_turn_sequence_number + 1,
        .resolutions = &.{resolution},
    });
    const continue_bytes = try continue_input.encode(allocator);
    try validateStandaloneResolutionInput(allocator, resolution_bytes.items, continue_bytes, world.Appliance.TurnClosureLimits.fromCapacity(capacity));
    try writer.write("artifacts/effects/retry.persisted.resolution-input", resolution_bytes.items);
    try writer.write("artifacts/inputs/retry.continue.turn-input", continue_bytes);
    if (first_native.submitTurn(continue_bytes) != .completed) return error.ExpectedCompleted;
    const first_output_bytes = try common.readOutputOwned(allocator, &first_native);
    const first_closure_bytes = try common.readClosureOwned(allocator, &first_native);
    var first_output = try world.Appliance.TurnOutput.decode(allocator, first_output_bytes, manifest.manifest_fingerprint, capacity);
    defer first_output.deinit(allocator);
    var first_closure = try world.Appliance.TurnClosure.decode(allocator, first_closure_bytes);
    defer first_closure.deinit(allocator);
    try validateOracleTurnClosure(allocator, first_closure, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, &parent.closure);
    try writer.write("artifacts/outputs/retry.first.turn-output", first_output_bytes);
    try writer.write("artifacts/transitions/retry.first.turn-closure", first_closure_bytes);

    var retry_native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer retry_native.deinit();
    if (retry_native.submitTurn(continue_bytes) != .completed) return error.ExpectedCompleted;
    const retry_output_bytes = try common.readOutputOwned(allocator, &retry_native);
    const retry_closure_bytes = try common.readClosureOwned(allocator, &retry_native);
    var retry_output = try world.Appliance.TurnOutput.decode(allocator, retry_output_bytes, manifest.manifest_fingerprint, capacity);
    defer retry_output.deinit(allocator);
    var retry_closure = try world.Appliance.TurnClosure.decode(allocator, retry_closure_bytes);
    defer retry_closure.deinit(allocator);
    try validateOracleTurnClosure(allocator, retry_closure, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, &parent.closure);
    try writer.write("artifacts/outputs/retry.repeated.turn-output", retry_output_bytes);
    try writer.write("artifacts/transitions/retry.repeated.turn-closure", retry_closure_bytes);
    if (!std.mem.eql(u8, first_output_bytes, retry_output_bytes)) return error.RetryOutputMismatch;
    if (!std.mem.eql(u8, first_closure_bytes, retry_closure_bytes)) return error.RetryClosureMismatch;
    if (effect_fixture.call_count != 1) return error.UnexpectedRetryEffectCallCount;

    const transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: lost-output-retry\n" ++
            "owner_surface: Appliance/TurnClosure\n" ++
            "result_transport_owner: Wire.TurnInput\n" ++
            "effect_call_count: 1\n" ++
            "result_persisted_before_step: true\n" ++
            "fresh_runtime_count: 2\n" ++
            "fresh_runtimes_restored_from_authoritative_parent: true\n" ++
            "identical_turn_input_resubmitted: true\n" ++
            "persisted_resolution_input_reused: true\n" ++
            "first_retry_output_byte_equal: true\n" ++
            "first_retry_closure_byte_equal: true\n" ++
            "wire_restore_equivalence_claimed: false\n" ++
            "parent_closure_fingerprint: 0x{x:0>16}\n" ++
            "result_closure_fingerprint: 0x{x:0>16}\n",
        .{ parent.closure.closure_fingerprint, first_closure.closure_fingerprint },
    );
    try writer.write("cases/lost-output-retry.txt", transcript);
}

fn emitReplay(allocator: std.mem.Allocator, writer: *Writer) !void {
    var transcript = world.Transcript.init(allocator);
    defer transcript.deinit();
    var fresh_runtime = boundary.Runtime.init(allocator);
    defer fresh_runtime.deinit();
    var fresh_ctx: ReplayCtx = .{};
    var fresh = try ReplayMachine.run(&fresh_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
    });
    defer fresh.deinit(allocator);
    var image = try transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(allocator);
    const image_bytes = try image.encode(allocator);
    try writer.write("artifacts/states/replay.transcript-image", image_bytes);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .completed_run);
    try run_image.validate(.{ .require_portable_values = true });
    const run_image_bytes = try run_image.encode(allocator);
    var decoded_run_image = try world.RunImage.decode(allocator, run_image_bytes);
    defer decoded_run_image.deinit(allocator);
    try decoded_run_image.validate(.{ .require_portable_values = true });
    try writer.write("artifacts/states/replay.completed.run-image", run_image_bytes);

    var decoded = try world.TranscriptImage.decode(allocator, image_bytes);
    defer decoded.deinit(allocator);
    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replayed = try ReplayMachine.run(&replay_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.replay,
        .transcript_image = &decoded,
    });
    defer replayed.deinit(allocator);
    if (fresh_ctx.calls != 1 or replayed.audit.replayed_response_count != 1 or fresh.value != replayed.value) {
        return error.ReplaySemanticMismatch;
    }

    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: replay-without-fresh-effect\n" ++
            "owner_surface: Machine/Transcript\n" ++
            "turn_closure_authority: false\n" ++
            "fresh_handler_calls: {d}\n" ++
            "replay_handler_calls: 0\n" ++
            "replayed_response_count: {d}\n" ++
            "fresh_result: {d}\n" ++
            "replay_result: {d}\n" ++
            "transcript_image_fingerprint: 0x{x:0>16}\n" ++
            "run_image_fingerprint: 0x{x:0>16}\n",
        .{
            fresh_ctx.calls,
            replayed.audit.replayed_response_count,
            fresh.value,
            replayed.value,
            image.transcript_image_fingerprint,
            run_image.run_image_fingerprint,
        },
    );
    try writer.write("cases/replay-without-fresh-effect.txt", case_transcript);
}

const BranchRun = struct {
    value: []const u8,
    transcript: world.Transcript,
    image: world.TranscriptImage,
};

fn runBranch(allocator: std.mem.Allocator, alternate: bool) !BranchRun {
    var transcript = world.Transcript.init(allocator);
    errdefer transcript.deinit();
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: BranchCtx = .{ .allocator = allocator, .alternate = alternate };
    var result = try BranchMachine.run(&runtime, .{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(allocator);
    const value = try allocator.dupe(u8, result.value);
    var image = try transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    errdefer image.deinit(allocator);
    return .{ .value = value, .transcript = transcript, .image = image };
}

fn forkBranchTranscript(
    allocator: std.mem.Allocator,
    baseline: *const world.Transcript,
    alternate: *const world.Transcript,
    checkpoint_event_index: usize,
) !world.Transcript {
    if (checkpoint_event_index > baseline.events.items.len or checkpoint_event_index > alternate.events.items.len) return error.InvalidFrameEncoding;
    var forked = world.Transcript.init(allocator);
    errdefer forked.deinit();
    for (baseline.events.items[0..checkpoint_event_index]) |event| try forked.append(event);
    for (alternate.events.items[checkpoint_event_index..]) |event| try forked.append(event);
    return forked;
}

fn emitBranching(allocator: std.mem.Allocator, writer: *Writer) !void {
    var baseline = try runBranch(allocator, false);
    defer {
        baseline.image.deinit(allocator);
        baseline.transcript.deinit();
    }
    var alternate = try runBranch(allocator, true);
    defer {
        alternate.image.deinit(allocator);
        alternate.transcript.deinit();
    }
    const checkpoint_event_index = 2;
    const checkpoint_event = baseline.image.events[checkpoint_event_index - 1];
    if (alternate.image.events[checkpoint_event_index - 1].request_fingerprint != checkpoint_event.request_fingerprint) {
        return error.BranchParentMismatch;
    }
    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = fixtures.Agent.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Agent.Target.Certificate.certificate_fingerprint,
        .event_index = checkpoint_event_index,
        .turn_index = checkpoint_event.turn_index orelse 0,
        .current_request_fingerprint = checkpoint_event.request_fingerprint,
        .transcript_prefix_fingerprint = checkpoint_event.event_fingerprint,
        .branch_id = 1,
        .status = .parked_on_port,
    });
    var forked_transcript = try forkBranchTranscript(allocator, &baseline.transcript, &alternate.transcript, checkpoint.event_index);
    defer forked_transcript.deinit();
    var forked_image = try forked_transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer forked_image.deinit(allocator);
    const baseline_image_bytes = try baseline.image.encode(allocator);
    const branch_image_bytes = try forked_image.encode(allocator);
    try writer.write("artifacts/states/branch.baseline.transcript-image", baseline_image_bytes);
    try writer.write("artifacts/states/branch.alternate.transcript-image", branch_image_bytes);

    const baseline_run_image = world.RunImage.fromTranscriptImage(fixtures.Agent.Target, baseline.image, .completed_run);
    try baseline_run_image.validate(.{ .require_portable_values = true });
    const baseline_run_bytes = try baseline_run_image.encode(allocator);
    var decoded_baseline_run = try world.RunImage.decode(allocator, baseline_run_bytes);
    defer decoded_baseline_run.deinit(allocator);
    try decoded_baseline_run.validate(.{ .require_portable_values = true });
    try writer.write("artifacts/states/branch.baseline.run-image", baseline_run_bytes);
    const projected_run_image = world.RunImage.fromTranscriptImage(fixtures.Agent.Target, forked_image, .branched_run);
    const projected_state = projected_run_image.current_state;
    if (projected_state.status != .completed or
        projected_state.final_response_fingerprint == null or
        projected_state.final_value_image_fingerprint == null or
        projected_state.turn_index <= checkpoint.turn_index)
    {
        return error.InvalidBranchStateProjection;
    }
    const target_ref = projected_run_image.target_ref;
    const branch = world.Timeline.Branch{
        .branch_id = 1,
        .parent_branch_id = null,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .branch_label = "world-image-v1-oracle.alternate",
        .start_event_index = checkpoint.event_index,
        .final_event_index = forked_image.events.len,
        .final_status = .completed,
        .event_count = forked_image.events.len - checkpoint.event_index,
        .response_count = forked_image.response_count,
    };
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = projected_state.transcript_image_fingerprint,
        .branch_id = 1,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .final_response_fingerprint = projected_state.final_response_fingerprint,
        .final_value_image_fingerprint = projected_state.final_value_image_fingerprint,
        .turn_index = projected_state.turn_index,
        .status = projected_state.status,
    });
    const branch_run_image = world.RunImage.init(.{
        .kind = .branched_run,
        .target_ref = target_ref,
        .import_set_fingerprint = projected_run_image.import_set_fingerprint,
        .transcript_image = forked_image,
        .current_state = state,
        .checkpoints = &.{checkpoint},
        .branches = @constCast(&[_]world.Timeline.Branch{branch}),
    });
    try branch_run_image.validate(.{ .require_portable_values = true });
    const branch_run_bytes = try branch_run_image.encode(allocator);
    try writer.write("artifacts/states/branch.alternate.run-image", branch_run_bytes);
    var decoded_branch_run = try world.RunImage.decode(allocator, branch_run_bytes);
    defer decoded_branch_run.deinit(allocator);
    try decoded_branch_run.validate(.{ .require_portable_values = true });
    if (decoded_branch_run.current_state.transcript_image_fingerprint != projected_state.transcript_image_fingerprint or
        decoded_branch_run.current_state.final_response_fingerprint != projected_state.final_response_fingerprint or
        decoded_branch_run.current_state.final_value_image_fingerprint != projected_state.final_value_image_fingerprint or
        decoded_branch_run.current_state.turn_index != projected_state.turn_index or
        decoded_branch_run.current_state.status != projected_state.status)
    {
        return error.InvalidBranchStateProjection;
    }

    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: branching\n" ++
            "owner_surface: Machine/Transcript/Timeline/RunImage\n" ++
            "turn_closure_authority: false\n" ++
            "checkpoint_fingerprint: 0x{x:0>16}\n" ++
            "common_parent_request_fingerprint: 0x{x:0>16}\n" ++
            "baseline_transcript_fingerprint: 0x{x:0>16}\n" ++
            "alternate_transcript_fingerprint: 0x{x:0>16}\n" ++
            "baseline_result: {s}\n" ++
            "alternate_result: {s}\n" ++
            "parent_unchanged: true\n",
        .{
            checkpoint.checkpoint_fingerprint,
            checkpoint.current_request_fingerprint orelse 0,
            baseline.image.transcript_image_fingerprint,
            forked_image.transcript_image_fingerprint,
            baseline.value,
            alternate.value,
        },
    );
    try writer.write("cases/branching.txt", case_transcript);
}

fn emitPartialBatch(allocator: std.mem.Allocator, writer: *Writer) !void {
    const executable_image_fingerprint: u64 = 0xA109_0000_0000_0001;
    const manifest = BatchAppliance.manifest();
    const capacity = world.Appliance.Capacity.wasm_agent;
    var core = world.Appliance.Core.initWithCapacity(allocator, manifest, BatchAppliance.memoryPlan(), capacity);
    core.executable_image_fingerprint = executable_image_fingerprint;
    var native = world.Appliance.Native.init(core);
    defer native.deinit();

    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_images = &.{"agent:prompt"},
    });
    const boot_bytes = try boot.encode(allocator);
    try writer.write("artifacts/inputs/partial-batch.boot.turn-input", boot_bytes);
    if (native.submitTurn(boot_bytes) != .needs_host) return error.ExpectedNeedsHost;
    const parent_output_bytes = try common.readOutputOwned(allocator, &native);
    const parent_closure_bytes = try common.readClosureOwned(allocator, &native);
    var parent_output = try world.Appliance.TurnOutput.decode(allocator, parent_output_bytes, manifest.manifest_fingerprint, capacity);
    defer parent_output.deinit(allocator);
    var parent_closure = try world.Appliance.TurnClosure.decode(allocator, parent_closure_bytes);
    defer parent_closure.deinit(allocator);
    try validateOracleTurnClosure(allocator, parent_closure, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, null);
    if (parent_output.host_requests.len != 2) return error.ExpectedBatchedRequests;
    try writer.write("artifacts/outputs/partial-batch.parent.turn-output", parent_output_bytes);
    try writer.write("artifacts/transitions/partial-batch.parent.turn-closure", parent_closure_bytes);

    const first_resolution = try common.wireResolutionFor(allocator, parent_output.host_requests[0], .responded, 0xA109_0002);
    const partial_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent_closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent_closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = parent_output.turn_receipt.receipt_fingerprint,
        .turn_sequence_number = 1,
        .resolutions = &.{first_resolution},
    });
    const partial_input_bytes = try partial_input.encode(allocator);
    try writer.write("artifacts/inputs/partial-batch.one-result.turn-input", partial_input_bytes);
    if (native.submitTurn(partial_input_bytes) != .needs_host) return error.ExpectedNeedsHost;
    const partial_output_bytes = try common.readOutputOwned(allocator, &native);
    const partial_closure_bytes = try common.readClosureOwned(allocator, &native);
    var partial_output = try world.Appliance.TurnOutput.decode(allocator, partial_output_bytes, manifest.manifest_fingerprint, capacity);
    defer partial_output.deinit(allocator);
    var partial_closure = try world.Appliance.TurnClosure.decode(allocator, partial_closure_bytes);
    defer partial_closure.deinit(allocator);
    try validateOracleTurnClosure(allocator, partial_closure, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, &parent_closure);
    if (partial_output.host_requests.len != 1) return error.ExpectedOneHostRequest;
    if (partial_output.host_requests[0].request_fingerprint != parent_output.host_requests[1].request_fingerprint) return error.PartialBatchMismatch;
    try writer.write("artifacts/outputs/partial-batch.remaining.turn-output", partial_output_bytes);
    try writer.write("artifacts/transitions/partial-batch.remaining.turn-closure", partial_closure_bytes);
    try writer.write("artifacts/states/partial-batch.remaining.checkpoint", partial_closure.checkpoint_bytes);

    const second_resolution = try common.wireResolutionFor(allocator, partial_output.host_requests[0], .responded, 0xA109_0003);
    const final_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = partial_closure.closure_fingerprint,
        .expected_parent_state_fingerprint = partial_closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = partial_output.turn_receipt.receipt_fingerprint,
        .turn_sequence_number = 2,
        .resolutions = &.{second_resolution},
    });
    const final_input_bytes = try final_input.encode(allocator);
    try writer.write("artifacts/inputs/partial-batch.final-result.turn-input", final_input_bytes);
    if (native.submitTurn(final_input_bytes) != .completed) return error.ExpectedCompleted;
    const final_output_bytes = try common.readOutputOwned(allocator, &native);
    const final_closure_bytes = try common.readClosureOwned(allocator, &native);
    var final_output = try world.Appliance.TurnOutput.decode(allocator, final_output_bytes, manifest.manifest_fingerprint, capacity);
    defer final_output.deinit(allocator);
    var final_closure = try world.Appliance.TurnClosure.decode(allocator, final_closure_bytes);
    defer final_closure.deinit(allocator);
    try validateOracleTurnClosure(allocator, final_closure, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, &partial_closure);
    if (final_output.status != .completed or final_closure.status != .completed or final_output.host_requests.len != 0) return error.ExpectedCompleted;
    try writer.write("artifacts/outputs/partial-batch.completed.turn-output", final_output_bytes);
    try writer.write("artifacts/transitions/partial-batch.completed.turn-closure", final_closure_bytes);

    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: partial-response-batch\n" ++
            "owner_surface: Appliance/TurnClosure\n" ++
            "result_transport_owner: Wire.TurnInput\n" ++
            "initial_request_count: {d}\n" ++
            "supplied_first_batch_count: 1\n" ++
            "remaining_request_count: {d}\n" ++
            "remaining_request_identity_preserved: true\n" ++
            "closure_chain_validated: true\n" ++
            "final_status: {s}\n" ++
            "parent_closure_fingerprint: 0x{x:0>16}\n" ++
            "partial_closure_fingerprint: 0x{x:0>16}\n",
        .{
            parent_output.host_requests.len,
            partial_output.host_requests.len,
            @tagName(final_output.status),
            parent_closure.closure_fingerprint,
            partial_closure.closure_fingerprint,
        },
    );
    try writer.write("cases/partial-response-batch.txt", case_transcript);
}

fn emitDeterministicFailure(allocator: std.mem.Allocator, writer: *Writer) !void {
    const executable_image_fingerprint: u64 = 0xA10A_0000_0000_0001;
    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    var core = world.Appliance.Core.initWithCapacity(allocator, manifest, common.PortsAppliance.memoryPlan(), capacity);
    core.executable_image_fingerprint = executable_image_fingerprint;
    var native = world.Appliance.Native.init(core);
    defer native.deinit();

    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    if (native.submitTurn(boot_bytes) != .needs_host) return error.ExpectedNeedsHost;
    const parent_output_bytes = try common.readOutputOwned(allocator, &native);
    const parent_closure_bytes = try common.readClosureOwned(allocator, &native);
    var parent_output = try world.Appliance.TurnOutput.decode(allocator, parent_output_bytes, manifest.manifest_fingerprint, capacity);
    defer parent_output.deinit(allocator);
    var parent_closure = try world.Appliance.TurnClosure.decode(allocator, parent_closure_bytes);
    defer parent_closure.deinit(allocator);
    try validateOracleTurnClosure(allocator, parent_closure, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, null);
    if (parent_output.status != .needs_host or parent_output.host_requests.len != 1 or parent_closure.status != .needs_host) return error.ExpectedNeedsHost;
    try writer.write("artifacts/outputs/failure.parent.turn-output", parent_output_bytes);
    try writer.write("artifacts/transitions/failure.parent.turn-closure", parent_closure_bytes);
    try writer.write("artifacts/states/failure.parent.checkpoint", parent_closure.checkpoint_bytes);
    const failed_resolution = try common.wireResolutionFor(allocator, parent_output.host_requests[0], .failed, 0);
    var failed_resolution_bytes: std.ArrayList(u8) = .empty;
    try failed_resolution.encode(&failed_resolution_bytes, allocator);
    const failed_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent_closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent_closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = parent_output.turn_receipt.receipt_fingerprint,
        .turn_sequence_number = 1,
        .resolutions = &.{failed_resolution},
    });
    const failed_input_bytes = try failed_input.encode(allocator);
    try validateStandaloneResolutionInput(allocator, failed_resolution_bytes.items, failed_input_bytes, world.Appliance.TurnClosureLimits.fromCapacity(capacity));
    try writer.write("artifacts/effects/failure.failed.resolution-input", failed_resolution_bytes.items);
    try writer.write("artifacts/inputs/failure.failed-result.turn-input", failed_input_bytes);
    if (native.submitTurn(failed_input_bytes) != .failed) return error.ExpectedFailed;
    const failed_output_bytes = try common.readOutputOwned(allocator, &native);
    const failed_closure_bytes = try common.readClosureOwned(allocator, &native);
    var failed_output = try world.Appliance.TurnOutput.decode(allocator, failed_output_bytes, manifest.manifest_fingerprint, capacity);
    defer failed_output.deinit(allocator);
    var failed_closure = try world.Appliance.TurnClosure.decode(allocator, failed_closure_bytes);
    defer failed_closure.deinit(allocator);
    try validateOracleTurnClosure(allocator, failed_closure, capacity, executable_image_fingerprint, manifest.manifest_fingerprint, &parent_closure);
    if (failed_output.status != .failed or failed_closure.status != .failed) return error.ExpectedFailed;
    try writer.write("artifacts/outputs/failure.failed.turn-output", failed_output_bytes);
    try writer.write("artifacts/transitions/failure.failed.turn-closure", failed_closure_bytes);
    try writer.write("artifacts/states/failure.failed.checkpoint", failed_closure.checkpoint_bytes);

    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: deterministic-failure\n" ++
            "owner_surface: Appliance/TurnClosure\n" ++
            "result_transport_owner: Wire.TurnInput\n" ++
            "accepted_result_status: failed\n" ++
            "transition_status: {s}\n" ++
            "next_state_status: failed\n" ++
            "root_result_present: {}\n" ++
            "parent_state_published: true\n" ++
            "parent_output_artifact: artifacts/outputs/failure.parent.turn-output\n" ++
            "parent_closure_artifact: artifacts/transitions/failure.parent.turn-closure\n" ++
            "parent_checkpoint_artifact: artifacts/states/failure.parent.checkpoint\n" ++
            "parent_closure_fingerprint: 0x{x:0>16}\n" ++
            "failed_closure_fingerprint: 0x{x:0>16}\n",
        .{
            @tagName(failed_output.status),
            failed_closure.root_result_bytes.len != 0,
            parent_closure.closure_fingerprint,
            failed_closure.closure_fingerprint,
        },
    );
    try writer.write("cases/deterministic-failure.txt", case_transcript);
}

fn emitCapacityExhaustion(allocator: std.mem.Allocator, writer: *Writer) !void {
    const tight = comptime blk: {
        var capacity = world.Appliance.Capacity.tiny_one_port;
        capacity.max_output_bytes = 1;
        break :blk capacity;
    };
    const TightAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = tight,
    });
    const manifest = TightAppliance.manifest();
    const core = world.Appliance.Core.initWithCapacity(allocator, manifest, TightAppliance.memoryPlan(), tight);
    var native = world.Appliance.Native.init(core);
    defer native.deinit();
    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    try writer.write("artifacts/inputs/capacity-exhaustion.boot.command", boot_bytes);
    try native.core.submit(boot_bytes);
    const before_failure = try captureNativeSemanticSnapshot(allocator, &native);
    if (!std.mem.eql(u8, before_failure.pending_command_bytes, boot_bytes)) return error.PendingCommandMismatch;
    var observed_error: ?anyerror = null;
    native.core.executeTurn() catch |err| {
        observed_error = err;
    };
    if (observed_error == null or observed_error.? != error.CapacityExceeded) return error.ExpectedCapacityExceeded;
    const after_failure = try captureNativeSemanticSnapshot(allocator, &native);
    if (!nativeSemanticSnapshotEqual(before_failure, after_failure)) return error.PartialSemanticMutation;
    if (!std.mem.eql(u8, after_failure.pending_command_bytes, boot_bytes)) return error.PendingCommandMismatch;
    if (native.core.state != .uninitialized or native.core.current_turn_sequence_number != 0 or native.core.previous_turn_receipt_fingerprint != null) {
        return error.PartialSemanticMutation;
    }
    if (native.core.outstanding_host_requests.len != 0 or
        native.core.outstanding_host_request != null or
        native.core.readOutput().len != 0 or
        native.core.pending_command == null)
    {
        return error.PartialSemanticMutation;
    }
    const state_snapshot = "core_state=uninitialized\nturn_sequence_number=0\nprevious_turn_receipt=null\noutstanding_host_request=null\noutput_bytes=0\npending_command_preserved=true\n";
    try writer.write("artifacts/states/capacity-exhaustion.after.txt", state_snapshot);
    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: capacity-exhaustion\n" ++
            "owner_surface: Appliance/Core\n" ++
            "turn_closure_produced: false\n" ++
            "error: {s}\n" ++
            "state_unchanged: true\n" ++
            "turn_sequence_number: 0\n" ++
            "output_bytes: 0\n" ++
            "pending_command_preserved: true\n",
        .{@errorName(observed_error.?)},
    );
    try writer.write("cases/capacity-exhaustion.txt", case_transcript);
}

const NativeSemanticSnapshot = struct {
    state: world.Appliance.CoreState,
    sequence: u64,
    previous_receipt: ?u64,
    pending_command_present: bool,
    pending_command_bytes: []const u8,
    pending_archive_append_batch_fingerprint: ?u64,
    pending_archive_resulting_cursor_fingerprint: ?u64,
    latest_archive_cursor_fingerprint: u64,
    latest_archive_moment_fingerprint: ?u64,
    latest_archive_seal_fingerprint: ?u64,
    latest_chronicle_cursor_fingerprint: ?u64,
    last_output_status: ?world.Appliance.TurnStatus,
    last_turn_status: ?world.Appliance.TurnStatus,
    outstanding_request_bytes: []const u8,
    legacy_outstanding_request_present: bool,
    legacy_outstanding_request_bytes: []const u8,
    output_bytes: []const u8,
    closure_bytes: []const u8,
};

fn encodeHostRequestsForSnapshot(allocator: std.mem.Allocator, host_requests: []const world.Appliance.HostRequest) ![]u8 {
    var encoded_requests: std.ArrayList(u8) = .empty;
    errdefer encoded_requests.deinit(allocator);
    for (host_requests) |request| {
        var encoded: std.ArrayList(u8) = .empty;
        defer encoded.deinit(allocator);
        try request.encode(&encoded, allocator);
        var length_bytes = [_]u8{0} ** 8;
        std.mem.writeInt(u64, &length_bytes, @intCast(encoded.items.len), .little);
        try encoded_requests.appendSlice(allocator, &length_bytes);
        try encoded_requests.appendSlice(allocator, encoded.items);
    }
    return encoded_requests.toOwnedSlice(allocator);
}

fn captureNativeSemanticSnapshot(allocator: std.mem.Allocator, native: *world.Appliance.Native) !NativeSemanticSnapshot {
    return .{
        .state = native.core.state,
        .sequence = native.core.current_turn_sequence_number,
        .previous_receipt = native.core.previous_turn_receipt_fingerprint,
        .pending_command_present = native.core.pending_command != null,
        .pending_command_bytes = if (native.core.pending_command) |command|
            try command.encode(allocator)
        else
            try allocator.dupe(u8, ""),
        .pending_archive_append_batch_fingerprint = native.core.pending_archive_append_batch_fingerprint,
        .pending_archive_resulting_cursor_fingerprint = if (native.core.pending_archive_resulting_cursor) |cursor| cursor.cursor_fingerprint else null,
        .latest_archive_cursor_fingerprint = native.core.latest_archive_cursor.cursor_fingerprint,
        .latest_archive_moment_fingerprint = native.core.latest_archive_moment_fingerprint,
        .latest_archive_seal_fingerprint = native.core.latest_archive_seal_fingerprint,
        .latest_chronicle_cursor_fingerprint = native.core.latest_chronicle_cursor_fingerprint,
        .last_output_status = native.core.last_output_status,
        .last_turn_status = native.core.last_turn_status,
        .outstanding_request_bytes = try encodeHostRequestsForSnapshot(allocator, native.core.outstanding_host_requests),
        .legacy_outstanding_request_present = native.core.outstanding_host_request != null,
        .legacy_outstanding_request_bytes = if (native.core.outstanding_host_request) |request|
            try encodeHostRequestsForSnapshot(allocator, &.{request})
        else
            try allocator.dupe(u8, ""),
        .output_bytes = try allocator.dupe(u8, native.core.readOutput()),
        .closure_bytes = try allocator.dupe(u8, native.last_closure_bytes),
    };
}

fn nativeSemanticSnapshotEqual(lhs: NativeSemanticSnapshot, rhs: NativeSemanticSnapshot) bool {
    return lhs.state == rhs.state and
        lhs.sequence == rhs.sequence and
        lhs.previous_receipt == rhs.previous_receipt and
        lhs.pending_command_present == rhs.pending_command_present and
        std.mem.eql(u8, lhs.pending_command_bytes, rhs.pending_command_bytes) and
        lhs.pending_archive_append_batch_fingerprint == rhs.pending_archive_append_batch_fingerprint and
        lhs.pending_archive_resulting_cursor_fingerprint == rhs.pending_archive_resulting_cursor_fingerprint and
        lhs.latest_archive_cursor_fingerprint == rhs.latest_archive_cursor_fingerprint and
        lhs.latest_archive_moment_fingerprint == rhs.latest_archive_moment_fingerprint and
        lhs.latest_archive_seal_fingerprint == rhs.latest_archive_seal_fingerprint and
        lhs.latest_chronicle_cursor_fingerprint == rhs.latest_chronicle_cursor_fingerprint and
        lhs.last_output_status == rhs.last_output_status and
        lhs.last_turn_status == rhs.last_turn_status and
        std.mem.eql(u8, lhs.outstanding_request_bytes, rhs.outstanding_request_bytes) and
        lhs.legacy_outstanding_request_present == rhs.legacy_outstanding_request_present and
        std.mem.eql(u8, lhs.legacy_outstanding_request_bytes, rhs.legacy_outstanding_request_bytes) and
        std.mem.eql(u8, lhs.output_bytes, rhs.output_bytes) and
        std.mem.eql(u8, lhs.closure_bytes, rhs.closure_bytes);
}

fn requireDiagnosticPublishedAfterReject(before_error_len: usize, native: *world.Appliance.Native) !void {
    if (before_error_len != 0 or native.lastErrorLen() == 0) return error.MissingRejectedSubmissionDiagnostic;
}

test "semantic snapshot distinguishes plural and legacy singular request carriers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    const executable_image_fingerprint: u64 = 0xA10C_0000_0000_1001;
    var parent = try makeRetryParent(allocator, manifest, capacity, executable_image_fingerprint);
    defer parent.closure.deinit(allocator);
    var native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer native.deinit();

    try std.testing.expect(native.core.outstanding_host_requests.len != 0);
    try std.testing.expect(native.core.outstanding_host_request != null);
    const before = try captureNativeSemanticSnapshot(allocator, &native);
    native.core.outstanding_host_request = null;
    const after = try captureNativeSemanticSnapshot(allocator, &native);
    try std.testing.expect(!nativeSemanticSnapshotEqual(before, after));
}

fn replaceUniqueU64LittleEndian(bytes: []u8, from: u64, to: u64) !void {
    var from_bytes = [_]u8{0} ** 8;
    var to_bytes = [_]u8{0} ** 8;
    std.mem.writeInt(u64, &from_bytes, from, .little);
    std.mem.writeInt(u64, &to_bytes, to, .little);
    var found: ?usize = null;
    var cursor: usize = 0;
    while (cursor + from_bytes.len <= bytes.len) : (cursor += 1) {
        if (!std.mem.eql(u8, bytes[cursor .. cursor + from_bytes.len], &from_bytes)) continue;
        if (found != null) return error.NonUniqueMutationTarget;
        found = cursor;
    }
    const offset = found orelse return error.MutationTargetMissing;
    @memcpy(bytes[offset .. offset + to_bytes.len], &to_bytes);
}

fn emitMalformed(allocator: std.mem.Allocator, writer: *Writer) !void {
    var image = try buildLoadedProviderImage(allocator);
    defer image.deinit(allocator);
    const image_bytes = try image.encode(allocator);
    const malformed_image = try allocator.alloc(u8, image_bytes.len + 1);
    @memcpy(malformed_image[0..image_bytes.len], image_bytes);
    malformed_image[malformed_image.len - 1] = 0;
    try writer.write("artifacts/malformed/executable-image.trailing-byte", malformed_image);
    var image_error: ?anyerror = null;
    var decoded_image: ?world.Executable.Image = world.Executable.Image.decode(allocator, malformed_image, .{
        .max_image_bytes = malformed_image.len,
    }) catch |err| blk: {
        image_error = err;
        break :blk null;
    };
    if (decoded_image) |*decoded| decoded.deinit(allocator);
    if (image_error == null) return error.MalformedImageAccepted;

    const executable_image_fingerprint: u64 = 0xA10C_0000_0000_0001;
    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    var parent = try makeRetryParent(allocator, manifest, capacity, executable_image_fingerprint);
    defer parent.closure.deinit(allocator);
    const malformed_state = try allocator.alloc(u8, parent.closure_bytes.len + 1);
    @memcpy(malformed_state[0..parent.closure_bytes.len], parent.closure_bytes);
    malformed_state[malformed_state.len - 1] = 0;
    try writer.write("artifacts/malformed/state.turn-closure.trailing-byte", malformed_state);
    var state_error: ?anyerror = null;
    var decoded_state: ?world.Appliance.TurnClosure = world.Appliance.TurnClosure.decode(allocator, malformed_state) catch |err| blk: {
        state_error = err;
        break :blk null;
    };
    if (decoded_state) |*decoded| decoded.deinit(allocator);
    if (state_error == null) return error.MalformedStateAccepted;

    var native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer native.deinit();
    const request = native.core.outstanding_host_requests[0];
    const response_bytes = try common.responseValueImageBytes(allocator, request, 0xA10C_0002);
    var wrong_target = request.request_fingerprint ^ 0xFFFF;
    if (wrong_target == 0) wrong_target = 1;
    const wrong_result = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = wrong_target,
        .status = .responded,
        .response_value_image_bytes = response_bytes,
        .host_claim_bytes = "world-image-v1-oracle.wrong-target",
        .attempt_number = 1,
    });
    const wrong_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent.closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = native.core.previous_turn_receipt_fingerprint,
        .turn_sequence_number = native.core.current_turn_sequence_number + 1,
        .resolutions = &.{wrong_result},
    });
    const wrong_input_bytes = try wrong_input.encode(allocator);
    try writer.write("artifacts/malformed/result.wrong-target.turn-input", wrong_input_bytes);
    const before_wrong = try captureNativeSemanticSnapshot(allocator, &native);
    const before_wrong_error_len = native.lastErrorLen();
    const wrong_status = native.submitTurn(wrong_input_bytes);
    if (wrong_status == .completed or wrong_status == .needs_host or wrong_status == .failed) return error.MalformedResultAccepted;
    try requireDiagnosticPublishedAfterReject(before_wrong_error_len, &native);
    const after_wrong = try captureNativeSemanticSnapshot(allocator, &native);
    if (!nativeSemanticSnapshotEqual(before_wrong, after_wrong)) return error.PartialSemanticMutation;

    const valid_result = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .status = .responded,
        .response_value_image_bytes = response_bytes,
        .host_claim_bytes = "world-image-v1-oracle.valid-result",
        .attempt_number = 1,
    });
    var fake_target = request.request_fingerprint ^ 0xA10C_A10C_A10C_A10C;
    if (fake_target == 0 or fake_target == request.request_fingerprint) fake_target = request.request_fingerprint +% 1;
    const fake_result = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = fake_target,
        .status = .responded,
        .response_value_image_bytes = response_bytes,
        .host_claim_bytes = "world-image-v1-oracle.fake-second-result",
        .attempt_number = 1,
    });
    const distinct_results = [_]world.Appliance.Wire.ResolutionInput{ valid_result, fake_result };
    const distinct_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent.closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = native.core.previous_turn_receipt_fingerprint,
        .turn_sequence_number = native.core.current_turn_sequence_number + 1,
        .resolutions = &distinct_results,
    });
    const distinct_input_bytes = try distinct_input.encode(allocator);
    const duplicate_input_bytes = try allocator.dupe(u8, distinct_input_bytes);
    try replaceUniqueU64LittleEndian(duplicate_input_bytes, fake_target, request.request_fingerprint);
    try writer.write("artifacts/malformed/result.duplicate-target.turn-input", duplicate_input_bytes);
    var duplicate_native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer duplicate_native.deinit();
    const before_duplicate = try captureNativeSemanticSnapshot(allocator, &duplicate_native);
    const before_duplicate_error_len = duplicate_native.lastErrorLen();
    const duplicate_status = duplicate_native.submitTurn(duplicate_input_bytes);
    if (duplicate_status == .completed or duplicate_status == .needs_host or duplicate_status == .failed) return error.DuplicateResultAccepted;
    try requireDiagnosticPublishedAfterReject(before_duplicate_error_len, &duplicate_native);
    const after_duplicate = try captureNativeSemanticSnapshot(allocator, &duplicate_native);
    if (!nativeSemanticSnapshotEqual(before_duplicate, after_duplicate)) return error.PartialSemanticMutation;

    const duplicate_preflight_results = [_]world.Appliance.Wire.ResolutionInput{ valid_result, valid_result };
    const duplicate_preflight_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .previous_turn_receipt_fingerprint = parent.closure.turn_receipt_fingerprint,
        .turn_sequence_number = parent.closure.turn_sequence_number + 1,
        .resolutions = &duplicate_preflight_results,
    });
    var duplicate_preflight_error: ?anyerror = null;
    _ = duplicate_preflight_input.encode(allocator) catch |err| {
        duplicate_preflight_error = err;
    };
    if (duplicate_preflight_error == null) return error.DuplicateResultAccepted;

    var stale_native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer stale_native.deinit();
    const stale_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent.closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = stale_native.core.previous_turn_receipt_fingerprint,
        .turn_sequence_number = stale_native.core.current_turn_sequence_number + 1,
        .resolutions = &.{valid_result},
    });
    const stale_input_bytes = try stale_input.encode(allocator);
    try writer.write("artifacts/malformed/result.stale-replay.turn-input", stale_input_bytes);
    if (stale_native.submitTurn(stale_input_bytes) != .completed) return error.ExpectedCompleted;
    const before_stale = try captureNativeSemanticSnapshot(allocator, &stale_native);
    const before_stale_error_len = stale_native.lastErrorLen();
    const stale_status = stale_native.submitTurn(stale_input_bytes);
    if (stale_status == .completed or stale_status == .needs_host or stale_status == .failed) return error.StaleResultAccepted;
    try requireDiagnosticPublishedAfterReject(before_stale_error_len, &stale_native);
    const after_stale = try captureNativeSemanticSnapshot(allocator, &stale_native);
    if (!nativeSemanticSnapshotEqual(before_stale, after_stale)) return error.PartialSemanticMutation;

    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: malformed-records\n" ++
            "owner_surface: Executable.Image + Appliance/TurnClosure + Appliance/Wire\n" ++
            "malformed_image_error: {s}\n" ++
            "malformed_state_error: {s}\n" ++
            "wrong_target_result_status: {s}\n" ++
            "duplicate_result_status: {s}\n" ++
            "duplicate_preflight_error: {s}\n" ++
            "stale_result_status: {s}\n" ++
            "semantic_state_unchanged_after_wrong_result: true\n" ++
            "semantic_state_unchanged_after_duplicate_result: true\n" ++
            "semantic_state_unchanged_after_stale_result: true\n" ++
            "diagnostic_error_published_after_wrong_result: true\n" ++
            "diagnostic_error_published_after_duplicate_result: true\n" ++
            "diagnostic_error_published_after_stale_result: true\n" ++
            "partial_transition_published: false\n",
        .{
            @errorName(image_error.?),
            @errorName(state_error.?),
            @tagName(wrong_status),
            @tagName(duplicate_status),
            @errorName(duplicate_preflight_error.?),
            @tagName(stale_status),
        },
    );
    try writer.write("cases/malformed-records.txt", case_transcript);
}

fn pathLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn mutablePathLessThan(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn listFiles(io: std.Io, allocator: std.mem.Allocator, root: std.Io.Dir) !OwnedPaths {
    var walker = try root.walk(allocator);
    defer walker.deinit();
    var items: std.ArrayList([]u8) = .empty;
    errdefer {
        for (items.items) |item| allocator.free(item);
        items.deinit(allocator);
    }
    while (try walker.next(io)) |entry| {
        switch (entry.kind) {
            .file => {
                const portable_path = try allocator.dupe(u8, entry.path);
                errdefer allocator.free(portable_path);
                canonicalizePathSeparators(portable_path, std.fs.path.sep);
                try items.append(allocator, portable_path);
            },
            .directory => {},
            .block_device,
            .character_device,
            .named_pipe,
            .sym_link,
            .unix_domain_socket,
            .whiteout,
            .door,
            .event_port,
            .unknown,
            => return error.UnsupportedOracleTreeEntry,
        }
    }
    const owned = try items.toOwnedSlice(allocator);
    std.mem.sort([]u8, owned, {}, mutablePathLessThan);
    return .{ .allocator = allocator, .items = owned };
}

fn isExpectedPath(writer: *const Writer, relative_path: []const u8) bool {
    for (writer.paths.items) |expected| {
        if (std.mem.eql(u8, expected, relative_path)) return true;
    }
    return false;
}

fn validatePublicationDestination(
    io: std.Io,
    allocator: std.mem.Allocator,
    writer: *const Writer,
    target: PublicationTarget,
    output_dir: std.Io.Dir,
) !void {
    var existing_paths = try listFiles(io, allocator, output_dir);
    defer existing_paths.deinit();
    for (existing_paths.items) |relative_path| {
        if (std.mem.endsWith(u8, relative_path, ".oracle-tmp")) {
            return error.UnsafePublicationTemporaryPath;
        }
        switch (target) {
            .isolated => if (!isExpectedPath(writer, relative_path)) return error.UnexpectedIsolatedOutputPath,
            .trusted_prefix => {},
        }
    }
    for (writer.paths.items) |relative_path| {
        const destination_stat = output_dir.statFile(io, relative_path, .{ .follow_symlinks = false }) catch |err| switch (err) {
            error.FileNotFound => continue,
            error.NotDir, error.SymLinkLoop => return error.UnsafePublicationPath,
            else => |unexpected| return unexpected,
        };
        if (destination_stat.kind != .file) return error.UnsafePublicationPath;
    }
}

fn promoteFile(
    allocator: std.mem.Allocator,
    writer: *Writer,
    output_dir: std.Io.Dir,
    relative_path: []const u8,
) !void {
    const source_path = try std.fs.path.join(allocator, &.{ writer.root, relative_path });
    var destination = try openPublicationLeaf(output_dir, writer.io, relative_path, true);
    defer destination.deinit(writer.io);
    try std.Io.Dir.cwd().copyFile(
        source_path,
        destination.parent,
        destination.leaf,
        writer.io,
        .{ .make_path = false, .replace = true },
    );
}

const PublicationLeaf = struct {
    parent: std.Io.Dir,
    leaf: []const u8,
    parent_owned: bool,

    fn deinit(self: *@This(), io: std.Io) void {
        if (self.parent_owned) self.parent.close(io);
        self.* = undefined;
    }
};

fn requirePublicationDirectory(dir: std.Io.Dir, io: std.Io) !std.Io.Dir {
    errdefer dir.close(io);
    if ((try dir.stat(io)).kind != .directory) return error.UnsafePublicationPath;
    return dir;
}

fn openPublicationChild(parent: std.Io.Dir, io: std.Io, name: []const u8) !std.Io.Dir {
    const options: std.Io.Dir.OpenOptions = .{
        .follow_symlinks = false,
        .iterate = true,
    };
    const child = parent.openDir(io, name, options) catch |open_error| switch (open_error) {
        error.FileNotFound => blk: {
            parent.createDir(io, name, .default_dir) catch |create_error| switch (create_error) {
                error.PathAlreadyExists => {},
                error.NotDir, error.SymLinkLoop => return error.UnsafePublicationPath,
                else => |err| return err,
            };
            break :blk parent.openDir(io, name, options) catch |retry_error| switch (retry_error) {
                error.NotDir, error.SymLinkLoop => return error.UnsafePublicationPath,
                else => |err| return err,
            };
        },
        error.NotDir, error.SymLinkLoop => return error.UnsafePublicationPath,
        else => |err| return err,
    };
    return requirePublicationDirectory(child, io);
}

fn openExistingPublicationChild(parent: std.Io.Dir, io: std.Io, name: []const u8) !std.Io.Dir {
    const child = parent.openDir(io, name, .{
        .follow_symlinks = false,
        .iterate = true,
    }) catch |err| switch (err) {
        error.NotDir, error.SymLinkLoop => return error.UnsafePublicationPath,
        else => |unexpected| return unexpected,
    };
    return requirePublicationDirectory(child, io);
}

fn openPublicationLeaf(
    root: std.Io.Dir,
    io: std.Io,
    relative_path: []const u8,
    create_parents: bool,
) !PublicationLeaf {
    if (relative_path.len == 0 or std.fs.path.isAbsolute(relative_path)) return error.UnsafePublicationPath;
    const leaf = std.fs.path.basename(relative_path);
    if (leaf.len == 0 or std.mem.eql(u8, leaf, ".") or std.mem.eql(u8, leaf, "..")) {
        return error.UnsafePublicationPath;
    }
    const parent_path = std.fs.path.dirname(relative_path) orelse return .{
        .parent = root,
        .leaf = leaf,
        .parent_owned = false,
    };

    var current = root;
    var current_owned = false;
    errdefer if (current_owned) current.close(io);
    var components = std.fs.path.componentIterator(parent_path);
    if (components.root() != null) return error.UnsafePublicationPath;
    while (components.next()) |component| {
        if (std.mem.eql(u8, component.name, ".") or std.mem.eql(u8, component.name, "..")) {
            return error.UnsafePublicationPath;
        }
        const child = if (create_parents)
            try openPublicationChild(current, io, component.name)
        else
            try openExistingPublicationChild(current, io, component.name);
        if (current_owned) current.close(io);
        current = child;
        current_owned = true;
    }
    return .{
        .parent = current,
        .leaf = leaf,
        .parent_owned = current_owned,
    };
}

fn deletePublicationFile(io: std.Io, publication_dir: std.Io.Dir, relative_path: []const u8) !void {
    var destination = try openPublicationLeaf(publication_dir, io, relative_path, false);
    defer destination.deinit(io);
    try destination.parent.deleteFile(io, destination.leaf);
}

fn openPublicationPathNoFollow(io: std.Io, output_dir: []const u8) !std.Io.Dir {
    var components = std.fs.path.componentIterator(output_dir);
    const initial = if (components.root()) |root|
        try std.Io.Dir.cwd().openDir(io, root, .{ .follow_symlinks = false, .iterate = true })
    else
        try std.Io.Dir.cwd().openDir(io, ".", .{ .follow_symlinks = false, .iterate = true });
    var current = try requirePublicationDirectory(initial, io);
    errdefer current.close(io);

    while (components.next()) |component| {
        if (std.mem.eql(u8, component.name, ".")) continue;
        if (std.mem.eql(u8, component.name, "..")) return error.UnsafePublicationPath;
        const child = try openPublicationChild(current, io, component.name);
        current.close(io);
        current = child;
    }
    return current;
}

fn openTrustedPublicationDirectory(io: std.Io, trusted_prefix: []const u8) !std.Io.Dir {
    const cwd = std.Io.Dir.cwd();
    const prefix_dir = try cwd.createDirPathOpen(io, trusted_prefix, .{
        .open_options = .{ .follow_symlinks = true, .iterate = true },
    });
    var current = try requirePublicationDirectory(prefix_dir, io);
    errdefer current.close(io);

    var components = std.fs.path.componentIterator(canonical_output_suffix);
    while (components.next()) |component| {
        const child = try openPublicationChild(current, io, component.name);
        current.close(io);
        current = child;
    }
    return current;
}

fn openPublicationDirectory(io: std.Io, target: PublicationTarget) !std.Io.Dir {
    return switch (target) {
        .isolated => |output_dir| openPublicationPathNoFollow(io, output_dir),
        .trusted_prefix => |prefix| openTrustedPublicationDirectory(io, prefix),
    };
}

fn promoteCorpus(allocator: std.mem.Allocator, writer: *Writer, target: PublicationTarget) !void {
    var publication_dir = try openPublicationDirectory(writer.io, target);
    defer publication_dir.close(writer.io);
    try validatePublicationDestination(writer.io, allocator, writer, target, publication_dir);

    // The standard atomic-copy primitive owns collision-safe temporary files
    // beside each destination and replaces only after the full file is ready.
    for (writer.paths.items) |relative_path| {
        try promoteFile(allocator, writer, publication_dir, relative_path);
    }

    switch (target) {
        .isolated => {},
        .trusted_prefix => {
            // Retire obsolete artifacts only after the complete new file set is present.
            // An interrupted cleanup can leave detectable extras, but cannot remove any
            // artifact required by the new manifest.
            var published_paths = try listFiles(writer.io, allocator, publication_dir);
            defer published_paths.deinit();
            for (published_paths.items) |relative_path| {
                if (isExpectedPath(writer, relative_path)) continue;
                try deletePublicationFile(writer.io, publication_dir, relative_path);
            }
        },
    }
}

test "candidate publisher copies the exact candidate tree" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const candidate_root = try std.fs.path.join(allocator, &.{ root, "candidate" });
    const trusted_prefix = try std.fs.path.join(allocator, &.{ root, "prefix" });
    const admission_digest = try std.fs.path.join(allocator, &.{ root, "admission.sha256" });
    const staging_root = try std.fs.path.join(allocator, &.{ root, "staging" });
    const published_root = try std.fs.path.join(allocator, &.{ trusted_prefix, canonical_output_suffix });
    const candidate_case = try std.fs.path.join(allocator, &.{ candidate_root, "cases/example.txt" });
    const candidate_manifest = try std.fs.path.join(allocator, &.{ candidate_root, "manifest.json" });
    const published_case = try std.fs.path.join(allocator, &.{ published_root, "cases/example.txt" });
    const obsolete = try std.fs.path.join(allocator, &.{ published_root, "obsolete.txt" });

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, std.fs.path.dirname(candidate_case).?);
    try cwd.createDirPath(io, published_root);
    try cwd.writeFile(io, .{ .sub_path = candidate_case, .data = "admitted case\n" });
    try cwd.writeFile(io, .{ .sub_path = candidate_manifest, .data = "admitted manifest\n" });
    try cwd.writeFile(io, .{ .sub_path = obsolete, .data = "obsolete\n" });

    try writeCandidateAdmissionDigestForTest(io, allocator, candidate_root, admission_digest);
    try publishCandidate(io, allocator, candidate_root, admission_digest, trusted_prefix, staging_root);

    const case_bytes = try cwd.readFileAlloc(io, published_case, allocator, .limited(1024));
    try std.testing.expectEqualStrings("admitted case\n", case_bytes);
    try std.testing.expectError(error.FileNotFound, cwd.access(io, obsolete, .{}));
}

test "candidate publisher rejects a post-admission mutation before target mutation" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const candidate_root = try std.fs.path.join(allocator, &.{ root, "candidate" });
    const trusted_prefix = try std.fs.path.join(allocator, &.{ root, "prefix" });
    const admission_digest = try std.fs.path.join(allocator, &.{ root, "admission.sha256" });
    const staging_root = try std.fs.path.join(allocator, &.{ root, "staging" });
    const candidate_case = try std.fs.path.join(allocator, &.{ candidate_root, "cases/example.txt" });
    const published_root = try std.fs.path.join(allocator, &.{ trusted_prefix, canonical_output_suffix });
    const sentinel = try std.fs.path.join(allocator, &.{ published_root, "sentinel.txt" });

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, std.fs.path.dirname(candidate_case).?);
    try cwd.createDirPath(io, published_root);
    try cwd.writeFile(io, .{ .sub_path = candidate_case, .data = "admitted bytes\n" });
    try cwd.writeFile(io, .{ .sub_path = sentinel, .data = "must survive\n" });
    try writeCandidateAdmissionDigestForTest(io, allocator, candidate_root, admission_digest);
    try cwd.writeFile(io, .{ .sub_path = candidate_case, .data = "mutated after admission\n" });

    try std.testing.expectError(
        error.CandidateAdmissionMismatch,
        publishCandidate(io, allocator, candidate_root, admission_digest, trusted_prefix, staging_root),
    );
    const sentinel_bytes = try cwd.readFileAlloc(io, sentinel, allocator, .limited(1024));
    try std.testing.expectEqualStrings("must survive\n", sentinel_bytes);
}

test "publication retains no-follow nested parent authority after preflight" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const candidate_root = try std.fs.path.join(allocator, &.{ root, "candidate" });
    const trusted_prefix = try std.fs.path.join(allocator, &.{ root, "prefix" });
    const published_root = try std.fs.path.join(allocator, &.{ trusted_prefix, canonical_output_suffix });
    const published_cases = try std.fs.path.join(allocator, &.{ published_root, "cases" });
    const published_case = try std.fs.path.join(allocator, &.{ published_cases, "example.txt" });
    const published_obsolete = try std.fs.path.join(allocator, &.{ published_cases, "obsolete.txt" });
    const external_cases = try std.fs.path.join(allocator, &.{ root, "external-cases" });
    const external_case = try std.fs.path.join(allocator, &.{ external_cases, "example.txt" });
    const external_obsolete = try std.fs.path.join(allocator, &.{ external_cases, "obsolete.txt" });

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, candidate_root);
    try cwd.createDirPath(io, published_cases);
    try cwd.createDirPath(io, external_cases);
    var writer = Writer{ .io = io, .allocator = allocator, .root = candidate_root };
    try writer.write("cases/example.txt", "candidate bytes\n");
    try cwd.writeFile(io, .{ .sub_path = published_case, .data = "published bytes\n" });
    try cwd.writeFile(io, .{ .sub_path = published_obsolete, .data = "published obsolete\n" });
    try cwd.writeFile(io, .{ .sub_path = external_case, .data = "external case sentinel\n" });
    try cwd.writeFile(io, .{ .sub_path = external_obsolete, .data = "external obsolete sentinel\n" });

    var publication_dir = try cwd.openDir(io, published_root, .{ .follow_symlinks = false, .iterate = true });
    defer publication_dir.close(io);
    try validatePublicationDestination(io, allocator, &writer, .{ .trusted_prefix = trusted_prefix }, publication_dir);
    try cwd.deleteTree(io, published_cases);
    try cwd.symLink(io, external_cases, published_cases, .{});

    try std.testing.expectError(
        error.UnsafePublicationPath,
        promoteFile(allocator, &writer, publication_dir, "cases/example.txt"),
    );
    try std.testing.expectError(
        error.UnsafePublicationPath,
        deletePublicationFile(io, publication_dir, "cases/obsolete.txt"),
    );
    const external_case_bytes = try cwd.readFileAlloc(io, external_case, allocator, .limited(1024));
    const external_obsolete_bytes = try cwd.readFileAlloc(io, external_obsolete, allocator, .limited(1024));
    try std.testing.expectEqualStrings("external case sentinel\n", external_case_bytes);
    try std.testing.expectEqualStrings("external obsolete sentinel\n", external_obsolete_bytes);
}

test "isolated publication rejects unowned paths before writing" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const output_dir = try std.fs.path.join(allocator, &.{ root, "output" });
    const existing_relative_path = "artifacts/manifests/one-port.appliance-manifest";
    const new_relative_path = "cases/new.txt";
    const existing_path = try std.fs.path.join(allocator, &.{ output_dir, existing_relative_path });
    const new_path = try std.fs.path.join(allocator, &.{ output_dir, new_relative_path });
    const unowned_path = try std.fs.path.join(allocator, &.{ output_dir, "unowned.txt" });

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, std.fs.path.dirname(existing_path).?);
    try cwd.writeFile(io, .{ .sub_path = existing_path, .data = "old expected\n" });
    try cwd.writeFile(io, .{ .sub_path = unowned_path, .data = "must survive\n" });

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(existing_relative_path, "replacement");
    try writer.write(new_relative_path, "new");
    try std.testing.expectError(
        error.UnexpectedIsolatedOutputPath,
        promoteCorpus(allocator, &writer, .{ .isolated = output_dir }),
    );

    const existing_bytes = try cwd.readFileAlloc(io, existing_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("old expected\n", existing_bytes);
    const unowned_bytes = try cwd.readFileAlloc(io, unowned_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("must survive\n", unowned_bytes);
    try std.testing.expectError(error.FileNotFound, cwd.access(io, new_path, .{}));

    try cwd.deleteFile(io, unowned_path);
    try promoteCorpus(allocator, &writer, .{ .isolated = output_dir });
    const replaced_bytes = try cwd.readFileAlloc(io, existing_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("replacement", replaced_bytes);
    const new_bytes = try cwd.readFileAlloc(io, new_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("new", new_bytes);
}

test "publication rejects an expected file directory collision before writing" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const output_dir = try std.fs.path.join(allocator, &.{ root, "output" });
    const first_relative_path = "cases/first.txt";
    const collision_relative_path = "cases/second.txt";
    const first_path = try std.fs.path.join(allocator, &.{ output_dir, first_relative_path });
    const collision_path = try std.fs.path.join(allocator, &.{ output_dir, collision_relative_path });

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, std.fs.path.dirname(first_path).?);
    try cwd.writeFile(io, .{ .sub_path = first_path, .data = "must survive\n" });
    try cwd.createDirPath(io, collision_path);

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(first_relative_path, "replacement");
    try writer.write(collision_relative_path, "second");
    try std.testing.expectError(
        error.UnsafePublicationPath,
        promoteCorpus(allocator, &writer, .{ .isolated = output_dir }),
    );

    const first_bytes = try cwd.readFileAlloc(io, first_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("must survive\n", first_bytes);
    try std.testing.expectEqual(std.Io.File.Kind.directory, (try cwd.statFile(io, collision_path, .{})).kind);

    try cwd.deleteTree(io, collision_path);
    try promoteCorpus(allocator, &writer, .{ .isolated = output_dir });
    const replaced_bytes = try cwd.readFileAlloc(io, first_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("replacement", replaced_bytes);
    const second_bytes = try cwd.readFileAlloc(io, collision_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("second", second_bytes);
}

test "publication rejects unsafe temporary symlink before writing" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const output_dir = try std.fs.path.join(allocator, &.{ root, "output" });
    const victim_path = try std.fs.path.join(allocator, &.{ root, "victim.txt" });
    const relative_path = "artifacts/manifests/one-port.appliance-manifest";
    const destination_path = try std.fs.path.join(allocator, &.{ output_dir, relative_path });
    const temporary_path = try std.fmt.allocPrint(allocator, "{s}.oracle-tmp", .{destination_path});

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, std.fs.path.dirname(temporary_path).?);
    try cwd.writeFile(io, .{ .sub_path = victim_path, .data = "must survive\n" });
    try cwd.symLink(io, victim_path, temporary_path, .{});

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(relative_path, "replacement");
    try std.testing.expectError(
        error.UnsupportedOracleTreeEntry,
        promoteCorpus(allocator, &writer, .{ .isolated = output_dir }),
    );

    const victim_bytes = try cwd.readFileAlloc(io, victim_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("must survive\n", victim_bytes);
    try std.testing.expectError(error.FileNotFound, cwd.access(io, destination_path, .{}));
}

test "publication rejects symlinked output root before writing" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const victim_dir = try std.fs.path.join(allocator, &.{ root, "victim" });
    const victim_path = try std.fs.path.join(allocator, &.{ victim_dir, "sentinel.txt" });
    const output_dir = try std.fs.path.join(allocator, &.{ root, "output" });
    const relative_path = "artifacts/manifests/one-port.appliance-manifest";

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, victim_dir);
    try cwd.writeFile(io, .{ .sub_path = victim_path, .data = "must survive\n" });
    try cwd.symLink(io, victim_dir, output_dir, .{});

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(relative_path, "replacement");
    try std.testing.expectError(
        error.UnsafePublicationPath,
        promoteCorpus(allocator, &writer, .{ .isolated = output_dir }),
    );

    const victim_bytes = try cwd.readFileAlloc(io, victim_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("must survive\n", victim_bytes);
}

test "publication rejects symlinked output ancestor before writing" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const victim_dir = try std.fs.path.join(allocator, &.{ root, "victim" });
    const victim_path = try std.fs.path.join(allocator, &.{ victim_dir, "sentinel.txt" });
    const linked_ancestor = try std.fs.path.join(allocator, &.{ root, "linked" });
    const output_dir = try std.fs.path.join(allocator, &.{ linked_ancestor, "output" });
    const relative_path = "artifacts/manifests/one-port.appliance-manifest";

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, victim_dir);
    try cwd.writeFile(io, .{ .sub_path = victim_path, .data = "must survive\n" });
    try cwd.symLink(io, victim_dir, linked_ancestor, .{});

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(relative_path, "replacement");
    try std.testing.expectError(
        error.UnsafePublicationPath,
        promoteCorpus(allocator, &writer, .{ .isolated = output_dir }),
    );

    const victim_bytes = try cwd.readFileAlloc(io, victim_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("must survive\n", victim_bytes);
    const redirected_output = try std.fs.path.join(allocator, &.{ victim_dir, "output" });
    try std.testing.expectError(error.FileNotFound, cwd.access(io, redirected_output, .{}));
}

test "publication accepts a symlinked trusted prefix" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const real_prefix = try std.fs.path.join(allocator, &.{ root, "real-prefix" });
    const linked_prefix = try std.fs.path.join(allocator, &.{ root, "linked-prefix" });
    const relative_path = "artifacts/manifests/one-port.appliance-manifest";
    const destination_path = try std.fs.path.join(allocator, &.{ real_prefix, canonical_output_suffix, relative_path });
    const obsolete_path = try std.fs.path.join(allocator, &.{ real_prefix, canonical_output_suffix, "obsolete.txt" });

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, real_prefix);
    try cwd.createDirPath(io, std.fs.path.dirname(obsolete_path).?);
    try cwd.writeFile(io, .{ .sub_path = obsolete_path, .data = "obsolete" });
    try cwd.symLink(io, real_prefix, linked_prefix, .{});

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(relative_path, "replacement");
    try promoteCorpus(allocator, &writer, .{ .trusted_prefix = linked_prefix });

    const destination_bytes = try cwd.readFileAlloc(io, destination_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("replacement", destination_bytes);
    try std.testing.expectError(error.FileNotFound, cwd.access(io, obsolete_path, .{}));
}

test "trusted prefix rejects a symlinked oracle suffix" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const trusted_prefix = try std.fs.path.join(allocator, &.{ root, "prefix" });
    const victim_dir = try std.fs.path.join(allocator, &.{ root, "victim" });
    const victim_path = try std.fs.path.join(allocator, &.{ victim_dir, "sentinel.txt" });
    const linked_suffix = try std.fs.path.join(allocator, &.{ trusted_prefix, "conformance" });
    const relative_path = "artifacts/manifests/one-port.appliance-manifest";

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, trusted_prefix);
    try cwd.createDirPath(io, victim_dir);
    try cwd.writeFile(io, .{ .sub_path = victim_path, .data = "must survive\n" });
    try cwd.symLink(io, victim_dir, linked_suffix, .{});

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(relative_path, "replacement");
    try std.testing.expectError(
        error.UnsafePublicationPath,
        promoteCorpus(allocator, &writer, .{ .trusted_prefix = trusted_prefix }),
    );

    const victim_bytes = try cwd.readFileAlloc(io, victim_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("must survive\n", victim_bytes);
}

fn canonicalSourceBytes(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var canonical: std.ArrayList(u8) = .empty;
    errdefer canonical.deinit(allocator);
    try canonical.ensureTotalCapacity(allocator, bytes.len);
    var index: usize = 0;
    while (index < bytes.len) {
        if (bytes[index] == '\r') {
            if (index + 1 >= bytes.len or bytes[index + 1] != '\n') return error.InvalidSourceLineEnding;
            canonical.appendAssumeCapacity('\n');
            index += 2;
            continue;
        }
        canonical.appendAssumeCapacity(bytes[index]);
        index += 1;
    }
    return canonical.toOwnedSlice(allocator);
}

fn generatorSourceInventory(io: std.Io, allocator: std.mem.Allocator, source_dir: std.Io.Dir) !OwnedPaths {
    var items: std.ArrayList([]u8) = .empty;
    errdefer {
        for (items.items) |item| allocator.free(item);
        items.deinit(allocator);
    }

    for (generator_source_package_paths) |package_path| {
        const path_stat = try source_dir.statFile(io, package_path, .{ .follow_symlinks = false });
        switch (path_stat.kind) {
            .file => {
                if (std.mem.startsWith(u8, package_path, generator_source_excluded_prefix)) continue;
                try items.append(allocator, try allocator.dupe(u8, package_path));
            },
            .directory => {
                var root = try source_dir.openDir(io, package_path, .{ .follow_symlinks = false, .iterate = true });
                defer root.close(io);
                var root_files = try listFiles(io, allocator, root);
                defer root_files.deinit();
                for (root_files.items) |relative_path| {
                    const joined = try std.fs.path.join(allocator, &.{ package_path, relative_path });
                    errdefer allocator.free(joined);
                    canonicalizePathSeparators(joined, std.fs.path.sep);
                    if (std.mem.startsWith(u8, joined, generator_source_excluded_prefix)) {
                        allocator.free(joined);
                        continue;
                    }
                    try items.append(allocator, joined);
                }
            },
            else => return error.InvalidGeneratorSourceEntry,
        }
    }

    const owned = try items.toOwnedSlice(allocator);
    std.mem.sort([]u8, owned, {}, mutablePathLessThan);
    for (owned[1..], owned[0 .. owned.len - 1]) |current, previous| {
        if (std.mem.eql(u8, current, previous)) return error.InvalidGeneratorSourceInventory;
    }
    return .{ .allocator = allocator, .items = owned };
}

fn validateGeneratorSourceInventory(actual_files: anytype) !void {
    if (actual_files.len != compiled_generator_sources.len) return error.InvalidGeneratorSourceInventory;
    for (actual_files, compiled_generator_sources) |actual_path, compiled_source| {
        if (!std.mem.eql(u8, actual_path, compiled_source.path)) return error.InvalidGeneratorSourceInventory;
    }
}

fn generatorSourceIdentity(io: std.Io, allocator: std.mem.Allocator, source_root: []const u8) ![32]u8 {
    var source_dir = try std.Io.Dir.cwd().openDir(io, source_root, .{ .follow_symlinks = true, .iterate = true });
    defer source_dir.close(io);
    var actual_files = try generatorSourceInventory(io, allocator, source_dir);
    defer actual_files.deinit();
    try validateGeneratorSourceInventory(actual_files.items);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(generator_source_identity_domain);
    for (actual_files.items) |relative_path| {
        var file = source_dir.openFile(io, relative_path, .{
            .mode = .read_only,
            .follow_symlinks = false,
            .resolve_beneath = true,
        }) catch |err| switch (err) {
            error.SymLinkLoop => return error.InvalidGeneratorSourceEntry,
            else => |other| return other,
        };
        defer file.close(io);
        if ((try file.stat(io)).kind != .file) return error.InvalidGeneratorSourceEntry;
        var read_buffer: [4096]u8 = undefined;
        var reader = file.reader(io, &read_buffer);
        const raw_bytes = try reader.interface.allocRemaining(allocator, .limited(16 * 1024 * 1024));
        defer allocator.free(raw_bytes);
        try updateGeneratorSourceIdentity(&hasher, allocator, relative_path, raw_bytes);
    }
    var digest = [_]u8{0} ** 32;
    hasher.final(&digest);
    return digest;
}

test "generator source inventory rejects an omitted package helper" {
    var actual: std.ArrayList([]const u8) = .empty;
    defer actual.deinit(std.testing.allocator);
    for (compiled_generator_sources) |source| try actual.append(std.testing.allocator, source.path);
    try actual.append(std.testing.allocator, "examples/world_transition_oracle_untracked_helper.zig");
    std.mem.sort([]const u8, actual.items, {}, pathLessThan);
    try std.testing.expectError(error.InvalidGeneratorSourceInventory, validateGeneratorSourceInventory(actual.items));
}

fn compiledGeneratorSourceIdentity(allocator: std.mem.Allocator) ![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(generator_source_identity_domain);
    for (compiled_generator_sources) |source| {
        try updateGeneratorSourceIdentity(&hasher, allocator, source.path, source.bytes);
    }
    var digest = [_]u8{0} ** 32;
    hasher.final(&digest);
    return digest;
}

fn updateGeneratorSourceIdentity(
    hasher: *std.crypto.hash.sha2.Sha256,
    allocator: std.mem.Allocator,
    relative_path: []const u8,
    raw_bytes: []const u8,
) !void {
    const canonical_bytes = try canonicalSourceBytes(allocator, raw_bytes);
    defer allocator.free(canonical_bytes);

    var path_length_bytes = [_]u8{0} ** 4;
    std.mem.writeInt(u32, &path_length_bytes, @intCast(relative_path.len), .little);
    var content_length_bytes = [_]u8{0} ** 8;
    std.mem.writeInt(u64, &content_length_bytes, @intCast(canonical_bytes.len), .little);
    hasher.update(&path_length_bytes);
    hasher.update(relative_path);
    hasher.update(&content_length_bytes);
    hasher.update(canonical_bytes);
}

fn validatedGeneratorSourceIdentity(io: std.Io, allocator: std.mem.Allocator, source_root: []const u8) ![32]u8 {
    const compiled_identity = try compiledGeneratorSourceIdentity(allocator);
    const live_identity = try generatorSourceIdentity(io, allocator, source_root);
    if (!std.mem.eql(u8, &compiled_identity, &live_identity)) return error.GeneratorSourceIdentityMismatch;
    return live_identity;
}

test "generator source canonicalization is checkout stable" {
    const lf = try canonicalSourceBytes(std.testing.allocator, "first\nsecond\n");
    defer std.testing.allocator.free(lf);
    const crlf = try canonicalSourceBytes(std.testing.allocator, "first\r\nsecond\r\n");
    defer std.testing.allocator.free(crlf);
    try std.testing.expectEqualSlices(u8, lf, crlf);
    try std.testing.expectError(error.InvalidSourceLineEnding, canonicalSourceBytes(std.testing.allocator, "bare\rcarriage"));
}

test "generator rejects a live source root that diverges from its compiled source closure" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const cwd = std.Io.Dir.cwd();
    for (compiled_generator_sources) |source| {
        const full_path = try std.fs.path.join(allocator, &.{ root, source.path });
        if (std.fs.path.dirname(full_path)) |parent| try cwd.createDirPath(io, parent);
        const bytes = if (std.mem.eql(u8, source.path, "src/world.zig"))
            try std.mem.concat(allocator, u8, &.{ source.bytes, "// stale generator falsifier\n" })
        else
            source.bytes;
        try cwd.writeFile(io, .{ .sub_path = full_path, .data = bytes });
    }

    try std.testing.expectError(
        error.GeneratorSourceIdentityMismatch,
        validatedGeneratorSourceIdentity(io, allocator, root),
    );
}

fn sha256(bytes: []const u8) [32]u8 {
    var digest = [_]u8{0} ** 32;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

fn digestHex(digest: [32]u8) [64]u8 {
    return std.fmt.bytesToHex(digest, .lower);
}

fn readArtifact(allocator: std.mem.Allocator, writer: *Writer, relative_path: []const u8) ![]u8 {
    const full_path = try std.fs.path.join(allocator, &.{ writer.root, relative_path });
    return std.Io.Dir.cwd().readFileAlloc(writer.io, full_path, allocator, .limited(16 * 1024 * 1024));
}

fn writeManifest(allocator: std.mem.Allocator, writer: *Writer, generator_source_identity: [32]u8) !void {
    std.mem.sort([]const u8, writer.paths.items, {}, pathLessThan);
    var artifact_set_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (writer.paths.items) |relative_path| {
        const bytes = try readArtifact(allocator, writer, relative_path);
        const digest = sha256(bytes);
        var length_bytes = [_]u8{0} ** 8;
        std.mem.writeInt(u64, &length_bytes, @intCast(bytes.len), .little);
        artifact_set_hasher.update(relative_path);
        artifact_set_hasher.update(&.{0});
        artifact_set_hasher.update(&length_bytes);
        artifact_set_hasher.update(&digest);
    }
    var artifact_set_digest = [_]u8{0} ** 32;
    artifact_set_hasher.final(&artifact_set_digest);
    const artifact_set_hex = digestHex(artifact_set_digest);
    const generator_source_identity_hex = digestHex(generator_source_identity);
    const package_version = try compiledPackageVersion(allocator);
    defer allocator.free(package_version);
    var boundary_package = try compiledBoundaryPackage(allocator);
    defer boundary_package.deinit(allocator);

    var manifest: std.ArrayList(u8) = .empty;
    try manifest.print(
        allocator,
        "{{\n" ++
            "  \"format\": \"world-image-v1-rewrite-world-oracle-v0\",\n" ++
            "  \"format_version\": 1,\n" ++
            "  \"semantic_source\": {{\n" ++
            "    \"package\": \"world\",\n" ++
            "    \"package_version\": \"{s}\",\n" ++
            "    \"baseline_commit\": \"969f23f6bad87ca9d535d92d62b6418612891699\",\n" ++
            "    \"baseline_tree\": \"b2bd776125bc17215916e2a48bc7102a861788db\",\n" ++
            "    \"boundary_package\": \"{s}\",\n" ++
            "    \"boundary_package_hash\": \"{s}\",\n",
        .{ package_version, boundary_package.version, boundary_package.hash },
    );
    try manifest.print(
        allocator,
        "    \"baseline_scope\": \"historical-reference-parent\",\n" ++
            "    \"generator_source_identity\": {{\n" ++
            "      \"algorithm\": \"{s}\",\n" ++
            "      \"normalization\": \"{s}\",\n" ++
            "      \"sha256\": \"{s}\",\n" ++
            "      \"files\": [",
        .{ generator_source_identity_algorithm, generator_source_normalization, &generator_source_identity_hex },
    );
    for (compiled_generator_sources, 0..) |source, index| {
        if (index != 0) try manifest.append(allocator, ',');
        try appendJsonString(allocator, &manifest, source.path);
    }
    try manifest.appendSlice(allocator, "]\n    },\n");
    try manifest.appendSlice(
        allocator,
        "    \"version_fields_scope\": \"selected-compatibility-cut-lines\",\n" ++
            "    \"world_executable_image_format\": 2,\n" ++
            "    \"world_executable_image_fingerprint\": 2,\n" ++
            "    \"world_executable_image_codec\": 1,\n" ++
            "    \"world_turn_closure_format\": 1,\n" ++
            "    \"world_turn_closure_fingerprint\": 1,\n" ++
            "    \"world_archive_append_batch_format\": 1,\n" ++
            "    \"world_archive_append_batch_fingerprint\": 1,\n" ++
            "    \"world_appliance_abi\": 4,\n" ++
            "    \"world_appliance_manifest_format\": 3,\n" ++
            "    \"world_appliance_manifest_fingerprint\": 3,\n" ++
            "    \"world_appliance_command_format\": 1,\n" ++
            "    \"world_appliance_command_fingerprint\": 1,\n" ++
            "    \"world_appliance_wire_turn_input_format\": 2,\n" ++
            "    \"world_appliance_wire_resolution_input_format\": 1,\n" ++
            "    \"zig_version\": \"" ++ builtin.zig_version_string ++ "\"\n" ++
            "  },\n" ++
            "  \"binary_family_policy\": {\n" ++
            "    \"scope\": \"exhaustive-top-level-binary-artifacts\",\n" ++
            "    \"nested_authority\": \"top-level-owner+world-generator-source-identity+boundary-package-hash\",\n" ++
            "    \"unclassified\": \"reject\",\n" ++
            "    \"binary_artifact_count\": 64\n" ++
            "  },\n" ++
            "  \"binary_families\": [\n" ++
            "    {\"id\":\"world_executable_image\",\"owner\":\"world.Executable.Image\",\"versioning\":\"header\",\"expected_count\":2,\"magic\":\"world.Executable.Image.v2\\u0000\",\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_executable_image_format_version\",\"offset\":26,\"value\":2},{\"name\":\"fingerprint_version\",\"constant\":\"world_executable_image_fingerprint_version\",\"offset\":30,\"value\":2},{\"name\":\"codec_version\",\"constant\":\"world_executable_image_codec_version\",\"offset\":34,\"value\":1}]},\n" ++
            "    {\"id\":\"world_appliance_manifest\",\"owner\":\"world.Appliance.Manifest\",\"versioning\":\"header\",\"expected_count\":2,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_appliance_manifest_format_version\",\"offset\":0,\"value\":3},{\"name\":\"fingerprint_version\",\"constant\":\"world_appliance_manifest_fingerprint_version\",\"offset\":4,\"value\":3},{\"name\":\"appliance_abi_version\",\"constant\":\"world_appliance_abi_version\",\"offset\":16,\"value\":4}]},\n" ++
            "    {\"id\":\"world_appliance_command\",\"owner\":\"world.Appliance.Command\",\"versioning\":\"header\",\"expected_count\":1,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_appliance_command_format_version\",\"offset\":0,\"value\":1},{\"name\":\"fingerprint_version\",\"constant\":\"world_appliance_command_fingerprint_version\",\"offset\":4,\"value\":1}]},\n" ++
            "    {\"id\":\"world_appliance_wire_turn_input\",\"owner\":\"world.Appliance.Wire.TurnInput\",\"versioning\":\"format-only\",\"expected_count\":11,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_appliance_wire_turn_input_format_version\",\"offset\":0,\"value\":2}]},\n" ++
            "    {\"id\":\"world_appliance_wire_resolution_input\",\"owner\":\"world.Appliance.Wire.ResolutionInput\",\"versioning\":\"format-only\",\"expected_count\":3,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_appliance_wire_resolution_input_format_version\",\"offset\":0,\"value\":1}]},\n" ++
            "    {\"id\":\"world_appliance_turn_output\",\"owner\":\"world.Appliance.TurnOutput\",\"versioning\":\"header\",\"expected_count\":10,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_appliance_turn_output_format_version\",\"offset\":0,\"value\":3},{\"name\":\"fingerprint_version\",\"constant\":\"world_appliance_turn_output_fingerprint_version\",\"offset\":4,\"value\":2}]},\n" ++
            "    {\"id\":\"world_appliance_turn_closure\",\"owner\":\"world.Appliance.TurnClosure\",\"versioning\":\"header\",\"expected_count\":12,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_appliance_turn_closure_format_version\",\"offset\":0,\"value\":1},{\"name\":\"fingerprint_version\",\"constant\":\"world_appliance_turn_closure_fingerprint_version\",\"offset\":4,\"value\":1}]},\n" ++
            "    {\"id\":\"world_appliance_checkpoint\",\"owner\":\"world.Appliance.Checkpoint\",\"versioning\":\"header\",\"expected_count\":6,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_appliance_checkpoint_format_version\",\"offset\":0,\"value\":1},{\"name\":\"fingerprint_version\",\"constant\":\"world_appliance_checkpoint_fingerprint_version\",\"offset\":4,\"value\":1}]},\n" ++
            "    {\"id\":\"world_capsule_image\",\"owner\":\"world.Capsule.Image\",\"versioning\":\"header\",\"expected_count\":6,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_capsule_image_format_version\",\"offset\":0,\"value\":3},{\"name\":\"fingerprint_version\",\"constant\":\"world_capsule_image_fingerprint_version\",\"offset\":4,\"value\":1}]},\n" ++
            "    {\"id\":\"world_appliance_host_request_batch\",\"owner\":\"world.Appliance.encodeHostRequestsImageOwned\",\"versioning\":\"member-versioned-container\",\"expected_count\":1,\"container_count_offset\":0,\"expected_member_count\":1,\"member_header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_appliance_host_request_format_version\",\"offset\":8,\"value\":4},{\"name\":\"fingerprint_version\",\"constant\":\"world_appliance_host_request_fingerprint_version\",\"offset\":12,\"value\":4}]},\n" ++
            "    {\"id\":\"world_frame_request\",\"owner\":\"world.Frame.Request\",\"versioning\":\"header\",\"expected_count\":1,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_frame_request_format_version\",\"offset\":0,\"value\":1},{\"name\":\"fingerprint_version\",\"constant\":\"world_frame_request_fingerprint_version\",\"offset\":4,\"value\":1}]},\n" ++
            "    {\"id\":\"world_archive_append_batch\",\"owner\":\"world.Archive.AppendBatch\",\"versioning\":\"header\",\"expected_count\":1,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_archive_append_batch_format_version\",\"offset\":0,\"value\":1},{\"name\":\"fingerprint_version\",\"constant\":\"world_archive_append_batch_fingerprint_version\",\"offset\":4,\"value\":1}]},\n" ++
            "    {\"id\":\"world_run_image\",\"owner\":\"world.RunImage\",\"versioning\":\"header\",\"expected_count\":3,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_run_image_format_version\",\"offset\":0,\"value\":3},{\"name\":\"fingerprint_version\",\"constant\":\"world_run_image_fingerprint_version\",\"offset\":4,\"value\":1}]},\n" ++
            "    {\"id\":\"world_transcript_image\",\"owner\":\"world.TranscriptImage\",\"versioning\":\"header\",\"expected_count\":3,\"header_fields\":[{\"name\":\"format_version\",\"constant\":\"world_transcript_image_format_version\",\"offset\":0,\"value\":3},{\"name\":\"fingerprint_version\",\"constant\":\"world_transcript_image_fingerprint_version\",\"offset\":4,\"value\":1}]},\n" ++
            "    {\"id\":\"world_appliance_root_result_value_image\",\"owner\":\"world.Appliance.validateRootResultValueImageBytes\",\"versioning\":\"unversioned-container-owned\",\"expected_count\":2,\"label\":\"world.appliance.root_result.value_image\",\"label_length_offset\":0,\"label_offset\":4,\"value_fingerprint_offset\":43}\n" ++
            "  ],\n" ++
            "  \"offline_regeneration\": \"requires-preseeded-boundary-package-cache\",\n" ++
            "  \"generator\": \"zig build update-world-image-v1-transition-oracle\",\n" ++
            "  \"normal_check\": \"zig build check-world-image-v1-transition-oracle --summary all\",\n" ++
            "  \"case_count\": 12,\n" ++
            "  \"cases\": [\n",
    );
    for (cases, 0..) |case, index| {
        try manifest.print(allocator, "    {{\"id\":\"{s}\",\"transcript\":\"{s}\"}}{s}\n", .{
            case.id,
            case.transcript,
            if (index + 1 == cases.len) "" else ",",
        });
    }
    try manifest.print(
        allocator,
        "  ],\n" ++
            "  \"artifact_set_sha256\": \"{s}\",\n" ++
            "  \"artifact_count\": {d},\n" ++
            "  \"artifacts\": [\n",
        .{ &artifact_set_hex, writer.paths.items.len },
    );
    for (writer.paths.items, 0..) |relative_path, index| {
        const bytes = try readArtifact(allocator, writer, relative_path);
        const hex = digestHex(sha256(bytes));
        try manifest.print(allocator, "    {{\"path\":\"{s}\",\"length\":{d},\"sha256\":\"{s}\"}}{s}\n", .{
            relative_path,
            bytes.len,
            &hex,
            if (index + 1 == writer.paths.items.len) "" else ",",
        });
    }
    try manifest.appendSlice(allocator, "  ]\n}\n");
    try writer.write("manifest.json", manifest.items);
}

fn writeChecksums(allocator: std.mem.Allocator, writer: *Writer) !void {
    std.mem.sort([]const u8, writer.paths.items, {}, pathLessThan);
    var checksums: std.ArrayList(u8) = .empty;
    for (writer.paths.items) |relative_path| {
        const bytes = try readArtifact(allocator, writer, relative_path);
        const hex = digestHex(sha256(bytes));
        try checksums.print(allocator, "{s}  {s}{s}\n", .{ &hex, checksum_prefix, relative_path });
    }
    try writer.write("checksums.sha256", checksums.items);
}
