//! Standalone measurement executable. This file is never imported by World or
//! its guest. It times the production transition implementation directly.
const std = @import("std");
const data = @import("boundary_data_v2");
const process = @import("process.zig");
const Machine = @import("machine.zig").Machine;

const Phases = struct {
    initialization_ns: u64 = 0,
    direct_clause_ns: u64 = 0,
    one_shot_capture_ns: u64 = 0,
    multi_template_capture_ns: u64 = 0,
    branch_creation_transition_ns: u64 = 0,
    execution_ns: u64 = 0,
    unwind_ns: u64 = 0,
    collection_ns: u64 = 0,
    snapshot_validation_encoding_ns: u64 = 0,
    outcome_encoding_ns: u64 = 0,
};
fn elapsed(io: std.Io, start: std.Io.Timestamp) u64 {
    return @intCast(start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds);
}
const Measurement = struct {
    phases: Phases,
    statistics: process.Statistics,
    peak_working_bytes: usize,
    output_bytes: usize,
    output_sha256: [64]u8,
};

fn measure(init: std.process.Init, program: data.program.Program, initial: []const u8, storage: []u8) !Measurement {
    var arena = process.Workspace.init(storage);
    const allocator = arena.allocator();
    var statistics: process.Statistics = .{};
    var machine: Machine = .{ .allocator = allocator, .program = program, .identity = try data.image.identity(program), .store = .{ .allocator = allocator, .statistics = &statistics.storage }, .statistics = &statistics };
    defer machine.store.deinit();
    var phases: Phases = .{};
    var start = std.Io.Clock.awake.now(init.io);
    try machine.initialize(initial);
    phases.initialization_ns = elapsed(init.io, start);
    var outcome: process.Outcome = undefined;
    for (0..1000000) |_| {
        const before = statistics;
        const unwinding = machine.status == .unwinding;
        start = std.Io.Clock.awake.now(init.io);
        const terminal = try machine.step();
        const duration = elapsed(init.io, start);
        if (statistics.direct_clauses != before.direct_clauses) {
            phases.direct_clause_ns += duration;
        } else if (statistics.one_shot_captures != before.one_shot_captures) {
            phases.one_shot_capture_ns += duration;
        } else if (statistics.multi_templates != before.multi_templates) {
            phases.multi_template_capture_ns += duration;
        } else if (statistics.branch_activations != before.branch_activations) {
            phases.branch_creation_transition_ns += duration;
        } else if (unwinding) {
            phases.unwind_ns += duration;
        } else phases.execution_ns += duration;
        if (terminal) |result| {
            outcome = result;
            break;
        }
        start = std.Io.Clock.awake.now(init.io);
        try machine.store.collect(machine.roots);
        phases.collection_ns += elapsed(init.io, start);
        if (machine.status != .active and machine.status != .unwinding) {
            start = std.Io.Clock.awake.now(init.io);
            outcome = try machine.finish();
            phases.snapshot_validation_encoding_ns += elapsed(init.io, start);
            break;
        }
    } else return error.FiniteMeasurementHarnessLimit;
    defer outcome.deinit();
    start = std.Io.Clock.awake.now(init.io);
    const bytes = try init.gpa.alloc(u8, try data.protocol.encodedLength(data.protocol.Outcome, outcome.record));
    defer init.gpa.free(bytes);
    _ = try data.protocol.encode(data.protocol.Outcome, allocator, outcome.record, bytes);
    phases.outcome_encoding_ns = elapsed(init.io, start);
    return .{ .phases = phases, .statistics = statistics, .peak_working_bytes = arena.peak_payload, .output_bytes = bytes.len, .output_sha256 = std.fmt.bytesToHex(data.wire.digest(bytes), .lower) };
}

pub fn main(init: std.process.Init) !void {
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().reader(init.io, &input_buffer);
    const bytes = try input.interface.allocRemaining(init.gpa, .limited(64 << 20));
    defer init.gpa.free(bytes);
    var admitted = std.heap.ArenaAllocator.init(init.gpa);
    defer admitted.deinit();
    const start = std.Io.Clock.awake.now(init.io);
    const invocation = try data.protocol.decode(data.protocol.Input, admitted.allocator(), bytes);
    if (invocation.instance != .initial_args or invocation.control != .continue_value or invocation.control.continue_value != null) return error.ExpectedInitialArgs;
    var image = try data.image.decode(admitted.allocator(), invocation.image);
    defer image.deinit();
    const admission_ns = elapsed(init.io, start);
    const storage = try init.gpa.alloc(u8, 16 << 20);
    defer init.gpa.free(storage);
    for (0..5) |_| _ = try measure(init, image.program, invocation.instance.initial_args, storage);
    var measurements: [21]Measurement = undefined;
    for (&measurements) |*result| result.* = try measure(init, image.program, invocation.instance.initial_args, storage);
    for (measurements[1..]) |result| if (!std.mem.eql(u8, &result.output_sha256, &measurements[0].output_sha256)) return error.NondeterministicOutput;
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try std.json.Stringify.value(.{ .admission_ns = admission_ns, .warmups = 5, .measurements = measurements }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
