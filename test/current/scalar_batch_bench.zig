// Uninstalled same-image P25 benchmark, shared by baseline and candidate builds.
const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const count = try std.fmt.parseInt(usize, args.next() orelse return error.Count, 10);
    const mode = args.next() orelse return error.Mode;
    if (count > 4096 or args.next() != null) return error.Arguments;
    const fresh = std.mem.eql(u8, mode, "fresh");
    if (!fresh and !std.mem.eql(u8, mode, "prepared")) return error.Mode;
    const operations = try init.gpa.alloc(data.activation.Instruction, count);
    defer init.gpa.free(operations);
    for (operations) |*op| op.* = .{ .destination = 0, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } };
    const program: data.activation.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit },
        .constants = &.{},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0 }},
        .blocks = &.{.{ .function = 0, .instructions = operations, .terminator = .{ .return_value = 0 } }},
    };
    const image = try init.gpa.alloc(u8, try data.program_image.encodedLength(program));
    defer init.gpa.free(image);
    _ = try data.program_image.encode(init.gpa, program, image);
    var prepared = try world.Prepared.init(init.gpa, image);
    defer prepared.deinit();
    var input: [16]u8 = undefined;
    std.mem.writeInt(u64, input[0..8], 0x123456789abcdef0, .little);
    std.mem.writeInt(u64, input[8..16], 0xfedcba9876543210, .little);
    const expected: u64 = 0x123456789abcdef0 ^ (if (count % 2 == 0) @as(u64, 0) else @as(u64, 0xfedcba9876543210));
    var samples: [9]f64 = undefined;
    const batch: usize = if (count < 32) 128 else 16;
    for (0..12) |sample| {
        const start = std.Io.Clock.awake.now(init.io);
        for (0..batch) |_| {
            var session = if (fresh) try world.Session.initImage(init.gpa, image, &input) else try world.Session.start(init.gpa, &prepared, &input);
            defer session.deinit();
            const result = try session.run(null);
            if (result != .completed or std.mem.readInt(u64, (try session.bytes(&result.completed))[0..8], .little) != expected) return error.WrongResult;
        }
        const elapsed = start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds;
        if (sample >= 3) samples[sample - 3] = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(batch));
    }
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .operations = count, .mode = mode, .imageDigest = data.wire.digest(image), .samplesNs = samples }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
