const std = @import("std");
const world = @import("world");

const Protocol = world.Protocol;

const source_package_root_files = [_][]const u8{
    "build.zig",
    "build.zig.zon",
};

const source_package_dirs = [_][]const u8{
    "src",
    "examples",
    "scripts",
    "test",
    "docs",
    "conformance",
};

const max_wasm_types = 256;
const max_wasm_functions = 4096;

const WasmSignature = struct {
    params: u32 = 0,
    results: u32 = 0,
    params_all_i32: bool = true,
    results_all_i32: bool = true,
    results_all_i64: bool = true,

    fn matches(self: @This(), params: u32, results: u32, result_type: ?u8) bool {
        if (self.params != params or self.results != results or !self.params_all_i32) return false;
        return switch (result_type orelse 0) {
            0 => results == 0,
            0x7f => self.results_all_i32,
            0x7e => self.results_all_i64,
            else => false,
        };
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();

    var wasm_path: ?[]const u8 = null;
    var wasm_inspection_receipt_path: ?[]const u8 = null;
    var proof_receipts_path: ?[]const u8 = null;
    var out_path: ?[]const u8 = null;
    var proof_gates: [Protocol.required_proof_kind_count][]const u8 = undefined;
    var proof_gate_count: usize = 0;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--wasm")) {
            wasm_path = args.next() orelse return error.MissingWasmPath;
        } else if (std.mem.eql(u8, arg, "--wasm-inspection-receipt")) {
            wasm_inspection_receipt_path = args.next() orelse return error.MissingWasmInspectionReceiptPath;
        } else if (std.mem.eql(u8, arg, "--proof-receipts")) {
            proof_receipts_path = args.next() orelse return error.MissingProofReceiptsPath;
        } else if (std.mem.eql(u8, arg, "--out")) {
            out_path = args.next() orelse return error.MissingOutPath;
        } else if (std.mem.eql(u8, arg, "--proof-gate")) {
            if (proof_gate_count >= proof_gates.len) return error.TooManyProofGates;
            proof_gates[proof_gate_count] = args.next() orelse return error.MissingProofGate;
            proof_gate_count += 1;
        } else {
            return error.UnknownArgument;
        }
    }
    if (proof_gate_count != Protocol.required_proof_kind_count) return error.MissingProofGate;

    const wasm_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, wasm_path orelse return error.MissingWasmPath, allocator, .limited(world.world_max_decoded_byte_field_len));
    defer allocator.free(wasm_bytes);
    try validateUniversalWasmArtifact(wasm_bytes);
    const universal_wasm_checksum = checksum64(wasm_bytes);
    const wasm_inspection_receipt_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, wasm_inspection_receipt_path orelse return error.MissingWasmInspectionReceiptPath, allocator, .limited(1024 * 1024));
    defer allocator.free(wasm_inspection_receipt_bytes);
    try validateWasmInspectionReceipt(allocator, wasm_inspection_receipt_bytes, universal_wasm_checksum);
    const proof_receipts_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, proof_receipts_path orelse return error.MissingProofReceiptsPath, allocator, .limited(1024 * 1024));
    defer allocator.free(proof_receipts_bytes);

    const source_package_checksum = try sourcePackageChecksum(init.io, allocator);

    var proof_receipts: [Protocol.required_proof_kind_count]Protocol.ProofReceipt = undefined;
    var input_evidence: [Protocol.required_proof_kind_count][2]u64 = undefined;
    var expected_evidence: [Protocol.required_proof_kind_count][2]u64 = undefined;
    var actual_evidence: [Protocol.required_proof_kind_count][2]u64 = undefined;
    var diagnostics_evidence: [Protocol.required_proof_kind_count][2]u64 = undefined;
    var artifact_evidence: [Protocol.required_proof_kind_count][4]u64 = undefined;
    try buildProofReceiptsFromEvidence(
        allocator,
        proof_receipts_bytes,
        proof_gates[0..],
        universal_wasm_checksum,
        source_package_checksum,
        &proof_receipts,
        &input_evidence,
        &expected_evidence,
        &actual_evidence,
        &diagnostics_evidence,
        &artifact_evidence,
    );
    const release_receipt = Protocol.ReleaseReceipt.init(.{
        .proof_receipts = proof_receipts[0..],
        .universal_wasm_checksum = universal_wasm_checksum,
        .source_package_checksum = source_package_checksum,
    });
    try release_receipt.validate();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try writeReleaseReceiptJson(allocator, &out, release_receipt, proof_receipts[0..], proof_gates[0..]);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path orelse return error.MissingOutPath, .data = out.items });
}

