const std = @import("std");
const application_build = @import("build_support/application.zig");

pub const ApplicationWasmMemory = application_build.Memory;
pub const ApplicationWasmOptions = application_build.Options;
pub const ApplicationWasm = application_build.ApplicationWasm;

/// Package one `world.application` declaration as a checked, import-free
/// Application ABI v1 WebAssembly artifact and canonical manifest.
pub fn addApplicationWasm(
    b: *std.Build,
    options: ApplicationWasmOptions,
) ApplicationWasm {
    return application_build.add(b, @This(), options);
}

fn runArtifact(b: *std.Build, artifact: *std.Build.Step.Compile) *std.Build.Step.Run {
    const run = b.addRunArtifact(artifact);
    if (b.args) |args| run.addArgs(args);
    return run;
}

fn addApplicationTest(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    world: *std.Build.Module,
    boundary: *std.Build.Module,
) *std.Build.Step.Compile {
    return b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "boundary", .module = boundary },
        },
    }) });
}

fn configureWitnessWasm(
    wasm: *std.Build.Step.Compile,
    stack_size: u64,
    memory_bytes: u64,
) void {
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.export_memory = true;
    wasm.stack_size = stack_size;
    wasm.initial_memory = memory_bytes;
    wasm.max_memory = memory_bytes;
}

