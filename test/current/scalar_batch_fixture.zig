// Data-only images shared by native and WASM same-image P25 qualification.
const std = @import("std");
const data = @import("boundary_data");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const count = try std.fmt.parseInt(usize, args.next() orelse return error.Count, 10);
    const mode = args.next();
    const failure = if (mode) |text| std.mem.eql(u8, text, "failure") else false;
    if (mode != null and (!failure or count < 3)) return error.Mode;
    if (count > 4096 or args.next() != null) return error.Arguments;
    const operations = try init.gpa.alloc(data.activation.Instruction, count);
    defer init.gpa.free(operations);
    for (operations) |*op| op.* = .{ .destination = 0, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } };
    if (failure) operations[2] = .{ .destination = 0, .opcode = .integer_add, .operands = &.{ 0, 0 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 0 }} };
    const program: data.activation.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit },
        .constants = if (failure) &.{.{ .schema = 1, .bytes = &.{} }} else &.{},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0 }},
        .blocks = &.{.{ .function = 0, .instructions = operations, .terminator = .{ .return_value = 0 } }},
    };
    const image = try init.gpa.alloc(u8, try data.program_image.encodedLength(program));
    defer init.gpa.free(image);
    _ = try data.program_image.encode(init.gpa, program, image);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(image);
    try output.interface.flush();
}
