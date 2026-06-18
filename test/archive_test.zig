const std = @import("std");
const world = @import("world");

test "archive public root exposes portable byte format surface" {
    try std.testing.expect(@hasDecl(world, "Archive"));
    try std.testing.expect(@hasDecl(world.Archive, "Header"));
    try std.testing.expect(@hasDecl(world.Archive, "SegmentKind"));
    try std.testing.expect(@hasDecl(world.Archive, "SegmentHeader"));
    try std.testing.expect(@hasDecl(world.Archive, "Moment"));
    try std.testing.expect(@hasDecl(world.Archive, "MomentData"));
    try std.testing.expect(@hasDecl(world.Archive, "Seal"));
    try std.testing.expect(@hasDecl(world.Archive, "AppendBatch"));
    try std.testing.expect(@hasDecl(world.Archive, "Image"));
    try std.testing.expect(@hasDecl(world.Archive, "Reader"));
    try std.testing.expect(@hasDecl(world.Archive, "Writer"));
    try std.testing.expect(@hasDecl(world.Archive, "Snapshot"));
    try std.testing.expect(@hasDecl(world.Archive, "Memory"));
    try std.testing.expect(!@hasDecl(world.Archive, "Backend"));
    try std.testing.expect(!@hasDecl(world.Archive, "Session"));
}

test "archive v1 constants and header validate canonical bytes" {
    try std.testing.expectEqual(@as(u32, 1), world.Archive.world_archive_format_version);
    try std.testing.expectEqual(@as(u32, 1), world.Archive.world_archive_header_format_version);
    try std.testing.expectEqual(@as(u32, 1), world.Archive.world_archive_segment_format_version);
    try std.testing.expectEqual(@as(u32, 1), world.Archive.world_archive_moment_format_version);
    try std.testing.expectEqual(@as(u32, 1), world.Archive.world_archive_seal_format_version);
    try std.testing.expectEqual(@as(u32, 1), world.Archive.world_archive_append_batch_format_version);

    const header = world.Archive.Header.init(.{});
    try header.validate();
    try std.testing.expectEqualStrings("WRLDARC1", &header.magic);
    try std.testing.expectEqual(@as(u64, 0x0102030405060708), header.byte_order_marker);

    var bad = header;
    bad.magic[0] = 'X';
    try std.testing.expectError(error.InvalidFrameEncoding, bad.validate());
}

test "archive native fixture exposes stable header identity for wasm parity" {
    const header = world.Archive.Header.init(.{});
    try std.testing.expect(header.header_fingerprint != 0);
    try std.testing.expect(header.archive_profile_fingerprint != 0);
    try std.testing.expectEqual(world.Archive.world_archive_format_version, header.archive_format_version);
    try std.testing.expectEqual(world.Continuity.Chronicle.Cursor.initial().cursor_fingerprint, header.genesis_cursor_fingerprint);
}

test "archive memory reports honest byte-store capabilities" {
    world.Archive.Conformance.requireMemorySurface();

    const caps = world.Archive.Memory.capabilities();
    try std.testing.expect(!caps.persistent_across_process);
    try std.testing.expect(caps.supports_reopen);
    try std.testing.expect(caps.supports_historical_moments);
    try std.testing.expect(caps.supports_valid_prefix_recovery);
    try std.testing.expect(caps.wasm_memory_compatible);
    try std.testing.expect(!caps.wasm_file_compatible);
    try std.testing.expectEqual(world.Archive.DurabilityPosture.memory_only, caps.durability_posture);

    const safety = world.Archive.Memory.safetyReport();
    try safety.validate();
}

fn archiveEnvelope(
    kind: world.Continuity.ObjectKind,
    payload: []const u8,
    label: []const u8,
) world.Continuity.ObjectEnvelope {
    return world.Continuity.ObjectEnvelope.init(.{
        .kind = kind,
        .payload_bytes = payload,
        .label = label,
    });
}

fn commitArchiveObject(
    archive: *world.Archive.Memory,
    envelope: world.Continuity.ObjectEnvelope,
) !world.Archive.Moment {
    var tx = try archive.begin(if (archive.image.latestMoment()) |moment|
        moment.chronicle_resulting_cursor
    else
        world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    const ref = try tx.putObject(envelope);
    const refs = [_]world.Continuity.ObjectRef{ref};
    try tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .object_refs = &refs,
    }));
    return tx.commit();
}

test "archive memory stores canonical bytes and sealed moments" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const initial_len = archive.bytesView().len;
    const envelope = archiveEnvelope(.capsule_image, "capsule-bytes", "capsule");
    const ref = envelope.objectRef();
    const moment = try commitArchiveObject(&archive, envelope);
    try moment.validate();

    try std.testing.expect(archive.bytesView().len > initial_len);
    try std.testing.expect(archive.hasObject(ref));
    const latest = try archive.latestMoment();
    try std.testing.expectEqual(moment.moment_fingerprint, latest.moment_fingerprint);

    const reader = world.Archive.Reader.init(std.testing.allocator, archive.bytesView(), .{});
    const validation = reader.validate();
    try std.testing.expect(validation.valid);
    const scan = try reader.scan();
    try std.testing.expectEqual(@as(usize, 1), scan.committed_moment_count);
    try std.testing.expectEqual(archive.bytesView().len, scan.committed_prefix_byte_len);
}

