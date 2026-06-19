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
    try world.Archive.Conformance.requireCanonicalOptionalTags();
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
    if (kind == .capsule_image) return archiveCapsuleEnvelope(payload, label);
    return world.Continuity.ObjectEnvelope.init(.{
        .kind = kind,
        .payload_bytes = payload,
        .label = label,
    });
}

var archive_capsule_payload_slots: [512][4096]u8 = undefined;
var archive_capsule_payload_next: usize = 0;

fn archiveCapsuleEnvelope(metadata: []const u8, label: []const u8) world.Continuity.ObjectEnvelope {
    const slot_index = archive_capsule_payload_next % archive_capsule_payload_slots.len;
    archive_capsule_payload_next += 1;
    var fixed = std.heap.FixedBufferAllocator.init(&archive_capsule_payload_slots[slot_index]);
    const manifest = world.Capsule.Manifest.init(.{
        .kind = .reference_only,
        .root_target_ref_fingerprint = 0xA4C1_0001,
        .normal_form = .quiescent_completed,
        .metadata = metadata,
    });
    const runspace_image = world.Capsule.RunspaceImage.init(.{
        .runspace_fingerprint = 0xA4C1_0002,
        .runspace_report_fingerprint = 0xA4C1_0003,
        .metadata = metadata,
    });
    const image = world.Capsule.Image.init(.{
        .manifest = manifest,
        .runspace_image = runspace_image,
        .metadata = metadata,
    });
    image.validate(.{}) catch unreachable;
    const encoded = image.encode(fixed.allocator()) catch unreachable;
    return world.Continuity.ObjectEnvelope.init(.{
        .kind = .capsule_image,
        .object_format_version = image.format_version,
        .payload_bytes = encoded,
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
    defer {
        var cleanup = recovery;
        cleanup.deinit(std.testing.allocator);
    }
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
    defer {
        var cleanup = recovery;
        cleanup.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(first_len, recovery.committed_prefix_byte_len);
    try std.testing.expectEqual(@as(usize, 1), recovery.recovered_moment_count);
}

test "archive recovery discards complete moment data followed by non-seal segment" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "first-sealed", "first-sealed"));
    const first_len = archive.bytesView().len;
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_manifest, "second-unsealed", "second-unsealed"));
    const second_data_end = try archiveSecondMomentDataEnd(archive.bytesView());

    var damaged: std.ArrayList(u8) = .empty;
    defer damaged.deinit(std.testing.allocator);
    try damaged.appendSlice(std.testing.allocator, archive.bytesView()[0..second_data_end]);
    try appendArchiveOptionalExtension(std.testing.allocator, &damaged, 2, "valid-non-seal-tail");

    const reader = world.Archive.Reader.init(std.testing.allocator, damaged.items, .{});
    var recovery = try reader.recover();
    defer recovery.deinit(std.testing.allocator);
    try std.testing.expectEqual(first_len, recovery.committed_prefix_byte_len);
    try std.testing.expectEqual(damaged.items.len - first_len, recovery.discarded_tail_byte_len);
    try std.testing.expectEqual(@as(usize, 1), recovery.recovered_moment_count);
}

test "archive recovery discards stray complete seal tail" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "stray-seal-first", "stray-seal-first"));
    const first_len = archive.bytesView().len;

    var damaged: std.ArrayList(u8) = .empty;
    defer damaged.deinit(std.testing.allocator);
    try damaged.appendSlice(std.testing.allocator, archive.bytesView());
    try appendArchiveRequiredSegment(std.testing.allocator, &damaged, .moment_seal, 2, "stray-seal-tail");

    const reader = world.Archive.Reader.init(std.testing.allocator, damaged.items, .{});
    var recovery = try reader.recover();
    defer recovery.deinit(std.testing.allocator);
    try std.testing.expectEqual(first_len, recovery.committed_prefix_byte_len);
    try std.testing.expectEqual(damaged.items.len - first_len, recovery.discarded_tail_byte_len);
    try std.testing.expectEqual(@as(usize, 1), recovery.recovered_moment_count);
}

test "archive recovery latest cursor is bound to cloned latest moment" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const moment = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "cursor-owned", "cursor-owned"));
    const reader = world.Archive.Reader.init(std.testing.allocator, archive.bytesView(), .{});
    var recovery = try reader.recover();
    defer recovery.deinit(std.testing.allocator);

    try std.testing.expect(recovery.latest_moment != null);
    try std.testing.expectEqual(moment.moment_fingerprint, recovery.latest_moment.?.moment_fingerprint);
    try std.testing.expectEqual(
        recovery.latest_moment.?.chronicle_resulting_cursor.cursor_fingerprint,
        recovery.latest_cursor.cursor_fingerprint,
    );
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
    defer snapshot.deinit();
    var visible = try snapshot.getObject(first_ref);
    defer visible.deinit(std.testing.allocator);
    try std.testing.expectEqual(first_ref.ref_fingerprint, visible.objectRef().ref_fingerprint);
    const semantic_first_ref = world.Continuity.ObjectRef.init(.{
        .kind = first_ref.kind,
        .object_format_version = first_ref.object_format_version,
        .object_fingerprint = first_ref.object_fingerprint,
        .byte_len = 0,
    });
    var semantic_visible = try snapshot.getObject(semantic_first_ref);
    defer semantic_visible.deinit(std.testing.allocator);
    try std.testing.expectEqual(first_ref.ref_fingerprint, semantic_visible.objectRef().ref_fingerprint);
    try std.testing.expectError(error.ObjectMissing, snapshot.getObject(second_ref));
    try std.testing.expectEqual(@as(usize, 1), try snapshot.objectCount());
    try std.testing.expectEqual(@as(usize, 1), try snapshot.commitCount());

    var projection = try snapshot.replayProjection(.object_index);
    defer snapshot.deinitProjectionReport(&projection);
    try projection.validate();
    try std.testing.expectEqual(snapshot.cursor().cursor_fingerprint, projection.source_cursor_fingerprint);
}

test "archive snapshot remains valid after memory refresh" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const first = archiveEnvelope(.capsule_image, "snapshot-refresh-one", "snapshot-refresh-one");
    const second = archiveEnvelope(.capsule_manifest, "snapshot-refresh-two", "snapshot-refresh-two");
    const first_ref = first.objectRef();
    const second_ref = second.objectRef();

    const first_moment = try commitArchiveObject(&archive, first);
    var snapshot = try archive.openMoment(first_moment);
    defer snapshot.deinit();
    _ = try commitArchiveObject(&archive, second);

    var visible = try snapshot.getObject(first_ref);
    defer visible.deinit(std.testing.allocator);
    try std.testing.expectEqual(first_ref.ref_fingerprint, visible.objectRef().ref_fingerprint);
    try std.testing.expectError(error.ObjectMissing, snapshot.getObject(second_ref));
    try std.testing.expectEqual(@as(usize, 1), try snapshot.objectCount());
}

test "archive snapshot indexes are rebuilt by Chronicle projection" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const capsule = archiveEnvelope(.capsule_image, "capsule-index", "capsule-index");
    const receipt = try archiveReceiptEnvelope(std.testing.allocator, "receipt-index", 0xA700);
    defer std.testing.allocator.free(receipt.payload_bytes);
    defer std.testing.allocator.free(receipt.dependency_refs);
    const capsule_ref = capsule.objectRef();
    const receipt_ref = receipt.objectRef();

    _ = try commitArchiveObject(&archive, capsule);
    const moment = try commitArchiveObject(&archive, receipt);
    var snapshot = try archive.openMoment(moment);
    defer snapshot.deinit();

    var capsule_index = try snapshot.capsuleIndex();
    defer capsule_index.deinit();
    try std.testing.expect(refSliceContains(capsule_index.refs, capsule_ref));

    var actuation_index = try snapshot.actuationIndex();
    defer actuation_index.deinit();
    try std.testing.expect(refSliceContains(actuation_index.refs, receipt_ref));
}

test "archive transactions populate dedicated moment summary refs" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const assembly = archiveEnvelope(.assembly, "assembly-summary", "assembly-summary");
    const assembly_ref = assembly.objectRef();
    const moment = try commitArchiveObject(&archive, assembly);

    try std.testing.expect(refSliceContains(moment.root_object_refs, assembly_ref));
    try std.testing.expect(refSliceContains(moment.link_assembly_refs, assembly_ref));
}

test "archive transactions accept semantic dependency refs resolved by fingerprint" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const dependency = archiveEnvelope(.capsule_manifest, "semantic-dep", "semantic-dep");
    _ = try commitArchiveObject(&archive, dependency);
    const dependency_ref = dependency.objectRef();
    const semantic_dependency_ref = world.Continuity.ObjectRef.init(.{
        .kind = dependency_ref.kind,
        .object_format_version = dependency_ref.object_format_version,
        .object_fingerprint = dependency_ref.object_fingerprint,
        .byte_len = 0,
    });
    const dependency_refs = [_]world.Continuity.ObjectRef{semantic_dependency_ref};
    const envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .bundle,
        .payload_bytes = "semantic-dep-user",
        .label = "semantic-dep-user",
        .dependency_refs = &dependency_refs,
    });

    var tx = try archive.begin(archive.image.latestMoment().?.chronicle_resulting_cursor, .{});
    defer tx.deinit();
    _ = try tx.putObject(envelope);
    _ = try tx.commit();
}

test "archive object lookup validates semantic refs before matching" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const envelope = archiveEnvelope(.capsule_manifest, "semantic-lookup", "semantic-lookup");
    _ = try commitArchiveObject(&archive, envelope);
    const ref = envelope.objectRef();
    const semantic_ref = world.Continuity.ObjectRef.init(.{
        .kind = ref.kind,
        .object_format_version = ref.object_format_version,
        .object_fingerprint = ref.object_fingerprint,
        .byte_len = 0,
    });
    var object = try archive.getObject(semantic_ref);
    defer object.deinit(std.testing.allocator);
    try std.testing.expect(archive.hasObject(semantic_ref));

    var malformed_ref = ref;
    malformed_ref.byte_len = 0;
    try std.testing.expect(!archive.hasObject(malformed_ref));
    try std.testing.expectError(error.InvalidFrameEncoding, archive.getObject(malformed_ref));
}