fn writeReleaseReceiptJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), receipt: Protocol.ReleaseReceipt, proof_receipts: []const Protocol.ProofReceipt, proof_gates: []const []const u8) !void {
    try out.print(allocator,
        \\{{
        \\  "release_receipt_format_version": {d},
        \\  "release_receipt_fingerprint_version": {d},
        \\  "release_receipt_fingerprint": "0x{x:0>16}",
        \\  "boundary_protocol_manifest_fingerprint": "0x{x:0>16}",
        \\  "world_protocol_manifest_fingerprint": "0x{x:0>16}",
        \\  "conformance_corpus_root_fingerprint": "0x{x:0>16}",
        \\  "universal_wasm_checksum": "0x{x:0>16}",
        \\  "source_package_checksum": "0x{x:0>16}",
        \\  "complete": {},
        \\  "proof_receipts": [
        \\
    , .{
        receipt.release_receipt_format_version,
        receipt.release_receipt_fingerprint_version,
        receipt.release_receipt_fingerprint,
        receipt.boundary_protocol_manifest_fingerprint,
        receipt.world_protocol_manifest_fingerprint,
        receipt.conformance_corpus_root_fingerprint,
        receipt.universal_wasm_checksum,
        receipt.source_package_checksum,
        receipt.complete,
    });
    for (proof_receipts, 0..) |proof_receipt, index| {
        if (index != 0) try out.appendSlice(allocator, ",\n");
        try writeProofReceiptJson(allocator, out, proof_receipt, proof_gates[index]);
    }
    try out.print(allocator,
        \\
        \\  ],
        \\  "blockers": [],
        \\  "warnings": []
        \\}}
        \\
    , .{});
}

fn writeProofReceiptJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), receipt: Protocol.ProofReceipt, proof_gate: []const u8) !void {
    try out.print(allocator,
        \\    {{
        \\      "proof_gate": "{s}",
        \\      "proof_gate_fingerprint": "0x{x:0>16}",
        \\      "receipt_format_version": {d},
        \\      "receipt_fingerprint_version": {d},
        \\      "receipt_fingerprint": "0x{x:0>16}",
        \\      "proof_kind": "{s}",
        \\      "protocol_manifest_fingerprint": "0x{x:0>16}",
        \\      "input_corpus_case_fingerprints": 
    , .{
        proof_gate,
        Protocol.proofGateFingerprint(receipt.proof_kind),
        receipt.receipt_format_version,
        receipt.receipt_fingerprint_version,
        receipt.receipt_fingerprint,
        Protocol.proofKindName(receipt.proof_kind),
        receipt.protocol_manifest_fingerprint,
    });
    try writeU64Array(allocator, out, receipt.input_corpus_case_fingerprints);
    try out.appendSlice(allocator, ",\n      \"expected_output_fingerprints\": ");
    try writeU64Array(allocator, out, receipt.expected_output_fingerprints);
    try out.appendSlice(allocator, ",\n      \"actual_output_fingerprints\": ");
    try writeU64Array(allocator, out, receipt.actual_output_fingerprints);
    try out.print(allocator, ",\n      \"actual_comparison_result\": {},\n      \"artifact_fingerprints\": ", .{receipt.actual_comparison_result});
    try writeU64Array(allocator, out, receipt.artifact_fingerprints);
    try out.print(allocator, ",\n      \"blocker_count\": {d},\n      \"warning_count\": {d},\n      \"bounded_diagnostics\": ", .{ receipt.blocker_count, receipt.warning_count });
    try writeU64Array(allocator, out, receipt.bounded_diagnostics);
    try out.appendSlice(allocator, "\n    }");
}

fn writeU64Array(allocator: std.mem.Allocator, out: *std.ArrayList(u8), values: []const u64) !void {
    try out.append(allocator, '[');
    for (values, 0..) |value, index| {
        if (index != 0) try out.appendSlice(allocator, ", ");
        try out.print(allocator, "\"0x{x:0>16}\"", .{value});
    }
    try out.append(allocator, ']');
}

fn sourcePackageChecksum(io: std.Io, allocator: std.mem.Allocator) !u64 {
    var paths = try collectSourcePackagePaths(io, allocator);
    defer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (paths.items) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(8 * 1024 * 1024));
        defer allocator.free(bytes);
        hasher.update(path);
        hasher.update(&.{0});
        hasher.update(bytes);
        hasher.update(&.{0});
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.mem.readInt(u64, digest[0..8], .big);
}

fn collectSourcePackagePaths(io: std.Io, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var paths: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }

    for (source_package_root_files) |path| {
        const owned = try allocator.dupe(u8, path);
        errdefer allocator.free(owned);
        try paths.append(allocator, owned);
    }

    for (source_package_dirs) |root| {
        var dir = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
        defer dir.close(io);

        var walker = try dir.walk(allocator);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            const owned = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, entry.path });
            errdefer allocator.free(owned);
            try paths.append(allocator, owned);
        }
    }

    std.mem.sort([]const u8, paths.items, {}, sourcePathLessThan);
    return paths;
}

