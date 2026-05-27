const fixtures = @import("world_fixtures");
const world = @import("world");

const PortsCtx = struct {};

fn approve(_: *PortsCtx, _: []const u8) !i32 {
    return 7;
}

const Good = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);

const Forged = struct {
    pub const TargetType = Good.TargetType;
    pub const SiteType = Good.SiteType;
    pub const Payload = Good.Payload;
    pub const Response = Good.Response;
    pub const Result = Good.Result;
    pub const world_port_id = Good.world_port_id;
    pub const residual_site_index = Good.residual_site_index;
    pub const residual_site_fingerprint = Good.residual_site_fingerprint + 1;
    pub const payload_ref = Good.payload_ref;
    pub const response_ref = Good.response_ref;
    pub const result_ref = Good.result_ref;
    pub const source_ref = .{
        .domain_id = Good.source_ref.domain_id,
        .fingerprint = Good.source_ref.fingerprint + 1,
        .format_version = Good.source_ref.format_version,
        .label = Good.source_ref.label,
        .branch_id = Good.source_ref.branch_id,
        .site_index = Good.source_ref.site_index,
        .kind_tag = Good.source_ref.kind_tag,
    };
    pub const world_port_ref = Good.world_port_ref;
    pub const suggested_name = Good.suggested_name;
    pub const handler = Good.handler;

    pub fn replayKey(request_fingerprint: u64) world.ReplayKeySeed {
        return Good.replayKey(request_fingerprint);
    }
};

const Machine = world.Machine(fixtures.Ports.Target, .{
    .ports = .{Forged},
    .strict_handler_coverage = true,
});

comptime {
    _ = Machine;
}
