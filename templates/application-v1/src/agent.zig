const boundary = @import("boundary");
const effects = @import("effects.zig");

const semantic = boundary.ir.builder.semantic;
const DigestRows = effects.Digest.Rows(struct {}, .{
    .requirement_index = 0,
    .first_op = 0,
    .schema_refs = effects.Schemas.schema_refs,
});
const Format = DigestRows.op("format");
const compiled = semantic.finish(.{
    .label = "research-digest-root",
    .ir_hash = 0x5245534541524348,
    .entry = "run",
    .schemas = effects.Schemas,
    .requirements = &.{DigestRows.requirement},
    .ops = &DigestRows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = semantic.span(0, 1),
        .params = .{
            semantic.param("request", effects.ResearchRequest),
        },
        .locals = .{
            semantic.local("digest", effects.DigestResult),
        },
        .result = effects.DigestResult,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                semantic.call(Format, .{
                    .dst = "digest",
                    .payload = "request",
                    .label = "digest.format",
                }),
            },
            .terminator = semantic.returnValue("digest"),
        }},
    }},
}) catch |err| @compileError(
    "invalid Research Digest root ProgramPlan: " ++ @errorName(err),
);

const Body = struct {
    pub const value_schema_types = effects.Schemas.value_schema_types;
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};

pub const Program = boundary.program(
    "research-digest-root",
    struct {},
    Body,
);
pub const Machine = boundary.staticMachine(Program, .{
    .maximum_state_bytes = 128 * 1024,
});
pub const FormatSite = Machine.EffectRow.operationSite(
    "digest",
    "format",
    0,
);
