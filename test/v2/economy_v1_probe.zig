//! Isolated legacy execution probe, compiled only with frozen Boundary 1.8.2.
const std = @import("std");
const image = @import("image_v1");
const process = @import("process_advance_v1");

fn read(init: std.process.Init, path: []const u8) ![]u8 {
    const file = try std.Io.Dir.openFile(.cwd(), init.io, path, .{});
    defer file.close(init.io);
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(init.io, &buffer);
    return reader.interface.allocRemaining(init.gpa, .limited(64 << 20));
}

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    defer arguments.deinit();
    _ = arguments.skip();
    const code = try read(init, arguments.next() orelse return error.MissingImage);
    defer init.gpa.free(code);
    const initial = try read(init, arguments.next() orelse return error.MissingInitialArgs);
    defer init.gpa.free(initial);
    if (arguments.next() != null) return error.UnexpectedArgument;
    const workspace = try init.gpa.create(image.ValidationWorkspace);
    defer init.gpa.destroy(workspace);
    const buffer_bytes = 1 << 20;
    const owned = try init.gpa.alloc(u8, 7 * buffer_bytes);
    defer init.gpa.free(owned);
    const buffers: process.Buffers = .{
        .output_state = owned[0 * buffer_bytes .. 1 * buffer_bytes],
        .output_value = owned[1 * buffer_bytes .. 2 * buffer_bytes],
        .output_request = owned[2 * buffer_bytes .. 3 * buffer_bytes],
        .candidate_state = owned[3 * buffer_bytes .. 4 * buffer_bytes],
        .environment = owned[4 * buffer_bytes .. 5 * buffer_bytes],
        .auxiliary_environment = owned[5 * buffer_bytes .. 6 * buffer_bytes],
        .scratch = owned[6 * buffer_bytes .. 7 * buffer_bytes],
    };
    var saved: ?[]u8 = null;
    defer if (saved) |state| init.gpa.free(state);
    var maximum: process.CapacityEvidence = .{};
    var outcome: process.Outcome = undefined;
    for (0..10000) |_| {
        workspace.* = .{};
        const result = try process.advanceAttempt(code, if (saved) |state| .{ .process_state = state } else .{ .initial_args = initial }, null, buffers, workspace);
        for (&maximum.required_bytes, result.capacity.required_bytes) |*to, from| to.* = @max(to.*, from);
        outcome = result.outcome;
        if (outcome == .needs_capacity) return error.InsufficientProbeStorage;
        if (outcome != .progressed) break;
        const successor = try init.gpa.dupe(u8, outcome.progressed);
        if (saved) |state| init.gpa.free(state);
        saved = successor;
    } else return error.FiniteHarnessLimit;
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try std.json.Stringify.value(.{
        .platform = @tagName(@import("builtin").cpu.arch),
        .pointer_bytes = @sizeOf(usize),
        .mandatory_validation_workspace_bytes = @sizeOf(image.ValidationWorkspace),
        .reserved_buffer_bytes = owned.len,
        .observed_arena_demands = maximum.required_bytes,
        .outcome = @tagName(outcome),
    }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
