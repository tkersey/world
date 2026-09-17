//! Same authored variant workload for an explicitly selected source pair.
const std = @import("std");
const boundary = @import("boundary");
const world = @import("world");
const data = boundary.data_v2;
const source = boundary.source;
const current = @hasDecl(source, "construct");
const protocol = if (current) data.invocation else data.protocol;
const runtime = if (current) world else world.process_v2;

fn module(b: *source.Builder) !source.Module {
    const integer = try b.scalar(u64);
    const unit = try b.scalar(void);
    const bytes = try b.schema(.bytes);
    const variant = try b.schema(.{ .sum = &.{ bytes, unit } });
    const boolean = try b.scalar(bool);
    const entry = try b.declare(&.{ variant, integer, integer }, integer, &.{}, &.{});
    const value = try b.reference(b.parameter(entry, 0));
    const count = try b.reference(b.parameter(entry, 1));
    const sum = try b.reference(b.parameter(entry, 2));
    const tag = try b.primitive(integer, .variant_tag, &.{value}, 0);
    const fault = try b.failureLiteral(try b.constant(void, {}));
    const decrement = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{
        .opcode = .integer_sub,
        .operands = &.{ count, try b.constant(u64, 1) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = fault }},
    } } });
    const accumulated = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{
        .opcode = .integer_add,
        .operands = &.{ sum, tag },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = fault }},
    } } });
    try b.define(entry, try b.term(.{ .conditional = .{
        .condition = try b.primitive(boolean, .equal, &.{ count, try b.constant(u64, 0) }, 0),
        .when_true = try b.pure(sum),
        .when_false = try b.term(.{ .call = .{
            .function = entry,
            .arguments = &.{ value, decrement, accumulated },
        } }),
    } }));
    return b.module(entry, unit);
}

fn command(a: std.mem.Allocator, compact: bool, size: usize, tag: u64, iterations: u64) ![]u8 {
    var b = source.Builder.init(a);
    defer b.deinit();
    const input = try module(&b);
    var compiled = if (current) try source.construct(a, input) else try source.lower(a, input);
    defer compiled.deinit();
    const length = if (current) try data.program_image.encodedLength(compiled.program) else if (compact) try data.compact_image.encodedLength(a, compiled.program) else try data.image.encodedLength(compiled.program);
    const image = try a.alloc(u8, length);
    defer a.free(image);
    if (current) {
        _ = try compiled.encode(a, image);
    } else if (compact) {
        _ = try data.compact_image.encode(a, compiled.program, image);
    } else _ = try compiled.encode(a, image);
    const args = try a.alloc(u8, size + 32);
    defer a.free(args);
    var writer: data.wire.Writer = .{ .output = args };
    try writer.natural(tag);
    if (tag == 0) {
        try writer.natural(size);
        const payload = try a.alloc(u8, size);
        defer a.free(payload);
        @memset(payload, 0xa7);
        try writer.put(payload);
    }
    try writer.fixed(u64, iterations);
    try writer.fixed(u64, 0);
    const invocation: protocol.Input = if (current)
        .{ .image = image, .instance = .{ .initial_args = args[0..writer.position] } }
    else
        .{ .mode = .run, .image = image, .instance = .{ .initial_args = args[0..writer.position] }, .control = .{ .continue_value = null } };
    const encoded = try a.alloc(u8, try protocol.encodedLength(protocol.Input, invocation));
    errdefer a.free(encoded);
    _ = try protocol.encode(protocol.Input, a, invocation, encoded);
    return encoded;
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
        if (decoded.value != .completed or
            std.mem.readInt(u64, decoded.value.completed[0..8], .little) != expected)
            return error.UnexpectedResult;
    } else {
        var scratch = std.heap.ArenaAllocator.init(a);
        defer scratch.deinit();
        const decoded = try protocol.decode(protocol.Outcome, scratch.allocator(), bytes);
        if (decoded != .completed or std.mem.readInt(u64, decoded.completed[0..8], .little) != expected)
            return error.UnexpectedResult;
    }
}

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const format = args.next() orelse return error.ExpectedFormat;
    const size = try std.fmt.parseInt(usize, args.next() orelse return error.ExpectedSize, 10);
    const tag = try std.fmt.parseInt(u64, args.next() orelse return error.ExpectedTag, 10);
    const iterations: u64 = 256;
    if (size > 16 << 20 or tag > 1 or (tag == 1 and size != 0)) return error.InvalidFixture;
    if (!std.mem.eql(u8, format, if (current) "bpi3" else "bpi2") and
        (current or !std.mem.eql(u8, format, "bpc1"))) return error.InvalidFormat;
    const input = try command(init.gpa, std.mem.eql(u8, format, "bpc1"), size, tag, iterations);
    defer init.gpa.free(input);
    const storage = try init.gpa.alloc(u8, 32 << 20);
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
        try verify(init.gpa, encoded, iterations * tag);
        if (iteration >= 3) samples[iteration - 3] = elapsed;
    }
    // Allocation counters are a separate replay, outside acceptance timings.
    var arena = runtime.Workspace.init(storage);
    var tracked = std.testing.FailingAllocator.init(arena.allocator(), .{});
    var output: [256]u8 = undefined;
    try verify(init.gpa, try invoke(tracked.allocator(), input, &output), iterations * tag);
    peak = arena.peak_payload;
    allocations = tracked.allocations;
    allocated_bytes = tracked.allocated_bytes;
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .format = format, .payload_bytes = size, .tag = tag, .iterations = iterations, .input_bytes = input.len, .input_sha256 = std.fmt.bytesToHex(data.wire.digest(input), .lower), .samples_ns = samples, .working_capacity = storage.len, .peak_working_payload_bytes = peak, .allocation_calls = allocations, .allocated_bytes = allocated_bytes, .expected = iterations * tag }, .{}, &stdout.interface);
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();
}
