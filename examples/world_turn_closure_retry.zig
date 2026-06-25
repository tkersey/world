const common = @import("world_appliance_common.zig");
const std = @import("std");
const world = @import("world");

const Native = world.Appliance.Native;
const executable_image_fingerprint: u64 = 0xCE11_C105_0000_0001;

fn readClosureOwned(allocator: std.mem.Allocator, native: *Native) ![]u8 {
    const len = native.closureLen();
    if (len == 0) return error.ExpectedClosureBytes;
    const bytes = try allocator.alloc(u8, len);
    errdefer allocator.free(bytes);
    if (native.readClosure(bytes) != len) return error.ClosureReadMismatch;
    return bytes;
}

fn readOutputOwned(allocator: std.mem.Allocator, native: *Native) ![]u8 {
    const len = native.outputLen();
    if (len == 0) return error.ExpectedOutputBytes;
    const bytes = try allocator.alloc(u8, len);
    errdefer allocator.free(bytes);
    if (native.readOutput(bytes) != len) return error.OutputReadMismatch;
    return bytes;
}

fn responseValueImageBytes(
    allocator: std.mem.Allocator,
    request: world.Appliance.HostRequest,
    response_fingerprint: u64,
) ![]const u8 {
    var image = try world.Frame.ValueImage.fromCanonicalBytes(
        allocator,
        null,
        request.expected_response_value_ref_fingerprint,
        request.expected_response_schema_ref_fingerprint,
        std.mem.asBytes(&response_fingerprint),
        false,
    );
    defer image.deinit(allocator);
    return image.encode(allocator);
}

fn nativeFromClosure(
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    capacity: world.Appliance.Capacity,
    closure_bytes: []const u8,
) !Native {
    var closure = try world.Appliance.TurnClosure.decode(allocator, closure_bytes);
    defer closure.deinit(allocator);
    const checkpoint_bytes = try closure.materializeCheckpoint(allocator);
    defer allocator.free(checkpoint_bytes);
    var checkpoint = try world.Appliance.Checkpoint.decode(
        allocator,
        checkpoint_bytes,
        manifest.manifest_fingerprint,
        capacity,
    );
    defer checkpoint.deinit(allocator);

    var core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.PortsAppliance.memoryPlan(),
        capacity,
    );
    core.executable_image_fingerprint = executable_image_fingerprint;
    errdefer core.deinit();
    try core.restore(checkpoint);
    var native = Native.init(core);
    native.last_closure_bytes = try allocator.dupe(u8, closure_bytes);
    native.last_closure_owned = true;
    return native;
}

fn freshNative(
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    capacity: world.Appliance.Capacity,
) Native {
    var core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.PortsAppliance.memoryPlan(),
        capacity,
    );
    core.executable_image_fingerprint = executable_image_fingerprint;
    return Native.init(core);
}

fn submitBootClosure(
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    capacity: world.Appliance.Capacity,
) ![]u8 {
    var core = world.Appliance.Core.initWithCapacity(
        allocator,
        manifest,
        common.PortsAppliance.memoryPlan(),
        capacity,
    );
    core.executable_image_fingerprint = executable_image_fingerprint;
    var native = Native.init(core);
    defer native.deinit();

    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    defer allocator.free(boot_bytes);
    if (native.submitTurn(boot_bytes) != .needs_host) return error.ExpectedNeedsHost;
    return readClosureOwned(allocator, &native);
}

fn decodeOutputFromNative(
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    capacity: world.Appliance.Capacity,
    native: *Native,
) !world.Appliance.TurnOutput {
    const output_bytes = try readOutputOwned(allocator, native);
    defer allocator.free(output_bytes);
    return world.Appliance.TurnOutput.decode(allocator, output_bytes, manifest.manifest_fingerprint, capacity);
}

