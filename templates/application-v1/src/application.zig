const world = @import("world");
const agent = @import("agent.zig");
const effects = @import("effects.zig");
const provider = @import("provider.zig");

pub const Effects = effects;
pub const ResearchLookupMachine = provider.Machine;
pub const ResearchLookupSite = provider.LookupSite;

/// Closed Research Digest application with one residual external effect.
pub const Application = world.application(.{
    .name = "research-digest-agent",
    .version = "2.0.0",
    .root = agent.Machine,
    .handlers = .{
        world.handle(
            agent.Machine,
            0,
            "research.digest.format.v2",
            provider.Machine,
        ),
    },
    .external = .{
        world.external(provider.Machine, 0, .{
            .site_identity = "research.lookup.v2",
            .interface = "research.lookup.v2",
            .authority = world.Authority.database,
            .maximum_payload_bytes = 64 * 1024,
            .maximum_result_bytes = 256 * 1024,
            .maximum_attempts = 3,
        }),
    },
    .limits = .{
        .maximum_manifest_bytes = 64 * 1024,
        .maximum_initial_args_bytes = 64 * 1024,
        .maximum_state_bytes = 512 * 1024,
        .maximum_payload_bytes = 64 * 1024,
        .maximum_result_bytes = 256 * 1024,
        .maximum_host_claim_bytes = 8 * 1024,
        .maximum_host_metadata_bytes = 8 * 1024,
        .maximum_failure_bytes = 8 * 1024,
        .maximum_internal_handlers = 4,
        .maximum_residual_effects = 1,
        .maximum_fuel_per_step = 10_000,
        .maximum_frame_depth = 16,
        .maximum_provider_depth = 2,
    },
});
