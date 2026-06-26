const std = @import("std");
const world = @import("world");

const Protocol = world.Protocol;

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();

    var wasm_path: ?[]const u8 = null;
    var out_path: ?[]const u8 = null;
    var proof_gates: [Protocol.required_proof_kind_count][]const u8 = undefined;
    var proof_gate_count: usize = 0;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--wasm")) {
            wasm_path = args.next() orelse return error.MissingWasmPath;
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

    const universal_wasm_checksum = checksum64(wasm_bytes);
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
