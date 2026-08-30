const boundary = @import("boundary");
const world = @import("world");

const ResumeA = struct { value: u32 };
const ResumeB = struct { value: u32 };
const SourceA = boundary.effect.site(0, "nominal.source-a.v1", u32, ResumeA);
const SourceB = boundary.effect.site(1, "nominal.source-b.v1", u32, ResumeB);
const TargetA = boundary.effect.site(0, "nominal.target.v1", u32, ResumeA);
const TargetB = boundary.effect.site(1, "nominal.target.v1", u32, ResumeB);
const resume_and_input = [_]boundary.ir.EdgeArgument{
    .@"resume",
    .{ .value = 0 },
};
const resume_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};
const blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{ .target = 1, .arguments = &resume_and_input },
            .resume_type = .{ .schema = 0 },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{ 1, 2 },
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 1,
            .request_values = &.{2},
            .continuation = .{ .target = 2, .arguments = &resume_arguments },
            .resume_type = .{ .schema = 1 },
        } },
    },
    .{
        .id = 2,
        .parameters = &.{3},
        .terminator = .{ .return_value = 3 },
    },
};
const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = ResumeB;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{ SourceA, SourceB };
    pub const schema_types = .{ ResumeA, ResumeB };
    pub const control_ir: boundary.ir.Program = .{
        .label = "nominal-residual-merge",
        .value_types = &.{
            .{ .scalar = .u32 },
            .{ .schema = 0 },
            .{ .scalar = .u32 },
            .{ .schema = 1 },
        },
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 1 },
    };
};
const Program = boundary.program("nominal-residual-merge", Body);
const Invalid = world.system(.{
    .name = "nominal-residual-merge",
    .root = Program,
    .handlers = .{},
    .morphisms = .{
        world.systemMorphism(.{
            .consumer = Program,
            .site = SourceA,
            .target = TargetA,
        }),
        world.systemMorphism(.{
            .consumer = Program,
            .site = SourceB,
            .target = TargetB,
        }),
    },
    .external = .{TargetA},
});

comptime {
    _ = Invalid.Program;
}