fn sourcePathLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn sourcePackagePathCovered(path: []const u8) bool {
    for (source_package_root_files) |covered| {
        if (std.mem.eql(u8, covered, path)) return true;
    }
    for (source_package_dirs) |dir| {
        if (std.mem.startsWith(u8, path, dir) and
            path.len > dir.len and
            path[dir.len] == '/') return true;
    }
    return false;
}

fn checksum64(bytes: []const u8) u64 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.mem.readInt(u64, digest[0..8], .big);
}

fn validateUniversalWasmArtifact(bytes: []const u8) !void {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..4], "\x00asm")) return error.InvalidFrameEncoding;
    if (std.mem.readInt(u32, bytes[4..8], .little) != 1) return error.InvalidFrameEncoding;

    var required_seen = [_]bool{false} ** world.Appliance.Abi.universal_required_exports.len;
    var type_sigs: [max_wasm_types]WasmSignature = undefined;
    var type_count: usize = 0;
    var function_type_indices: [max_wasm_functions]u32 = undefined;
    var function_count: usize = 0;
    var import_count: u32 = 0;
    var cursor: usize = 8;
    while (cursor < bytes.len) {
        const section_id = try readWasmU8(bytes, &cursor);
        const section_len = try readWasmU32(bytes, &cursor);
        if (section_len > bytes.len - cursor) return error.InvalidFrameEncoding;
        const section = bytes[cursor .. cursor + section_len];
        if (section_id == 1) type_count = try inspectWasmTypes(section, &type_sigs);
        if (section_id == 2) import_count = try countWasmImports(section);
        if (section_id == 3) function_count = try inspectWasmFunctions(section, &function_type_indices, type_count);
        if (section_id == 7) try inspectUniversalExports(
            section,
            type_sigs[0..type_count],
            function_type_indices[0..function_count],
            &required_seen,
        );
        cursor += section_len;
    }
    if (import_count != 0) return error.UniversalWasmInspectionFailed;
    for (required_seen) |seen| {
        if (!seen) return error.MissingUniversalWasmExport;
    }
}

const WasmInspectionReceipt = struct {
    universal_wasm_checksum: []const u8,
    protocol_manifest_fingerprint_lo: []const u8,
    protocol_manifest_fingerprint_hi: []const u8,
    artifact_inspection: bool,
    actual_webassembly_execution: bool,
    memory_limit_compliance: bool,
    complete: bool,
};

const ProofReceipts = struct {
    receipt_format_version: u32,
    runner: []const u8,
    evidence_scope: []const u8,
    artifact_inspection: bool,
    actual_webassembly_execution: bool,
    positive_success: bool,
    expected_rejection: bool,
    byte_equality: bool,
    semantic_fingerprint_equality: bool,
    memory_limit_compliance: bool,
    blockers: []const []const u8,
    warnings: []const []const u8,
    complete: bool,
    proof_receipts: []const ProofReceiptEvidence,
    receipt_fingerprint: []const u8,
};

const ProofReceiptEvidence = struct {
    proof_kind: []const u8,
    proof_gate: []const u8,
    proof_gate_fingerprint: []const u8,
    input_corpus_case_fingerprints: []const []const u8,
    expected_output_fingerprints: []const []const u8,
    actual_output_fingerprints: []const []const u8,
    actual_comparison_result: bool,
    bounded_diagnostics: []const []const u8,
    blocker_count: u32,
    warning_count: u32,
};

