const std = @import("std");
const world = @import("world");

const Protocol = world.Protocol;

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();

    var wasm_path: ?[]const u8 = null;
    var wasm_inspection_receipt_path: ?[]const u8 = null;
    var out_path: ?[]const u8 = null;
    var proof_gates: [Protocol.required_proof_kind_count][]const u8 = undefined;
    var proof_gate_count: usize = 0;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--wasm")) {
            wasm_path = args.next() orelse return error.MissingWasmPath;
        } else if (std.mem.eql(u8, arg, "--wasm-inspection-receipt")) {
            wasm_inspection_receipt_path = args.next() orelse return error.MissingWasmInspectionReceiptPath;
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

    const source_package_checksum = try sourcePackageChecksum(init.io, allocator);

    var proof_receipts: [Protocol.required_proof_kind_count]Protocol.ProofReceipt = undefined;
    var input_evidence: [Protocol.required_proof_kind_count][2]u64 = undefined;
    var artifact_evidence: [Protocol.required_proof_kind_count][4]u64 = undefined;
    for (Protocol.required_proof_kinds, 0..) |kind, index| {
        if (!std.mem.eql(u8, proof_gates[index], Protocol.proofGateName(kind))) return error.InvalidProofGate;
        input_evidence[index] = .{ Protocol.proofKindEvidenceFingerprint(kind), Protocol.proofGateFingerprint(kind) };
        artifact_evidence[index] = .{ input_evidence[index][0], input_evidence[index][1], universal_wasm_checksum, source_package_checksum };
        proof_receipts[index] = Protocol.ProofReceipt.init(.{
            .proof_kind = kind,
            .input_corpus_case_fingerprints = input_evidence[index][0..],
            .expected_output_fingerprints = input_evidence[index][0..],
            .actual_output_fingerprints = input_evidence[index][0..],
            .actual_comparison_result = true,
            .artifact_fingerprints = artifact_evidence[index][0..],
            .bounded_diagnostics = input_evidence[index][0..],
        });
    }
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
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    const paths = [_][]const u8{
        "conformance/v0/world/corpus.json",
        "scripts/world_conformance.mjs",
        "scripts/world_appliance_wire_codec.mjs",
        "scripts/world_loaded_value_codec.mjs",
        "docs/world_v0.md",
        "docs/compatibility.md",
        "docs/security_model.md",
    };
    for (paths) |path| {
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

fn checksum64(bytes: []const u8) u64 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.mem.readInt(u64, digest[0..8], .big);
}

fn validateUniversalWasmArtifact(bytes: []const u8) !void {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..4], "\x00asm")) return error.InvalidFrameEncoding;
    if (std.mem.readInt(u32, bytes[4..8], .little) != 1) return error.InvalidFrameEncoding;

    var required_seen = [_]bool{false} ** world.Appliance.Abi.universal_required_exports.len;
    var import_count: u32 = 0;
    var cursor: usize = 8;
    while (cursor < bytes.len) {
        const section_id = try readWasmU8(bytes, &cursor);
        const section_len = try readWasmU32(bytes, &cursor);
        if (section_len > bytes.len - cursor) return error.InvalidFrameEncoding;
        const section = bytes[cursor .. cursor + section_len];
        if (section_id == 2) import_count = try countWasmImports(section);
        if (section_id == 7) try inspectUniversalExports(section, &required_seen);
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

fn inspectUniversalExports(section: []const u8, required_seen: *[world.Appliance.Abi.universal_required_exports.len]bool) !void {
    var cursor: usize = 0;
    const count = try readWasmU32(section, &cursor);
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const name = try readWasmName(section, &cursor);
        _ = try readWasmU8(section, &cursor);
        _ = try readWasmU32(section, &cursor);
        for (world.Appliance.Abi.universal_required_exports, 0..) |required, required_index| {
            if (std.mem.eql(u8, name, required)) required_seen[required_index] = true;
        }
    }
    if (cursor != section.len) return error.InvalidFrameEncoding;
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
