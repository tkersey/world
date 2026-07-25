const boundary = @import("boundary");

/// One bounded clean-room research request.
///
/// Boundary StaticMachine v1 represents portable word fields canonically as
/// u64. Narrower integer carriers are intentionally post-v1 work.
pub const ResearchRequest = struct {
    query: []const u8,
    maximum_items: u64,
};

/// One deterministic research item returned by the fixture capability.
pub const ResearchItem = struct {
    title: []const u8,
    summary: []const u8,
};

/// Terminal application value.
pub const DigestResult = struct {
    digest: []const u8,
    item_count: u64,
};

/// Bounded lookup response for the v1 template.
///
/// Two named items keep the schema inside StaticMachine v1’s closed,
/// source-independent carrier set. Dynamic product collections remain
/// post-v1 work.
pub const ResearchResponse = struct {
    first: ResearchItem,
    second: ResearchItem,
    digest_result: DigestResult,
};

/// Canonical schema registry shared by both Boundary programs.
pub const Schemas = boundary.ir.schema.Registry(.{
    ResearchRequest,
    ResearchItem,
    DigestResult,
    ResearchResponse,
});

/// Application-internal formatting protocol.
pub const Digest = boundary.ir.schema.Protocol(.{
    .label = "digest",
    .ops = .{
        boundary.ir.schema.transform(
            "format",
            ResearchRequest,
            DigestResult,
        ),
    },
});

/// Residual protocol implemented by the independently authored capability.
pub const Research = boundary.ir.schema.Protocol(.{
    .label = "research",
    .ops = .{
        boundary.ir.schema.transform(
            "lookup",
            ResearchRequest,
            ResearchResponse,
        ),
    },
});