fn validateWasmInspectionReceipt(allocator: std.mem.Allocator, bytes: []const u8, expected_wasm_checksum: u64) !void {
    const parsed = std.json.parseFromSlice(WasmInspectionReceipt, allocator, bytes, .{
        .ignore_unknown_fields = true,
    }) catch return error.WasmInspectionReceiptIncomplete;
    defer parsed.deinit();

    const receipt = parsed.value;
    if (!receipt.artifact_inspection) return error.WasmInspectionReceiptIncomplete;
    if (!receipt.actual_webassembly_execution) return error.WasmInspectionReceiptIncomplete;
    if (!receipt.memory_limit_compliance) return error.WasmInspectionReceiptIncomplete;
    if (!receipt.complete) return error.WasmInspectionReceiptIncomplete;

    var checksum_buf: [18]u8 = undefined;
    const expected_checksum = try std.fmt.bufPrint(&checksum_buf, "0x{x:0>16}", .{expected_wasm_checksum});
    if (!std.mem.eql(u8, receipt.universal_wasm_checksum, expected_checksum)) return error.WasmInspectionReceiptArtifactMismatch;

    var manifest_buf: [18]u8 = undefined;
    const expected_manifest = try std.fmt.bufPrint(&manifest_buf, "0x{x}", .{Protocol.Manifest.manifestFingerprint().lo});
    if (!std.mem.eql(u8, receipt.protocol_manifest_fingerprint_lo, expected_manifest)) return error.WasmInspectionReceiptArtifactMismatch;

    var manifest_hi_buf: [18]u8 = undefined;
    const expected_manifest_hi = try std.fmt.bufPrint(&manifest_hi_buf, "0x{x}", .{Protocol.Manifest.manifestFingerprint().hi});
    if (!std.mem.eql(u8, receipt.protocol_manifest_fingerprint_hi, expected_manifest_hi)) return error.WasmInspectionReceiptArtifactMismatch;
}

fn validateProofReceipts(allocator: std.mem.Allocator, bytes: []const u8) !void {
    const parsed = std.json.parseFromSlice(ProofReceipts, allocator, bytes, .{
        .ignore_unknown_fields = true,
    }) catch return error.ProofReceiptsIncomplete;
    defer parsed.deinit();

    const receipt = parsed.value;
    if (receipt.receipt_format_version != 1) return error.ProofReceiptsIncomplete;
    if (!std.mem.eql(u8, receipt.runner, "scripts/world_conformance.mjs")) return error.ProofReceiptsIncomplete;
    if (!std.mem.eql(u8, receipt.evidence_scope, "js-corpus")) return error.ProofReceiptsIncomplete;
    if (receipt.artifact_inspection) return error.ProofReceiptsIncomplete;
    if (receipt.actual_webassembly_execution) return error.ProofReceiptsIncomplete;
    if (receipt.memory_limit_compliance) return error.ProofReceiptsIncomplete;
    if (!receipt.positive_success) return error.ProofReceiptsIncomplete;
    if (!receipt.expected_rejection) return error.ProofReceiptsIncomplete;
    if (!receipt.byte_equality) return error.ProofReceiptsIncomplete;
    if (!receipt.semantic_fingerprint_equality) return error.ProofReceiptsIncomplete;
    if (receipt.blockers.len != 0) return error.ProofReceiptsIncomplete;
    if (!receipt.complete) return error.ProofReceiptsIncomplete;
    if (receipt.proof_receipts.len != Protocol.required_proof_kind_count) return error.ProofReceiptsIncomplete;
    if (receipt.receipt_fingerprint.len == 0) return error.ProofReceiptsIncomplete;
}

