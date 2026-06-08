const world = @import("world");

pub const Context = struct {
    target_ref_fingerprint: u64,
    world_surface_fingerprint: u64,
    request_fingerprint: u64,
    ref: world.Actuation.Ref,
    descriptor: world.Actuation.Descriptor,
    key: world.Actuation.IdempotencyKey,
    intent: world.Actuation.Intent,
    envelope: world.Actuation.Envelope,
};

pub fn context(args: struct {
    label: []const u8,
    kind: world.Actuation.Kind = .fixture,
    class: world.Actuation.Class = .deterministic_fixture,
    mode: world.Mode = .fresh,
    target_ref_fingerprint: u64 = 0xacc7_0001,
    world_surface_fingerprint: u64 = 0xacc7_0002,
    world_port_id: u32 = 0,
    request_fingerprint: u64 = 0xacc7_0003,
    response_value_table_id: ?u32 = null,
    pending_port_fingerprint: ?u64 = null,
    capsule_fingerprint: ?u64 = null,
}) Context {
    const ref = world.Actuation.Ref.init(.{
        .kind = args.kind,
        .class = args.class,
        .label = args.label,
        .supported_modes = .all,
        .supported_response_statuses = .all,
        .value_policy_fingerprint = world.Actuation.valuePolicyFingerprint(.portable),
    });
    const descriptor = world.Actuation.Descriptor.init(.{
        .actuator_ref = ref,
        .world_surface_fingerprint = args.world_surface_fingerprint,
        .target_ref_fingerprint = args.target_ref_fingerprint,
        .world_port_id = args.world_port_id,
        .response_value_table_id = args.response_value_table_id,
        .allowed_response_kinds = .all,
        .label = args.label,
    });
    const key = world.Actuation.IdempotencyKey.init(.{
        .target_ref_fingerprint = args.target_ref_fingerprint,
        .world_surface_fingerprint = args.world_surface_fingerprint,
        .world_port_id = args.world_port_id,
        .request_fingerprint = args.request_fingerprint,
        .pending_port_fingerprint = args.pending_port_fingerprint,
        .capsule_fingerprint = args.capsule_fingerprint,
        .actuator_ref_fingerprint = ref.ref_fingerprint,
    });
    const intent = world.Actuation.Intent.init(.{
        .actuator_ref_fingerprint = ref.ref_fingerprint,
        .descriptor_fingerprint = descriptor.descriptor_fingerprint,
        .target_ref_fingerprint = args.target_ref_fingerprint,
        .world_surface_fingerprint = args.world_surface_fingerprint,
        .world_port_id = args.world_port_id,
        .pending_port_fingerprint = args.pending_port_fingerprint,
        .frame_request_fingerprint = args.request_fingerprint,
        .encoded_frame_request_fingerprint = args.request_fingerprint,
        .idempotency_key_fingerprint = key.key_fingerprint,
        .capsule_fingerprint = args.capsule_fingerprint,
        .class = args.class,
        .requested_mode = args.mode,
    });
    const envelope = world.Actuation.Envelope.init(.{
        .intent_fingerprint = intent.intent_fingerprint,
        .encoded_frame_request_fingerprint = args.request_fingerprint,
        .idempotency_key = key,
        .expected_response_value_table_id = args.response_value_table_id,
    });
    return .{
        .target_ref_fingerprint = args.target_ref_fingerprint,
        .world_surface_fingerprint = args.world_surface_fingerprint,
        .request_fingerprint = args.request_fingerprint,
        .ref = ref,
        .descriptor = descriptor,
        .key = key,
        .intent = intent,
        .envelope = envelope,
    };
}

pub fn execute(
    ctx: Context,
    policy: world.Actuation.Policy,
    actuator: world.Actuation.Membrane.Interface,
    attempt_number: u32,
) !world.Actuation.Membrane.Execution {
    return world.Actuation.Membrane.execute(.{
        .policy = policy,
        .intent = ctx.intent,
        .envelope = ctx.envelope,
        .descriptor = ctx.descriptor,
        .actuator = actuator,
        .explicit_mutation_approval = ctx.intent.class.isMutation(),
        .explicit_irreversible_approval = ctx.intent.class == .irreversible_mutation,
        .attempt_number = attempt_number,
        .target_ref_fingerprint = ctx.target_ref_fingerprint,
        .world_surface_fingerprint = ctx.world_surface_fingerprint,
    });
}

pub fn receiptWithResponseFingerprint(receipt: world.Actuation.Receipt, response_fingerprint: u64, mode: world.Mode) world.Actuation.Receipt {
    return receiptWithResponseEvidence(receipt, response_fingerprint, receipt.frame_response_fingerprint orelse response_fingerprint, mode);
}

pub fn receiptWithResponseEvidence(
    receipt: world.Actuation.Receipt,
    response_fingerprint: u64,
    frame_response_fingerprint: u64,
    mode: world.Mode,
) world.Actuation.Receipt {
    return world.Actuation.Receipt.init(.{
        .intent_fingerprint = receipt.intent_fingerprint,
        .envelope_fingerprint = receipt.envelope_fingerprint,
        .decision_fingerprint = receipt.decision_fingerprint,
        .commit_fingerprint = receipt.commit_fingerprint,
        .response_fingerprint = response_fingerprint,
        .response_kind = receipt.response_kind,
        .frame_response_fingerprint = frame_response_fingerprint,
        .response_value_image_fingerprint = receipt.response_value_image_fingerprint,
        .actuator_ref_fingerprint = receipt.actuator_ref_fingerprint,
        .idempotency_key_fingerprint = receipt.idempotency_key_fingerprint,
        .target_ref_fingerprint = receipt.target_ref_fingerprint,
        .world_surface_fingerprint = receipt.world_surface_fingerprint,
        .world_port_id = receipt.world_port_id,
        .class = receipt.class,
        .mode = mode,
        .fresh_called = false,
        .replayed = mode == .replay,
        .verified = mode == .verify,
        .pending = receipt.pending,
        .deferred = receipt.deferred,
        .rejected = receipt.rejected,
        .failed = receipt.failed,
        .cancelled = receipt.cancelled,
        .attempt_number = receipt.attempt_number,
    });
}