test "archive transactions accept receipt-backed semantic idempotency keys" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const receipt = try archiveReceiptEnvelope(std.testing.allocator, "receipt-key-evidence", 0xA800);
    defer std.testing.allocator.free(receipt.payload_bytes);
    defer std.testing.allocator.free(receipt.dependency_refs);
    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    const receipt_ref = try tx.putObject(receipt);
    const actuation_refs = [_]world.Continuity.ObjectRef{receipt_ref};
    const key_ref = world.Continuity.ObjectRef.init(.{
        .kind = .actuation_idempotency_key,
        .object_fingerprint = 0xA800 + 8,
        .byte_len = 0,
    });
    try tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .actuation_idempotency_registered,
        .actuation_refs = &actuation_refs,
        .actuation_idempotency_key_ref = key_ref,
        .target_ref = receipt_ref,
    }));
    _ = try tx.commit();
}

test "archive transactions reject receipt-backed concrete idempotency keys when missing" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const receipt = try archiveReceiptEnvelope(std.testing.allocator, "receipt-key-concrete", 0xA810);
    defer std.testing.allocator.free(receipt.payload_bytes);
    defer std.testing.allocator.free(receipt.dependency_refs);
    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    const receipt_ref = try tx.putObject(receipt);
    const actuation_refs = [_]world.Continuity.ObjectRef{receipt_ref};
    const key_ref = world.Continuity.ObjectRef.init(.{
        .kind = .actuation_idempotency_key,
        .object_fingerprint = 0xA810 + 8,
        .byte_len = 1,
    });
    try tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .actuation_idempotency_registered,
        .actuation_refs = &actuation_refs,
        .actuation_idempotency_key_ref = key_ref,
        .target_ref = receipt_ref,
    }));
    try std.testing.expectError(error.InvalidFrameEncoding, tx.commit());
}

test "archive transactions reject unproven semantic idempotency keys" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const receipt = try archiveReceiptEnvelope(std.testing.allocator, "receipt-key-mismatch", 0xA820);
    defer std.testing.allocator.free(receipt.payload_bytes);
    defer std.testing.allocator.free(receipt.dependency_refs);
    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    const receipt_ref = try tx.putObject(receipt);
    const actuation_refs = [_]world.Continuity.ObjectRef{receipt_ref};
    const key_ref = world.Continuity.ObjectRef.init(.{
        .kind = .actuation_idempotency_key,
        .object_fingerprint = 0xA820 + 9,
        .byte_len = 0,
    });
    try tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .actuation_idempotency_registered,
        .actuation_refs = &actuation_refs,
        .actuation_idempotency_key_ref = key_ref,
        .target_ref = receipt_ref,
    }));
    try std.testing.expectError(error.InvalidFrameEncoding, tx.commit());
}

test "archive writer enforces configured ref-count limit before append" {
    const envelope = archiveEnvelope(.bundle, "limit-object", "limit-object");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = 0xA900,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const event_fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&event_fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = 0xA900,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &event_fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{ .max_ref_count = 0 });
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
    try std.testing.expectEqual(@as(usize, 0), writer.bytes.items.len);
}

test "archive writer rejects malformed typed payloads before append" {
    const envelope = archiveEnvelope(.actuation_receipt, "writer-bad-receipt", "writer-bad-receipt");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = 0xA930,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const event_fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&event_fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = 0xA930,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .actuation_refs = &refs,
        .committed_event_fingerprints = &event_fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
    try std.testing.expectEqual(@as(usize, 0), writer.bytes.items.len);
}

test "archive writer rejects malformed capsule image payloads before append" {
    const envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .capsule_image,
        .payload_bytes = "writer-bad-capsule",
        .label = "writer-bad-capsule",
    });
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = 0xA931,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const event_fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&event_fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = 0xA931,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .capsule_refs = &refs,
        .committed_event_fingerprints = &event_fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
    try std.testing.expectEqual(@as(usize, 0), writer.bytes.items.len);
}

test "archive writer enforces configured payload limit before append" {
    const envelope = archiveEnvelope(.bundle, "payload-over-limit", "limit");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = 0xA940,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const event_fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&event_fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = 0xA940,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &event_fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{ .max_payload_bytes = 4 });
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
    try std.testing.expectEqual(@as(usize, 0), writer.bytes.items.len);
}

test "archive writer rejects encoded envelopes over configured payload limit" {
    const envelope = archiveEnvelope(.bundle, "p", "l");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = 0xA941,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const event_fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&event_fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = 0xA941,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &event_fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{ .max_payload_bytes = 16 });
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
    try std.testing.expectEqual(@as(usize, 0), writer.bytes.items.len);
}

test "archive reader honors configured payload limit while decoding" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.bundle, "reader-payload-over-limit", "reader-limit"));

    const reader = world.Archive.Reader.init(std.testing.allocator, archive.bytesView(), .{ .max_payload_bytes = 4 });
    const scan = try reader.scan();
    try std.testing.expect(scan.recovered);
    try std.testing.expectEqual(@as(usize, 0), scan.committed_moment_count);
    try std.testing.expect(scan.discarded_tail_byte_len > 0);
}

test "archive reader honors configured event-count limit while decoding" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.bundle, "reader-event-over-limit", "reader-event-limit"));

    const reader = world.Archive.Reader.init(std.testing.allocator, archive.bytesView(), .{ .max_event_count_per_moment = 0 });
    const scan = try reader.scan();
    try std.testing.expect(scan.recovered);
    try std.testing.expectEqual(@as(usize, 0), scan.committed_moment_count);
    try std.testing.expect(scan.discarded_tail_byte_len > 0);
}

test "archive reader honors configured object-count limit while decoding" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.bundle, "reader-object-over-limit", "reader-object-limit"));

    const reader = world.Archive.Reader.init(std.testing.allocator, archive.bytesView(), .{ .max_object_count_per_moment = 0 });
    const scan = try reader.scan();
    try std.testing.expect(scan.recovered);
    try std.testing.expectEqual(@as(usize, 0), scan.committed_moment_count);
    try std.testing.expect(scan.discarded_tail_byte_len > 0);
}

test "archive writer accepts semantic evidence refs in domain events" {
    const bundle_ref = world.Continuity.ObjectRef.init(.{
        .kind = .bundle,
        .object_fingerprint = 0xAA01,
        .byte_len = 0,
    });
    const capsule_ref = world.Continuity.ObjectRef.init(.{
        .kind = .capsule_image,
        .object_fingerprint = 0xAA02,
        .byte_len = 0,
    });
    const recovery_plan_ref = world.Continuity.ObjectRef.init(.{
        .kind = .capsule_thaw_plan,
        .object_fingerprint = 0xAA03,
        .byte_len = 0,
    });
    const recovery_report_ref = world.Continuity.ObjectRef.init(.{
        .kind = .capsule_restore_report,
        .object_fingerprint = 0xAA04,
        .byte_len = 0,
    });
    const handoff_ref = world.Continuity.ObjectRef.init(.{
        .kind = .handoff_envelope,
        .object_fingerprint = 0xAA05,
        .byte_len = 0,
    });
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .bundle_import_committed,
        .capsule_ref = capsule_ref,
        .bundle_ref = bundle_ref,
        .recovery_plan_ref = recovery_plan_ref,
        .recovery_report_ref = recovery_report_ref,
        .inbox_outbox_item_ref = handoff_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const event_fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&event_fingerprints, 0, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = 0xAA10,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_event_fingerprints = &event_fingerprints,
    });
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &.{},
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    _ = try writer.append(batch, null, null);
    const reader = world.Archive.Reader.init(std.testing.allocator, writer.bytes.items, .{});
    const scan = try reader.scan();
    try std.testing.expectEqual(@as(usize, 1), scan.committed_moment_count);
}

test "archive putObject rejects malformed typed actuation receipt payloads" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    try std.testing.expectError(
        error.InvalidFrameEncoding,
        tx.putObject(archiveEnvelope(.actuation_receipt, "not-a-receipt", "not-a-receipt")),
    );
}

test "archive putObject rejects malformed portable evidence payloads" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    try std.testing.expectError(
        error.InvalidFrameEncoding,
        tx.putObject(archiveEnvelope(.actuation_idempotency_key, "not-a-key", "not-a-key")),
    );
}

test "archive transaction fingerprints bind envelope fingerprints" {
    const first = world.Continuity.ObjectEnvelope.init(.{
        .kind = .bundle,
        .payload_bytes = "same-payload",
        .label = "same-label",
        .summary_metadata_bytes = "first-summary",
    });
    const second = world.Continuity.ObjectEnvelope.init(.{
        .kind = .bundle,
        .payload_bytes = "same-payload",
        .label = "same-label",
        .summary_metadata_bytes = "second-summary",
    });
    try std.testing.expect(first.objectRef().eql(second.objectRef()));
    try std.testing.expect(first.envelope_fingerprint != second.envelope_fingerprint);

    var first_archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer first_archive.deinit();
    var second_archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer second_archive.deinit();
    const first_moment = try commitArchiveObject(&first_archive, first);
    const second_moment = try commitArchiveObject(&second_archive, second);

    try std.testing.expect(
        first_moment.chronicle_commit_ref.transaction_fingerprint !=
            second_moment.chronicle_commit_ref.transaction_fingerprint,
    );
}

test "archive byte clone reopen preserves idempotency conflict evidence" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const key_envelope = try archiveIdempotencyKeyEnvelope(std.testing.allocator, "idem-key-persisted", 0xA900);
    defer std.testing.allocator.free(key_envelope.payload_bytes);
    defer std.testing.allocator.free(key_envelope.dependency_refs);
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