fn buildProofReceiptsFromEvidence(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    proof_gates: []const []const u8,
    universal_wasm_checksum: u64,
    source_package_checksum: u64,
    proof_receipts: *[Protocol.required_proof_kind_count]Protocol.ProofReceipt,
    input_evidence: *[Protocol.required_proof_kind_count][2]u64,
    expected_evidence: *[Protocol.required_proof_kind_count][2]u64,
    actual_evidence: *[Protocol.required_proof_kind_count][2]u64,
    diagnostics_evidence: *[Protocol.required_proof_kind_count][2]u64,
    artifact_evidence: *[Protocol.required_proof_kind_count][4]u64,
) !void {
    try validateProofReceipts(allocator, bytes);
    const parsed = std.json.parseFromSlice(ProofReceipts, allocator, bytes, .{
        .ignore_unknown_fields = true,
    }) catch return error.ProofReceiptsIncomplete;
    defer parsed.deinit();

    var seen = [_]bool{false} ** Protocol.required_proof_kind_count;
    for (parsed.value.proof_receipts) |receipt| {
        const index = proofEvidenceIndex(receipt.proof_kind) orelse return error.ProofReceiptsIncomplete;
        if (seen[index]) return error.ProofReceiptsIncomplete;
        seen[index] = true;

        const kind = Protocol.required_proof_kinds[index];
        if (!std.mem.eql(u8, receipt.proof_gate, Protocol.proofGateName(kind))) return error.ProofReceiptsIncomplete;
        if (!std.mem.eql(u8, proof_gates[index], receipt.proof_gate)) return error.InvalidProofGate;
        if (try parseHexU64(receipt.proof_gate_fingerprint) != Protocol.proofGateFingerprint(kind)) return error.ProofReceiptsIncomplete;
        input_evidence[index] = try parseEvidencePair(receipt.input_corpus_case_fingerprints);
        expected_evidence[index] = try parseEvidencePair(receipt.expected_output_fingerprints);
        actual_evidence[index] = try parseEvidencePair(receipt.actual_output_fingerprints);
        diagnostics_evidence[index] = try parseEvidencePair(receipt.bounded_diagnostics);
        const canonical_evidence = [_]u64{ Protocol.proofKindEvidenceFingerprint(kind), Protocol.proofGateFingerprint(kind) };
        if (!std.mem.eql(u64, input_evidence[index][0..], canonical_evidence[0..])) return error.ProofReceiptsIncomplete;
        if (!std.mem.eql(u64, expected_evidence[index][0..], canonical_evidence[0..])) return error.ProofReceiptsIncomplete;
        if (!std.mem.eql(u64, actual_evidence[index][0..], canonical_evidence[0..])) return error.ProofReceiptsIncomplete;
        if (!std.mem.eql(u64, diagnostics_evidence[index][0..], canonical_evidence[0..])) return error.ProofReceiptsIncomplete;
        artifact_evidence[index] = .{ input_evidence[index][0], input_evidence[index][1], universal_wasm_checksum, source_package_checksum };
        proof_receipts[index] = Protocol.ProofReceipt.init(.{
            .proof_kind = kind,
            .input_corpus_case_fingerprints = input_evidence[index][0..],
            .expected_output_fingerprints = expected_evidence[index][0..],
            .actual_output_fingerprints = actual_evidence[index][0..],
            .actual_comparison_result = receipt.actual_comparison_result,
            .artifact_fingerprints = artifact_evidence[index][0..],
            .blocker_count = receipt.blocker_count,
            .warning_count = receipt.warning_count,
            .bounded_diagnostics = diagnostics_evidence[index][0..],
        });
    }
    for (seen) |present| if (!present) return error.ProofReceiptsIncomplete;
}

fn proofEvidenceIndex(name: []const u8) ?usize {
    for (Protocol.required_proof_kinds, 0..) |kind, index| {
        if (std.mem.eql(u8, name, Protocol.proofKindName(kind))) return index;
    }
    return null;
}

fn parseEvidencePair(values: []const []const u8) ![2]u64 {
    if (values.len != 2) return error.ProofReceiptsIncomplete;
    return .{ try parseHexU64(values[0]), try parseHexU64(values[1]) };
}

fn parseHexU64(value: []const u8) !u64 {
    if (!std.mem.startsWith(u8, value, "0x")) return error.ProofReceiptsIncomplete;
    return std.fmt.parseInt(u64, value[2..], 16) catch return error.ProofReceiptsIncomplete;
}

test "wasm inspection receipt validation uses parsed fields" {
    const allocator = std.testing.allocator;
    const valid = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "universal_wasm_checksum": "0x0000000000001234",
        \\  "protocol_manifest_fingerprint_lo": "0x{x}",
        \\  "protocol_manifest_fingerprint_hi": "0x{x}",
        \\  "artifact_inspection": true,
        \\  "actual_webassembly_execution": true,
        \\  "memory_limit_compliance": true,
        \\  "complete": true
        \\}}
    , .{ Protocol.Manifest.manifestFingerprint().lo, Protocol.Manifest.manifestFingerprint().hi });
    defer allocator.free(valid);
    try validateWasmInspectionReceipt(allocator, valid, 0x1234);

    const decoy_complete = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "not_complete": true,
        \\  "universal_wasm_checksum": "0x0000000000001234",
        \\  "protocol_manifest_fingerprint_lo": "0x{x}",
        \\  "protocol_manifest_fingerprint_hi": "0x{x}",
        \\  "artifact_inspection": true,
        \\  "actual_webassembly_execution": true,
        \\  "memory_limit_compliance": true,
        \\  "complete": false
        \\}}
    , .{ Protocol.Manifest.manifestFingerprint().lo, Protocol.Manifest.manifestFingerprint().hi });
    defer allocator.free(decoy_complete);
    try std.testing.expectError(error.WasmInspectionReceiptIncomplete, validateWasmInspectionReceipt(allocator, decoy_complete, 0x1234));

    const decoy_checksum = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "not_universal_wasm_checksum": "0x0000000000001234",
        \\  "universal_wasm_checksum": "0x0000000000005678",
        \\  "protocol_manifest_fingerprint_lo": "0x{x}",
        \\  "protocol_manifest_fingerprint_hi": "0x{x}",
        \\  "artifact_inspection": true,
        \\  "actual_webassembly_execution": true,
        \\  "memory_limit_compliance": true,
        \\  "complete": true
        \\}}
    , .{ Protocol.Manifest.manifestFingerprint().lo, Protocol.Manifest.manifestFingerprint().hi });
    defer allocator.free(decoy_checksum);
    try std.testing.expectError(error.WasmInspectionReceiptArtifactMismatch, validateWasmInspectionReceipt(allocator, decoy_checksum, 0x1234));

    const wrong_manifest_hi = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "universal_wasm_checksum": "0x0000000000001234",
        \\  "protocol_manifest_fingerprint_lo": "0x{x}",
        \\  "protocol_manifest_fingerprint_hi": "0x0",
        \\  "artifact_inspection": true,
        \\  "actual_webassembly_execution": true,
        \\  "memory_limit_compliance": true,
        \\  "complete": true
        \\}}
    , .{Protocol.Manifest.manifestFingerprint().lo});
    defer allocator.free(wrong_manifest_hi);
    try std.testing.expectError(error.WasmInspectionReceiptArtifactMismatch, validateWasmInspectionReceipt(allocator, wrong_manifest_hi, 0x1234));
}

