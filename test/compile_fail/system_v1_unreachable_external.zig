const fixtures = @import("system_v1_fixtures");
const world = @import("world");

const Invalid = world.system(.{
    .name = "unreachable-external",
    .root = fixtures.MorphProgram,
    .handlers = .{},
    .morphisms = .{world.systemMorphism(.{
        .consumer = fixtures.MorphProgram,
        .site = fixtures.MorphSource,
        .target = fixtures.MorphTarget,
    })},
    .external = .{ fixtures.MorphTarget, fixtures.ProviderObserve },
});

comptime {
    _ = Invalid.Program;
}
