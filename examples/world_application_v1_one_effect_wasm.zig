const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const Abi = world.ApplicationAbiV1(fixtures.OneEffectApp, .{
    .input_capacity = 1024 * 1024,
    .output_capacity = 1024 * 1024,
    .scratch_capacity = 4 * 1024 * 1024,
});

pub export fn world_abi_version() u32 {
    return Abi.worldAbiVersion();
}

pub export fn world_manifest_ptr() u32 {
    return Abi.worldManifestPtr();
}

pub export fn world_manifest_len() u32 {
    return Abi.worldManifestLen();
}

pub export fn world_input_ptr() u32 {
    return Abi.worldInputPtr();
}

pub export fn world_input_capacity() u32 {
    return Abi.worldInputCapacity();
}

pub export fn world_step(input_len: u32) u32 {
    return Abi.worldStep(input_len);
}

pub export fn world_output_ptr() u32 {
    return Abi.worldOutputPtr();
}

pub export fn world_output_len() u32 {
    return Abi.worldOutputLen();
}

pub export fn world_error_ptr() u32 {
    return Abi.worldErrorPtr();
}

pub export fn world_error_len() u32 {
    return Abi.worldErrorLen();
}

pub export fn world_reset() u32 {
    return Abi.worldReset();
}
