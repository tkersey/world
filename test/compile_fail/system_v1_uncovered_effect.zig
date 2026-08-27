const fixtures = @import("system_v1_fixtures");
const world = @import("world");

const Invalid = world.system(.{
    .name = "uncovered",
    .root = fixtures.RootProgram,
    .handlers = .{},
    .morphisms = .{},
    .external = .{fixtures.Observe},
});

comptime {
    _ = Invalid.Program;
}
