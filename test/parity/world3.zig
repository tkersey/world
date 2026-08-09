const runtime = @import("application_runtime_v1.zig");
const wasm = @import("application_wasm_v1.zig");

pub const Authority = runtime.Authority;
pub const external = runtime.external;
pub const ApplicationAbiV1 = wasm.ApplicationAbiV1;

pub fn application(comptime spec: anytype) type {
    return runtime.applicationWithIdentityForConformance(spec, .{
        .boundary_version = "1.0.0",
        .world_version = "2.0.0",
    });
}
