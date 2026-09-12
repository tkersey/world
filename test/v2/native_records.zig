//! Test embedding: the native and WASM hosts exchange the same public records.
const std = @import("std");
const data = @import("boundary_data_v2");
const process = @import("world").process_v2;

pub fn main(init: std.process.Init) !void {
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().reader(init.io, &input_buffer);
    const bytes = try input.interface.allocRemaining(init.gpa, .unlimited);
    defer init.gpa.free(bytes);
    const original = try init.gpa.dupe(u8, bytes);
    defer init.gpa.free(original);
    const invocation = try data.protocol.decode(data.protocol.Input, init.gpa, bytes);
    var outcome = process.invoke(init.gpa, invocation) catch |err| {
        if (!std.mem.eql(u8, bytes, original)) return error.InvocationChangedInput;
        return err;
    };
    defer outcome.deinit();
    if (!std.mem.eql(u8, bytes, original)) return error.InvocationChangedInput;
    const buffer = try init.gpa.alloc(u8, try data.protocol.encodedLength(data.protocol.Outcome, outcome.record));
    defer init.gpa.free(buffer);
    const encoded = try data.protocol.encode(data.protocol.Outcome, init.gpa, outcome.record, buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try output.interface.writeAll(encoded);
    try output.interface.flush();
}
