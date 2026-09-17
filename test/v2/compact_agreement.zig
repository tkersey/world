//! Fresh invocation and saved-State interchange for one logical Program.
const std = @import("std");
const boundary = @import("boundary");
const data = @import("boundary_data");
const world = @import("world").process_v2;

const Images = struct {
    legacy: []u8,
    compact: []u8,

    fn init(program: data.program.Program) !Images {
        const allocator = std.testing.allocator;
        const legacy = try allocator.alloc(u8, try data.image.encodedLength(program));
        errdefer allocator.free(legacy);
        _ = try data.image.encode(allocator, program, legacy);
        const compact = try allocator.alloc(u8, try data.compact_image.encodedLength(allocator, program));
        errdefer allocator.free(compact);
        _ = try data.compact_image.encode(allocator, program, compact);
        return .{ .legacy = legacy, .compact = compact };
    }

    fn deinit(self: Images) void {
        std.testing.allocator.free(self.legacy);
        std.testing.allocator.free(self.compact);
    }
};

test "packed installation run and every advance preserve exact portable outcomes" {
    const allocator = std.testing.allocator;
    var builder = boundary.source.Builder.init(allocator);
    defer builder.deinit();
    var compiled = try boundary.program.compile(allocator, try boundary.source.examples.installations(&builder, 64));
    defer compiled.deinit();
    const images = try Images.init(compiled.program);
    defer images.deinit();
    try std.testing.expect(data.compact_image.isCompact(images.compact));
    var expected = try world.run(allocator, .{ .program = .{ .image = images.legacy }, .instance = .{ .initial_args = &.{} } });
    defer expected.deinit();
    var actual = try world.run(allocator, .{ .program = .{ .image = images.compact }, .instance = .{ .initial_args = &.{} } });
    defer actual.deinit();
    try std.testing.expectEqualDeep(expected.record, actual.record);
    try std.testing.expectEqualSlices(u8, &.{ 32, 8, 0, 0, 0, 0, 0, 0 }, actual.record.completed);
    var step = try world.advance(allocator, .{ .program = .{ .image = images.legacy }, .instance = .{ .initial_args = &.{} } });
    defer step.deinit();
    var index: usize = 0;
    while (step.record == .progressed) : (index += 1) {
        try std.testing.expect(index < 400);
        var legacy = try world.advance(allocator, .{ .program = .{ .image = images.legacy }, .instance = .{ .snapshot = step.record.progressed } });
        var compact = try world.advance(allocator, .{ .program = .{ .image = images.compact }, .instance = .{ .snapshot = step.record.progressed } });
        try std.testing.expectEqualDeep(legacy.record, compact.record);
        step.deinit();
        if (index % 2 == 0) {
            step = compact;
            legacy.deinit();
        } else {
            step = legacy;
            compact.deinit();
        }
    }
    try std.testing.expectEqualDeep(expected.record, step.record);
}

test "packed saved search response uses original BPI2 request and State identities" {
    const allocator = std.testing.allocator;
    var builder = boundary.source.Builder.init(allocator);
    defer builder.deinit();
    var compiled = try boundary.program.compile(allocator, try boundary.source.examples.queensDfs(&builder));
    defer compiled.deinit();
    const images = try Images.init(compiled.program);
    defer images.deinit();
    var step = try world.run(allocator, .{ .program = .{ .image = images.legacy }, .instance = .{ .initial_args = &.{} } });
    defer step.deinit();
    var actual = try world.run(allocator, .{ .program = .{ .image = images.compact }, .instance = .{ .initial_args = &.{} } });
    defer actual.deinit();
    try std.testing.expectEqualDeep(step.record, actual.record);
    for (0..16) |_| {
        if (step.record != .yielded) break;
        const next = try world.run(allocator, .{ .program = .{ .image = images.compact }, .instance = .{ .snapshot = step.record.yielded } });
        step.deinit();
        step = next;
    }
    try std.testing.expect(step.record == .requested);
    const request = try data.protocol.decode(data.protocol.Request, allocator, step.record.requested.request);
    const result: data.protocol.Result = .{
        .request_identity = request.request_identity,
        .resume_schema_digest = data.wire.digest(request.resume_schema),
        .value = &.{ 201, 0, 0, 0, 0, 0, 0, 0 },
    };
    const response = try allocator.alloc(u8, try data.protocol.encodedLength(data.protocol.Result, result));
    defer allocator.free(response);
    _ = try data.protocol.encode(data.protocol.Result, allocator, result, response);
    var legacy = try world.run(allocator, .{
        .program = .{ .image = images.legacy },
        .instance = .{ .snapshot = step.record.requested.state },
        .control = .{ .continue_value = response },
    });
    defer legacy.deinit();
    var compact = try world.run(allocator, .{
        .program = .{ .image = images.compact },
        .instance = .{ .snapshot = step.record.requested.state },
        .control = .{ .continue_value = response },
    });
    defer compact.deinit();
    try std.testing.expectEqualDeep(legacy.record, compact.record);
}