test "archive append rejects stale batches before mutating bytes" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const stale_parent = archive.image.latestCursor();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "first", "first"));
    const bytes_before = try std.testing.allocator.dupe(u8, archive.bytesView());
    defer std.testing.allocator.free(bytes_before);

    const envelope = archiveEnvelope(.capsule_manifest, "second", "second");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const transaction_fingerprint = 0xDAD;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const resulting = stale_parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = 0xABCDEF,
        .parent_cursor_fingerprint = stale_parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = stale_parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    try std.testing.expectError(error.StaleProjection, archive.appendBatch(batch));
    try std.testing.expectEqualSlices(u8, bytes_before, archive.bytesView());
}

test "archive append allocation failure preserves canonical bytes" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "stable", "stable"));
    const bytes_before = try std.testing.allocator.dupe(u8, archive.bytesView());
    defer std.testing.allocator.free(bytes_before);

    var induced_failures: usize = 0;
    for (0..64) |fail_index| {
        {
            var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
                .fail_index = fail_index,
            });
            var reopened = world.Archive.Memory.reopenFrom(&archive, failing_allocator.allocator()) catch |err| switch (err) {
                error.OutOfMemory => continue,
                else => return err,
            };
            defer reopened.deinit();
            const result = commitArchiveObject(&reopened, archiveEnvelope(.capsule_manifest, "oom", "oom"));
            if (result) |moment| {
                try moment.validate();
            } else |err| switch (err) {
                error.OutOfMemory => {
                    induced_failures += 1;
                    try std.testing.expectEqualSlices(u8, bytes_before, reopened.bytesView());
                },
                else => return err,
            }
        }
    }
    try std.testing.expect(induced_failures > 0);
}

test "archive recovery truncates memory bytes to valid sealed prefix" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "first", "first"));
    const sealed_len = archive.bytesView().len;
    try archive.bytes.appendSlice(std.testing.allocator, "unsealed-tail");

    var recovery = try archive.recover();
    defer recovery.deinit(std.testing.allocator);
    try std.testing.expectEqual(sealed_len, archive.bytesView().len);
    try std.testing.expectEqual(@as(usize, "unsealed-tail".len), recovery.discarded_tail_byte_len);

    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_manifest, "second", "second"));
    const reader = world.Archive.Reader.init(std.testing.allocator, archive.bytesView(), .{});
    const scan = try reader.scan();
    try std.testing.expectEqual(@as(usize, 2), scan.committed_moment_count);
}

test "archive recovery allocation failure preserves canonical bytes" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "recovery-oom", "recovery-oom"));
    try archive.bytes.appendSlice(std.testing.allocator, "recovery-tail");
    const bytes_before = try std.testing.allocator.dupe(u8, archive.bytesView());
    defer std.testing.allocator.free(bytes_before);

    var induced_failures: usize = 0;
    for (0..128) |fail_index| {
        var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        var reopened = world.Archive.Memory.reopenFrom(&archive, failing_allocator.allocator()) catch |err| switch (err) {
            error.OutOfMemory => continue,
            else => return err,
        };
        defer reopened.deinit();
        var recovery = reopened.recover() catch |err| switch (err) {
            error.OutOfMemory => {
                induced_failures += 1;
                try std.testing.expectEqualSlices(u8, bytes_before, reopened.bytesView());
                continue;
            },
            else => return err,
        };
        recovery.deinit(failing_allocator.allocator());
    }
    try std.testing.expect(induced_failures > 0);
}

test "archive append ignores stale unsealed tail" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "tail-first", "tail-first"));
    try archive.bytes.appendSlice(std.testing.allocator, "stale-tail");

    const second = try commitArchiveObject(&archive, archiveEnvelope(.capsule_manifest, "tail-second", "tail-second"));
    try std.testing.expectEqual(@as(u64, 2), second.sequence_number);
    const reader = world.Archive.Reader.init(std.testing.allocator, archive.bytesView(), .{});
    const scan = try reader.scan();
    try std.testing.expectEqual(@as(usize, 2), scan.committed_moment_count);
    try std.testing.expectEqual(archive.bytesView().len, scan.committed_prefix_byte_len);
}

test "archive recovery report owns latest moment" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    var archive_active = true;
    defer if (archive_active) archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "owned", "owned"));

    const reader = world.Archive.Reader.init(std.testing.allocator, archive.bytesView(), .{});
    var recovery = try reader.recover();
    defer recovery.deinit(std.testing.allocator);
    try std.testing.expect(recovery.latest_moment != null);
    try std.testing.expect(recovery.latest_moment.?.owns_memory);
    archive.deinit();
    archive_active = false;
    try recovery.latest_moment.?.validate();
}

test "archive latest moment returns borrowed ownership" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "borrowed-moment", "borrowed-moment"));

    var moment = try archive.latestMoment();
    try std.testing.expect(!moment.owns_memory);
    moment.deinit(std.testing.allocator);
    try std.testing.expect(archive.hasObject(archiveEnvelope(.capsule_image, "borrowed-moment", "borrowed-moment").objectRef()));
}

test "archive snapshot moment returns borrowed ownership" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    const committed = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "snapshot-borrowed", "snapshot-borrowed"));

    var snapshot = try archive.openMoment(committed);
    defer snapshot.deinit();
    var moment = snapshot.moment();
    try std.testing.expect(!moment.owns_memory);
    moment.deinit(std.testing.allocator);
    try std.testing.expect(archive.hasObject(archiveEnvelope(.capsule_image, "snapshot-borrowed", "snapshot-borrowed").objectRef()));
}

test "archive rejects non-canonical required segment flag" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "flag", "flag"));

    const segment_required_flag_offset = 72 + 8 + 4 + 1;
    var corrupted = try std.testing.allocator.dupe(u8, archive.bytesView());
    defer std.testing.allocator.free(corrupted);
    corrupted[segment_required_flag_offset] = 2;

    const reader = world.Archive.Reader.init(std.testing.allocator, corrupted, .{});
    const validation = reader.validate();
    try std.testing.expect(!validation.valid);
}

test "archive reader skips optional extension between sealed moments" {
    const first = archiveEnvelope(.capsule_image, "extension-first", "extension-first");
    const second = archiveEnvelope(.capsule_manifest, "extension-second", "extension-second");
    const first_ref = first.objectRef();
    const second_ref = second.objectRef();
    const first_refs = [_]world.Continuity.ObjectRef{first_ref};
    const second_refs = [_]world.Continuity.ObjectRef{second_ref};
    const first_transaction_fingerprint = 0xE001;
    const first_event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = first_transaction_fingerprint,
        .object_refs = &first_refs,
        .target_ref = first_ref,
    });
    const first_events = [_]world.Continuity.Chronicle.Event{first_event};
    const first_fingerprints = [_]u64{first_event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const first_resulting = parent.advance(&first_fingerprints, first_refs.len, 1);
    const first_commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = first_transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = first_resulting.cursor_fingerprint,
        .committed_object_refs = &first_refs,
        .committed_event_fingerprints = &first_fingerprints,
        .capsule_refs = &first_refs,
    });
    const first_objects = [_]world.Continuity.ObjectEnvelope{first};
    const first_batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = first_commit,
        .events = &first_events,
        .objects = &first_objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    const first_seal = try writer.append(first_batch, null, null);
    var first_reader = world.Archive.Reader.init(std.testing.allocator, writer.bytes.items, .{});
    var first_image = try first_reader.readImage();
    defer first_image.deinit();
    const first_moment = first_image.latestMoment() orelse return error.ObjectMissing;
    try appendArchiveOptionalExtension(std.testing.allocator, &writer.bytes, 2, "extension-payload");

    const second_transaction_fingerprint = 0xE002;
    const second_event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = second_transaction_fingerprint,
        .object_refs = &second_refs,
        .target_ref = second_ref,
    });
    const second_events = [_]world.Continuity.Chronicle.Event{second_event};
    const second_fingerprints = [_]u64{second_event.event_fingerprint};
    const second_resulting = first_moment.chronicle_resulting_cursor.advance(&second_fingerprints, second_refs.len, 1);
    const second_commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = second_transaction_fingerprint,
        .parent_cursor_fingerprint = first_moment.chronicle_resulting_cursor.cursor_fingerprint,
        .resulting_cursor_fingerprint = second_resulting.cursor_fingerprint,
        .committed_object_refs = &second_refs,
        .committed_event_fingerprints = &second_fingerprints,
    });
    const second_objects = [_]world.Continuity.ObjectEnvelope{second};
    const second_batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = first_moment.chronicle_resulting_cursor,
        .commit = second_commit,
        .events = &second_events,
        .objects = &second_objects,
    });
    _ = try writer.append(second_batch, first_moment, first_seal);

    const reader = world.Archive.Reader.init(std.testing.allocator, writer.bytes.items, .{});
    const scan = try reader.scan();
    try std.testing.expect(scan.valid);
    try std.testing.expectEqual(@as(usize, 2), scan.committed_moment_count);
    try std.testing.expectEqual(@as(usize, 0), scan.discarded_tail_byte_len);
}

test "archive recovery discards trailing optional extension without later seal" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "extension-tail", "extension-tail"));
    const sealed_len = archive.bytesView().len;

    var damaged: std.ArrayList(u8) = .empty;
    defer damaged.deinit(std.testing.allocator);
    try damaged.appendSlice(std.testing.allocator, archive.bytesView());
    try appendArchiveOptionalExtension(std.testing.allocator, &damaged, 2, "unsealed-extension-tail");

    const reader = world.Archive.Reader.init(std.testing.allocator, damaged.items, .{});
    const scan = try reader.scan();
    try std.testing.expect(scan.recovered);
    try std.testing.expectEqual(sealed_len, scan.committed_prefix_byte_len);
    try std.testing.expectEqual(damaged.items.len - sealed_len, scan.discarded_tail_byte_len);
    const validation = reader.validate();
    try std.testing.expect(!validation.valid);
}

