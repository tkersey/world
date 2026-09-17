//! Frozen source-pair controls; complete fresh invocation and independent results.
const std = @import("std");
const boundary = @import("boundary");
const world = @import("world");
const data = if (@hasDecl(boundary, "data")) boundary.data else boundary.data_v2;
const source = boundary.source;
const current = @hasDecl(world, "Session");
const protocol = if (current) data.invocation else data.protocol;
const runtime = if (current) world else world.process_v2;

const Fixture = enum { scalar, install, deep };
const Command = struct { bytes: []u8, image_bytes: usize };
fn command(a: std.mem.Allocator, compact: bool, fixture: Fixture, count: usize) !Command {
    var b = source.Builder.init(a);
    defer b.deinit();
    const input = switch (fixture) {
        .install => try source.examples.installations(&b, count),
        .deep => try source.examples.deep(&b),
        .scalar => blk: {
            const integer = try b.scalar(u64);
            const unit = try b.scalar(void);
            const entry = try b.declare(&.{}, integer, &.{}, &.{});
            try b.define(entry, try b.pure(try b.constant(u64, 42)));
            break :blk b.module(entry, unit);
        },
    };
    var compiled = try source.lower(a, input);
    defer compiled.deinit();
    const length = if (current) try data.program_image.encodedLength(compiled.program) else if (compact) try data.compact_image.encodedLength(a, compiled.program) else try data.image.encodedLength(compiled.program);
    const image = try a.alloc(u8, length);
    defer a.free(image);
    if (current) {
        _ = try compiled.encode(a, image);
    } else if (compact) {
        _ = try data.compact_image.encode(a, compiled.program, image);
    } else {
        _ = try compiled.encode(a, image);
    }
    const invocation: protocol.Input = if (current)
        .{ .image = image, .instance = .{ .initial_args = &.{} } }
    else
        .{ .mode = .run, .image = image, .instance = .{ .initial_args = &.{} }, .control = .{ .continue_value = null } };
    const encoded = try a.alloc(u8, try protocol.encodedLength(protocol.Input, invocation));
    errdefer a.free(encoded);
    _ = try protocol.encode(protocol.Input, a, invocation, encoded);
    return .{ .bytes = encoded, .image_bytes = length };
}

fn invoke(a: std.mem.Allocator, input: []const u8, output: []u8) ![]const u8 {
    if (current) return world.invocation.invokeInto(a, input, output);
    const decoded = try protocol.decode(protocol.Input, a, input);
    var result = try runtime.invoke(a, decoded);
    defer result.deinit();
    return protocol.encode(protocol.Outcome, a, result.record, output);
}

fn verify(a: std.mem.Allocator, bytes: []const u8, expected: u64) !void {
    if (current) {
        var decoded = try protocol.decode(protocol.Outcome, a, bytes);
        defer decoded.deinit();
        if (decoded.value != .completed or decoded.value.completed.len != 8 or
            std.mem.readInt(u64, decoded.value.completed[0..8], .little) != expected)
            return error.UnexpectedResult;
    } else {
        var scratch = std.heap.ArenaAllocator.init(a);
        defer scratch.deinit();
        const decoded = try protocol.decode(protocol.Outcome, scratch.allocator(), bytes);
        if (decoded != .completed or decoded.completed.len != 8 or std.mem.readInt(u64, decoded.completed[0..8], .little) != expected)
            return error.UnexpectedResult;
    }
}

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const format = args.next() orelse return error.ExpectedFormat;
    const fixture = std.meta.stringToEnum(Fixture, args.next() orelse return error.ExpectedFixture) orelse return error.InvalidFixture;
    const count = try std.fmt.parseInt(usize, args.next() orelse return error.ExpectedCount, 10);
    if (count > 256 or (fixture == .install and count == 0) or args.next() != null) return error.InvalidFixture;
    if (!std.mem.eql(u8, format, if (current) "bpi3" else "bpi2") and
        (current or !std.mem.eql(u8, format, "bpc1"))) return error.InvalidFormat;
    const producing = std.Io.Clock.awake.now(init.io);
    const produced = try command(init.gpa, std.mem.eql(u8, format, "bpc1"), fixture, count);
    const producer_ns: u64 = @intCast(producing.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
    const input = produced.bytes;
    defer init.gpa.free(input);
    const expected: u64 = switch (fixture) {
        .scalar => 42,
        .deep => 67,
        .install => count * (count + 1) / 2,
    };
    const storage = try init.gpa.alloc(u8, 128 << 20);
    defer init.gpa.free(storage);
    var samples: [9]u64 = undefined;
    var peak: usize = 0;
    var allocations: usize = 0;
    var allocated_bytes: usize = 0;
    for (0..12) |iteration| {
        var output: [256]u8 = undefined;
        const started = std.Io.Clock.awake.now(init.io);
        var arena = runtime.Workspace.init(storage);
        const encoded = try invoke(arena.allocator(), input, &output);
        const elapsed: u64 = @intCast(started.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
        try verify(init.gpa, encoded, expected);
        if (iteration >= 3) samples[iteration - 3] = elapsed;
    }
    // Allocation counters are a separate replay, outside acceptance timings.
    var arena = runtime.Workspace.init(storage);
    var tracked = std.testing.FailingAllocator.init(arena.allocator(), .{});
    var output: [256]u8 = undefined;
    try verify(init.gpa, try invoke(tracked.allocator(), input, &output), expected);
    peak = arena.peak_payload;
    allocations = tracked.allocations;
    allocated_bytes = tracked.allocated_bytes;
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .format = format, .fixture = @tagName(fixture), .count = count, .image_bytes = produced.image_bytes, .producer_ns = producer_ns, .input_bytes = input.len, .input_sha256 = std.fmt.bytesToHex(data.wire.digest(input), .lower), .samples_ns = samples, .working_capacity = storage.len, .peak_working_payload_bytes = peak, .allocation_calls = allocations, .allocated_bytes = allocated_bytes, .expected = expected }, .{}, &stdout.interface);
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();
}
