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
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.export_memory = true;
    wasm.stack_size = 1024 * 1024;
    wasm.initial_memory = 8 * 1024 * 1024;
    wasm.max_memory = 8 * 1024 * 1024;
    const wasm_conformance = b.addSystemCommand(&.{ "node", "scripts/world_application_v1_conformance.mjs" });
    wasm_conformance.addFileArg(wasm.getEmittedBin());
    const wasm_step = b.step("check-world-application-wasm", "Build and inspect the import-free bounded-memory application WASM.");
    wasm_step.dependOn(&wasm_conformance.step);

    const external_build = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "--summary", "all" });
    external_build.setCwd(b.path("conformance/external-build-helper"));
    const external_step = b.step("check-world-external-build-helper", "Build an application through public addApplicationWasm.");
    external_step.dependOn(&external_build.step);

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
        .contains = "world.application owns the World 3.0.0 / Boundary 1.0.0 package identity",
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

    const dependency_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_boundary_dependency.mjs" });
    const surface_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_public_surface.mjs" });
    const singularity_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_singularity.mjs" });
    const singularity_step = b.step("check-world-singularity", "Fail closed unless World has one canonical application compiler surface.");
    singularity_step.dependOn(&dependency_gate.step);
    singularity_step.dependOn(&surface_gate.step);
    singularity_step.dependOn(&singularity_gate.step);
    singularity_step.dependOn(compile_fail_step);
    const singularity_negative_gate = b.addSystemCommand(&.{ "node", "scripts/check_world_singularity.mjs", "--negative-self-test" });
    const singularity_negative_step = b.step("check-world-singularity-negative", "Prove the singularity checker rejects an injected legacy package surface.");
    singularity_negative_step.dependOn(&singularity_negative_gate.step);

    const application_step = b.step("check-world-application", "Prove native, WASM, and external application compilation.");
    application_step.dependOn(native_step);
    application_step.dependOn(wasm_step);
    application_step.dependOn(external_step);

    const check = b.step("check", "Run the complete World 3 application compiler proof.");
    check.dependOn(singularity_step);
    check.dependOn(singularity_negative_step);
    check.dependOn(application_step);
}
