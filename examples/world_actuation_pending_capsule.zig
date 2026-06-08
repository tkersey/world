const common = @import("world_actuation_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const ctx = common.context(.{
        .label = "pending.capsule",
        .kind = .human_like,
        .class = .human_gated,
        .world_port_id = 0,
        .request_fingerprint = 0xacc7_4001,
        .pending_port_fingerprint = 0xacc7_4aaa,
    });
    const pending = try common.execute(ctx, world.Actuation.Policy.fixture_test, .{
        .pending = .{ .frame_response_fingerprint = 0xacc7_4002 },
    }, 1);

    const intent_refs = [_]u64{ctx.intent.intent_fingerprint};
    const receipt_refs = [_]u64{pending.receipt.receipt_fingerprint};
    const journal_refs = [_]u64{0xacc7_4333};
    const manifest = world.Capsule.Manifest.init(.{
        .kind = .replay_only,
        .root_target_ref_fingerprint = ctx.target_ref_fingerprint,
        .actuation_intent_fingerprints = &intent_refs,
        .actuation_receipt_fingerprints = &receipt_refs,
        .actuation_journal_fingerprints = &journal_refs,
        .normal_form = .quiescent_completed,
    });
    const mailbox = world.Capsule.MailboxImage.init(.{
        .pending_actuation_intent_fingerprints = &intent_refs,
        .committed_actuation_receipt_fingerprints = &receipt_refs,
    });
    const runspace_image = world.Capsule.RunspaceImage.init(.{
        .runspace_fingerprint = 0xacc7_4441,
        .runspace_report_fingerprint = 0xacc7_4442,
        .mailbox_image = mailbox,
        .actuation_intent_refs = &intent_refs,
        .actuation_receipt_refs = &receipt_refs,
        .actuation_journal_refs = &journal_refs,
    });
    const dependency_refs = [_]world.Capsule.DependencyRef{
        world.Capsule.DependencyRef.init(.manifest, manifest.manifest_fingerprint),
        world.Capsule.DependencyRef.init(.runspace_image, runspace_image.image_fingerprint),
        world.Capsule.DependencyRef.init(.actuation_intent, intent_refs[0]),
        world.Capsule.DependencyRef.init(.actuation_receipt, receipt_refs[0]),
        world.Capsule.DependencyRef.init(.actuation_journal, journal_refs[0]),
    };
    const object_refs = [_]world.Capsule.ObjectRef{
        world.Capsule.ObjectRef.init(.capsule_manifest, manifest.manifest_fingerprint),
        world.Capsule.ObjectRef.init(.runspace_image, runspace_image.image_fingerprint),
        world.Capsule.ObjectRef.init(.actuation_intent, intent_refs[0]),
        world.Capsule.ObjectRef.init(.actuation_receipt, receipt_refs[0]),
        world.Capsule.ObjectRef.init(.actuation_journal, journal_refs[0]),
    };
    const image = world.Capsule.Image.init(.{
        .manifest = manifest,
        .runspace_image = runspace_image,
        .actuation_intent_refs = &intent_refs,
        .actuation_receipt_refs = &receipt_refs,
        .actuation_journal_refs = &journal_refs,
        .dependency_refs = &dependency_refs,
        .object_refs = &object_refs,
    });
    try image.validate(.{});

    var receiver = world.Runspace.init(allocator, .{});
    defer receiver.deinit();
    var restore = try world.Capsule.thawIntoRunspace(image, &receiver, ctx.target_ref_fingerprint, 0, null, .{
        .mode = .replay_only,
        .require_local_permit = false,
    });
    defer restore.deinit(allocator);

    const resolved = try common.execute(common.context(.{
        .label = "pending.capsule.resolve",
        .kind = .fixture,
        .world_port_id = 0,
        .request_fingerprint = 0xacc7_4001,
    }), world.Actuation.Policy.fixture_test, .{
        .fixture = .{ .frame_response_fingerprint = 0xacc7_4003 },
    }, 2);

    try stdout.print("pending_actuation_intent_fingerprint={x}\n", .{ctx.intent.intent_fingerprint});
    try stdout.print("capsule_fingerprint={x}\n", .{image.image_fingerprint});
    try stdout.print("restore_report_fingerprint={x}\n", .{restore.restore_report_fingerprint});
    try stdout.print("final_result={}\n", .{resolved.parent_terminal});
    try stdout.flush();
}