fn closuresMatch(
    allocator: std.mem.Allocator,
    first_bytes: []const u8,
    retry_bytes: []const u8,
) !bool {
    if (!std.mem.eql(u8, first_bytes, retry_bytes)) return false;

    var first = try world.Appliance.TurnClosure.decode(allocator, first_bytes);
    defer first.deinit(allocator);
    var retry = try world.Appliance.TurnClosure.decode(allocator, retry_bytes);
    defer retry.deinit(allocator);

    if (first.status != .completed or retry.status != .completed) return false;
    if (!std.mem.eql(u8, first.capsule_bytes, retry.capsule_bytes)) return false;
    if (!std.mem.eql(u8, first.turn_receipt_bytes, retry.turn_receipt_bytes)) return false;
    if (!std.mem.eql(u8, first.archive_append_batch_bytes, retry.archive_append_batch_bytes)) return false;
    if (!std.mem.eql(u8, first.root_result_bytes, retry.root_result_bytes)) return false;
    if (!std.mem.eql(u64, first.finalized_actuation_receipt_fingerprints, retry.finalized_actuation_receipt_fingerprints)) return false;
    if (first.resulting_state_fingerprint != retry.resulting_state_fingerprint) return false;
    if (first.turn_receipt_fingerprint != retry.turn_receipt_fingerprint) return false;
    return true;
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    const parent_closure_bytes = try submitBootClosure(allocator, manifest, capacity);
    defer allocator.free(parent_closure_bytes);
    var parent_closure = try world.Appliance.TurnClosure.decode(allocator, parent_closure_bytes);
    defer parent_closure.deinit(allocator);

    var first_native = try nativeFromClosure(allocator, manifest, capacity, parent_closure_bytes);
    defer first_native.deinit();
    if (first_native.core.state != .waiting_host) return error.ExpectedNeedsHost;
    if (first_native.core.outstanding_host_requests.len != 1) return error.ExpectedOneHostRequest;

    var effect_call_count: usize = 0;
    effect_call_count += 1;
    const request = first_native.core.outstanding_host_requests[0];
    const response_bytes = try responseValueImageBytes(allocator, request, 0xCE11_0001);
    defer allocator.free(response_bytes);
    const resolution = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .status = .responded,
        .response_value_image_bytes = response_bytes,
        .host_claim_bytes = "fixture-effect-called-once",
        .attempt_number = 1,
    });
    const continue_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent_closure.closure_fingerprint,
        .previous_turn_receipt_fingerprint = first_native.core.previous_turn_receipt_fingerprint,
        .turn_sequence_number = first_native.core.current_turn_sequence_number + 1,
        .resolutions = &.{resolution},
    });
    const continue_bytes = try continue_input.encode(allocator);
    defer allocator.free(continue_bytes);

    if (first_native.submitTurn(continue_bytes) != .completed) return error.ExpectedCompleted;
    const first_closure_bytes = try readClosureOwned(allocator, &first_native);
    defer allocator.free(first_closure_bytes);
    var first_output = try decodeOutputFromNative(allocator, manifest, capacity, &first_native);
    defer first_output.deinit(allocator);

    var retry_native = try nativeFromClosure(allocator, manifest, capacity, parent_closure_bytes);
    defer retry_native.deinit();
    if (retry_native.submitTurn(continue_bytes) != .completed) return error.ExpectedRetryCompleted;
    const retry_closure_bytes = try readClosureOwned(allocator, &retry_native);
    defer allocator.free(retry_closure_bytes);
    var retry_output = try decodeOutputFromNative(allocator, manifest, capacity, &retry_native);
    defer retry_output.deinit(allocator);

    const closure_retry_equal = try closuresMatch(allocator, first_closure_bytes, retry_closure_bytes);
    if (!closure_retry_equal) return error.ClosureRetryMismatch;
    if (!std.mem.eql(u8, first_output.checkpoint_bytes, retry_output.checkpoint_bytes)) return error.CapsuleRetryMismatch;
    if (first_output.turn_receipt.receipt_fingerprint != retry_output.turn_receipt.receipt_fingerprint) return error.TurnReceiptRetryMismatch;
    const archive_batch_retry_equal = std.mem.eql(u8, first_output.archive_append_batch_bytes, retry_output.archive_append_batch_bytes);
    if (!archive_batch_retry_equal) return error.ArchiveBatchRetryMismatch;
    if (!std.mem.eql(u8, first_output.root_result_value_image_bytes, retry_output.root_result_value_image_bytes)) return error.RootResultRetryMismatch;
    if (!std.mem.eql(u64, first_output.finalized_actuation_receipt_fingerprints, retry_output.finalized_actuation_receipt_fingerprints)) return error.ActuationReceiptRetryMismatch;
    if (first_output.resulting_state_fingerprint != retry_output.resulting_state_fingerprint) return error.StateRetryMismatch;

    var restore_native = freshNative(allocator, manifest, capacity);
    defer restore_native.deinit();
    const restore_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .restore,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent_closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent_closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = parent_closure.turn_receipt_fingerprint,
        .turn_sequence_number = parent_closure.turn_sequence_number + 1,
        .parent_turn_closure_bytes = parent_closure_bytes,
        .resolutions = &.{resolution},
    });
    const restore_bytes = try restore_input.encode(allocator);
    defer allocator.free(restore_bytes);
    if (restore_native.submitTurn(restore_bytes) != .completed) return error.ExpectedRestoreCompleted;

    var stale_parent_state_fingerprint = parent_closure.resulting_state_fingerprint ^ 0xA5A5_A5A5_A5A5_A5A5;
    if (stale_parent_state_fingerprint == 0) stale_parent_state_fingerprint = 1;
    const stale_restore_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .restore,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent_closure.closure_fingerprint,
        .expected_parent_state_fingerprint = stale_parent_state_fingerprint,
        .previous_turn_receipt_fingerprint = parent_closure.turn_receipt_fingerprint,
        .turn_sequence_number = parent_closure.turn_sequence_number + 1,
        .parent_turn_closure_bytes = parent_closure_bytes,
        .resolutions = &.{resolution},
    });
    const stale_restore_bytes = try stale_restore_input.encode(allocator);
    defer allocator.free(stale_restore_bytes);
    var stale_restore_native = freshNative(allocator, manifest, capacity);
    defer stale_restore_native.deinit();
    if (stale_restore_native.submitTurn(stale_restore_bytes) != .stale_turn) return error.ExpectedStaleParentState;

    if (first_output.archive_append_batch_bytes.len == 0) return error.ExpectedArchiveAppendBatch;
    const retained_append_batch = try allocator.dupe(u8, first_output.archive_append_batch_bytes);
    defer allocator.free(retained_append_batch);

    try stdout.print("effect_call_count={d}\n", .{effect_call_count});
    try stdout.print("closure_retry_equal={}\n", .{closure_retry_equal});
    try stdout.print("archive_batch_retry_equal={}\n", .{archive_batch_retry_equal});
    try stdout.flush();
}
