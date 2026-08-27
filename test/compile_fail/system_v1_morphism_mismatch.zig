const boundary = @import("boundary");
const fixtures = @import("system_v1_fixtures");
const world = @import("world");

const WrongTarget = boundary.effect.site(
    0,
    "generic.wrong-morph-target.v1",
    bool,
    u32,
);
const Invalid = world.system(.{
    .name = "morphism-mismatch",
    .root = fixtures.MorphProgram,
    .handlers = .{},
    .morphisms = .{world.systemMorphism(.{
        .consumer = fixtures.MorphProgram,
        .site = fixtures.MorphSource,
        .target = WrongTarget,
    })},
    .external = .{WrongTarget},
});

comptime {
    _ = Invalid.Program;
}
