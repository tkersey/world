//! Fixed-compiler input for retained resident transaction and binding probes.
//! Every dormant continuation emits its own depth on resumption.
const std = @import("std");
const boundary = @import("boundary");
const p = boundary.data.program;

fn checked(b: *boundary.source.Builder, schema: p.Id, opcode: p.Opcode, left: p.Id, right: p.Id, fault: p.Id) !p.Id {
    return b.value(.{ .schema = schema, .expression = .{ .primitive = .{
        .opcode = opcode,
        .operands = &.{ left, right },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(fault) }},
    } } });
}

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.Mode;
    if (args.next() != null) return error.Arguments;
    const request = std.mem.eql(u8, mode, "Q");
    if (!request and !std.mem.eql(u8, mode, "H")) return error.Mode;
    var b = boundary.source.Builder.init(init.gpa);
    defer b.deinit();
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const unit = try b.scalar(void);
    const fault = try b.constant(void, {});
    const observe = try b.effect(.{ .identity = "retained-history/depth", .payload = integer, .result = unit });
    const ask = try b.effect(.{ .identity = "retained-history/ask", .payload = unit, .result = integer });
    const effects: []const p.Id = if (request) &.{ observe, ask } else &.{observe};
    const recurse = try b.declare(&.{ integer, integer }, integer, effects, &.{});
    const depth = try b.reference(b.parameter(recurse, 0));
    const seed = try b.reference(b.parameter(recurse, 1));
    const condition = try b.primitive(boolean, .equal, &.{ depth, try b.constant(u64, 0) }, fault);
    const decrement = try checked(&b, integer, .integer_sub, depth, try b.constant(u64, 1), fault);
    const answer = try b.variable(integer);
    const observed = try b.variable(unit);
    const call = try b.term(.{ .call = .{ .function = recurse, .arguments = &.{ decrement, seed } } });
    const report = try b.term(.{ .perform = .{ .effect = observe, .payload = depth } });
    const continuation = try b.bind(answer, call, try b.bind(observed, report, try b.pure(try b.reference(answer))));

    // Dynamic checked arithmetic keeps every logical prefix observable.
    var variables: [256]p.Id = undefined;
    for (&variables) |*variable| variable.* = try b.variable(integer);
    const initial = if (request) try b.variable(integer) else null;
    var active = try b.pure(try b.reference(variables[variables.len - 1]));
    var index: usize = variables.len;
    while (index > 0) {
        index -= 1;
        const previous = if (index == 0)
            if (initial) |v| try b.reference(v) else seed
        else
            try b.reference(variables[index - 1]);
        const value = try checked(&b, integer, .integer_add, previous, try b.constant(u64, 1), fault);
        active = try b.bind(variables[index], try b.pure(value), active);
    }
    const bottom = if (initial) |v|
        try b.bind(v, try b.term(.{ .perform = .{ .effect = ask, .payload = fault } }), active)
    else
        try b.term(.{ .yield_then = active });
    try b.define(recurse, try b.term(.{ .conditional = .{ .condition = condition, .when_true = bottom, .when_false = continuation } }));
    var compiled = try boundary.program.compile(init.gpa, b.module(recurse, unit));
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
