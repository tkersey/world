const std = @import("std");
const boundary = @import("boundary");
const options = @import("options");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var b = boundary.computation.Builder.init(allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const byte = try b.scalar(u8);
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const bytes = try b.schema(.bytes);
    const optional_byte = try b.schema(.{ .sum = &.{ unit, byte } });
    const failure = try b.failureLiteral(try b.constant(void, {}));
    const mix = try b.effect(.{ .identity = "checksum/mix-byte", .payload = byte, .result = integer, .external = false });
    const capability = try b.schema(.{ .internal = .{ .capability = mix } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{ .effect = mix, .input = integer, .answer = integer, .capture_bound = &.{ unit, byte, integer, bytes, optional_byte, capability }, .handled = &.{mix}, .mode = .deep, .use = .linear } } });
    const returns = try b.declare(&.{ integer, integer }, integer, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 1))));
    const clause = try b.declare(&.{ integer, byte, token }, integer, &.{}, &.{});
    const widened = try b.primitive(integer, .integer_convert, &.{try b.reference(b.parameter(clause, 1))}, 0);
    const mixed = try b.primitive(integer, .integer_bit_xor, &.{ widened, try b.reference(b.parameter(clause, 0)) }, 0);
    try b.define(clause, try b.term(.{ .resume_value = .{ .resumption = try b.reference(b.parameter(clause, 2)), .argument = mixed } }));
    const mixer = try b.handler(.{ .mode = .deep, .input = integer, .answer = integer, .state = &.{integer}, .return_function = returns, .clauses = &.{.{ .effect = mix, .function = clause, .resumption = token }} });
    const loop = try b.declare(&.{ capability, bytes, integer, integer }, integer, &.{mix}, &.{});
    const cap = try b.reference(b.parameter(loop, 0));
    const input = try b.reference(b.parameter(loop, 1));
    const index = try b.reference(b.parameter(loop, 2));
    const accumulated = try b.reference(b.parameter(loop, 3));
    const length = try b.primitive(integer, .blob_length, &.{input}, 0);
    const more = try b.primitive(boolean, .less, &.{ index, length }, 0);
    const found = try b.primitive(optional_byte, .blob_byte, &.{ input, index }, 0);
    const selected = try b.value(.{ .schema = byte, .expression = .{ .primitive = .{ .opcode = .variant_payload, .operands = &.{found}, .immediate = 1, .failures = &.{.{ .kind = .invalid_variant, .value = failure }} } } });
    const delta = try b.variable(integer);
    const operation = try b.term(.{ .perform = .{ .effect = mix, .capability = cap, .payload = selected } });
    const next_index = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ index, try b.constant(u64, 1) }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = failure }} } } });
    const checksum = try b.primitive(integer, .integer_bit_xor, &.{ accumulated, try b.reference(delta) }, 0);
    const next = try b.term(.{ .call = .{ .function = loop, .arguments = &.{ cap, input, next_index, checksum } } });
    const step = try b.bind(delta, operation, try b.term(.{ .yield_then = next }));
    try b.define(loop, try b.term(.{ .conditional = .{ .condition = more, .when_true = step, .when_false = try b.pure(accumulated) } }));
    const body = try b.declare(&.{ capability, bytes }, integer, &.{mix}, &.{});
    try b.define(body, try b.term(.{ .call = .{ .function = loop, .arguments = &.{ try b.reference(b.parameter(body, 0)), try b.reference(b.parameter(body, 1)), try b.constant(u64, 0), try b.constant(u64, 17) } } }));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ capability, bytes }, .result = integer, .effects = &.{mix} } } });
    const main_function = try b.declare(&.{bytes}, integer, &.{}, &.{});
    try b.define(main_function, try b.term(.{ .handle = .{ .handler = mixer, .body = try b.lambda(body, body_type), .arguments = &.{try b.reference(b.parameter(main_function, 0))}, .state = &.{try b.constant(u64, 165)} } }));
    const module = b.module(main_function, unit);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (options.source) {
        try std.json.Stringify.value(module, .{ .emit_strings_as_arrays = true }, &output.interface);
        try output.interface.writeByte('\n');
    } else {
        var diagnostic: boundary.program.Diagnostic = .{};
        var compiled = boundary.program.compileObserved(allocator, module, .{ .diagnostic = &diagnostic }) catch |err| {
            std.debug.print("checksum compilation: {any}\n", .{diagnostic});
            return err;
        };
        defer compiled.deinit();
        const image = try allocator.alloc(u8, try boundary.image_v2.encodedLength(compiled.program));
        defer allocator.free(image);
        _ = try compiled.encode(allocator, image);
        try output.interface.writeAll(image);
    }
    try output.interface.flush();
}
