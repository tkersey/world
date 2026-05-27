const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Machine = world.Machine(fixtures.Strict.Target, .{
    .ports = .{},
    .strict_handler_coverage = true,
});

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    var transcript = world.Transcript.init(std.heap.page_allocator);
    defer transcript.deinit();

    var result = try Machine.run(&runtime, .{}, .{
        .allocator = std.heap.page_allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
        .expected_world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
    });
    defer result.deinit(std.heap.page_allocator);

    try stdout.print("world_surface_fingerprint={x}\n", .{fixtures.Strict.Target.WorldSurface.surface_fingerprint});
    try stdout.print("target_certificate_fingerprint={x}\n", .{fixtures.Strict.Target.Certificate.certificate_fingerprint});
    try stdout.print("final_result={d}\n", .{result.value});
    try stdout.flush();
}
