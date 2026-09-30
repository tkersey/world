// Compiler-emitted H/Q inputs. Every dormant caller must later emit its own
// depth, so coalescing cannot discard the retained continuations.
const std = @import("std");
const boundary = @import("boundary");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.Mode;
    const pending = std.mem.eql(u8, mode, "Q");
    if (!pending and !std.mem.eql(u8, mode, "H")) return error.Mode;
    if (args.next() != null) return error.Arguments;
    var b = boundary.source.Builder.init(init.gpa);
    defer b.deinit();
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const unit = try b.scalar(void);
    const effect = try b.effect(.{ .identity = "history/observe", .payload = integer, .result = integer });
    const entry = try b.declare(&.{integer}, integer, &.{effect}, &.{});
    const depth = try b.reference(b.parameter(entry, 0));
    const fault = try b.failureLiteral(try b.constant(void, {}));
    const decremented = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{
        .opcode = .integer_sub,
        .operands = &.{ depth, try b.constant(u64, 1) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = fault }},
    } } });
    const child = try b.variable(integer);
    const call = try b.term(.{ .call = .{ .function = entry, .arguments = &.{decremented} } });
    const observe = try b.term(.{ .perform = .{ .effect = effect, .payload = depth } });
    const recursive = try b.bind(child, call, try b.bind(try b.variable(integer), observe, try b.pure(try b.reference(child))));
    const seed = try b.variable(integer);
    var value = if (pending) try b.reference(seed) else depth;
    // A fixed active fragment remains in the admitted image; every intermediate
    // arithmetic step can be observed through a bounded public quantum.
    for (0..128) |_| value = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{
        .opcode = .integer_add,
        .operands = &.{ value, try b.constant(u64, 1) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = fault }},
    } } });
    const bottom = if (pending)
        try b.bind(seed, observe, try b.pure(value))
    else
        try b.term(.{ .yield_then = try b.pure(value) });
    const condition = try b.primitive(boolean, .equal, &.{ depth, try b.constant(u64, 0) }, 0);
    try b.define(entry, try b.term(.{ .conditional = .{ .condition = condition, .when_true = bottom, .when_false = recursive } }));
    var compiled = try boundary.program.compile(init.gpa, b.module(entry, unit));
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