test "source package checksum covers release-defining source paths" {
    for ([_][]const u8{
        "build.zig",
        "src/protocol.zig",
        "src/appliance.zig",
        "examples/world_universal_appliance_wasm.zig",
        "examples/world_universal_appliance_fixtures.zig",
        "examples/world_release_receipt_emit.zig",
        "scripts/world_release_artifacts.mjs",
        "scripts/world_conformance.mjs",
        "scripts/world_universal_appliance_conformance.mjs",
        "scripts/world_universal_appliance_host.mjs",
    }) |path| {
        try std.testing.expect(sourcePackagePathCovered(path));
    }
}

test "proof receipts validation requires complete corpus evidence" {
    const allocator = std.testing.allocator;
    const valid =
        \\{
        \\  "receipt_format_version": 1,
        \\  "runner": "scripts/world_conformance.mjs",
        \\  "evidence_scope": "js-corpus",
        \\  "artifact_inspection": false,
        \\  "actual_webassembly_execution": false,
        \\  "positive_success": true,
        \\  "expected_rejection": true,
        \\  "byte_equality": true,
        \\  "semantic_fingerprint_equality": true,
        \\  "memory_limit_compliance": false,
        \\  "blockers": [],
        \\  "warnings": [],
        \\  "complete": true,
        \\  "proof_receipts": [],
        \\  "receipt_fingerprint": "0x600b4a5cd40bcb72"
        \\}
    ;
    try std.testing.expectError(error.ProofReceiptsIncomplete, validateProofReceipts(allocator, valid));

    const decoy_complete =
        \\{
        \\  "receipt_format_version": 1,
        \\  "runner": "scripts/world_conformance.mjs",
        \\  "evidence_scope": "js-corpus",
        \\  "artifact_inspection": false,
        \\  "actual_webassembly_execution": false,
        \\  "positive_success": true,
        \\  "expected_rejection": true,
        \\  "byte_equality": true,
        \\  "semantic_fingerprint_equality": true,
        \\  "memory_limit_compliance": false,
        \\  "blockers": [],
        \\  "warnings": [],
        \\  "complete": false,
        \\  "proof_receipts": [],
        \\  "receipt_fingerprint": "0x600b4a5cd40bcb72"
        \\}
    ;
    try std.testing.expectError(error.ProofReceiptsIncomplete, validateProofReceipts(allocator, decoy_complete));

    const partial_corpus =
        \\{
        \\  "receipt_format_version": 1,
        \\  "runner": "scripts/world_conformance.mjs",
        \\  "evidence_scope": "js-corpus",
        \\  "artifact_inspection": false,
        \\  "actual_webassembly_execution": false,
        \\  "positive_success": true,
        \\  "expected_rejection": false,
        \\  "byte_equality": true,
        \\  "semantic_fingerprint_equality": true,
        \\  "memory_limit_compliance": false,
        \\  "blockers": [],
        \\  "warnings": [],
        \\  "complete": true,
        \\  "proof_receipts": [],
        \\  "receipt_fingerprint": "0x600b4a5cd40bcb72"
        \\}
    ;
    try std.testing.expectError(error.ProofReceiptsIncomplete, validateProofReceipts(allocator, partial_corpus));
}