test "archive readEvents returns only requested commit events" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const first = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "first", "first"));
    const first_event_refs = [_]u64{first.committed_event_refs[0]};
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_manifest, "second", "second"));

    const events = try archive.readEvents(first.chronicle_commit_ref);
    try std.testing.expectEqual(first_event_refs.len, events.len);
    for (events, first_event_refs) |event, expected| {
        try std.testing.expectEqual(expected, event.event_fingerprint);
    }

    var invalid = first.chronicle_commit_ref;
    invalid.transaction_fingerprint +%= 1;
    try std.testing.expectError(error.ObjectMissing, archive.readEvents(invalid));
}

test "archive readCommit returns owned commit" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const moment = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "owned-commit", "owned-commit"));
    var commit = try archive.readCommit(moment.chronicle_commit_ref);
    defer commit.deinit(std.testing.allocator);
    try std.testing.expect(commit.owns_memory);
    try commit.validate();
    try std.testing.expect(archive.hasObject(archiveEnvelope(.capsule_image, "owned-commit", "owned-commit").objectRef()));
}

test "archive transactions synthesize object commit events" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    const envelope = archiveEnvelope(.bundle, "bundle-no-explicit-object-event", "bundle");
    const ref = try tx.putObject(envelope);
    try tx.addEvent(world.Continuity.Chronicle.Event.init(.{ .kind = .bundle_import_committed, .bundle_ref = ref }));
    const moment = try tx.commit();

    const events = try archive.readEvents(moment.chronicle_commit_ref);
    try std.testing.expectEqual(@as(usize, 2), events.len);
    try std.testing.expectEqual(world.Continuity.Chronicle.EventKind.object_committed, events[0].kind);
    try std.testing.expect(refSliceContains(events[0].object_refs, ref));
    var replay = try archive.replay();
    defer replay.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), replay.mismatch_count);
}

test "archive moment data rejects forged resulting cursor" {
    const envelope = archiveEnvelope(.capsule_image, "forged-cursor", "forged-cursor");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const transaction_fingerprint = 0xA17C;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const forged_resulting = parent.advance(&fingerprints, refs.len + 1, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = forged_resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .capsule_refs = &refs,
    });
    const moment = world.Archive.Moment.init(.{
        .sequence_number = 1,
        .chronicle_parent_cursor = parent,
        .chronicle_resulting_cursor = forged_resulting,
        .chronicle_commit_ref = world.Archive.CommitRef.fromCommit(commit),
        .committed_event_refs = &fingerprints,
        .committed_object_refs = &refs,
        .capsule_refs = &refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const data = world.Archive.MomentData{
        .moment = moment,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    };

    try std.testing.expectError(error.InvalidFrameEncoding, data.validate());
}

test "archive append batch rejects missing committed objects" {
    const present = archiveEnvelope(.bundle, "append-batch-present", "append-batch-present");
    const missing = archiveEnvelope(.bundle, "append-batch-missing", "append-batch-missing");
    const present_ref = present.objectRef();
    const missing_ref = missing.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ present_ref, missing_ref };
    const transaction_fingerprint = 0xA17B;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = present_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .bundle_refs = &refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{present};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    try std.testing.expectError(error.InvalidFrameEncoding, batch.validate());
}

test "archive moment data rejects forged summary refs" {
    const capsule = archiveEnvelope(.capsule_image, "summary-capsule", "summary-capsule");
    const bundle = archiveEnvelope(.bundle, "summary-bundle", "summary-bundle");
    const capsule_ref = capsule.objectRef();
    const bundle_ref = bundle.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ capsule_ref, bundle_ref };
    const capsule_refs = [_]world.Continuity.ObjectRef{capsule_ref};
    const bundle_refs = [_]world.Continuity.ObjectRef{bundle_ref};
    const forged_capsule_refs = [_]world.Continuity.ObjectRef{bundle_ref};
    const transaction_fingerprint = 0xA17D;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = bundle_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .bundle_refs = &bundle_refs,
        .capsule_refs = &capsule_refs,
    });
    const forged_moment = world.Archive.Moment.init(.{
        .sequence_number = 1,
        .chronicle_parent_cursor = parent,
        .chronicle_resulting_cursor = resulting,
        .chronicle_commit_ref = world.Archive.CommitRef.fromCommit(commit),
        .committed_event_refs = &fingerprints,
        .committed_object_refs = &refs,
        .bundle_refs = &bundle_refs,
        .capsule_refs = &forged_capsule_refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{ capsule, bundle };
    const data = world.Archive.MomentData{
        .moment = forged_moment,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    };

    try std.testing.expectError(error.InvalidFrameEncoding, data.validate());
}

test "archive moment data rejects forged commit summary refs" {
    const bundle = archiveEnvelope(.bundle, "commit-summary-bundle", "commit-summary-bundle");
    const bundle_ref = bundle.objectRef();
    const refs = [_]world.Continuity.ObjectRef{bundle_ref};
    const bundle_refs = [_]world.Continuity.ObjectRef{bundle_ref};
    const transaction_fingerprint = 0xC055;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = bundle_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const forged_key_ref = archiveEnvelope(.actuation_idempotency_key, "forged-commit-key", "forged-commit-key").objectRef();
    const forged_report_ref = archiveEnvelope(.actuation_verify_report, "forged-validation-report", "forged-validation-report").objectRef();
    const objects = [_]world.Continuity.ObjectEnvelope{bundle};

    {
        const idempotency_key_refs = [_]world.Continuity.ObjectRef{forged_key_ref};
        const commit = world.Continuity.Chronicle.Commit.init(.{
            .transaction_fingerprint = transaction_fingerprint,
            .parent_cursor_fingerprint = parent.cursor_fingerprint,
            .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
            .committed_object_refs = &refs,
            .committed_event_fingerprints = &fingerprints,
            .bundle_refs = &bundle_refs,
            .idempotency_key_refs = &idempotency_key_refs,
        });
        const moment = world.Archive.Moment.init(.{
            .sequence_number = 1,
            .chronicle_parent_cursor = parent,
            .chronicle_resulting_cursor = resulting,
            .chronicle_commit_ref = world.Archive.CommitRef.fromCommit(commit),
            .committed_event_refs = &fingerprints,
            .committed_object_refs = &refs,
            .bundle_refs = &bundle_refs,
        });
        const data = world.Archive.MomentData{
            .moment = moment,
            .commit = commit,
            .events = &events,
            .objects = &objects,
        };

        try std.testing.expectError(error.InvalidFrameEncoding, data.validate());
    }

    {
        const validation_report_refs = [_]world.Continuity.ObjectRef{forged_report_ref};
        const commit = world.Continuity.Chronicle.Commit.init(.{
            .transaction_fingerprint = transaction_fingerprint,
            .parent_cursor_fingerprint = parent.cursor_fingerprint,
            .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
            .committed_object_refs = &refs,
            .committed_event_fingerprints = &fingerprints,
            .bundle_refs = &bundle_refs,
            .validation_report_refs = &validation_report_refs,
        });
        const moment = world.Archive.Moment.init(.{
            .sequence_number = 1,
            .chronicle_parent_cursor = parent,
            .chronicle_resulting_cursor = resulting,
            .chronicle_commit_ref = world.Archive.CommitRef.fromCommit(commit),
            .committed_event_refs = &fingerprints,
            .committed_object_refs = &refs,
            .bundle_refs = &bundle_refs,
        });
        const data = world.Archive.MomentData{
            .moment = moment,
            .commit = commit,
            .events = &events,
            .objects = &objects,
        };

        try std.testing.expectError(error.InvalidFrameEncoding, data.validate());
    }
}

test "archive moment data rejects omitted dedicated summary refs" {
    const assembly = archiveEnvelope(.assembly, "omitted-dedicated-summary", "omitted-dedicated-summary");
    const assembly_ref = assembly.objectRef();
    const refs = [_]world.Continuity.ObjectRef{assembly_ref};
    const transaction_fingerprint = 0xA55E;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = assembly_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
    });
    const moment = world.Archive.Moment.init(.{
        .sequence_number = 1,
        .chronicle_parent_cursor = parent,
        .chronicle_resulting_cursor = resulting,
        .chronicle_commit_ref = world.Archive.CommitRef.fromCommit(commit),
        .committed_event_refs = &fingerprints,
        .committed_object_refs = &refs,
        .root_object_refs = &refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{assembly};
    const data = world.Archive.MomentData{
        .moment = moment,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    };

    try std.testing.expectError(error.InvalidFrameEncoding, data.validate());
}

test "archive moment data rejects forged dependency summaries" {
    const dependency = archiveEnvelope(.capsule_manifest, "dependency-summary-dep", "dependency-summary-dep");
    const dependency_ref = dependency.objectRef();
    const dependency_refs = [_]world.Continuity.ObjectRef{dependency_ref};
    const dependent = world.Continuity.ObjectEnvelope.init(.{
        .kind = .bundle,
        .payload_bytes = "dependency-summary-user",
        .label = "dependency-summary-user",
        .dependency_refs = &dependency_refs,
    });
    const dependent_ref = dependent.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ dependency_ref, dependent_ref };
    const bundle_refs = [_]world.Continuity.ObjectRef{dependent_ref};
    const transaction_fingerprint = 0xD3D3;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = dependent_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .bundle_refs = &bundle_refs,
    });
    const forged_moment = world.Archive.Moment.init(.{
        .sequence_number = 1,
        .chronicle_parent_cursor = parent,
        .chronicle_resulting_cursor = resulting,
        .chronicle_commit_ref = world.Archive.CommitRef.fromCommit(commit),
        .committed_event_refs = &fingerprints,
        .committed_object_refs = &refs,
        .bundle_refs = &bundle_refs,
        .dependency_refs = &.{},
    });
    const objects = [_]world.Continuity.ObjectEnvelope{ dependency, dependent };
    const data = world.Archive.MomentData{
        .moment = forged_moment,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    };

    try std.testing.expectError(error.InvalidFrameEncoding, data.validate());
}

