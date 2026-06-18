const world = @import("world");

comptime {
    world.Archive.Conformance.requireMemorySurface();
    const caps = world.Archive.Memory.capabilities();
    if (!caps.wasm_memory_compatible) @compileError("Archive.Memory must remain wasm-memory compatible");
    if (caps.wasm_file_compatible) @compileError("Archive.Memory must not claim wasm file compatibility");
}

export fn world_archive_moment_format_version() u32 {
    return world.Archive.world_archive_moment_format_version;
}

export fn world_archive_format_version() u32 {
    return world.Archive.world_archive_format_version;
}

export fn world_archive_header_fingerprint() u64 {
    return world.Archive.Header.init(.{}).header_fingerprint;
}

export fn world_archive_profile_fingerprint() u64 {
    return world.Archive.Header.init(.{}).archive_profile_fingerprint;
}
