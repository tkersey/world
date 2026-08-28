const boundary = @import("boundary");
const world = @import("world");

const SourceA = boundary.effect.site(0, "duplicate.source-a.v1", u32, u32);
const SourceB = boundary.effect.site(1, "duplicate.source-b.v1", u32, u32);
const Target = boundary.effect.site(0, "duplicate.target.v1", u32, u32);
const resume_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};
const blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{ .target = 1, .arguments = &resume_arguments },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 1,
            .request_values = &.{1},
            .continuation = .{ .target = 2, .arguments = &resume_arguments },
            .resume_type = .{ .scalar = .u32 },
        } },
    },
    .{
        .id = 2,
        .parameters = &.{2},
        .terminator = .{ .return_value = 2 },
    },
};
const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{ SourceA, SourceB };
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "duplicate-residual-identity",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
            .{ .scalar = .u32 },
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .scalar = .u32 },
    };
};
const Program = boundary.program("duplicate-residual-identity", Body);
const Invalid = world.system(.{
    .name = "duplicate-residual-identity",
    .root = Program,
    .handlers = .{},
    .morphisms = .{
        world.systemMorphism(.{
            .consumer = Program,
            .site = SourceA,
            .target = Target,
        }),
        world.systemMorphism(.{
            .consumer = Program,
            .site = SourceB,
            .target = Target,
        }),
    },
    .external = .{Target},
});

comptime {
    _ = Invalid.Program;
}
