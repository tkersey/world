const boundary = @import("boundary");
const world = @import("world");

const u32_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const block_costs = [_]u64{0};
    pub const control_ir: boundary.ir.Program = .{
        .label = "forged-component",
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
const ForgedProgram = struct {
    pub fn component() type {
        return Body;
    }
};
const Invalid = world.system(.{
    .name = "forged-component-system",
    .root = ForgedProgram,
    .handlers = .{},
    .morphisms = .{},
    .external = .{},
});

comptime {
    _ = Invalid.Program;
}
