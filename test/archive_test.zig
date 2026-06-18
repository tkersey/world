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
    var visible = try snapshot.getObject(first_ref);
    defer visible.deinit(std.testing.allocator);
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

test "archive putObject returns staged stable ref" {
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    const payload = try std.testing.allocator.dupe(u8, "stable-ref-payload");
    const label = try std.testing.allocator.dupe(u8, "stable-ref-label");
    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    const ref = try tx.putObject(world.Continuity.ObjectEnvelope.init(.{
        .kind = .capsule_image,
        .payload_bytes = payload,
        .label = label,
    }));
    try std.testing.expect(ref.label.ptr != label.ptr);
    std.testing.allocator.free(payload);
    std.testing.allocator.free(label);
    const refs = [_]world.Continuity.ObjectRef{ref};
    try tx.addEvent(world.Continuity.Chronicle.Event.init(.{ .kind = .object_committed, .object_refs = &refs }));
    const moment = try tx.commit();
    try moment.validate();
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

test "archive append rejects cross-moment object ref conflicts" {
    const first = archiveEnvelope(.capsule_image, "same-ref", "same-ref");
    const dep = archiveEnvelope(.capsule_manifest, "dependency", "dependency").objectRef();
    const deps = [_]world.Continuity.ObjectRef{dep};
    const conflicting = world.Continuity.ObjectEnvelope.init(.{
        .kind = .capsule_image,
        .payload_bytes = "same-ref",
        .label = "same-ref",
        .dependency_refs = &deps,
    });
    try std.testing.expect(first.objectRef().eql(conflicting.objectRef()));
    try std.testing.expect(first.envelope_fingerprint != conflicting.envelope_fingerprint);

    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    const first_moment = try commitArchiveObject(&archive, first);

    var tx = try archive.begin(first_moment.chronicle_resulting_cursor, .{});
    defer tx.deinit();
    _ = try tx.putObject(conflicting);
    try std.testing.expectError(error.DuplicateBinding, tx.commit());
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
    const second = world.Continuity.ObjectEnvelope.init(.{
        .kind = .capsule_image,
        .payload_bytes = "second",
        .label = "second",
        .dependency_refs = &second_deps,
    });

    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    var tx = try archive.begin(world.Continuity.Chronicle.Cursor.initial(), .{});
    defer tx.deinit();
    _ = try tx.putObject(first);
    _ = try tx.putObject(second);
    const moment = try tx.commit();

    try std.testing.expect(refSliceContains(moment.dependency_refs, dep_a));
    try std.testing.expect(refSliceContains(moment.dependency_refs, dep_b));
}

fn refSliceContains(refs: []const world.Continuity.ObjectRef, needle: world.Continuity.ObjectRef) bool {
    for (refs) |ref| {
        if (ref.eql(needle)) return true;
    }
    return false;
}
