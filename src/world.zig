const application_protocol = @import("application_v1.zig");
const application_runtime = @import("application_runtime_v1.zig");
const application_wasm = @import("application_wasm_v1.zig");
const system_link = @import("system_v1.zig");

/// Canonical World wire protocols.
pub const protocol = struct {
    pub const v1 = struct {
        pub const format_version = application_protocol.format_version;
        pub const abi_version = application_protocol.abi_version;
        pub const Digest = application_protocol.Digest;
        pub const zero_digest = application_protocol.zero_digest;
        pub const Error = application_protocol.Error;
        pub const Limits = application_protocol.Limits;
        pub const EffectStatus = application_protocol.EffectStatus;
        pub const AllowedStatuses = application_protocol.AllowedStatuses;
        pub const EffectLimits = application_protocol.EffectLimits;
        pub const EffectRequest = application_protocol.EffectRequest;
        pub const EffectResult = application_protocol.EffectResult;
        pub const FrameStatus = application_protocol.FrameStatus;
        pub const ResourceCounters = application_protocol.ResourceCounters;
        pub const Frame = application_protocol.Frame;
        pub const StepInput = application_protocol.StepInput;
        pub const ResidualEffect = application_protocol.ResidualEffect;
        pub const ApplicationManifest = application_protocol.ApplicationManifest;
        pub const digestLabel = application_protocol.digestLabel;
        pub const validateResultForRequest = application_protocol.validateResultForRequest;
    };
};

pub const Authority = application_runtime.Authority;
pub const ResponseMode = application_runtime.ResponseMode;
pub const handle = application_runtime.handle;
pub const external = application_runtime.external;
pub const application = application_runtime.application;
pub const valueSchemaId = application_runtime.valueSchemaId;
pub const siteId = application_runtime.siteId;
pub const encodeValue = application_runtime.encodeValue;

/// Bind one typed Boundary Program effect to an internal provider Program.
pub const systemHandle = system_link.handle;
/// Bind one typed Boundary Program effect to a residual effect morphism.
pub const systemMorphism = system_link.morphism;
/// Map one provider Failure enum into the root system Failure enum.
pub const failureMorphism = system_link.failureMorphism;
/// Link one acyclic Boundary Program graph into one ordinary closed Program.
pub const system = system_link.system;

pub const WasmOptions = application_wasm.Options;
pub const WasmStatus = application_wasm.Status;
pub const ApplicationAbiV1 = application_wasm.ApplicationAbiV1;

test {
    _ = application_protocol;
    _ = application_runtime;
    _ = application_wasm;
    _ = system_link;
}