test "archive append rejects omitted committed object summary refs" {
    const bundle = archiveEnvelope(.bundle, "missing-summary-bundle", "missing-summary-bundle");
    const capsule = archiveEnvelope(.capsule_image, "missing-summary-capsule", "missing-summary-capsule");
    const actuation = archiveEnvelope(.actuation_receipt, "missing-summary-actuation", "missing-summary-actuation");
    const refs = [_]world.Continuity.ObjectRef{ bundle.objectRef(), capsule.objectRef(), actuation.objectRef() };
    const transaction_fingerprint = 0x5055;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = refs[0],
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{ bundle, capsule, actuation };
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
}

test "archive writer append allocation failure rolls back bytes" {
    const envelope = archiveEnvelope(.capsule_image, "writer-oom", "writer-oom");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const transaction_fingerprint = 0xDAD;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .capsule_refs = &refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var induced_failures: usize = 0;
    for (0..96) |fail_index| {
        {
            var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
                .fail_index = fail_index,
            });
            var writer = world.Archive.Writer.init(failing_allocator.allocator(), .{});
            defer writer.deinit();
            writer.writeHeader(world.Archive.Header.init(.{})) catch |err| switch (err) {
                error.OutOfMemory => continue,
                else => return err,
            };
            const len_before = writer.bytes.items.len;
            if (writer.append(batch, null, null)) |_| {
                continue;
            } else |err| switch (err) {
                error.OutOfMemory => {
                    induced_failures += 1;
                    try std.testing.expectEqual(len_before, writer.bytes.items.len);
                },
                else => return err,
            }
        }
    }
    try std.testing.expect(induced_failures > 0);
}

test "archive writer rolls back fresh header allocation failure" {
    const envelope = archiveEnvelope(.capsule_image, "fresh-oom-object", "fresh-oom-object");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const transaction_fingerprint = 0xDAE;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .capsule_refs = &refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var induced_failures: usize = 0;
    for (0..32) |fail_index| {
        var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        var writer = world.Archive.Writer.init(failing_allocator.allocator(), .{});
        defer writer.deinit();
        if (writer.append(batch, null, null)) |_| {
            continue;
        } else |err| switch (err) {
            error.OutOfMemory => {
                if (!writer.header_written) {
                    induced_failures += 1;
                    try std.testing.expectEqual(@as(usize, 0), writer.bytes.items.len);
                }
            },
            else => return err,
        }
    }
    try std.testing.expect(induced_failures > 0);
}

test "archive writer enforces header size limit when writing header directly" {
    var writer = world.Archive.Writer.init(std.testing.allocator, .{ .max_archive_bytes = 1 });
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.writeHeader(world.Archive.Header.init(.{})));
    try std.testing.expectEqual(@as(usize, 0), writer.bytes.items.len);
    try std.testing.expect(!writer.header_written);
}

test "archive writer enforces total archive size limits" {
    const envelope = archiveEnvelope(.capsule_image, "size-limit-object", "size-limit-object");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const transaction_fingerprint = 0xDAF;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{ .max_archive_bytes = 96 });
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
    try std.testing.expectEqual(@as(usize, 0), writer.bytes.items.len);
    try std.testing.expect(!writer.header_written);
}

test "archive direct writer rejects stale appends" {
    const envelope = archiveEnvelope(.capsule_image, "direct-stale", "direct-stale");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const transaction_fingerprint = 0xDA7A;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .capsule_refs = &refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    _ = try writer.append(batch, null, null);
    const len_after_first = writer.bytes.items.len;
    try std.testing.expectError(error.StaleProjection, writer.append(batch, null, null));
    try std.testing.expectEqual(len_after_first, writer.bytes.items.len);
}

test "archive direct writer rejects unsealed tail before append" {
    const first = archiveEnvelope(.capsule_image, "tail-first", "tail-first");
    const first_ref = first.objectRef();
    const first_refs = [_]world.Continuity.ObjectRef{first_ref};
    const first_tx = 0x7A11;
    const first_event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = first_tx,
        .object_refs = &first_refs,
        .target_ref = first_ref,
    });
    const first_events = [_]world.Continuity.Chronicle.Event{first_event};
    const first_fingerprints = [_]u64{first_event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const first_resulting = parent.advance(&first_fingerprints, first_refs.len, 1);
    const first_commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = first_tx,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = first_resulting.cursor_fingerprint,
        .committed_object_refs = &first_refs,
        .committed_event_fingerprints = &first_fingerprints,
        .capsule_refs = &first_refs,
    });
    const first_objects = [_]world.Continuity.ObjectEnvelope{first};
    const first_batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = first_commit,
        .events = &first_events,
        .objects = &first_objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    const first_seal = try writer.append(first_batch, null, null);
    var reader = world.Archive.Reader.init(std.testing.allocator, writer.bytes.items, .{});
    var image = try reader.readImage();
    defer image.deinit();
    const first_moment = image.latestMoment().?;

    try writer.bytes.appendSlice(std.testing.allocator, "unsealed");
    const len_with_tail = writer.bytes.items.len;
    const second = archiveEnvelope(.capsule_image, "tail-second", "tail-second");
    const second_ref = second.objectRef();
    const second_refs = [_]world.Continuity.ObjectRef{second_ref};
    const second_tx = 0x7A12;
    const second_event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = second_tx,
        .object_refs = &second_refs,
        .target_ref = second_ref,
    });
    const second_events = [_]world.Continuity.Chronicle.Event{second_event};
    const second_fingerprints = [_]u64{second_event.event_fingerprint};
    const second_resulting = first_moment.chronicle_resulting_cursor.advance(&second_fingerprints, second_refs.len, 1);
    const second_commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = second_tx,
        .parent_cursor_fingerprint = first_moment.chronicle_resulting_cursor.cursor_fingerprint,
        .resulting_cursor_fingerprint = second_resulting.cursor_fingerprint,
        .committed_object_refs = &second_refs,
        .committed_event_fingerprints = &second_fingerprints,
        .capsule_refs = &second_refs,
    });
    const second_objects = [_]world.Continuity.ObjectEnvelope{second};
    const second_batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = first_moment.chronicle_resulting_cursor,
        .commit = second_commit,
        .events = &second_events,
        .objects = &second_objects,
    });

    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(second_batch, first_moment, first_seal));
    try std.testing.expectEqual(len_with_tail, writer.bytes.items.len);
}

test "archive append rejects missing domain event refs" {
    const missing_bundle_ref = archiveEnvelope(.bundle, "missing-bundle", "missing-bundle").objectRef();
    const transaction_fingerprint = 0xD04A;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .bundle_import_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .bundle_ref = missing_bundle_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, 0, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_event_fingerprints = &fingerprints,
    });
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &.{},
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
}

test "archive append rejects object commit events with missing extra refs" {
    const envelope = archiveEnvelope(.bundle, "object-commit-extra-ref", "object-commit-extra-ref");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const missing_ref = archiveEnvelope(.bundle, "object-commit-missing-extra", "object-commit-missing-extra").objectRef();
    const transaction_fingerprint = 0xD04D;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
        .bundle_ref = missing_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .bundle_refs = &refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
}

test "archive append rejects mismatched domain event transaction" {
    const envelope = archiveEnvelope(.bundle, "mismatched-domain-tx", "mismatched-domain-tx");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const transaction_fingerprint = 0xD04C;
    const object_event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const domain_event = world.Continuity.Chronicle.Event.init(.{
        .kind = .bundle_import_committed,
        .transaction_fingerprint = transaction_fingerprint + 1,
        .bundle_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{ object_event, domain_event };
    const fingerprints = [_]u64{ object_event.event_fingerprint, domain_event.event_fingerprint };
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .bundle_refs = &refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
}

test "archive append rejects missing object dependencies" {
    const missing_dep = archiveEnvelope(.capsule_manifest, "direct-missing-dep", "direct-missing-dep").objectRef();
    const deps = [_]world.Continuity.ObjectRef{missing_dep};
    const envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .bundle,
        .payload_bytes = "direct-missing-dep-user",
        .label = "direct-missing-dep-user",
        .dependency_refs = &deps,
    });
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const transaction_fingerprint = 0xD04B;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.ObjectMissing, writer.append(batch, null, null));
}

test "archive append rejects missing semantic object dependencies" {
    const missing_dep = world.Continuity.ObjectRef.init(.{
        .kind = .capsule_manifest,
        .object_fingerprint = 0x5EED,
        .byte_len = 0,
    });
    const deps = [_]world.Continuity.ObjectRef{missing_dep};
    const envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .bundle,
        .payload_bytes = "direct-missing-semantic-dep-user",
        .label = "direct-missing-semantic-dep-user",
        .dependency_refs = &deps,
    });
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const transaction_fingerprint = 0x5ED0;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .bundle_refs = &refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.ObjectMissing, writer.append(batch, null, null));
}

test "archive append rejects same-batch object dependency cycles" {
    const first_seed = archiveEnvelope(.bundle, "cycle-first", "cycle-first");
    const second_seed = archiveEnvelope(.capsule_image, "cycle-second", "cycle-second");
    const first_ref = first_seed.objectRef();
    const second_ref = second_seed.objectRef();
    const first_deps = [_]world.Continuity.ObjectRef{second_ref};
    const second_deps = [_]world.Continuity.ObjectRef{first_ref};
    const first = world.Continuity.ObjectEnvelope.init(.{
        .kind = first_seed.kind,
        .payload_bytes = first_seed.payload_bytes,
        .label = first_seed.label,
        .dependency_refs = &first_deps,
    });
    const second = world.Continuity.ObjectEnvelope.init(.{
        .kind = second_seed.kind,
        .payload_bytes = second_seed.payload_bytes,
        .label = second_seed.label,
        .dependency_refs = &second_deps,
    });
    const refs = [_]world.Continuity.ObjectRef{ first_ref, second_ref };
    const transaction_fingerprint = 0xC1C1;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = first_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .bundle_refs = &.{first_ref},
        .capsule_refs = &.{second_ref},
    });
    const objects = [_]world.Continuity.ObjectEnvelope{ first, second };
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
}

