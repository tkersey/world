const boundary = @import("boundary");
const effects = @import("effects.zig");

const semantic = boundary.ir.builder.semantic;
const ResearchRows = effects.Research.Rows(struct {}, .{
    .requirement_index = 0,
    .first_op = 0,
    .schema_refs = effects.Schemas.schema_refs,
});
const Lookup = ResearchRows.op("lookup");
const compiled = semantic.finish(.{
    .label = "research-digest-formatter",
    .ir_hash = 0x444947455354464d,
    .entry = "format",
    .schemas = effects.Schemas,
    .requirements = &.{ResearchRows.requirement},
    .ops = &ResearchRows.ops,
    .functions = .{.{
        .symbol_name = "format",
        .requirements = semantic.span(0, 1),
        .params = .{
            semantic.param("request", effects.ResearchRequest),
        },
        .locals = .{
            semantic.local("research", effects.ResearchResponse),
            semantic.local("digest", effects.DigestResult),
        },
        .result = effects.DigestResult,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                semantic.call(Lookup, .{
                    .dst = "research",
                    .payload = "request",
                    .label = "research.lookup",
                }),
                semantic.productExtractField(
                    "digest",
                    "research",
                    2,
                ),
            },
            .terminator = semantic.returnValue("digest"),
        }},
    }},
}) catch |err| @compileError(
    "invalid Digest Formatter ProgramPlan: " ++ @errorName(err),
);

const Body = struct {
    pub const value_schema_types = effects.Schemas.value_schema_types;
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};

pub const Program = boundary.program(
    "research-digest-formatter",
    struct {},
    Body,
);
pub const Machine = boundary.staticMachine(Program, .{
    .maximum_state_bytes = 128 * 1024,
});
pub const LookupSite = Machine.EffectRow.operationSite(
    "research",
    "lookup",
    0,
);