test "universal wasm artifact validation rejects non-function required exports" {
    const allocator = std.testing.allocator;
    var section: std.ArrayList(u8) = .empty;
    defer section.deinit(allocator);
    try appendWasmU32(allocator, &section, world.Appliance.Abi.universal_required_exports.len);
    for (world.Appliance.Abi.universal_required_exports) |name| {
        try appendWasmName(allocator, &section, name);
        try section.append(allocator, 3);
        try appendWasmU32(allocator, &section, 0);
    }

    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(allocator);
    try bytes.appendSlice(allocator, "\x00asm");
    try bytes.appendSlice(allocator, &.{ 1, 0, 0, 0 });
    try bytes.append(allocator, 7);
    try appendWasmU32(allocator, &bytes, @intCast(section.items.len));
    try bytes.appendSlice(allocator, section.items);

    try std.testing.expectError(error.UniversalWasmInspectionFailed, validateUniversalWasmArtifact(bytes.items));
}

test "universal wasm artifact validation rejects wrong required export signatures" {
    const allocator = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(allocator);
    try bytes.appendSlice(allocator, "\x00asm");
    try bytes.appendSlice(allocator, &.{ 1, 0, 0, 0 });

    var type_section: std.ArrayList(u8) = .empty;
    defer type_section.deinit(allocator);
    try appendWasmU32(allocator, &type_section, 1);
    try type_section.append(allocator, 0x60);
    try appendWasmU32(allocator, &type_section, 0);
    try appendWasmU32(allocator, &type_section, 0);
    try appendWasmSection(allocator, &bytes, 1, type_section.items);

    var function_section: std.ArrayList(u8) = .empty;
    defer function_section.deinit(allocator);
    try appendWasmU32(allocator, &function_section, world.Appliance.Abi.universal_required_exports.len);
    for (world.Appliance.Abi.universal_required_exports) |_| try appendWasmU32(allocator, &function_section, 0);
    try appendWasmSection(allocator, &bytes, 3, function_section.items);

    var export_section: std.ArrayList(u8) = .empty;
    defer export_section.deinit(allocator);
    try appendWasmU32(allocator, &export_section, world.Appliance.Abi.universal_required_exports.len);
    for (world.Appliance.Abi.universal_required_exports, 0..) |name, index| {
        try appendWasmName(allocator, &export_section, name);
        try export_section.append(allocator, 0);
        try appendWasmU32(allocator, &export_section, @intCast(index));
    }
    try appendWasmSection(allocator, &bytes, 7, export_section.items);

    try std.testing.expectError(error.UniversalWasmInspectionFailed, validateUniversalWasmArtifact(bytes.items));
}

fn countWasmImports(section: []const u8) !u32 {
    var cursor: usize = 0;
    const count = try readWasmU32(section, &cursor);
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        _ = try readWasmName(section, &cursor);
        _ = try readWasmName(section, &cursor);
        const kind = try readWasmU8(section, &cursor);
        switch (kind) {
            0 => _ = try readWasmU32(section, &cursor),
            1 => {
                _ = try readWasmU8(section, &cursor);
                try skipWasmLimits(section, &cursor);
            },
            2 => try skipWasmLimits(section, &cursor),
            3 => {
                _ = try readWasmU8(section, &cursor);
                _ = try readWasmU8(section, &cursor);
            },
            else => return error.InvalidFrameEncoding,
        }
    }
    if (cursor != section.len) return error.InvalidFrameEncoding;
    return count;
}

fn skipWasmLimits(bytes: []const u8, cursor: *usize) !void {
    const flags = try readWasmU8(bytes, cursor);
    _ = try readWasmU32(bytes, cursor);
    if ((flags & 0x01) != 0) _ = try readWasmU32(bytes, cursor);
    if ((flags & ~@as(u8, 0x01)) != 0) return error.InvalidFrameEncoding;
}

fn inspectWasmTypes(section: []const u8, out: *[max_wasm_types]WasmSignature) !usize {
    var cursor: usize = 0;
    const count = try readWasmU32(section, &cursor);
    if (count > out.len) return error.CapacityExceeded;
    var index: usize = 0;
    while (index < count) : (index += 1) {
        if (try readWasmU8(section, &cursor) != 0x60) return error.InvalidFrameEncoding;
        const params = try readWasmU32(section, &cursor);
        var params_all_i32 = true;
        var param_index: u32 = 0;
        while (param_index < params) : (param_index += 1) {
            if (try readWasmU8(section, &cursor) != 0x7f) params_all_i32 = false;
        }
        const results = try readWasmU32(section, &cursor);
        var results_all_i32 = true;
        var results_all_i64 = true;
        var result_index: u32 = 0;
        while (result_index < results) : (result_index += 1) {
            const result_type = try readWasmU8(section, &cursor);
            if (result_type != 0x7f) results_all_i32 = false;
            if (result_type != 0x7e) results_all_i64 = false;
        }
        out[index] = .{
            .params = params,
            .results = results,
            .params_all_i32 = params_all_i32,
            .results_all_i32 = results_all_i32,
            .results_all_i64 = results_all_i64,
        };
    }
    if (cursor != section.len) return error.InvalidFrameEncoding;
    return @intCast(count);
}

