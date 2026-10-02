const std = @import("std");
const data = @import("boundary_data");
const fixtures = @import("retention_fixture");
// Keep the reusable captured branch live across its first application. Both
// observations contribute to the result; prefix checks distinguish each call.
const retained = blk: {
    var p = fixtures.captured;
    p.blocks = &.{
        fixtures.captured.blocks[0],
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 2, .arguments = &.{}, .next = .{ .block = 3, .assignments = &.{.{ .destination = 1, .source = .returned }} } } } },
        fixtures.captured.blocks[2],
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .integer_bit_xor, .operands = &.{ 1, 3 } }}, .terminator = .{ .return_value = 3 } },
    };
    break :blk p;
};
fn aliases(a: std.mem.Allocator, count: usize) !data.activation.Program {
    if (count == 0 or count > 128) return error.Count;
    const inputs = try a.alloc(data.program.Id, count);
    const layout = try a.alloc(data.program.Id, count + 1);
    @memset(layout, 0);
    layout[count] = 1;
    const instructions = try a.alloc(data.activation.Instruction, count);
    for (inputs, instructions, 0..) |*input, *instruction, i| {
        input.* = i;
        instruction.* = .{ .destination = count, .opcode = .blob_length, .operands = inputs[i .. i + 1] };
    }
    const functions = try a.alloc(data.activation.Function, 1);
    functions[0] = .{ .entry = 0, .inputs = inputs, .layout = .{ .slots = layout }, .result = 1 };
    const blocks = try a.alloc(data.activation.Block, 1);
    blocks[0] = .{ .function = 0, .instructions = instructions, .terminator = .{ .return_value = count } };
    return .{ .roots = .{ .entry = 0, .result = 1, .failure = 2 }, .schemas = &.{ .bytes, .u64, .unit }, .constants = &.{}, .effects = &.{}, .functions = functions, .blocks = blocks };
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.Mode;
    if (args.next() != null) return error.Arguments;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const program = if (std.mem.eql(u8, mode, "unique")) comptime fixtures.program(false) else if (std.mem.eql(u8, mode, "alias")) comptime fixtures.program(true) else if (std.mem.eql(u8, mode, "captured")) fixtures.captured else if (std.mem.eql(u8, mode, "retained")) retained else if (std.mem.startsWith(u8, mode, "aliases-")) try aliases(arena.allocator(), try std.fmt.parseInt(usize, mode[8..], 10)) else return error.Mode;
    const image = try init.gpa.alloc(u8, try data.program_image.encodedLength(program));
    defer init.gpa.free(image);
    _ = try data.program_image.encode(init.gpa, program, image);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(image);
    try output.interface.flush();
}