test "archive valid-prefix recovery discards unsealed tail" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "first", "first"));
    const sealed_len = archive.bytesView().len;

    var damaged = try std.testing.allocator.dupe(u8, archive.bytesView());
    defer std.testing.allocator.free(damaged);
    damaged = try std.testing.allocator.realloc(damaged, sealed_len + 9);
    @memcpy(damaged[sealed_len..], "tailbytes");

    const reader = world.Archive.Reader.init(std.testing.allocator, damaged, .{});
    const scan = try reader.scan();
    try std.testing.expect(scan.recovered);
    try std.testing.expectEqual(sealed_len, scan.committed_prefix_byte_len);
    try std.testing.expectEqual(@as(usize, 9), scan.discarded_tail_byte_len);
    const recovery = try reader.recover();
    try std.testing.expectEqual(@as(usize, 1), recovery.recovered_moment_count);
}

test "archive partial final seal is not committed" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "first", "first"));
    const first_len = archive.bytesView().len;
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_manifest, "second", "second"));
    const all_bytes = archive.bytesView();
    const truncated = all_bytes[0 .. all_bytes.len - 10];

    const reader = world.Archive.Reader.init(std.testing.allocator, truncated, .{});
    const recovery = try reader.recover();
    try std.testing.expectEqual(first_len, recovery.committed_prefix_byte_len);
    try std.testing.expectEqual(@as(usize, 1), recovery.recovered_moment_count);
}

test "archive snapshot reads historical prefix and replay binds cursor" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const first = archiveEnvelope(.capsule_image, "capsule-one", "capsule-one");
    const second = archiveEnvelope(.capsule_manifest, "manifest-two", "manifest-two");
    const first_ref = first.objectRef();
    const second_ref = second.objectRef();

    const first_moment = try commitArchiveObject(&archive, first);
    _ = try commitArchiveObject(&archive, second);

    var snapshot = try archive.openMoment(first_moment);
    const visible = try snapshot.getObject(first_ref);
    try std.testing.expectEqual(first_ref.ref_fingerprint, visible.objectRef().ref_fingerprint);
    try std.testing.expectError(error.ObjectMissing, snapshot.getObject(second_ref));
    try std.testing.expectEqual(@as(usize, 1), try snapshot.objectCount());
    try std.testing.expectEqual(@as(usize, 1), try snapshot.commitCount());

    var projection = try snapshot.replayProjection(.object_index);
    defer snapshot.deinitProjectionReport(&projection);
    try projection.validate();
    try std.testing.expectEqual(snapshot.cursor().cursor_fingerprint, projection.source_cursor_fingerprint);
}

test "archive snapshot indexes are rebuilt by Chronicle projection" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const capsule = archiveEnvelope(.capsule_image, "capsule-index", "capsule-index");
    const receipt = archiveEnvelope(.actuation_receipt, "receipt-index", "receipt-index");
    const capsule_ref = capsule.objectRef();
    const receipt_ref = receipt.objectRef();

    _ = try commitArchiveObject(&archive, capsule);
    const moment = try commitArchiveObject(&archive, receipt);
    var snapshot = try archive.openMoment(moment);

    var capsule_index = try snapshot.capsuleIndex();
    defer capsule_index.deinit();
    try std.testing.expect(refSliceContains(capsule_index.refs, capsule_ref));

    var actuation_index = try snapshot.actuationIndex();
    defer actuation_index.deinit();
    try std.testing.expect(refSliceContains(actuation_index.refs, receipt_ref));
}

test "archive byte clone reopen preserves idempotency conflict evidence" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const key_envelope = archiveEnvelope(.actuation_idempotency_key, "idem-key-persisted", "idem-key-persisted");
    const key_ref = key_envelope.objectRef();
    _ = try commitArchiveObject(&archive, key_envelope);

    var reopened = try world.Archive.Memory.reopenFrom(&archive, std.testing.allocator);
    defer reopened.deinit();

    try std.testing.expectEqual(archive.bytesView().len, reopened.bytesView().len);
    try std.testing.expectError(error.DuplicateBinding, reopened.assertFreshIdempotencyAllowed(key_ref));
}

test "archive conformance memory trace proves reopen replay and historical reads" {
    const report = try world.Archive.Conformance.runMemory(std.testing.allocator);
    try report.validate();
    try std.testing.expectEqual(@as(usize, 0), report.replay_mismatch_count);
}

test "archive memory transaction hides staged objects until commit" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const envelope = archiveEnvelope(.bundle, "bundle-bytes", "bundle");
    const ref = envelope.objectRef();
    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();

    _ = try tx.putObject(envelope);
    try std.testing.expect(!archive.hasObject(ref));

    const refs = [_]world.Continuity.ObjectRef{ref};
    try tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .bundle_import_committed,
        .bundle_ref = ref,
        .object_refs = &refs,
    }));
    _ = try tx.commit();
    try std.testing.expect(archive.hasObject(ref));
}

fn refSliceContains(refs: []const world.Continuity.ObjectRef, needle: world.Continuity.ObjectRef) bool {
    for (refs) |ref| {
        if (ref.eql(needle)) return true;
    }
    return false;
}
