const research_digest = @import("research_digest_application");
const world = @import("world");

pub const App = research_digest.Application;
pub const WasmOptions: world.WasmOptions = .{
    .input_capacity = 2 * 1024 * 1024,
    .output_capacity = 4 * 1024 * 1024,
    .scratch_capacity = 16 * 1024 * 1024,
};