fn inspectWasmFunctions(section: []const u8, out: *[max_wasm_functions]u32, type_count: usize) !usize {
    var cursor: usize = 0;
    const count = try readWasmU32(section, &cursor);
    if (count > out.len) return error.CapacityExceeded;
    var index: usize = 0;
    while (index < count) : (index += 1) {
        const type_index = try readWasmU32(section, &cursor);
        if (type_index >= type_count) return error.InvalidFrameEncoding;
        out[index] = type_index;
    }
    if (cursor != section.len) return error.InvalidFrameEncoding;
    return @intCast(count);
}

fn inspectUniversalExports(
    section: []const u8,
    type_sigs: []const WasmSignature,
    function_type_indices: []const u32,
    required_seen: *[world.Appliance.Abi.universal_required_exports.len]bool,
) !void {
    var cursor: usize = 0;
    const count = try readWasmU32(section, &cursor);
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const name = try readWasmName(section, &cursor);
        const kind = try readWasmU8(section, &cursor);
        const export_index = try readWasmU32(section, &cursor);
        for (world.Appliance.Abi.universal_required_exports, 0..) |required, required_index| {
            if (!std.mem.eql(u8, name, required)) continue;
            if (kind != 0) return error.UniversalWasmInspectionFailed;
            if (!wasmSignatureMatches(
                export_index,
                type_sigs,
                function_type_indices,
                expectedWasmParamCount(required_index),
                expectedWasmResultCount(required_index),
                expectedWasmResultType(required_index),
            )) return error.UniversalWasmInspectionFailed;
            required_seen[required_index] = true;
        }
    }
    if (cursor != section.len) return error.InvalidFrameEncoding;
}

fn wasmSignatureMatches(
    function_index: u32,
    type_sigs: []const WasmSignature,
    function_type_indices: []const u32,
    params: u32,
    results: u32,
    result_type: ?u8,
) bool {
    if (function_index >= function_type_indices.len) return false;
    const type_index = function_type_indices[@intCast(function_index)];
    if (type_index >= type_sigs.len) return false;
    return type_sigs[@intCast(type_index)].matches(params, results, result_type);
}

fn expectedWasmParamCount(index: usize) u32 {
    return switch (index) {
        2, 3 => 2,
        6 => 2,
        7 => 2,
        9 => 2,
        11 => 2,
        13 => 1,
        14 => 2,
        16 => 2,
        else => 0,
    };
}

fn expectedWasmResultCount(index: usize) u32 {
    return switch (index) {
        14 => 0,
        else => 1,
    };
}

fn expectedWasmResultType(index: usize) ?u8 {
    return switch (index) {
        14 => null,
        17, 18 => 0x7e,
        else => 0x7f,
    };
}

fn appendWasmSection(allocator: std.mem.Allocator, out: *std.ArrayList(u8), id: u8, section: []const u8) !void {
    try out.append(allocator, id);
    try appendWasmU32(allocator, out, @intCast(section.len));
    try out.appendSlice(allocator, section);
}

fn appendWasmName(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8) !void {
    try appendWasmU32(allocator, out, @intCast(name.len));
    try out.appendSlice(allocator, name);
}

fn appendWasmU32(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: u32) !void {
    var remaining = value;
    while (true) {
        var byte: u8 = @intCast(remaining & 0x7f);
        remaining >>= 7;
        if (remaining != 0) byte |= 0x80;
        try out.append(allocator, byte);
        if (remaining == 0) break;
    }
}

fn readWasmName(bytes: []const u8, cursor: *usize) ![]const u8 {
    const len = try readWasmU32(bytes, cursor);
    if (len > bytes.len - cursor.*) return error.InvalidFrameEncoding;
    const name = bytes[cursor.* .. cursor.* + len];
    cursor.* += len;
    return name;
}

fn readWasmU8(bytes: []const u8, cursor: *usize) !u8 {
    if (cursor.* >= bytes.len) return error.InvalidFrameEncoding;
    const value = bytes[cursor.*];
    cursor.* += 1;
    return value;
}

fn readWasmU32(bytes: []const u8, cursor: *usize) !u32 {
    var result: u32 = 0;
    var shift: u5 = 0;
    while (true) {
        if (cursor.* >= bytes.len) return error.InvalidFrameEncoding;
        const byte = bytes[cursor.*];
        cursor.* += 1;
        result |= @as(u32, byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) return result;
        if (shift == 28) return error.InvalidFrameEncoding;
        shift += 7;
    }
}
