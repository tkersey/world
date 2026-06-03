const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const artifact_path = args.next() orelse return error.MissingWasmArtifactPath;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, artifact_path, allocator, .limited(1024 * 1024));
    defer allocator.free(bytes);

    const inspection = try world.Guest.Wasm.inspect(bytes);
    if (!inspection.passed()) return error.WasmInspectionFailed;

    try stdout.print("wasm_artifact={s}\n", .{artifact_path});
    try stdout.print("abi_version={d}\n", .{inspection.abi_version});
    try stdout.print("export_count={d}\n", .{inspection.export_count});
    try stdout.print("forbidden_imports={d}\n", .{inspection.forbidden_import_count});
    try stdout.flush();
}
