const boundary = @import("boundary");

pub const Query = boundary.Text(512);
pub const Title = boundary.Text(256);
pub const Summary = boundary.Text(1024);
pub const Separator = boundary.Text(1);
pub const Digest = boundary.Text(8192);

pub const ResearchRequest = struct {
    query: Query,
    maximum_items: u32,
};

pub const ResearchItem = struct {
    title: Title,
    summary: Summary,
};

pub const ResearchItems = boundary.Vector(ResearchItem, 8);

pub const ResearchResponse = struct {
    items: ResearchItems,
};

pub const DigestResult = struct {
    digest: Digest,
    item_count: u32,
};

/// Canonical schema order shared by the root and provider Machines.
pub const schema_types = .{
    ResearchRequest,
    Query,
    ResearchItem,
    Title,
    Summary,
    ResearchItems,
    ResearchResponse,
    Digest,
    Separator,
    DigestResult,
};
