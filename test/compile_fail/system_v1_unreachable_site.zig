const boundary = @import("boundary");
const world = @import("world");

const Unused = boundary.effect.site(
    0,
    "generic.unused.v1",
    u32,
    u32,
);
const u32_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{Unused};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "unused-site",
        .value_types = &.{u32_type},
        .blocks = &.{.{
            .id = 0,
            .parameters = &.{0},
            .terminator = .{ .return_value = 0 },
        }},
        .entry = 0,
        .result_type = u32_type,
    };
};
const Program = boundary.program("unused-site", Body);
const Invalid = world.system(.{
    .name = "unused-site-system",
    .root = Program,
    .handlers = .{},
    .morphisms = .{},
    .external = .{Unused},
});

comptime {
    _ = Invalid.Program;
}