test "archive append rejects semantic same-batch object dependency cycles" {
    const first_seed = archiveEnvelope(.bundle, "semantic-cycle-first", "semantic-cycle-first");
    const second_seed = archiveEnvelope(.capsule_image, "semantic-cycle-second", "semantic-cycle-second");
    const first_ref = first_seed.objectRef();
    const second_ref = second_seed.objectRef();
    const first_dep = world.Continuity.ObjectRef.init(.{
        .kind = second_ref.kind,
        .object_format_version = second_ref.object_format_version,
        .object_fingerprint = second_ref.object_fingerprint,
        .byte_len = 0,
    });
    const second_dep = world.Continuity.ObjectRef.init(.{
        .kind = first_ref.kind,
        .object_format_version = first_ref.object_format_version,
        .object_fingerprint = first_ref.object_fingerprint,
        .byte_len = 0,
    });
    const first_deps = [_]world.Continuity.ObjectRef{first_dep};
    const second_deps = [_]world.Continuity.ObjectRef{second_dep};
    const first = world.Continuity.ObjectEnvelope.init(.{
        .kind = first_seed.kind,
        .payload_bytes = first_seed.payload_bytes,
        .label = first_seed.label,
        .dependency_refs = &first_deps,
    });
    const second = world.Continuity.ObjectEnvelope.init(.{
        .kind = second_seed.kind,
        .payload_bytes = second_seed.payload_bytes,
        .label = second_seed.label,
        .dependency_refs = &second_deps,
    });
    const refs = [_]world.Continuity.ObjectRef{ first_ref, second_ref };
    const transaction_fingerprint = 0x5EC1;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = first_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .bundle_refs = &.{first_ref},
        .capsule_refs = &.{second_ref},
    });
    const objects = [_]world.Continuity.ObjectEnvelope{ first, second };
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
}

test "archive append rejects cross-moment semantic object dependency cycles" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const future_bundle_seed = archiveEnvelope(.bundle, "cross-cycle-bundle", "cross-cycle-bundle");
    const future_bundle_ref = future_bundle_seed.objectRef();
    const semantic_future_bundle_ref = world.Continuity.ObjectRef.init(.{
        .kind = future_bundle_ref.kind,
        .object_format_version = future_bundle_ref.object_format_version,
        .object_fingerprint = future_bundle_ref.object_fingerprint,
        .byte_len = 0,
    });
    const first_deps = [_]world.Continuity.ObjectRef{semantic_future_bundle_ref};
    const capsule_seed = archiveEnvelope(.capsule_image, "cross-cycle-capsule", "cross-cycle-capsule");
    const capsule = world.Continuity.ObjectEnvelope.init(.{
        .kind = capsule_seed.kind,
        .object_format_version = capsule_seed.object_format_version,
        .payload_bytes = capsule_seed.payload_bytes,
        .label = capsule_seed.label,
        .dependency_refs = &first_deps,
    });
    const capsule_ref = capsule.objectRef();
    _ = try commitArchiveObject(&archive, capsule);

    const second_deps = [_]world.Continuity.ObjectRef{capsule_ref};
    const bundle = world.Continuity.ObjectEnvelope.init(.{
        .kind = future_bundle_seed.kind,
        .payload_bytes = future_bundle_seed.payload_bytes,
        .label = future_bundle_seed.label,
        .dependency_refs = &second_deps,
    });

    var tx = try archive.begin(archive.image.latestMoment().?.chronicle_resulting_cursor, .{});
    defer tx.deinit();
    _ = try tx.putObject(bundle);
    try std.testing.expectError(error.InvalidFrameEncoding, tx.commit());
}

test "archive append accepts later same-batch object dependencies" {
    const dependency = archiveEnvelope(.capsule_manifest, "later-dependency", "later-dependency");
    const dependency_ref = dependency.objectRef();
    const dependency_refs = [_]world.Continuity.ObjectRef{dependency_ref};
    const dependent = world.Continuity.ObjectEnvelope.init(.{
        .kind = .bundle,
        .payload_bytes = "dependent-before-dependency",
        .label = "dependent-before-dependency",
        .dependency_refs = &dependency_refs,
    });
    const dependent_ref = dependent.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ dependent_ref, dependency_ref };
    const bundle_refs = [_]world.Continuity.ObjectRef{dependent_ref};
    const transaction_fingerprint = 0xD3F0;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = dependent_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
        .bundle_refs = &bundle_refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{ dependent, dependency };
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    const seal = try writer.append(batch, null, null);
    try seal.validate();
}

test "archive append rejects duplicate object payloads" {
    const envelope = archiveEnvelope(.capsule_image, "duplicate-payload", "duplicate-payload");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const transaction_fingerprint = 0xD0D0;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{ envelope, envelope };
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
}

test "archive append rejects duplicate committed object refs" {
    const envelope = archiveEnvelope(.capsule_image, "duplicate-ref", "duplicate-ref");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ ref, ref };
    const transaction_fingerprint = 0xD0D1;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, refs.len, 1);
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{ envelope, envelope };
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
}

test "archive append rejects duplicate committed refs across moments" {
    const envelope = archiveEnvelope(.capsule_image, "duplicate-across-moments", "duplicate-across-moments");
    const ref = envelope.objectRef();
    const refs = [_]world.Continuity.ObjectRef{ref};
    const first_transaction_fingerprint = 0xD0D2;
    const first_event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = first_transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const first_events = [_]world.Continuity.Chronicle.Event{first_event};
    const first_fingerprints = [_]u64{first_event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const first_resulting = parent.advance(&first_fingerprints, refs.len, 1);
    const first_commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = first_transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = first_resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &first_fingerprints,
        .capsule_refs = &refs,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{envelope};
    const first_batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = first_commit,
        .events = &first_events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    const first_seal = try writer.append(first_batch, null, null);
    var reader = world.Archive.Reader.init(std.testing.allocator, writer.bytes.items, .{});
    var image = try reader.readImage();
    defer image.deinit();
    const first_moment = image.latestMoment() orelse return error.ObjectMissing;

    const second_transaction_fingerprint = 0xD0D3;
    const second_event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = second_transaction_fingerprint,
        .object_refs = &refs,
        .target_ref = ref,
    });
    const second_events = [_]world.Continuity.Chronicle.Event{second_event};
    const second_fingerprints = [_]u64{second_event.event_fingerprint};
    const second_resulting = first_moment.chronicle_resulting_cursor.advance(&second_fingerprints, refs.len, 1);
    const second_commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = second_transaction_fingerprint,
        .parent_cursor_fingerprint = first_moment.chronicle_resulting_cursor.cursor_fingerprint,
        .resulting_cursor_fingerprint = second_resulting.cursor_fingerprint,
        .committed_object_refs = &refs,
        .committed_event_fingerprints = &second_fingerprints,
        .capsule_refs = &refs,
    });
    const second_batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = first_moment.chronicle_resulting_cursor,
        .commit = second_commit,
        .events = &second_events,
        .objects = &objects,
    });

    try std.testing.expectError(error.DuplicateBinding, writer.append(second_batch, first_moment, first_seal));
}

test "archive append rejects object committed event order mismatch" {
    const first = archiveEnvelope(.capsule_image, "order-mismatch-first", "order-mismatch-first");
    const second = archiveEnvelope(.capsule_manifest, "order-mismatch-second", "order-mismatch-second");
    const first_ref = first.objectRef();
    const second_ref = second.objectRef();
    const event_refs = [_]world.Continuity.ObjectRef{ first_ref, second_ref };
    const transaction_fingerprint = 0xFEED;
    const event = world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .transaction_fingerprint = transaction_fingerprint,
        .object_refs = &event_refs,
        .target_ref = second_ref,
    });
    const events = [_]world.Continuity.Chronicle.Event{event};
    const fingerprints = [_]u64{event.event_fingerprint};
    const parent = world.Continuity.Chronicle.Cursor.initial();
    const resulting = parent.advance(&fingerprints, event_refs.len, 1);
    const commit_refs = [_]world.Continuity.ObjectRef{ second_ref, first_ref };
    const commit = world.Continuity.Chronicle.Commit.init(.{
        .transaction_fingerprint = transaction_fingerprint,
        .parent_cursor_fingerprint = parent.cursor_fingerprint,
        .resulting_cursor_fingerprint = resulting.cursor_fingerprint,
        .committed_object_refs = &commit_refs,
        .committed_event_fingerprints = &fingerprints,
    });
    const objects = [_]world.Continuity.ObjectEnvelope{ first, second };
    const batch = world.Archive.AppendBatch.init(.{
        .parent_cursor = parent,
        .commit = commit,
        .events = &events,
        .objects = &objects,
    });

    var writer = world.Archive.Writer.init(std.testing.allocator, .{});
    defer writer.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, writer.append(batch, null, null));
}

test "archive multi-object transactions preserve commit ref order" {
    var first = archiveEnvelope(.capsule_image, "order-first", "order-first");
    var second = archiveEnvelope(.capsule_manifest, "order-second", "order-second");
    if (first.objectRef().ref_fingerprint < second.objectRef().ref_fingerprint) {
        const tmp = first;
        first = second;
        second = tmp;
    }
    const first_ref = first.objectRef();
    const second_ref = second.objectRef();
    try std.testing.expect(first_ref.ref_fingerprint > second_ref.ref_fingerprint);

    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    _ = try tx.putObject(first);
    _ = try tx.putObject(second);
    const moment = try tx.commit();

    try std.testing.expectEqual(@as(usize, 2), moment.committed_object_refs.len);
    try std.testing.expect(moment.committed_object_refs[0].eql(first_ref));
    try std.testing.expect(moment.committed_object_refs[1].eql(second_ref));
}

