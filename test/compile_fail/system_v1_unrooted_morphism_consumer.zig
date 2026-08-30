const fixtures = @import("system_v1_fixtures");
const world = @import("world");

const Invalid = world.system(.{
    .name = "unrooted-morphism-consumer",
    .root = fixtures.InertHandlerProvider,
    .handlers = .{},
    .morphisms = .{world.systemMorphism(.{
        .consumer = fixtures.MorphProgram,
        .site = fixtures.MorphSource,
        .target = fixtures.MorphTarget,
    })},
    .external = .{fixtures.MorphTarget},
});

comptime {
    _ = Invalid.Program;
}
