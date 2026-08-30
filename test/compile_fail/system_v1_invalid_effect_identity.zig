const boundary = @import("boundary");
const fixtures = @import("system_v1_fixtures");
const world = @import("world");

const InvalidTarget = boundary.effect.site(0, "\xff", u32, u32);

const Invalid = world.system(.{
    .name = "invalid-effect-identity",
    .root = fixtures.MorphProgram,
    .handlers = .{},
    .morphisms = .{world.systemMorphism(.{
        .consumer = fixtures.MorphProgram,
        .site = fixtures.MorphSource,
        .target = InvalidTarget,
    })},
    .external = .{InvalidTarget},
});

comptime {
    _ = Invalid.Program;
}