test "archive transactions deduplicate staged object refs" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    const envelope = archiveEnvelope(.capsule_image, "dedupe-staged", "dedupe-staged");
    const first_ref = try tx.putObject(envelope);
    const second_ref = try tx.putObject(envelope);
    try std.testing.expect(first_ref.eql(second_ref));
    const moment = try tx.commit();

    try std.testing.expectEqual(@as(usize, 1), moment.committed_object_refs.len);
}

test "archive transactions deduplicate already committed object refs" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const envelope = archiveEnvelope(.capsule_image, "dedupe-committed", "dedupe-committed");
    const first = try commitArchiveObject(&archive, envelope);
    try std.testing.expectEqual(@as(usize, 1), archive.image.objects.len);

    var tx = try archive.begin(first.chronicle_resulting_cursor, .{});
    defer tx.deinit();
    const ref = try tx.putObject(envelope);
    try tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .object_validated,
        .target_ref = ref,
    }));
    const second = try tx.commit();

    try std.testing.expectEqual(@as(usize, 0), second.committed_object_refs.len);
    try std.testing.expectEqual(@as(usize, 1), archive.image.objects.len);
}

test "archive putObject returns staged stable ref" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const payload = try std.testing.allocator.dupe(u8, "stable-ref-payload");
    const label = try std.testing.allocator.dupe(u8, "stable-ref-label");
    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    const ref = try tx.putObject(archiveEnvelope(.capsule_image, payload, label));
    try std.testing.expect(ref.label.ptr != label.ptr);
    std.testing.allocator.free(payload);
    std.testing.allocator.free(label);
    const refs = [_]world.Continuity.ObjectRef{ref};
    try tx.addEvent(world.Continuity.Chronicle.Event.init(.{ .kind = .object_committed, .object_refs = &refs }));
    const moment = try tx.commit();
    tx.deinit();
    try moment.validate();
    try ref.validate();
    try std.testing.expect(archive.hasObject(ref));
}

test "archive transactions canonicalize explicit object commit events" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    const first = archiveEnvelope(.capsule_image, "explicit-first", "explicit-first");
    const second = archiveEnvelope(.capsule_manifest, "explicit-second", "explicit-second");
    const first_ref = try tx.putObject(first);
    const second_ref = try tx.putObject(second);
    const explicit_refs = [_]world.Continuity.ObjectRef{first_ref};
    try tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .object_committed,
        .object_refs = &explicit_refs,
        .target_ref = first_ref,
    }));
    const moment = try tx.commit();

    const events = try archive.readEvents(moment.chronicle_commit_ref);
    try std.testing.expectEqual(@as(usize, 2), events.len);
    try std.testing.expectEqual(world.Continuity.Chronicle.EventKind.object_committed, events[0].kind);
    try std.testing.expectEqual(world.Continuity.Chronicle.EventKind.object_committed, events[1].kind);
    try std.testing.expect(events[0].object_refs[0].eql(first_ref));
    try std.testing.expect(events[1].object_refs[0].eql(second_ref));
}

test "archive transactions overwrite pre-bound domain event transaction" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    const envelope = archiveEnvelope(.bundle, "prebound-domain-event", "prebound-domain-event");
    const ref = try tx.putObject(envelope);
    try tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .bundle_import_committed,
        .transaction_fingerprint = 0x1234,
        .bundle_ref = ref,
    }));
    const moment = try tx.commit();

    const events = try archive.readEvents(moment.chronicle_commit_ref);
    try std.testing.expectEqual(@as(usize, 2), events.len);
    try std.testing.expectEqual(world.Continuity.Chronicle.EventKind.bundle_import_committed, events[1].kind);
    try std.testing.expectEqual(moment.chronicle_commit_ref.transaction_fingerprint, events[1].transaction_fingerprint.?);
}

test "archive transaction fingerprint binds staged domain events" {
    var first_archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer first_archive.deinit();
    var second_archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer second_archive.deinit();
    const envelope = archiveEnvelope(.bundle, "tx-event-bound", "tx-event-bound");

    var first_tx = try first_archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer first_tx.deinit();
    const first_ref = try first_tx.putObject(envelope);
    try first_tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .bundle_import_started,
        .bundle_ref = first_ref,
    }));
    const first_moment = try first_tx.commit();

    var second_tx = try second_archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer second_tx.deinit();
    const second_ref = try second_tx.putObject(envelope);
    try second_tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .bundle_import_committed,
        .bundle_ref = second_ref,
    }));
    const second_moment = try second_tx.commit();

    try std.testing.expect(first_ref.eql(second_ref));
    try std.testing.expect(first_moment.chronicle_commit_ref.transaction_fingerprint != second_moment.chronicle_commit_ref.transaction_fingerprint);
}

test "archive transaction fingerprint ignores pre-bound staged domain transaction" {
    var first_archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer first_archive.deinit();
    var second_archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer second_archive.deinit();
    const envelope = archiveEnvelope(.bundle, "tx-event-prebound", "tx-event-prebound");

    var first_tx = try first_archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer first_tx.deinit();
    const first_ref = try first_tx.putObject(envelope);
    try first_tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .bundle_import_committed,
        .transaction_fingerprint = 0xA001,
        .bundle_ref = first_ref,
    }));
    const first_moment = try first_tx.commit();

    var second_tx = try second_archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer second_tx.deinit();
    const second_ref = try second_tx.putObject(envelope);
    try second_tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .bundle_import_committed,
        .transaction_fingerprint = 0xA002,
        .bundle_ref = second_ref,
    }));
    const second_moment = try second_tx.commit();

    try std.testing.expect(first_ref.eql(second_ref));
    try std.testing.expectEqual(first_moment.chronicle_commit_ref.transaction_fingerprint, second_moment.chronicle_commit_ref.transaction_fingerprint);
}

test "archive append rejects cross-moment object ref conflicts" {
    const first = archiveEnvelope(.capsule_image, "same-ref", "same-ref");
    const dep = archiveEnvelope(.capsule_manifest, "dependency", "dependency").objectRef();
    const deps = [_]world.Continuity.ObjectRef{dep};
    const conflicting = world.Continuity.ObjectEnvelope.init(.{
        .kind = .capsule_image,
        .object_format_version = first.object_format_version,
        .payload_bytes = first.payload_bytes,
        .label = first.label,
        .dependency_refs = &deps,
    });
    try std.testing.expect(first.objectRef().eql(conflicting.objectRef()));
    try std.testing.expect(first.envelope_fingerprint != conflicting.envelope_fingerprint);

    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    const first_moment = try commitArchiveObject(&archive, first);

    var tx = try archive.begin(first_moment.chronicle_resulting_cursor, .{});
    defer tx.deinit();
    try std.testing.expectError(error.DuplicateBinding, tx.putObject(conflicting));
}

test "archive replay report owns source moment" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    var archive_active = true;
    defer if (archive_active) archive.deinit();

    {
        var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
        defer tx.deinit();
        const envelope = archiveEnvelope(.bundle, "owned-replay-report", "owned-replay-report");
        const ref = try tx.putObject(envelope);
        try tx.addEvent(world.Continuity.Chronicle.Event.init(.{ .kind = .bundle_import_committed, .bundle_ref = ref }));
        _ = try tx.commit();
    }

    var report = try archive.replay();
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.source_moment != null);
    try std.testing.expect(report.source_moment.?.owns_memory);
    archive.deinit();
    archive_active = false;
    try report.validate();
}

test "archive replay allocation failure keeps vault ownership singular" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_image, "vault-first", "vault-first"));
    _ = try commitArchiveObject(&archive, archiveEnvelope(.capsule_manifest, "vault-second", "vault-second"));

    var induced_failures: usize = 0;
    for (0..128) |fail_index| {
        {
            var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
                .fail_index = fail_index,
            });
            var reopened = world.Archive.Memory.reopenFrom(&archive, failing_allocator.allocator()) catch |err| switch (err) {
                error.OutOfMemory => continue,
                else => return err,
            };
            defer reopened.deinit();
            const result = reopened.replay();
            if (result) |report| {
                var cleanup = report;
                defer cleanup.deinit(failing_allocator.allocator());
                try cleanup.validate();
            } else |err| switch (err) {
                error.OutOfMemory => induced_failures += 1,
                error.InvalidFrameEncoding => {},
                else => return err,
            }
        }
    }
    try std.testing.expect(induced_failures > 0);
}

test "archive moments aggregate dependencies from every object" {
    const dep_a_envelope = archiveEnvelope(.capsule_manifest, "dep-a", "dep-a");
    const dep_b_envelope = archiveEnvelope(.capsule_manifest, "dep-b", "dep-b");
    const dep_a = dep_a_envelope.objectRef();
    const dep_b = dep_b_envelope.objectRef();
    const first_deps = [_]world.Continuity.ObjectRef{dep_a};
    const second_deps = [_]world.Continuity.ObjectRef{dep_b};
    const first = world.Continuity.ObjectEnvelope.init(.{
        .kind = .bundle,
        .payload_bytes = "first",
        .label = "first",
        .dependency_refs = &first_deps,
    });
    const second_seed = archiveEnvelope(.capsule_image, "second", "second");
    const second = world.Continuity.ObjectEnvelope.init(.{
        .kind = .capsule_image,
        .object_format_version = second_seed.object_format_version,
        .payload_bytes = second_seed.payload_bytes,
        .label = second_seed.label,
        .dependency_refs = &second_deps,
    });

    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    _ = try tx.putObject(dep_a_envelope);
    _ = try tx.putObject(dep_b_envelope);
    _ = try tx.putObject(first);
    _ = try tx.putObject(second);
    const moment = try tx.commit();

    try std.testing.expect(refSliceContains(moment.dependency_refs, dep_a));
    try std.testing.expect(refSliceContains(moment.dependency_refs, dep_b));
}

