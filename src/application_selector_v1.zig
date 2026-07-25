const application_source = @import("world_application_source");
const build_options = @import("world_application_build_options");

/// Application type selected by World’s public build helper.
pub const App = blk: {
    if (!@hasDecl(application_source, build_options.application_decl)) {
        @compileError(
            "World application source is missing public declaration '" ++
                build_options.application_decl ++
                "'",
        );
    }
    const candidate = @field(application_source, build_options.application_decl);
    if (@TypeOf(candidate) != type) {
        @compileError(
            "World application declaration '" ++
                build_options.application_decl ++
                "' must be a type returned by world.application",
        );
    }
    break :blk candidate;
};