fn addWitnessManifest(
    b: *std.Build,
    name: []const u8,
    application: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) std.Build.LazyPath {
    const emitter = b.addExecutable(.{
        .name = b.fmt("{s}-manifest", .{name}),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/application_manifest_emit_v1.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "world_application", .module = application }},
        }),
    });
    const run = b.addRunArtifact(emitter);
    const manifest = run.addOutputFileArg(b.fmt("{s}.manifest.bin", .{name}));
    _ = run.addOutputFileArg(b.fmt("{s}.manifest.txt", .{name}));
    return manifest;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const validation_target = if (target.result.os.tag == .freestanding) b.graph.host else target;
    const optimize = b.standardOptimizeOption(.{});

    const exported_boundary = b.dependency("boundary", .{
        .target = target,
        .optimize = optimize,
    }).module("boundary");
    const exported_world = b.addModule("world", .{
        .root_source_file = b.path("src/world.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = exported_boundary }},
    });

    const boundary = b.dependency("boundary", .{
        .target = validation_target,
        .optimize = optimize,
    }).module("boundary");
    const world = if (target.result.os.tag == .freestanding) b.createModule(.{
        .root_source_file = b.path("src/world.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) else exported_world;

    const root_tests = b.addTest(.{ .root_module = world });
    const application_golden_tests = addApplicationTest(
        b,
        "test/application_v1_golden_test.zig",
        validation_target,
        optimize,
        world,
        boundary,
    );
    const application_codec_tests = b.addTest(.{
        .root_module = world,
        .filters = &.{
            "world application v1 records round trip canonically",
            "world application v1 StepInput and manifest round trip",
        },
    });
    const application_malformed_tests = b.addTest(.{
        .root_module = world,
        .filters = &.{"world application v1 malformed records fail closed"},
    });
    const application_tests = addApplicationTest(
        b,
        "test/application_v1_test.zig",
        validation_target,
        optimize,
        world,
        boundary,
    );
    const application_fixtures = b.createModule(.{
        .root_source_file = b.path("test/application_v1_test.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "boundary", .module = boundary },
        },
    });
    const agent_tests = addApplicationTest(
        b,
        "test/application_v1_agent_fixtures.zig",
        validation_target,
        optimize,
        world,
        boundary,
    );
    const application_agent_fixtures = b.createModule(.{
        .root_source_file = b.path("test/application_v1_agent_fixtures.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "boundary", .module = boundary },
        },
    });
    const research_application = b.createModule(.{
        .root_source_file = b.path("templates/application-v1/src/application.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "boundary", .module = boundary },
        },
    });
    const research_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/application_v1_research_digest_test.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "research_digest_application", .module = research_application },
        },
    }) });
    const system_tests = addApplicationTest(
        b,
        "test/system_link_v1.zig",
        validation_target,
        optimize,
        world,
        boundary,
    );
    const system_scaling_tests = addApplicationTest(
        b,
        "test/system_link_scaling_v1.zig",
        validation_target,
        optimize,
        world,
        boundary,
    );
    const system_fixtures = b.createModule(.{
        .root_source_file = b.path("test/system_link_v1.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "boundary", .module = boundary },
        },
    });
    const system_topology_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/system_link_topology_v1.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "boundary", .module = boundary },
            .{ .name = "system_v1_fixtures", .module = system_fixtures },
        },
    }) });

    const build_support = b.createModule(.{
        .root_source_file = b.path("build_support/application.zig"),
        .target = validation_target,
        .optimize = optimize,
    });
    const wasm_support = b.createModule(.{
        .root_source_file = b.path("src/application_wasm_v1.zig"),
        .target = validation_target,
        .optimize = optimize,
    });
    const build_option_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/application_build_options_test.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world_application_build_support", .module = build_support },
            .{ .name = "world_application_wasm_v1", .module = wasm_support },
        },
    }) });

    const native_step = b.step("check-world-application-native", "Run the surviving application compiler tests.");
    native_step.dependOn(&runArtifact(b, root_tests).step);
    native_step.dependOn(&runArtifact(b, application_tests).step);
    native_step.dependOn(&runArtifact(b, agent_tests).step);
    native_step.dependOn(&runArtifact(b, research_tests).step);
    native_step.dependOn(&runArtifact(b, build_option_tests).step);
    const machine_v2_step = b.step("check-world-machine-v2", "Run the focused Boundary Machine ABI v2 application proofs.");
    machine_v2_step.dependOn(&runArtifact(b, application_tests).step);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const wasm_boundary = b.dependency("boundary", .{
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    }).module("boundary");
    const wasm_world = b.createModule(.{
        .root_source_file = b.path("src/world.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{.{ .name = "boundary", .module = wasm_boundary }},
    });
    const wasm_fixtures = b.createModule(.{
        .root_source_file = b.path("test/application_v1_test.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "world", .module = wasm_world },
            .{ .name = "boundary", .module = wasm_boundary },
        },
    });
    const wasm_agent_fixtures = b.createModule(.{
        .root_source_file = b.path("test/application_v1_agent_fixtures.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "world", .module = wasm_world },
            .{ .name = "boundary", .module = wasm_boundary },
        },
    });
    const wasm = b.addExecutable(.{
        .name = "one-effect.world",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/world_application_v1_one_effect_wasm.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "world", .module = wasm_world },
                .{ .name = "application_v1_fixtures", .module = wasm_fixtures },
            },
        }),
    });
    configureWitnessWasm(wasm, 1024 * 1024, 8 * 1024 * 1024);
    const wasm_conformance = b.addSystemCommand(&.{ "node", "scripts/world_application_v1_conformance.mjs" });
    wasm_conformance.addFileArg(wasm.getEmittedBin());
    const wasm_step = b.step("check-world-application-wasm", "Build and inspect the import-free bounded-memory application WASM.");
    wasm_step.dependOn(&wasm_conformance.step);

    const native_trace = b.addExecutable(.{
        .name = "one-effect-native-trace",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/application_v1_native_trace.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "application_v1_fixtures", .module = application_fixtures },
            },
        }),
    });
    const run_native_trace = b.addRunArtifact(native_trace);
    const native_trace_file = run_native_trace.addOutputFileArg("one-effect.native-trace.bin");
    const native_wasm_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_machine_native_wasm.mjs" });
    native_wasm_gate.addFileArg(wasm.getEmittedBin());
    native_wasm_gate.addFileArg(native_trace_file);
    const machine_native_wasm_step = b.step("check-world-machine-native-wasm", "Byte-compare the native and wasm32 one-effect Machine lifecycle.");
    machine_native_wasm_step.dependOn(&native_wasm_gate.step);
    const native_wasm_negative_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_machine_native_wasm.mjs", "--negative-self-test" });
    native_wasm_negative_gate.addFileArg(wasm.getEmittedBin());
    native_wasm_negative_gate.addFileArg(native_trace_file);
    const machine_native_wasm_negative_step = b.step("check-world-machine-native-wasm-negative", "Prove the native/wasm lifecycle comparator rejects byte drift.");
    machine_native_wasm_negative_step.dependOn(&native_wasm_negative_gate.step);

    const wasm_skeleton_application = b.createModule(.{
        .root_source_file = b.path("test/application_v1_skeleton_app.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{.{ .name = "application_v1_agent_fixtures", .module = wasm_agent_fixtures }},
    });
    const skeleton_wasm = b.addExecutable(.{
        .name = "skeleton-agent.world",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/world_application_v1_wasm.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "world", .module = wasm_world },
                .{ .name = "world_application", .module = wasm_skeleton_application },
            },
        }),
    });
    configureWitnessWasm(skeleton_wasm, 1024 * 1024, 16 * 1024 * 1024);
    const native_skeleton_application = b.createModule(.{
        .root_source_file = b.path("test/application_v1_skeleton_app.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "application_v1_agent_fixtures", .module = application_agent_fixtures }},
    });
    const skeleton_manifest = addWitnessManifest(b, "skeleton-agent", native_skeleton_application, validation_target, optimize);
    const skeleton_gate = b.addSystemCommand(&.{ "node", "scripts/world_application_v1_agent_conformance.mjs" });
    skeleton_gate.addFileArg(skeleton_wasm.getEmittedBin());
    skeleton_gate.addArg("skeleton");
    skeleton_gate.addFileArg(skeleton_manifest);
    const skeleton_step = b.step("check-world-skeleton-agent", "Prove the retained skeleton agent application witness.");
    skeleton_step.dependOn(&skeleton_gate.step);

    const wasm_fixture_application = b.createModule(.{
        .root_source_file = b.path("test/application_v1_fixture_app.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{.{ .name = "application_v1_agent_fixtures", .module = wasm_agent_fixtures }},
    });
    const fixture_wasm = b.addExecutable(.{
        .name = "fixture-agent.world",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/world_application_v1_wasm.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "world", .module = wasm_world },
                .{ .name = "world_application", .module = wasm_fixture_application },
            },
        }),
    });
    configureWitnessWasm(fixture_wasm, 1024 * 1024, 16 * 1024 * 1024);
    const native_fixture_application = b.createModule(.{
        .root_source_file = b.path("test/application_v1_fixture_app.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "application_v1_agent_fixtures", .module = application_agent_fixtures }},
    });
    const fixture_manifest = addWitnessManifest(b, "fixture-agent", native_fixture_application, validation_target, optimize);
    const fixture_gate = b.addSystemCommand(&.{ "node", "scripts/world_application_v1_agent_conformance.mjs" });
    fixture_gate.addFileArg(fixture_wasm.getEmittedBin());
    fixture_gate.addArg("fixture");
    fixture_gate.addFileArg(fixture_manifest);
    const fixture_step = b.step("check-world-fixture-agent", "Prove the retained fixture agent application witness.");
    fixture_step.dependOn(&fixture_gate.step);

    const wasm_research_source = b.createModule(.{
        .root_source_file = b.path("templates/application-v1/src/application.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "world", .module = wasm_world },
            .{ .name = "boundary", .module = wasm_boundary },
        },
    });
    const wasm_research_application = b.createModule(.{
        .root_source_file = b.path("test/application_v1_research_digest_app.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "world", .module = wasm_world },
            .{ .name = "research_digest_application", .module = wasm_research_source },
        },
    });
    const research_wasm = b.addExecutable(.{
        .name = "research-digest-agent.world",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/world_application_v1_wasm.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "world", .module = wasm_world },
                .{ .name = "world_application", .module = wasm_research_application },
            },
        }),
    });
    configureWitnessWasm(research_wasm, 4 * 1024 * 1024, 36 * 1024 * 1024);
    const native_research_application = b.createModule(.{
        .root_source_file = b.path("test/application_v1_research_digest_app.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "research_digest_application", .module = research_application },
        },
    });
    const research_manifest = addWitnessManifest(b, "research-digest-agent", native_research_application, validation_target, optimize);
    const research_gate = b.addSystemCommand(&.{ "node", "scripts/world_application_v1_research_digest_conformance.mjs" });
    research_gate.addFileArg(research_wasm.getEmittedBin());
    research_gate.addFileArg(research_manifest);
    const research_step = b.step("check-world-research-digest-v2", "Prove retained Research Digest Machine-owned formatting and lifecycle behavior.");
    research_step.dependOn(&runArtifact(b, research_tests).step);
    research_step.dependOn(&research_gate.step);
    const research_negative_gate = b.addSystemCommand(&.{ "node", "scripts/world_application_v1_research_digest_conformance.mjs", "--negative-self-test" });
    research_negative_gate.addFileArg(research_wasm.getEmittedBin());
    research_negative_gate.addFileArg(research_manifest);
    const research_negative_step = b.step("check-world-research-digest-v2-negative", "Prove the Research Digest comparator rejects expected result drift.");
    research_negative_step.dependOn(&research_negative_gate.step);

    const one_effect_step = b.step("check-world-one-effect", "Prove the retained one-effect application witness.");
    one_effect_step.dependOn(&wasm_conformance.step);
    one_effect_step.dependOn(machine_native_wasm_step);
    const witnesses_step = b.step("check-world-witnesses", "Run all retained application-specific witness lanes.");
    witnesses_step.dependOn(one_effect_step);
    witnesses_step.dependOn(skeleton_step);
    witnesses_step.dependOn(fixture_step);
    witnesses_step.dependOn(research_step);

    const external_consumer_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_external_consumer.mjs", "--zig" });
    external_consumer_gate.addArg(b.graph.zig_exe);
    const external_step = b.step("check-world-external-consumer", "Build a World application from only the materialized candidate package archive.");
    external_step.dependOn(&external_consumer_gate.step);

    const forged_identity = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/compile_fail/application_v1_forged_package_identity.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "application_v1_fixtures", .module = application_fixtures },
        },
    }) });
    forged_identity.expect_errors = .{
        .contains = "world.application owns the World 3.1.4 / Boundary 1.6.1 package identity",
    };

    const compile_fail_step = b.step("compile-fail", "Run the surviving application compiler negative witnesses.");
    compile_fail_step.dependOn(&forged_identity.step);
    for ([_]struct { path: []const u8, message: []const u8 }{
        .{ .path = "test/compile_fail/application_v1_missing_binding.zig", .message = "World application has an unhandled operation site; declare an internal handler or explicit external effect" },
        .{ .path = "test/compile_fail/application_v1_ambiguous_binding.zig", .message = "World application operation site has ambiguous handler ownership" },
        .{ .path = "test/compile_fail/application_v1_incompatible_provider.zig", .message = "World Machine provider InitialArgs must exactly match the parent payload type" },
        .{ .path = "test/compile_fail/application_v1_provider_cycle.zig", .message = "World application internal provider graph contains a static cycle" },
        .{ .path = "test/compile_fail/application_v1_provider_depth.zig", .message = "World application internal provider graph exceeds maximum_provider_depth" },
        .{ .path = "test/compile_fail/application_v1_external_zero_result_limit.zig", .message = "World external maximum_result_bytes must be positive" },
        .{ .path = "test/compile_fail/application_v1_external_oversized_result_limit.zig", .message = "World external maximum_result_bytes exceeds the application maximum_result_bytes" },
        .{ .path = "test/compile_fail/application_v1_provider_state_capacity.zig", .message = "World application provider stack exceeds maximum_state_bytes" },
        .{ .path = "test/compile_fail/application_v1_site_identity_mismatch.zig", .message = "World Machine site_identity does not match the selected effect-site ordinal" },
        .{ .path = "test/compile_fail/application_v1_duplicate_site_identity.zig", .message = "World application requires unique semantic_identity values for every reachable Machine effect site" },
        .{ .path = "test/compile_fail/application_v1_wasm_region_too_small.zig", .message = "World application WASM input region is smaller than the declared StepInput limits" },
    }) |witness| {
        const negative = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(witness.path),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "application_v1_fixtures", .module = application_fixtures },
            },
        }) });
        negative.expect_errors = .{ .contains = witness.message };
        compile_fail_step.dependOn(&negative.step);
    }
    const system_negative_step = b.step(
        "check-world-system-link-v1-negative",
        "Reject invalid World System Linker graphs and type relations.",
    );
    for ([_]struct { path: []const u8, message: []const u8 }{
        .{ .path = "test/compile_fail/system_v1_uncovered_effect.zig", .message = "World system has an uncovered non-external effect site" },
        .{ .path = "test/compile_fail/system_v1_ambiguous_handler.zig", .message = "World system effect site has ambiguous disposition" },
        .{ .path = "test/compile_fail/system_v1_incompatible_provider.zig", .message = "World system provider InitialArgs must match effect Payload" },
        .{ .path = "test/compile_fail/system_v1_failure_mismatch.zig", .message = "World system provider Failure requires an explicit pure total morphism" },
        .{ .path = "test/compile_fail/system_v1_duplicate_external.zig", .message = "World system has duplicate external declarations" },
        .{ .path = "test/compile_fail/system_v1_morphism_mismatch.zig", .message = "World system effect morphism must preserve Payload and Resume" },
        .{ .path = "test/compile_fail/system_v1_handler_cycle.zig", .message = "World system internal handler graph contains a cycle" },
        .{ .path = "test/compile_fail/system_v1_unreachable_external.zig", .message = "World system has an unreachable external declaration" },
        .{ .path = "test/compile_fail/system_v1_forged_failure_map.zig", .message = "World system Failure morphism must cover every source tag" },
        .{ .path = "test/compile_fail/system_v1_forged_component.zig", .message = "Boundary component admission requires a canonical Boundary Program" },
        .{ .path = "test/compile_fail/system_v1_duplicate_residual_identity.zig", .message = "World system residual effects require unique semantic identities" },
    }) |witness| {
        const negative = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(witness.path),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "system_v1_fixtures", .module = system_fixtures },
            },
        }) });
        negative.expect_errors = .{ .contains = witness.message };
        system_negative_step.dependOn(&negative.step);
    }

    const application_golden_step = b.step("check-world-application-v1-goldens", "Freeze and round-trip the canonical Application ABI v1 byte corpus.");
    application_golden_step.dependOn(&runArtifact(b, application_golden_tests).step);

    const application_codec_step = b.step("check-world-application-v1-codecs", "Run the focused Application ABI v1 codec proofs.");
    application_codec_step.dependOn(&runArtifact(b, application_codec_tests).step);

    const application_negative_step = b.step("check-world-application-v1-negative", "Run malformed-record and comptime compile-fail witnesses for Application ABI v1.");
    application_negative_step.dependOn(&runArtifact(b, application_malformed_tests).step);
    application_negative_step.dependOn(compile_fail_step);

    const application_v1_step = b.step("check-world-application-v1", "Run the complete focused Application ABI v1 proof.");
    application_v1_step.dependOn(application_golden_step);
    application_v1_step.dependOn(application_codec_step);
    application_v1_step.dependOn(application_negative_step);

    const system_link_step = b.step(
        "check-world-system-link-v1",
        "Link Boundary Program components into one ordinary BPI1.",
    );
    system_link_step.dependOn(&runArtifact(b, system_tests).step);
    system_link_step.dependOn(&runArtifact(b, system_scaling_tests).step);
    system_link_step.dependOn(&runArtifact(b, system_topology_tests).step);
    system_link_step.dependOn(system_negative_step);

    const dependency_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_boundary_dependency.mjs" });
    const dependency_step = b.step("check-world-boundary-dependency", "Require the sole exact Boundary v1.6.1 package dependency.");
    dependency_step.dependOn(&dependency_gate.step);
    const dependency_negative_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_boundary_dependency.mjs", "--negative-self-test" });
    const dependency_negative_step = b.step("check-world-boundary-dependency-negative", "Prove the dependency checker rejects an injected legacy dependency.");
    dependency_negative_step.dependOn(&dependency_negative_gate.step);
    const surface_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_public_surface.mjs" });
    const surface_step = b.step("check-world-public-surface", "Require the exact canonical World public root and protocol.v1 surface.");
    surface_step.dependOn(&surface_gate.step);
    const surface_negative_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_public_surface.mjs", "--negative-self-test" });
    const surface_negative_step = b.step("check-world-public-surface-negative", "Prove the public-surface checker rejects an injected legacy declaration.");
    surface_negative_step.dependOn(&surface_negative_gate.step);
    const source_archive_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_source_archive.mjs" });
    const source_archive_negative_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_source_archive.mjs", "--negative-self-test" });
    const source_archive_step = b.step("check-world-source-archive", "Build and inspect the normalized World source archive against the fixed baseline.");
    source_archive_step.dependOn(&source_archive_gate.step);
    source_archive_step.dependOn(&source_archive_negative_gate.step);
    const lint_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_lint.mjs", "--zig" });
    lint_gate.addArg(b.graph.zig_exe);
    if (b.args) |args| lint_gate.addArgs(args);
    const lint_step = b.step("lint", "Format-check every tracked Zig source with zero warnings.");
    lint_step.dependOn(&lint_gate.step);
    const singularity_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_singularity.mjs" });
    const singularity_step = b.step("check-world-singularity", "Fail closed unless World has one canonical application compiler surface.");
    singularity_step.dependOn(dependency_step);
    singularity_step.dependOn(surface_step);
    singularity_step.dependOn(source_archive_step);
    singularity_step.dependOn(&singularity_gate.step);
    singularity_step.dependOn(compile_fail_step);
    const singularity_negative_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_singularity.mjs", "--negative-self-test" });
    const singularity_negative_step = b.step("check-world-singularity-negative", "Prove the singularity checker rejects an injected legacy package surface.");
    singularity_negative_step.dependOn(&singularity_negative_gate.step);

    const parity_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_2_3_parity.mjs", "--zig" });
    parity_gate.addArg(b.graph.zig_exe);
    const parity_step = b.step("check-world-2-3-parity", "Prove fixed-identity World 2 and World 3 application artifacts and lifecycles are byte-identical.");
    parity_step.dependOn(&parity_gate.step);
    const parity_negative_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_2_3_parity.mjs", "--negative-self-test", "--zig" });
    parity_negative_gate.addArg(b.graph.zig_exe);
    const parity_negative_step = b.step("check-world-2-3-parity-negative", "Prove the World 2 / World 3 parity comparator rejects lifecycle drift.");
    parity_negative_step.dependOn(&parity_negative_gate.step);

    const externality_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_3_externality.mjs" });
    externality_gate.addFileArg(wasm.getEmittedBin());
    const externality_step = b.step("check-world-3-externality", "Prove World 3 applications run through the exact released generic world-host without source checkouts or Zig.");
    externality_step.dependOn(&externality_gate.step);
    externality_step.dependOn(external_step);
    const externality_negative_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_3_externality.mjs", "--negative-self-test" });
    const externality_negative_step = b.step("check-world-3-externality-negative", "Prove the exact world-host release authenticator rejects archive drift.");
    externality_negative_step.dependOn(&externality_negative_gate.step);
    const deterministic_retry_step = b.step("check-world-deterministic-retry", "Prove deterministic retry through the exact generic world-host.");
    deterministic_retry_step.dependOn(externality_step);
    const replay_step = b.step("check-world-replay", "Prove retained-result replay through the exact generic world-host.");
    replay_step.dependOn(externality_step);
    const branching_step = b.step("check-world-branching", "Prove immutable parent branching through the exact generic world-host.");
    branching_step.dependOn(externality_step);
    const migration_step = b.step("check-world-migration", "Prove receiver-preflight migration through the exact generic world-host.");
    migration_step.dependOn(externality_step);

    const sdk_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_sdk_v3.mjs", "--zig" });
    sdk_gate.addArg(b.graph.zig_exe);
    const sdk_step = b.step("check-world-sdk-v3", "Authenticate the four released components and prove the standalone World SDK v3 lifecycle.");
    sdk_step.dependOn(&sdk_gate.step);

    const application_step = b.step("check-world-application", "Prove native, WASM, and external application compilation.");
    application_step.dependOn(application_v1_step);
    application_step.dependOn(native_step);
    application_step.dependOn(wasm_step);
    application_step.dependOn(external_step);

    const check = b.step("check", "Run the complete World 3 compiler proof.");
    check.dependOn(singularity_step);
    check.dependOn(singularity_negative_step);
    check.dependOn(application_step);
    check.dependOn(application_v1_step);
    check.dependOn(system_link_step);
    check.dependOn(compile_fail_step);
    check.dependOn(dependency_step);
    check.dependOn(dependency_negative_step);
    check.dependOn(surface_step);
    check.dependOn(surface_negative_step);
    check.dependOn(parity_step);
    check.dependOn(parity_negative_step);
    check.dependOn(externality_step);
    check.dependOn(externality_negative_step);
    check.dependOn(sdk_step);
    check.dependOn(machine_v2_step);
    check.dependOn(machine_native_wasm_step);
    check.dependOn(machine_native_wasm_negative_step);
    check.dependOn(one_effect_step);
    check.dependOn(skeleton_step);
    check.dependOn(fixture_step);
    check.dependOn(research_step);
    check.dependOn(research_negative_step);
    check.dependOn(witnesses_step);
    check.dependOn(external_step);
    check.dependOn(source_archive_step);
    check.dependOn(lint_step);
}