test "archive transactions reject missing object dependencies" {
    const missing_dep = archiveEnvelope(.capsule_manifest, "missing-dep", "missing-dep").objectRef();
    const deps = [_]world.Continuity.ObjectRef{missing_dep};
    const envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .bundle,
        .payload_bytes = "missing-dep-user",
        .label = "missing-dep-user",
        .dependency_refs = &deps,
    });

    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    try std.testing.expectError(error.ObjectMissing, tx.putObject(envelope));
}

test "archive transactions reject missing semantic object dependencies" {
    const dep = world.Continuity.ObjectRef.init(.{
        .kind = .capsule_manifest,
        .object_fingerprint = 0x5EE1,
        .byte_len = 0,
    });
    const deps = [_]world.Continuity.ObjectRef{dep};
    const envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .bundle,
        .payload_bytes = "missing-semantic-dependency",
        .label = "missing-semantic-dependency",
        .dependency_refs = &deps,
    });

    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    try std.testing.expectError(error.ObjectMissing, tx.putObject(envelope));
}

test "archive transactions reject typed objects missing required dependencies" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const receipt = world.Actuation.Receipt.init(.{
        .intent_fingerprint = 0xAC00 + 1,
        .envelope_fingerprint = 0xAC00 + 2,
        .decision_fingerprint = 0xAC00 + 3,
        .commit_fingerprint = 0xAC00 + 4,
        .response_fingerprint = 0xAC00 + 5,
        .frame_response_fingerprint = 0xAC00 + 6,
        .actuator_ref_fingerprint = 0xAC00 + 7,
        .idempotency_key_fingerprint = 0xAC00 + 8,
        .target_ref_fingerprint = 0xAC00 + 9,
        .world_surface_fingerprint = 0xAC00 + 10,
        .world_port_id = 1,
        .class = .deterministic_fixture,
        .mode = .fresh,
        .fresh_called = true,
    });
    const payload = try receipt.encode(std.testing.allocator);
    defer std.testing.allocator.free(payload);
    const envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .actuation_receipt,
        .payload_bytes = payload,
        .label = "receipt-missing-required-deps",
    });

    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, tx.putObject(envelope));
}

test "archive transactions reject mutation after commit" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    _ = try tx.commit();

    try std.testing.expectError(error.InvalidFrameEncoding, tx.putObject(archiveEnvelope(.bundle, "after-commit", "after-commit")));
    try std.testing.expectError(error.InvalidFrameEncoding, tx.addEvent(world.Continuity.Chronicle.Event.init(.{
        .kind = .object_validated,
    })));
    try std.testing.expectEqual(@as(usize, 0), tx.staged_objects.items.len);
    try std.testing.expectEqual(@as(usize, 0), tx.staged_events.items.len);
}

test "archive transaction rolls back staged object when stable ref allocation fails" {
    const envelope = archiveEnvelope(.bundle, "stable-oom", "stable-oom");
    var observed_failure = false;
    for (0..64) |fail_index| {
        var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        var archive = world.Archive.Memory.open(failing_allocator.allocator(), .{}) catch |err| switch (err) {
            error.OutOfMemory => continue,
            else => return err,
        };
        defer archive.deinit();
        var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
        defer tx.deinit();
        if (tx.putObject(envelope)) |_| {
            continue;
        } else |err| switch (err) {
            error.OutOfMemory => {
                observed_failure = true;
                try std.testing.expectEqual(@as(usize, 0), tx.staged_objects.items.len);
            },
            else => return err,
        }
    }
    try std.testing.expect(observed_failure);
}

fn refSliceContains(refs: []const world.Continuity.ObjectRef, needle: world.Continuity.ObjectRef) bool {
    for (refs) |ref| {
        if (ref.eql(needle)) return true;
    }
    return false;
}

fn archiveReceiptEnvelope(
    allocator: std.mem.Allocator,
    label: []const u8,
    seed: u64,
) !world.Continuity.ObjectEnvelope {
    const receipt = world.Actuation.Receipt.init(.{
        .intent_fingerprint = seed + 1,
        .envelope_fingerprint = seed + 2,
        .decision_fingerprint = seed + 3,
        .commit_fingerprint = seed + 4,
        .response_fingerprint = seed + 5,
        .frame_response_fingerprint = seed + 6,
        .actuator_ref_fingerprint = seed + 7,
        .idempotency_key_fingerprint = seed + 8,
        .target_ref_fingerprint = seed + 9,
        .world_surface_fingerprint = seed + 10,
        .world_port_id = @intCast(seed & 0xffff),
        .class = .deterministic_fixture,
        .mode = .fresh,
        .fresh_called = true,
    });
    const payload = try receipt.encode(allocator);
    errdefer allocator.free(payload);
    const seed_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .actuation_receipt,
        .payload_bytes = payload,
        .label = label,
    });
    const deps = try world.Continuity.objectEnvelopeRequiredDependencyRefs(allocator, seed_envelope);
    errdefer allocator.free(deps);
    return world.Continuity.ObjectEnvelope.init(.{
        .kind = .actuation_receipt,
        .payload_bytes = payload,
        .label = label,
        .dependency_refs = deps,
    });
}

fn archiveIdempotencyKeyEnvelope(
    allocator: std.mem.Allocator,
    label: []const u8,
    seed: u64,
) !world.Continuity.ObjectEnvelope {
    const key = world.Actuation.IdempotencyKey.init(.{
        .target_ref_fingerprint = seed + 1,
        .world_surface_fingerprint = seed + 2,
        .world_port_id = @intCast(seed % 1024 + 1),
        .request_fingerprint = seed + 3,
        .actuator_ref_fingerprint = seed + 4,
    });
    const payload = try world.Continuity.encodePortableEvidence(world.Actuation.IdempotencyKey, allocator, key);
    errdefer allocator.free(payload);
    const seed_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .actuation_idempotency_key,
        .object_format_version = key.format_version,
        .payload_bytes = payload,
        .label = label,
    });
    const deps = try world.Continuity.objectEnvelopeRequiredDependencyRefs(allocator, seed_envelope);
    errdefer allocator.free(deps);
    return world.Continuity.ObjectEnvelope.init(.{
        .kind = .actuation_idempotency_key,
        .object_format_version = key.format_version,
        .payload_bytes = payload,
        .label = label,
        .dependency_refs = deps,
    });
}

fn archiveSecondMomentDataEnd(bytes: []const u8) !usize {
    var cursor: usize = archive_header_encoded_len;
    cursor = try nextArchiveSegmentOffset(bytes, cursor);
    cursor = try nextArchiveSegmentOffset(bytes, cursor);
    return nextArchiveSegmentOffset(bytes, cursor);
}

const archive_header_encoded_len: usize = 80;
const archive_segment_header_encoded_len: usize = 46;
const archive_segment_payload_len_offset: usize = 22;

fn nextArchiveSegmentOffset(bytes: []const u8, segment_start: usize) !usize {
    if (bytes.len < segment_start + archive_segment_header_encoded_len) return error.InvalidFrameEncoding;
    const payload_len = std.mem.readInt(
        u64,
        bytes[segment_start + archive_segment_payload_len_offset ..][0..8],
        .little,
    );
    const payload_len_usize = std.math.cast(usize, payload_len) orelse return error.InvalidFrameEncoding;
    const segment_len = archive_segment_header_encoded_len + payload_len_usize;
    if (bytes.len - segment_start < segment_len) return error.InvalidFrameEncoding;
    return segment_start + segment_len;
}

fn appendArchiveOptionalExtension(
    allocator: std.mem.Allocator,
    bytes: *std.ArrayList(u8),
    sequence_number: u64,
    payload: []const u8,
) !void {
    const header = world.Archive.SegmentHeader.init(.{
        .segment_kind = .optional_extension,
        .required = false,
        .sequence_number = sequence_number,
        .payload = payload,
    });
    try bytes.appendSlice(allocator, &header.magic);
    try appendTestU32(allocator, bytes, header.segment_format_version);
    try appendTestU8(allocator, bytes, @intFromEnum(header.segment_kind));
    try appendTestU8(allocator, bytes, if (header.required) 1 else 0);
    try appendTestU64(allocator, bytes, header.sequence_number);
    try appendTestU64(allocator, bytes, header.payload_byte_len);
    try appendTestU64(allocator, bytes, header.payload_fingerprint);
    try appendTestU64(allocator, bytes, header.segment_header_fingerprint);
    try bytes.appendSlice(allocator, payload);
}

fn appendArchiveRequiredSegment(
    allocator: std.mem.Allocator,
    bytes: *std.ArrayList(u8),
    segment_kind: world.Archive.SegmentKind,
    sequence_number: u64,
    payload: []const u8,
) !void {
    const header = world.Archive.SegmentHeader.init(.{
        .segment_kind = segment_kind,
        .required = true,
        .sequence_number = sequence_number,
        .payload = payload,
    });
    try bytes.appendSlice(allocator, &header.magic);
    try appendTestU32(allocator, bytes, header.segment_format_version);
    try appendTestU8(allocator, bytes, @intFromEnum(header.segment_kind));
    try appendTestU8(allocator, bytes, if (header.required) 1 else 0);
    try appendTestU64(allocator, bytes, header.sequence_number);
    try appendTestU64(allocator, bytes, header.payload_byte_len);
    try appendTestU64(allocator, bytes, header.payload_fingerprint);
    try appendTestU64(allocator, bytes, header.segment_header_fingerprint);
    try bytes.appendSlice(allocator, payload);
}

fn appendTestU8(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), value: u8) !void {
    try bytes.append(allocator, value);
}

fn appendTestU32(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try bytes.appendSlice(allocator, &buf);
}

fn appendTestU64(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), value: u64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    try bytes.appendSlice(allocator, &buf);
}
