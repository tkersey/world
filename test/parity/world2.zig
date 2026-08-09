const runtime = @import("application_runtime_v1.zig");
const wasm = @import("application_wasm_v1.zig");

pub const Authority = runtime.Authority;
pub const external = runtime.external;
pub const application = runtime.application;
pub const ApplicationAbiV1 = wasm.ApplicationAbi;
