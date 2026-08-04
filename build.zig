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

const TestArgs = struct {
    filters: []const []const u8,
    passthrough: []const []const u8,
};

fn parseTestArgs(b: *std.Build) TestArgs {
    const args = b.args orelse return .{ .filters = &.{}, .passthrough = &.{} };
    var filters: std.ArrayList([]const u8) = .empty;
    var passthrough: std.ArrayList([]const u8) = .empty;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--test-filter")) {
            index += 1;
            if (index >= args.len) std.process.fatal("missing --test-filter value", .{});
            filters.append(b.allocator, args[index]) catch @panic("oom");
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--test-filter=")) {
            filters.append(b.allocator, arg["--test-filter=".len..]) catch @panic("oom");
            continue;
        }
        passthrough.append(b.allocator, arg) catch @panic("oom");
    }
    return .{
        .filters = filters.toOwnedSlice(b.allocator) catch @panic("oom"),
        .passthrough = passthrough.toOwnedSlice(b.allocator) catch @panic("oom"),
    };
}

fn addRunArtifactWithArgs(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    args: []const []const u8,
) *std.Build.Step.Run {
    const run = b.addRunArtifact(artifact);
    if (args.len != 0) run.addArgs(args);
    return run;
}

fn dependOnNativeRunOrCompile(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    step: *std.Build.Step,
    artifact: *std.Build.Step.Compile,
    args: []const []const u8,
) void {
    if (target.query.isNative()) {
        step.dependOn(&addRunArtifactWithArgs(b, artifact, args).step);
    } else {
        step.dependOn(&artifact.step);
    }
}

const world_source_package_root_files = [_][]const u8{
    "README.md",
    "build.zig",
    "build.zig.zon",
};

const world_source_package_dirs = [_][]const u8{
    "build_support",
    "src",
    "examples",
    "scripts",
    "test",
    "docs",
    "conformance",
    "templates",
};

fn addWorldSourcePackageInputs(b: *std.Build, run: *std.Build.Step.Run) void {
    var paths: std.ArrayList([]const u8) = .empty;

    for (world_source_package_root_files) |path| {
        paths.append(b.allocator, b.dupe(path)) catch @panic("oom");
    }

    for (world_source_package_dirs) |root| {
        var dir = b.build_root.handle.openDir(b.graph.io, root, .{ .iterate = true }) catch |err| {
            std.debug.panic("failed to open source package directory '{s}': {s}", .{ root, @errorName(err) });
        };
        defer dir.close(b.graph.io);

        var walker = dir.walk(b.allocator) catch @panic("oom");
        defer walker.deinit();
        while (walker.next(b.graph.io) catch |err| {
            std.debug.panic("failed to walk source package directory '{s}': {s}", .{ root, @errorName(err) });
        }) |entry| {
            if (entry.kind != .file or sourcePackagePathExcluded(entry.path)) continue;
            paths.append(b.allocator, b.fmt("{s}/{s}", .{ root, entry.path })) catch @panic("oom");
        }
    }

    std.mem.sort([]const u8, paths.items, {}, sourcePathLessThan);
    for (paths.items) |path| run.addFileInput(b.path(path));
}

fn sourcePathLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn sourcePackagePathExcluded(path: []const u8) bool {
    var components = std.mem.tokenizeAny(u8, path, "/\\");
    while (components.next()) |component| {
        if (std.mem.eql(u8, component, ".git") or
            std.mem.eql(u8, component, ".zig-cache") or
            std.mem.eql(u8, component, "zig-out") or
            std.mem.eql(u8, component, "zig-pkg"))
        {
            return true;
        }
    }
    return false;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const validation_target = if (target.result.os.tag == .freestanding) b.graph.host else target;
    const optimize = b.standardOptimizeOption(.{});
    const test_args = parseTestArgs(b);
    const init_world_application = b.addSystemCommand(&.{"node"});
    init_world_application.addFileArg(b.path(
        "scripts/init_world_application.mjs",
    ));
    if (b.args) |args| init_world_application.addArgs(args);
    const init_world_application_step = b.step(
        "init-world-application",
        "Copy the Application v1 template with an exact World release identity.",
    );
    init_world_application_step.dependOn(&init_world_application.step);
    const exported_boundary_dep = b.dependency("boundary", .{
        .target = target,
        .optimize = optimize,
    });
    const exported_boundary = exported_boundary_dep.module("boundary");
    const exported_boundary_machine_dep = b.dependency("boundary_machine", .{
        .target = target,
        .optimize = optimize,
    });
    const exported_boundary_machine = exported_boundary_machine_dep.module("boundary");

    const exported_world = b.addModule("world", .{
        .root_source_file = b.path("src/world.zig"),
        .target = target,
        .optimize = optimize,
    });
    exported_world.addImport("boundary", exported_boundary);
    exported_world.addImport("boundary_machine", exported_boundary_machine);

    const boundary_dep = b.dependency("boundary", .{
        .target = validation_target,
        .optimize = optimize,
    });
    const boundary = boundary_dep.module("boundary");
    const boundary_machine_dep = b.dependency("boundary_machine", .{
        .target = validation_target,
        .optimize = optimize,
    });
    const boundary_machine = boundary_machine_dep.module("boundary");
    const world = if (target.result.os.tag == .freestanding) blk: {
        const validation_world = b.createModule(.{
            .root_source_file = b.path("src/world.zig"),
            .target = validation_target,
            .optimize = optimize,
        });
        validation_world.addImport("boundary", boundary);
        validation_world.addImport("boundary_machine", boundary_machine);
        break :blk validation_world;
    } else exported_world;
    const world_target_check = b.addLibrary(.{
        .linkage = .static,
        .name = "world-target-check",
        .root_module = exported_world,
    });
    const check_world_target_step = b.step("check-world-target", "Compile the exported World module for the requested target.");
    check_world_target_step.dependOn(&world_target_check.step);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const wasm_guest_module = b.createModule(.{
        .root_source_file = b.path("examples/world_wasm_guest_one_port.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    const wasm_guest = b.addExecutable(.{
        .name = "world_wasm_guest_one_port",
        .root_module = wasm_guest_module,
    });
    wasm_guest.entry = .disabled;
    wasm_guest.rdynamic = true;
    wasm_guest.export_memory = true;
    const install_wasm_guest = b.addInstallArtifact(wasm_guest, .{});
    const world_wasm_step = b.step("world-wasm", "Build World wasm guest artifacts.");
    world_wasm_step.dependOn(&install_wasm_guest.step);
    const check_world_wasm_step = b.step("check-world-wasm", "Build and inspect World wasm guest artifacts.");
    check_world_wasm_step.dependOn(&wasm_guest.step);

    const wasm_boundary_dep = b.dependency("boundary", .{
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    const wasm_boundary = wasm_boundary_dep.module("boundary");
    const wasm_boundary_machine_dep = b.dependency("boundary_machine", .{
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    const wasm_boundary_machine = wasm_boundary_machine_dep.module("boundary");
    const wasm_world = b.createModule(.{
        .root_source_file = b.path("src/world.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    wasm_world.addImport("boundary", wasm_boundary);
    wasm_world.addImport("boundary_machine", wasm_boundary_machine);
    const archive_wasm_probe = b.addExecutable(.{
        .name = "world_archive_wasm_probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/world_archive_wasm_probe.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "world", .module = wasm_world },
            },
        }),
    });
    archive_wasm_probe.entry = .disabled;
    archive_wasm_probe.rdynamic = true;
    const install_archive_wasm_probe = b.addInstallArtifact(archive_wasm_probe, .{});
    const world_archive_wasm_step = b.step("world-archive-wasm", "Build World Archive wasm probe artifact.");
    world_archive_wasm_step.dependOn(&install_archive_wasm_probe.step);
    const check_world_archive_wasm_step = b.step("check-world-archive-wasm", "Build and inspect World Archive wasm probe artifact.");
    check_world_archive_wasm_step.dependOn(&archive_wasm_probe.step);
    check_world_wasm_step.dependOn(&archive_wasm_probe.step);

    const fixtures = b.createModule(.{
        .root_source_file = b.path("test/fixtures.zig"),
        .target = validation_target,
        .optimize = optimize,
    });
    fixtures.addImport("world", world);
    fixtures.addImport("boundary", boundary);

    const host_boundary_dep = b.dependency("boundary", .{
        .target = b.graph.host,
        .optimize = optimize,
    });
    const host_boundary = host_boundary_dep.module("boundary");
    const host_boundary_machine_dep = b.dependency("boundary_machine", .{
        .target = b.graph.host,
        .optimize = optimize,
    });
    const host_boundary_machine = host_boundary_machine_dep.module("boundary");
    const host_world = b.createModule(.{
        .root_source_file = b.path("src/world.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    host_world.addImport("boundary", host_boundary);
    host_world.addImport("boundary_machine", host_boundary_machine);
    const host_fixtures = b.createModule(.{
        .root_source_file = b.path("test/fixtures.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    host_fixtures.addImport("world", host_world);
    host_fixtures.addImport("boundary", host_boundary);

    const wasm_fixtures = b.createModule(.{
        .root_source_file = b.path("test/fixtures.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    wasm_fixtures.addImport("world", wasm_world);
    wasm_fixtures.addImport("boundary", wasm_boundary);
    const appliance_wasm_module = b.createModule(.{
        .root_source_file = b.path("examples/world_appliance_agent_wasm.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    appliance_wasm_module.addImport("world", wasm_world);
    appliance_wasm_module.addImport("world_fixtures", wasm_fixtures);
    const appliance_wasm = b.addExecutable(.{
        .name = "world_appliance_agent_wasm",
        .root_module = appliance_wasm_module,
    });
    appliance_wasm.entry = .disabled;
    appliance_wasm.rdynamic = true;
    appliance_wasm.export_memory = true;
    appliance_wasm.initial_memory = 4_259_840;
    appliance_wasm.max_memory = 4_259_840;
    const install_appliance_wasm = b.addInstallArtifact(appliance_wasm, .{});
    const world_appliance_wasm_step = b.step("world-appliance-wasm", "Build World Appliance wasm artifact.");
    world_appliance_wasm_step.dependOn(&install_appliance_wasm.step);
    const check_world_appliance_wasm_step = b.step("check-world-appliance-wasm", "Build and inspect World Appliance wasm artifact.");
    check_world_appliance_wasm_step.dependOn(&appliance_wasm.step);
    const universal_appliance_wasm_module = b.createModule(.{
        .root_source_file = b.path("examples/world_universal_appliance_wasm.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    universal_appliance_wasm_module.addImport("world", wasm_world);
    const universal_appliance_wasm = b.addExecutable(.{
        .name = "world_universal_appliance",
        .root_module = universal_appliance_wasm_module,
    });
    universal_appliance_wasm.entry = .disabled;
    universal_appliance_wasm.rdynamic = true;
    universal_appliance_wasm.export_memory = true;
    universal_appliance_wasm.stack_size = 16_777_216;
    universal_appliance_wasm.initial_memory = 67_108_864;
    universal_appliance_wasm.max_memory = 67_108_864;
    const universal_appliance_wasm_repro_module = b.createModule(.{
        .root_source_file = b.path("examples/world_universal_appliance_wasm.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    universal_appliance_wasm_repro_module.addImport("world", wasm_world);
    const universal_appliance_wasm_repro = b.addExecutable(.{
        .name = "world_universal_appliance_repro",
        .root_module = universal_appliance_wasm_repro_module,
    });
    universal_appliance_wasm_repro.entry = .disabled;
    universal_appliance_wasm_repro.rdynamic = true;
    universal_appliance_wasm_repro.export_memory = true;
    universal_appliance_wasm_repro.stack_size = 16_777_216;
    universal_appliance_wasm_repro.initial_memory = 67_108_864;
    universal_appliance_wasm_repro.max_memory = 67_108_864;
    const install_universal_appliance_wasm = b.addInstallArtifact(universal_appliance_wasm, .{});
    const world_universal_appliance_wasm_step = b.step("world-universal-appliance-wasm", "Build World universal Appliance ABI conformance wasm artifact.");
    world_universal_appliance_wasm_step.dependOn(&install_universal_appliance_wasm.step);
    const check_world_universal_appliance_wasm_step = b.step("check-world-universal-appliance-wasm", "Build and inspect World universal Appliance ABI conformance wasm artifact.");
    check_world_universal_appliance_wasm_step.dependOn(&universal_appliance_wasm.step);
    const universal_fixture_mod = b.createModule(.{
        .root_source_file = b.path("examples/world_universal_appliance_fixtures.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    const boundary_agent_runtime_mod = b.createModule(.{
        .root_source_file = host_boundary_dep.path("examples/agent_loop.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    boundary_agent_runtime_mod.addImport("boundary", host_boundary);
    universal_fixture_mod.addImport("world", host_world);
    universal_fixture_mod.addImport("world_fixtures", host_fixtures);
    universal_fixture_mod.addImport("boundary_agent_runtime", boundary_agent_runtime_mod);
    const universal_fixture_gen = b.addExecutable(.{ .name = "world-universal-appliance-fixtures", .root_module = universal_fixture_mod });
    const run_universal_fixture_gen = b.addRunArtifact(universal_fixture_gen);
    const universal_image_a = run_universal_fixture_gen.addOutputFileArg("world-universal-image-a.bin");
    const universal_command_a = run_universal_fixture_gen.addOutputFileArg("world-universal-command-a.bin");
    const universal_image_b = run_universal_fixture_gen.addOutputFileArg("world-universal-image-b.bin");
    const universal_command_b = run_universal_fixture_gen.addOutputFileArg("world-universal-command-b.bin");
    const universal_proof = run_universal_fixture_gen.addOutputFileArg("world-universal-proof.txt");
    const world_agent_runtime_dist_dir = "zig-out/dist/world-v0.1.0/agent-runtime";
    const world_agent_runtime_check_dir = "zig-out/check/world-agent-runtime";
    const run_world_agent_runtime_artifact_gen = b.addRunArtifact(universal_fixture_gen);
    run_world_agent_runtime_artifact_gen.addArgs(&.{
        "--agent-runtime",
        world_agent_runtime_dist_dir,
    });
    const run_world_agent_runtime_artifact_check_gen = b.addRunArtifact(universal_fixture_gen);
    run_world_agent_runtime_artifact_check_gen.addArgs(&.{
        "--agent-runtime",
        world_agent_runtime_check_dir,
    });
    const check_world_agent_runtime_artifacts_cmd = b.addRunArtifact(universal_fixture_gen);
    check_world_agent_runtime_artifacts_cmd.addArgs(&.{
        "--check-agent-runtime",
        world_agent_runtime_check_dir,
    });
    check_world_agent_runtime_artifacts_cmd.step.dependOn(&run_world_agent_runtime_artifact_check_gen.step);
    const emit_world_agent_runtime_artifacts_step = b.step("emit-world-agent-runtime-artifacts", "Emit World-owned Agent Runtime executable image and appliance manifest artifacts.");
    emit_world_agent_runtime_artifacts_step.dependOn(&run_world_agent_runtime_artifact_gen.step);
    const check_world_agent_runtime_artifacts_step = b.step("check-world-agent-runtime-artifacts", "Validate World-owned Agent Runtime export artifacts exist and are non-empty.");
    check_world_agent_runtime_artifacts_step.dependOn(&check_world_agent_runtime_artifacts_cmd.step);
    const run_universal_appliance_node = b.addSystemCommand(&.{
        "node",
        "scripts/world_universal_appliance_conformance.mjs",
    });
    run_universal_appliance_node.addFileArg(universal_appliance_wasm.getEmittedBin());
    run_universal_appliance_node.addFileArg(universal_image_a);
    run_universal_appliance_node.addFileArg(universal_command_a);
    run_universal_appliance_node.addFileArg(universal_image_b);
    run_universal_appliance_node.addFileArg(universal_command_b);
    run_universal_appliance_node.addFileArg(universal_proof);
    const check_world_universal_appliance_node_step = b.step("check-world-universal-appliance-node", "Run World universal Appliance ABI conformance wasm in Node WebAssembly.");
    check_world_universal_appliance_node_step.dependOn(&run_universal_appliance_node.step);
    const check_world_js_codec_step = b.step("check-world-js-codec", "Run dependency-free JavaScript Appliance Wire codec conformance.");
    check_world_js_codec_step.dependOn(&run_universal_appliance_node.step);
    const run_loaded_value_codec_node = b.addSystemCommand(&.{
        "node",
        "scripts/world_loaded_value_codec_test.mjs",
    });
    check_world_js_codec_step.dependOn(&run_loaded_value_codec_node.step);
    check_world_universal_appliance_wasm_step.dependOn(&run_universal_fixture_gen.step);
    const check_world_universal_memory_step = b.step("check-world-universal-memory", "Inspect World universal Appliance memory bounds.");
    check_world_universal_memory_step.dependOn(check_world_universal_appliance_wasm_step);
    const check_world_universal_providers_step = b.step("check-world-universal-providers", "Run World universal loaded provider checks.");
    const check_world_two_programs_one_wasm_step = b.step("check-world-two-programs-one-wasm", "Run two unrelated World programs through one universal WASM.");
    const universal_appliance_tests = b.addTest(.{
        .root_module = blk: {
            const universal_impl = b.createModule(.{
                .root_source_file = b.path("examples/world_universal_appliance_wasm.zig"),
                .target = b.graph.host,
                .optimize = optimize,
            });
            universal_impl.addImport("world", host_world);
            break :blk b.createModule(.{
                .root_source_file = b.path("test/universal_appliance_test.zig"),
                .target = b.graph.host,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "universal_appliance_impl", .module = universal_impl },
                    .{ .name = "world", .module = host_world },
                    .{ .name = "world_fixtures", .module = host_fixtures },
                },
            });
        },
        .filters = test_args.filters,
    });
    check_world_universal_appliance_wasm_step.dependOn(&addRunArtifactWithArgs(b, universal_appliance_tests, test_args.passthrough).step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/world_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = test_args.filters,
    });
    const archive_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/archive_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
            },
        }),
        .filters = test_args.filters,
    });
    const appliance_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/appliance_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = test_args.filters,
    });
    const world_module_test_module = b.createModule(.{
        .root_source_file = b.path("src/world.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "boundary", .module = boundary },
            .{ .name = "boundary_machine", .module = boundary_machine },
        },
    });
    const world_module_tests = b.addTest(.{
        .root_module = world_module_test_module,
        .filters = test_args.filters,
    });
    const world_application_v1_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/world.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boundary", .module = boundary },
                .{ .name = "boundary_machine", .module = boundary_machine },
            },
        }),
        .filters = &.{"world application v1"},
    });
    const check_world_application_spec_step = b.step("check-world-application-spec", "Run World Comptime v1 protocol and canonical codec checks.");
    dependOnNativeRunOrCompile(b, validation_target, check_world_application_spec_step, world_application_v1_tests, test_args.passthrough);
    const world_comptime_application_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/application_v1_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary_machine },
            },
        }),
        .filters = test_args.filters,
    });
    const application_v1_fixtures = b.createModule(.{
        .root_source_file = b.path("test/application_v1_test.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "boundary", .module = boundary_machine },
        },
    });
    const run_world_comptime_application_tests = addRunArtifactWithArgs(b, world_comptime_application_tests, test_args.passthrough);
    const check_world_machine_v2_step = b.step(
        "check-world-machine-v2",
        "Run focused Boundary Machine ABI v2 admission and provider checks.",
    );
    check_world_machine_v2_step.dependOn(&run_world_comptime_application_tests.step);
    const check_world_machine_v2_surface = b.addSystemCommand(&.{"node"});
    check_world_machine_v2_surface.addFileArg(b.path(
        "scripts/check_world_machine_v2_surface.mjs",
    ));
    check_world_machine_v2_step.dependOn(
        &check_world_machine_v2_surface.step,
    );
    const check_world_machine_no_interpreter = b.addSystemCommand(&.{"node"});
    check_world_machine_no_interpreter.addFileArg(b.path(
        "scripts/check_world_machine_no_interpreter.mjs",
    ));
    const check_world_machine_no_interpreter_step = b.step(
        "check-world-machine-no-interpreter",
        "Prove the World Machine path delegates to Boundary without a generic interpreter.",
    );
    check_world_machine_no_interpreter_step.dependOn(
        &check_world_machine_no_interpreter.step,
    );
    check_world_machine_v2_step.dependOn(
        check_world_machine_no_interpreter_step,
    );
    const world_application_build_support = b.createModule(.{
        .root_source_file = b.path("build_support/application.zig"),
        .target = validation_target,
        .optimize = optimize,
    });
    const application_build_options_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/application_build_options_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{ .{
                .name = "world_application_build_support",
                .module = world_application_build_support,
            }, .{
                .name = "world_application_wasm_v1",
                .module = b.createModule(.{
                    .root_source_file = b.path("src/application_wasm_v1.zig"),
                    .target = validation_target,
                    .optimize = optimize,
                }),
            } },
        }),
    });
    const run_application_build_options_tests = addRunArtifactWithArgs(
        b,
        application_build_options_tests,
        test_args.passthrough,
    );
    const check_world_application_build_options_step = b.step(
        "check-world-application-build-options",
        "Reject invalid World application stack and memory envelopes.",
    );
    check_world_application_build_options_step.dependOn(
        &run_application_build_options_tests.step,
    );
    check_world_machine_v2_step.dependOn(
        check_world_application_build_options_step,
    );
    const world_comptime_agent_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/application_v1_agent_fixtures.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary_machine },
            },
        }),
        .filters = test_args.filters,
    });
    const run_world_comptime_agent_tests = addRunArtifactWithArgs(b, world_comptime_agent_tests, test_args.passthrough);
    check_world_machine_v2_step.dependOn(&run_world_comptime_agent_tests.step);
    const research_digest_application = b.createModule(.{
        .root_source_file = b.path(
            "templates/application-v1/src/application.zig",
        ),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = world },
            .{ .name = "boundary", .module = boundary_machine },
        },
    });
    const research_digest_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "test/application_v1_research_digest_test.zig",
            ),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{
                    .name = "research_digest_application",
                    .module = research_digest_application,
                },
            },
        }),
        .filters = test_args.filters,
    });
    const run_research_digest_tests = addRunArtifactWithArgs(
        b,
        research_digest_tests,
        test_args.passthrough,
    );
    const check_world_comptime_closure_step = b.step("check-world-comptime-closure", "Run World compile-time handler closure and residual-row checks.");
    check_world_comptime_closure_step.dependOn(&run_world_comptime_application_tests.step);
    check_world_comptime_closure_step.dependOn(&run_world_comptime_agent_tests.step);
    check_world_comptime_closure_step.dependOn(&run_research_digest_tests.step);
    const check_world_application_native_step = b.step("check-world-application-native", "Run World native application step and provider parking checks.");
    check_world_application_native_step.dependOn(&run_world_comptime_application_tests.step);
    check_world_application_native_step.dependOn(&run_world_comptime_agent_tests.step);
    check_world_application_native_step.dependOn(&run_research_digest_tests.step);
    const wasm_application_v1_fixtures = b.createModule(.{
        .root_source_file = b.path("test/application_v1_test.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "world", .module = wasm_world },
            .{ .name = "boundary", .module = wasm_boundary_machine },
        },
    });
    const one_effect_application_wasm_module = b.createModule(.{
        .root_source_file = b.path("examples/world_application_v1_one_effect_wasm.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "world", .module = wasm_world },
            .{ .name = "application_v1_fixtures", .module = wasm_application_v1_fixtures },
        },
    });
    const one_effect_application_wasm = b.addExecutable(.{
        .name = "one-effect.world",
        .root_module = one_effect_application_wasm_module,
    });
    one_effect_application_wasm.entry = .disabled;
    one_effect_application_wasm.rdynamic = true;
    one_effect_application_wasm.export_memory = true;
    one_effect_application_wasm.stack_size = 1024 * 1024;
    one_effect_application_wasm.initial_memory = 8 * 1024 * 1024;
    one_effect_application_wasm.max_memory = 8 * 1024 * 1024;
    const install_one_effect_application_wasm = b.addInstallArtifact(one_effect_application_wasm, .{});
    const world_one_effect_application_wasm_step = b.step("world-one-effect-application-wasm", "Build the standalone one-effect World application WASM.");
    world_one_effect_application_wasm_step.dependOn(&install_one_effect_application_wasm.step);
    const check_world_application_wasm_step = b.step("check-world-application-wasm", "Build and inspect the standalone World application WASM.");
    const run_external_build_helper = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build",
        "--summary",
        "all",
    });
    run_external_build_helper.setCwd(b.path("conformance/external-build-helper"));
    const check_world_external_build_helper_step = b.step(
        "check-world-external-build-helper",
        "Build a World application through the public helper from a dependent package.",
    );
    check_world_external_build_helper_step.dependOn(&run_external_build_helper.step);
    const check_world_research_digest_v2_step = b.step(
        "check-world-research-digest-v2",
        "Prove native and import-free wasm32 Research Digest v2 Machine-owned formatting.",
    );
    check_world_research_digest_v2_step.dependOn(
        &run_research_digest_tests.step,
    );
    check_world_research_digest_v2_step.dependOn(
        check_world_external_build_helper_step,
    );
    const check_world_external_consumer = b.addSystemCommand(&.{"node"});
    check_world_external_consumer.addFileArg(b.path(
        "scripts/check_world_external_consumer.mjs",
    ));
    check_world_external_consumer.addArgs(&.{
        "--zig",
        b.graph.zig_exe,
    });
    const check_world_external_consumer_step = b.step(
        "check-world-external-consumer",
        "Build the application template from isolated release archives and caches.",
    );
    check_world_external_consumer_step.dependOn(
        &check_world_external_consumer.step,
    );
    const check_world_1_0_externality = b.addSystemCommand(&.{"node"});
    check_world_1_0_externality.addFileArg(b.path(
        "scripts/check_world_1_0_externality.mjs",
    ));
    check_world_1_0_externality.addArgs(&.{
        "--zig",
        b.graph.zig_exe,
    });
    if (b.args) |args| check_world_1_0_externality.addArgs(args);
    const check_world_1_0_externality_step = b.step(
        "check-world-1.0-externality",
        "Prove a clean-room application through released World, host, and capability artifacts.",
    );
    check_world_1_0_externality_step.dependOn(
        &check_world_1_0_externality.step,
    );
    const check_world_2_externality = b.addSystemCommand(&.{"node"});
    check_world_2_externality.addFileArg(b.path(
        "scripts/check_world_2_externality.mjs",
    ));
    check_world_2_externality.addArgs(&.{
        "--zig",
        b.graph.zig_exe,
    });
    if (b.args) |args| {
        for (args) |arg| {
            if (std.mem.eql(u8, arg, "--negative")) {
                @panic(
                    "use check-world-externality-v2-negative for the negative World 2 externality proof",
                );
            }
        }
        check_world_2_externality.addArgs(args);
    }
    const check_world_2_externality_step = b.step(
        "check-world-2-externality",
        "Prove World 2 through checksum-bound Boundary, host, and capability artifacts.",
    );
    check_world_2_externality_step.dependOn(
        &check_world_2_externality.step,
    );
    const check_world_externality_v2_step = b.step(
        "check-world-externality-v2",
        "Run the canonical World 2 released-artifact externality proof.",
    );
    check_world_externality_v2_step.dependOn(
        check_world_2_externality_step,
    );
    const check_world_externality_v2_negative = b.addSystemCommand(&.{"node"});
    check_world_externality_v2_negative.addFileArg(b.path(
        "scripts/check_world_2_externality.mjs",
    ));
    check_world_externality_v2_negative.addArgs(&.{
        "--zig",
        b.graph.zig_exe,
        "--negative",
    });
    const check_world_externality_v2_negative_step = b.step(
        "check-world-externality-v2-negative",
        "Reject malformed World 2 caller archive and checksum pairs.",
    );
    check_world_externality_v2_negative_step.dependOn(
        &check_world_externality_v2_negative.step,
    );
    const build_world_sdk_v1 = b.addSystemCommand(&.{"node"});
    build_world_sdk_v1.addFileArg(b.path(
        "scripts/build_world_sdk_v1.mjs",
    ));
    build_world_sdk_v1.addArgs(&.{
        "--zig",
        b.graph.zig_exe,
    });
    if (b.args) |args| build_world_sdk_v1.addArgs(args);
    const build_world_sdk_v1_step = b.step(
        "build-world-sdk-v1",
        "Assemble the checksum-bound World SDK v1.0.0 release bundle.",
    );
    build_world_sdk_v1_step.dependOn(&build_world_sdk_v1.step);
    const check_world_sdk_v1 = b.addSystemCommand(&.{"node"});
    check_world_sdk_v1.addFileArg(b.path(
        "scripts/check_world_sdk_v1.mjs",
    ));
    if (b.args) |args| check_world_sdk_v1.addArgs(args);
    const check_world_sdk_v1_step = b.step(
        "check-world-sdk-v1",
        "Validate one assembled World SDK v1.0.0 bundle.",
    );
    check_world_sdk_v1_step.dependOn(&check_world_sdk_v1.step);
    const run_one_effect_application_wasm = b.addSystemCommand(&.{
        "node",
        "scripts/world_application_v1_conformance.mjs",
    });
    run_one_effect_application_wasm.addFileArg(one_effect_application_wasm.getEmittedBin());
    check_world_application_wasm_step.dependOn(&run_one_effect_application_wasm.step);
    const wasm_application_v1_agent_fixtures = b.createModule(.{
        .root_source_file = b.path("test/application_v1_agent_fixtures.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "world", .module = wasm_world },
            .{ .name = "boundary", .module = wasm_boundary_machine },
        },
    });
    const host_application_v1_agent_fixtures = b.createModule(.{
        .root_source_file = b.path("test/application_v1_agent_fixtures.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "world", .module = host_world },
            .{ .name = "boundary", .module = host_boundary_machine },
        },
    });
    const host_skeleton_application_selector = b.createModule(.{
        .root_source_file = b.path("test/application_v1_skeleton_app.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "application_v1_agent_fixtures", .module = host_application_v1_agent_fixtures },
        },
    });
    const host_fixture_application_selector = b.createModule(.{
        .root_source_file = b.path("test/application_v1_fixture_app.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "application_v1_agent_fixtures", .module = host_application_v1_agent_fixtures },
        },
    });
    const skeleton_manifest_emitter = b.addExecutable(.{
        .name = "world-v1-skeleton-manifest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/world_application_v1_manifest.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world_application", .module = host_skeleton_application_selector },
            },
        }),
    });
    const fixture_manifest_emitter = b.addExecutable(.{
        .name = "world-v1-fixture-manifest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/world_application_v1_manifest.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world_application", .module = host_fixture_application_selector },
            },
        }),
    });
    const run_skeleton_manifest_emitter = b.addRunArtifact(skeleton_manifest_emitter);
    const skeleton_manifest = run_skeleton_manifest_emitter.addOutputFileArg("skeleton-agent.manifest.bin");
    const run_fixture_manifest_emitter = b.addRunArtifact(fixture_manifest_emitter);
    const fixture_manifest = run_fixture_manifest_emitter.addOutputFileArg("fixture-agent.manifest.bin");
    const skeleton_application_selector = b.createModule(.{
        .root_source_file = b.path("test/application_v1_skeleton_app.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "application_v1_agent_fixtures", .module = wasm_application_v1_agent_fixtures },
        },
    });
    const fixture_application_selector = b.createModule(.{
        .root_source_file = b.path("test/application_v1_fixture_app.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "application_v1_agent_fixtures", .module = wasm_application_v1_agent_fixtures },
        },
    });
    const skeleton_application_wasm_module = b.createModule(.{
        .root_source_file = b.path("examples/world_application_v1_wasm.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "world", .module = wasm_world },
            .{ .name = "world_application", .module = skeleton_application_selector },
        },
    });
    const fixture_application_wasm_module = b.createModule(.{
        .root_source_file = b.path("examples/world_application_v1_wasm.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "world", .module = wasm_world },
            .{ .name = "world_application", .module = fixture_application_selector },
        },
    });
    const skeleton_application_wasm = b.addExecutable(.{
        .name = "skeleton-agent.world",
        .root_module = skeleton_application_wasm_module,
    });
    skeleton_application_wasm.entry = .disabled;
    skeleton_application_wasm.rdynamic = true;
    skeleton_application_wasm.export_memory = true;
    skeleton_application_wasm.stack_size = 1024 * 1024;
    skeleton_application_wasm.initial_memory = 16 * 1024 * 1024;
    skeleton_application_wasm.max_memory = 16 * 1024 * 1024;
    const fixture_application_wasm = b.addExecutable(.{
        .name = "fixture-agent.world",
        .root_module = fixture_application_wasm_module,
    });
    fixture_application_wasm.entry = .disabled;
    fixture_application_wasm.rdynamic = true;
    fixture_application_wasm.export_memory = true;
    fixture_application_wasm.stack_size = 1024 * 1024;
    fixture_application_wasm.initial_memory = 16 * 1024 * 1024;
    fixture_application_wasm.max_memory = 16 * 1024 * 1024;
    const install_skeleton_application_wasm = b.addInstallArtifact(skeleton_application_wasm, .{});
    const install_fixture_application_wasm = b.addInstallArtifact(fixture_application_wasm, .{});
    const install_skeleton_world_application = b.addInstallFile(
        skeleton_application_wasm.getEmittedBin(),
        "world-apps/skeleton-agent.world.wasm",
    );
    const install_fixture_world_application = b.addInstallFile(
        fixture_application_wasm.getEmittedBin(),
        "world-apps/fixture-agent.world.wasm",
    );
    const install_skeleton_application_manifest = b.addInstallFile(
        skeleton_manifest,
        "world-apps/skeleton-agent.manifest.bin",
    );
    const install_fixture_application_manifest = b.addInstallFile(
        fixture_manifest,
        "world-apps/fixture-agent.manifest.bin",
    );
    const world_skeleton_agent_wasm_step = b.step("world-skeleton-agent-wasm", "Build skeleton-agent.world.wasm.");
    world_skeleton_agent_wasm_step.dependOn(&install_skeleton_application_wasm.step);
    world_skeleton_agent_wasm_step.dependOn(&install_skeleton_world_application.step);
    world_skeleton_agent_wasm_step.dependOn(&install_skeleton_application_manifest.step);
    const world_fixture_agent_wasm_step = b.step("world-fixture-agent-wasm", "Build fixture-agent.world.wasm.");
    world_fixture_agent_wasm_step.dependOn(&install_fixture_application_wasm.step);
    world_fixture_agent_wasm_step.dependOn(&install_fixture_world_application.step);
    world_fixture_agent_wasm_step.dependOn(&install_fixture_application_manifest.step);
    const run_skeleton_application_wasm = b.addSystemCommand(&.{
        "node",
        "scripts/world_application_v1_agent_conformance.mjs",
    });
    run_skeleton_application_wasm.addFileArg(skeleton_application_wasm.getEmittedBin());
    run_skeleton_application_wasm.addArg("skeleton");
    run_skeleton_application_wasm.addFileArg(skeleton_manifest);
    const run_fixture_application_wasm = b.addSystemCommand(&.{
        "node",
        "scripts/world_application_v1_agent_conformance.mjs",
    });
    run_fixture_application_wasm.addFileArg(fixture_application_wasm.getEmittedBin());
    run_fixture_application_wasm.addArg("fixture");
    run_fixture_application_wasm.addFileArg(fixture_manifest);
    check_world_application_wasm_step.dependOn(&run_skeleton_application_wasm.step);
    check_world_application_wasm_step.dependOn(&run_fixture_application_wasm.step);
    check_world_application_wasm_step.dependOn(check_world_external_build_helper_step);
    const check_world_machine_native_wasm_step = b.step(
        "check-world-machine-native-wasm",
        "Prove native and wasm32 Boundary Machine application parity.",
    );
    check_world_machine_native_wasm_step.dependOn(
        check_world_application_native_step,
    );
    check_world_machine_native_wasm_step.dependOn(
        check_world_application_wasm_step,
    );
    check_world_machine_native_wasm_step.dependOn(
        check_world_research_digest_v2_step,
    );
    const check_world_application_v1_step = b.step(
        "check-world-application-v1",
        "Prove the preserved World Application ABI v1 surface.",
    );
    check_world_application_v1_step.dependOn(check_world_application_spec_step);
    check_world_application_v1_step.dependOn(
        check_world_machine_native_wasm_step,
    );
    const world_application_v1_wasm_check = b.addLibrary(.{
        .linkage = .static,
        .name = "world-application-v1-protocol-wasm-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/application_v1.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
        }),
    });
    check_world_application_spec_step.dependOn(&world_application_v1_wasm_check.step);
    const world_protocol_manifest_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/world.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boundary", .module = boundary },
                .{ .name = "boundary_machine", .module = boundary_machine },
            },
        }),
        .filters = &.{"world protocol manifest"},
    });
    const check_world_protocol_manifest_step = b.step("check-world-protocol-manifest", "Run World Protocol.Manifest canonical encoding and WASM export checks.");
    dependOnNativeRunOrCompile(b, validation_target, check_world_protocol_manifest_step, world_protocol_manifest_tests, test_args.passthrough);
    check_world_protocol_manifest_step.dependOn(check_world_universal_appliance_wasm_step);
    const boundary_world_compatibility_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/world.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boundary", .module = boundary },
                .{ .name = "boundary_machine", .module = boundary_machine },
            },
        }),
        .filters = &.{"boundary world protocol compatibility"},
    });
    const check_boundary_world_compatibility_step = b.step("check-boundary-world-compatibility", "Run World checks that bind the frozen Boundary v0 protocol manifest evidence.");
    dependOnNativeRunOrCompile(b, validation_target, check_boundary_world_compatibility_step, boundary_world_compatibility_tests, test_args.passthrough);
    const world_conformance_corpus_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/world.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boundary", .module = boundary },
                .{ .name = "boundary_machine", .module = boundary_machine },
            },
        }),
        .filters = &.{"world conformance corpus"},
    });
    const check_world_conformance_corpus_step = b.step("check-world-conformance-corpus", "Validate the World v0 conformance corpus case inventory.");
    dependOnNativeRunOrCompile(b, validation_target, check_world_conformance_corpus_step, world_conformance_corpus_tests, test_args.passthrough);
    const run_world_conformance_corpus_node = b.addSystemCommand(&.{
        "node",
        "scripts/world_conformance.mjs",
        "--corpus",
        "conformance/v0/world",
    });
    check_world_conformance_corpus_step.dependOn(&run_world_conformance_corpus_node.step);
    const check_world_agent_closure_step = b.step("check-world-agent-closure", "Run World Agent Closure skeleton and fixture proof surfaces.");
    const check_world_agent_replay_step = b.step("check-world-agent-replay", "Run World Agent Closure replay and deterministic retry proof surfaces.");
    const check_world_agent_migration_step = b.step("check-world-agent-migration", "Run World Agent Closure migration and branching proof surfaces.");
    const check_world_agent_conformance_corpus_step = b.step("check-world-agent-conformance-corpus", "Validate World Agent Closure named conformance vectors.");
    check_world_agent_conformance_corpus_step.dependOn(check_world_conformance_corpus_step);
    check_world_agent_conformance_corpus_step.dependOn(check_world_agent_closure_step);
    check_world_agent_conformance_corpus_step.dependOn(check_world_agent_replay_step);
    check_world_agent_conformance_corpus_step.dependOn(check_world_agent_migration_step);
    const check_world_comptime_v0_v1_oracle_step = b.step(
        "check-world-comptime-v0-v1-oracle",
        "Run the frozen v0 agent oracle beside the six World Comptime v1 scenarios.",
    );
    check_world_comptime_v0_v1_oracle_step.dependOn(check_world_agent_conformance_corpus_step);
    check_world_comptime_v0_v1_oracle_step.dependOn(check_world_application_wasm_step);
    const run_world_js_corpus = b.addSystemCommand(&.{
        "node",
        "scripts/world_conformance.mjs",
        "--corpus",
        "conformance/v0/world",
        "--mode",
        "js-corpus",
    });
    const check_world_js_corpus_step = b.step("check-world-js-corpus", "Run dependency-free JavaScript protocol corpus parity checks.");
    check_world_js_corpus_step.dependOn(&run_world_js_corpus.step);
    const run_world_js_malformed_corpus = b.addSystemCommand(&.{
        "node",
        "scripts/world_conformance.mjs",
        "--corpus",
        "conformance/v0/world",
        "--mode",
        "malformed",
    });
    const check_world_js_malformed_corpus_step = b.step("check-world-js-malformed-corpus", "Run dependency-free JavaScript malformed corpus rejection checks.");
    check_world_js_malformed_corpus_step.dependOn(&run_world_js_malformed_corpus.step);
    const world_adversarial_codec_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/world.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boundary", .module = boundary },
                .{ .name = "boundary_machine", .module = boundary_machine },
            },
        }),
        .filters = &.{"world adversarial codecs"},
    });
    const check_world_adversarial_codecs_step = b.step("check-world-adversarial-codecs", "Run World v0 adversarial protocol codec checks.");
    dependOnNativeRunOrCompile(b, validation_target, check_world_adversarial_codecs_step, world_adversarial_codec_tests, test_args.passthrough);
    const world_state_machine_differential_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/appliance_test.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boundary", .module = host_boundary },
                .{ .name = "world", .module = host_world },
                .{ .name = "world_fixtures", .module = host_fixtures },
            },
        }),
        .filters = &.{"world state machine differential"},
    });
    const check_world_state_machine_differential_step = b.step("check-world-state-machine-differential", "Run World state-machine differential classification checks.");
    check_world_state_machine_differential_step.dependOn(&addRunArtifactWithArgs(b, world_state_machine_differential_tests, test_args.passthrough).step);
    check_world_state_machine_differential_step.dependOn(check_world_universal_appliance_node_step);
    const world_release_receipt_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/world.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boundary", .module = host_boundary },
                .{ .name = "boundary_machine", .module = host_boundary_machine },
            },
        }),
        .filters = &.{"world protocol release receipt"},
    });
    const emit_world_proof_receipts_run = b.addSystemCommand(&.{"node"});
    emit_world_proof_receipts_run.addFileArg(b.path("scripts/world_conformance.mjs"));
    emit_world_proof_receipts_run.addArgs(&.{
        "--corpus",
    });
    emit_world_proof_receipts_run.addFileArg(b.path("conformance/v0/world/corpus.json"));
    emit_world_proof_receipts_run.addArgs(&.{
        "--wasm",
    });
    emit_world_proof_receipts_run.addFileArg(universal_appliance_wasm.getEmittedBin());
    emit_world_proof_receipts_run.addArgs(&.{
        "--proof-matrix",
        "zig-build-release-gates",
        "--release-gates-completed",
        "--receipt-out",
    });
    const world_proof_receipts = emit_world_proof_receipts_run.addOutputFileArg("world-proof-receipts.json");
    emit_world_proof_receipts_run.step.dependOn(world_universal_appliance_wasm_step);
    const emit_world_proof_receipts_step = b.step("emit-world-proof-receipts", "Emit machine-readable World v0 proof receipts.");
    emit_world_proof_receipts_step.dependOn(&emit_world_proof_receipts_run.step);
    const emit_world_release_receipt_run = b.addSystemCommand(&.{"node"});
    emit_world_release_receipt_run.addFileArg(b.path("scripts/world_conformance.mjs"));
    emit_world_release_receipt_run.addArgs(&.{
        "--corpus",
    });
    emit_world_release_receipt_run.addFileArg(b.path("conformance/v0/world/corpus.json"));
    emit_world_release_receipt_run.addArgs(&.{
        "--wasm",
    });
    emit_world_release_receipt_run.addFileArg(universal_appliance_wasm.getEmittedBin());
    emit_world_release_receipt_run.addArgs(&.{
        "--receipt-out",
    });
    const world_wasm_inspection_receipt = emit_world_release_receipt_run.addOutputFileArg("world-wasm-inspection-receipt.json");
    emit_world_release_receipt_run.step.dependOn(world_universal_appliance_wasm_step);
    const world_release_receipt_emit_mod = b.createModule(.{
        .root_source_file = b.path("examples/world_release_receipt_emit.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    world_release_receipt_emit_mod.addImport("world", host_world);
    const world_release_receipt_emit_exe = b.addExecutable(.{ .name = "world-release-receipt-emit", .root_module = world_release_receipt_emit_mod });
    const world_release_receipt_emit_test_mod = b.createModule(.{
        .root_source_file = b.path("examples/world_release_receipt_emit.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    world_release_receipt_emit_test_mod.addImport("world", host_world);
    const world_release_receipt_emit_tests = b.addTest(.{ .root_module = world_release_receipt_emit_test_mod });
    const emit_world_protocol_release_receipt_run = b.addRunArtifact(world_release_receipt_emit_exe);
    emit_world_protocol_release_receipt_run.addArgs(&.{"--wasm"});
    emit_world_protocol_release_receipt_run.addFileArg(universal_appliance_wasm.getEmittedBin());
    emit_world_protocol_release_receipt_run.addArgs(&.{"--wasm-inspection-receipt"});
    emit_world_protocol_release_receipt_run.addFileArg(world_wasm_inspection_receipt);
    emit_world_protocol_release_receipt_run.addArgs(&.{"--proof-receipts"});
    emit_world_protocol_release_receipt_run.addFileArg(world_proof_receipts);
    emit_world_protocol_release_receipt_run.addArgs(&.{"--out"});
    const world_protocol_release_receipt = emit_world_protocol_release_receipt_run.addOutputFileArg("world-release-receipt.json");
    addWorldSourcePackageInputs(b, emit_world_protocol_release_receipt_run);
    emit_world_protocol_release_receipt_run.addArgs(&.{
        "--proof-gate", "check-boundary-world-compatibility",
        "--proof-gate", "check-world-executable-image",
        "--proof-gate", "check-world-universal-appliance-node",
        "--proof-gate", "check-world-two-programs-one-wasm",
        "--proof-gate", "check-world-universal-providers",
        "--proof-gate", "check-world-loaded-runspace",
        "--proof-gate", "check-world-active-fabric-restore",
        "--proof-gate", "check-world-replay-positive",
        "--proof-gate", "check-world-v0-negative",
        "--proof-gate", "check-world-deterministic-retry",
        "--proof-gate", "check-world-appliance-batching",
        "--proof-gate", "check-world-js-codec",
        "--proof-gate", "check-world-conformance-corpus",
        "--proof-gate", "check-world-adversarial-codecs",
        "--proof-gate", "check-world-adversarial-codecs",
        "--proof-gate", "check-world-adversarial-codecs",
        "--proof-gate", "check-world-state-machine-differential",
        "--proof-gate", "check-world-state-machine-differential",
        "--proof-gate", "check-world-universal-memory",
        "--proof-gate", "check-world-js-malformed-corpus",
        "--proof-gate", "check-world-conformance-corpus",
        "--proof-gate", "check-world-reproducible-wasm",
    });
    emit_world_protocol_release_receipt_run.step.dependOn(&emit_world_release_receipt_run.step);
    const emit_world_release_receipt_step = b.step("emit-world-release-receipt", "Emit the World v0 release receipt from proof evidence.");
    emit_world_release_receipt_step.dependOn(&emit_world_protocol_release_receipt_run.step);
    const check_world_release_receipt_step = b.step("check-world-release-receipt", "Validate the World v0 release receipt proof matrix.");
    check_world_release_receipt_step.dependOn(&addRunArtifactWithArgs(b, world_release_receipt_tests, test_args.passthrough).step);
    check_world_release_receipt_step.dependOn(&addRunArtifactWithArgs(b, world_release_receipt_emit_tests, test_args.passthrough).step);
    if (target.query.isNative()) check_world_release_receipt_step.dependOn(emit_world_release_receipt_step);
    const world_v0_budget_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/world.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boundary", .module = boundary },
                .{ .name = "boundary_machine", .module = boundary_machine },
            },
        }),
        .filters = &.{"world v0 budgets"},
    });
    const check_world_v0_budgets_step = b.step("check-world-v0-budgets", "Validate World v0 structural budget baselines.");
    dependOnNativeRunOrCompile(b, validation_target, check_world_v0_budgets_step, world_v0_budget_tests, test_args.passthrough);
    const run_world_reproducible_wasm_check = b.addSystemCommand(&.{
        "node",
        "scripts/world_release_artifacts.mjs",
        "--mode",
        "check-repro",
        "--wasm",
    });
    run_world_reproducible_wasm_check.addFileArg(universal_appliance_wasm.getEmittedBin());
    run_world_reproducible_wasm_check.addArgs(&.{
        "--wasm-repro",
    });
    run_world_reproducible_wasm_check.addFileArg(universal_appliance_wasm_repro.getEmittedBin());
    run_world_reproducible_wasm_check.addArgs(&.{
        "--corpus",
        "conformance/v0/world/corpus.json",
    });
    run_world_reproducible_wasm_check.step.dependOn(world_universal_appliance_wasm_step);
    const check_world_reproducible_wasm_step = b.step("check-world-reproducible-wasm", "Validate deterministic World v0 release artifacts from current outputs.");
    check_world_reproducible_wasm_step.dependOn(&run_world_reproducible_wasm_check.step);
    const run_dist_world_v0 = b.addSystemCommand(&.{
        "node",
        "scripts/world_release_artifacts.mjs",
        "--mode",
        "dist",
        "--wasm",
    });
    run_dist_world_v0.addFileArg(universal_appliance_wasm.getEmittedBin());
    run_dist_world_v0.addArgs(&.{
        "--release-receipt",
    });
    run_dist_world_v0.addFileArg(world_protocol_release_receipt);
    run_dist_world_v0.addArgs(&.{
        "--out",
        "zig-out/dist/world-v0.1.0",
    });
    run_dist_world_v0.step.dependOn(world_universal_appliance_wasm_step);
    run_dist_world_v0.step.dependOn(emit_world_release_receipt_step);
    const emit_world_release_artifacts_step = b.step("emit-world-release-artifacts", "Emit World v0.1.0 release artifacts.");
    emit_world_release_artifacts_step.dependOn(&run_dist_world_v0.step);
    const dist_world_v0_1_step = b.step("dist-world-v0.1.0", "Package World v0.1.0 release artifacts.");
    dist_world_v0_1_step.dependOn(&run_dist_world_v0.step);
    const dist_world_agent_v0_step = b.step("dist-world-agent-v0", "Package World v0 artifacts with Agent Closure proof gates completed.");
    dist_world_agent_v0_step.dependOn(dist_world_v0_1_step);
    dist_world_agent_v0_step.dependOn(check_world_agent_conformance_corpus_step);
    dist_world_agent_v0_step.dependOn(check_world_agent_runtime_artifacts_step);
    const run_check_world_v0_1_dist = b.addSystemCommand(&.{
        "node",
        "scripts/world_release_artifacts.mjs",
        "--mode",
        "check-dist",
        "--dist",
        "zig-out/dist/world-v0.1.0",
    });
    run_check_world_v0_1_dist.step.dependOn(&run_dist_world_v0.step);
    const run_check_world_agent_v0_dist = b.addSystemCommand(&.{
        "node",
        "scripts/world_release_artifacts.mjs",
        "--mode",
        "check-dist",
        "--dist",
        "zig-out/dist/world-v0.1.0",
    });
    run_check_world_agent_v0_dist.step.dependOn(&run_world_agent_runtime_artifact_gen.step);
    dist_world_agent_v0_step.dependOn(&run_check_world_agent_v0_dist.step);
    const run_check_world_v0_1_standalone = b.addSystemCommand(&.{
        "node",
        "zig-out/dist/world-v0.1.0/scripts/world_conformance.mjs",
        "--wasm",
        "zig-out/dist/world-v0.1.0/world_universal_appliance.wasm",
        "--corpus",
        "zig-out/dist/world-v0.1.0/conformance/v0/world",
        "--receipt-out",
    });
    run_check_world_v0_1_standalone.addFileInput(b.path("zig-out/dist/world-v0.1.0/scripts/world_conformance.mjs"));
    run_check_world_v0_1_standalone.addFileInput(b.path("zig-out/dist/world-v0.1.0/scripts/world_appliance_wire_codec.mjs"));
    run_check_world_v0_1_standalone.addFileInput(b.path("zig-out/dist/world-v0.1.0/scripts/world_loaded_value_codec.mjs"));
    run_check_world_v0_1_standalone.addFileInput(b.path("zig-out/dist/world-v0.1.0/world_universal_appliance.wasm"));
    run_check_world_v0_1_standalone.addFileInput(b.path("zig-out/dist/world-v0.1.0/conformance/v0/world/corpus.json"));
    _ = run_check_world_v0_1_standalone.addOutputFileArg("world-distributed-conformance-receipt.json");
    run_check_world_v0_1_standalone.step.dependOn(&run_dist_world_v0.step);
    const check_world_v0_1_release_step = b.step("check-world-v0.1-release", "Validate packaged World v0.1.0 artifacts and source-free conformance.");
    check_world_v0_1_release_step.dependOn(&run_check_world_v0_1_dist.step);
    check_world_v0_1_release_step.dependOn(&run_check_world_v0_1_standalone.step);
    run_world_agent_runtime_artifact_gen.step.dependOn(&run_dist_world_v0.step);
    const wasm_guest_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/world_wasm_guest_one_port.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
        .filters = test_args.filters,
    });
    const test_step = b.step("test", "Run world tests.");
    b.default_step.dependOn(check_world_target_step);
    test_step.dependOn(check_world_target_step);
    test_step.dependOn(&addRunArtifactWithArgs(b, wasm_guest_tests, test_args.passthrough).step);
    if (validation_target.query.isNative()) {
        test_step.dependOn(&addRunArtifactWithArgs(b, tests, test_args.passthrough).step);
        test_step.dependOn(&addRunArtifactWithArgs(b, archive_tests, test_args.passthrough).step);
        test_step.dependOn(&addRunArtifactWithArgs(b, appliance_tests, test_args.passthrough).step);
        test_step.dependOn(&addRunArtifactWithArgs(b, world_module_tests, test_args.passthrough).step);
        b.default_step.dependOn(test_step);
    } else {
        test_step.dependOn(&tests.step);
        test_step.dependOn(&archive_tests.step);
        test_step.dependOn(&appliance_tests.step);
        test_step.dependOn(&world_module_tests.step);
        b.default_step.dependOn(&tests.step);
        b.default_step.dependOn(&archive_tests.step);
        b.default_step.dependOn(&appliance_tests.step);
        b.default_step.dependOn(&world_module_tests.step);
    }

    const check_world_turn_closure_step = b.step("check-world-turn-closure", "Run World Turn Closure contract tests.");
    const turn_closure_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/appliance_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{ "TurnClosure", "Wire TurnInput", "Continuity object kinds" },
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_turn_closure_step, turn_closure_tests, test_args.passthrough);

    const check_world_executable_image_step = b.step("check-world-executable-image", "Run World Executable image tests.");
    const executable_image_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/world_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{"Executable Builder"},
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_executable_image_step, executable_image_tests, test_args.passthrough);

    const check_world_loaded_runspace_step = b.step("check-world-loaded-runspace", "Run World loaded Runspace tests.");
    const loaded_runspace_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/world_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{"Loaded Runspace"},
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_loaded_runspace_step, loaded_runspace_tests, test_args.passthrough);

    const check_world_loaded_linker_step = b.step("check-world-loaded-linker", "Run World loaded Linker tests.");
    const loaded_linker_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/world_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{"Loaded Linker"},
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_loaded_linker_step, loaded_linker_tests, test_args.passthrough);

    const check_world_loaded_admission_step = b.step("check-world-loaded-admission", "Run World loaded Admission tests.");
    const loaded_admission_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/world_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{"Loaded Admission"},
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_loaded_admission_step, loaded_admission_tests, test_args.passthrough);

    const check_world_loaded_fabric_step = b.step("check-world-loaded-fabric", "Run World loaded Fabric tests.");
    const loaded_fabric_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/world_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{"Loaded Fabric"},
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_loaded_fabric_step, loaded_fabric_tests, test_args.passthrough);

    const check_world_loaded_capsule_step = b.step("check-world-loaded-capsule", "Run World loaded Capsule tests.");
    const loaded_capsule_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/world_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{"Loaded Capsule"},
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_loaded_capsule_step, loaded_capsule_tests, test_args.passthrough);

    const check_world_seed_migration_step = b.step("check-world-seed-migration", "Run World Seed migration tests.");
    const world_seed_migration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/world_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{"World Seed Migration"},
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_seed_migration_step, world_seed_migration_tests, test_args.passthrough);

    const check_world_universal_runtime_step = b.step("check-world-universal-runtime", "Run World universal executable Appliance runtime tests.");
    const world_universal_runtime_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/appliance_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{"Universal Runtime"},
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_universal_runtime_step, world_universal_runtime_tests, test_args.passthrough);

    const check_world_seed_replay_step = b.step("check-world-seed-replay", "Run World Seed replay and batched host closure tests.");
    const world_seed_replay_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/appliance_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{"World Seed Replay"},
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_seed_replay_step, world_seed_replay_tests, test_args.passthrough);
    const check_world_replay_positive_step = b.step("check-world-replay-positive", "Run World Appliance positive replay proof.");
    const world_replay_positive_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/appliance_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{
            "appliance Core accepts replay evidence with verified transcript support",
        },
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_replay_positive_step, world_replay_positive_tests, test_args.passthrough);
    const check_world_appliance_batching_step = b.step("check-world-appliance-batching", "Run World Appliance batched host turn proof.");
    const world_appliance_batching_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/appliance_test.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = &.{
            "World Seed Replay accepts batched host replies for independent requests",
            "appliance Core restore with partial terminal replies keeps only unreplied requests",
            "appliance Wire TurnInput canonicalizes resolution input order",
        },
    });
    dependOnNativeRunOrCompile(b, validation_target, check_world_appliance_batching_step, world_appliance_batching_tests, test_args.passthrough);
    const check_world_deterministic_retry_step = b.step("check-world-deterministic-retry", "Run World Appliance deterministic retry proof.");
    const check_world_universal_step = b.step("check-world-universal", "Run World universal Appliance runtime and WASM conformance checks.");
    check_world_universal_step.dependOn(check_world_universal_runtime_step);
    check_world_universal_step.dependOn(check_world_seed_replay_step);
    check_world_universal_step.dependOn(check_world_universal_appliance_wasm_step);
    check_world_universal_step.dependOn(check_world_universal_appliance_node_step);
    check_world_universal_step.dependOn(check_world_js_codec_step);
    check_world_universal_providers_step.dependOn(check_world_loaded_fabric_step);
    check_world_universal_providers_step.dependOn(check_world_universal_appliance_wasm_step);
    check_world_two_programs_one_wasm_step.dependOn(check_world_universal_appliance_node_step);
    check_world_two_programs_one_wasm_step.dependOn(check_world_js_codec_step);
    check_world_two_programs_one_wasm_step.dependOn(check_world_universal_providers_step);
    check_world_universal_step.dependOn(check_world_universal_providers_step);

    const check_world_runtime_closure_step = b.step("check-world-runtime-closure", "Run World Runtime Closure proof lanes.");
    check_world_runtime_closure_step.dependOn(check_world_loaded_runspace_step);
    check_world_runtime_closure_step.dependOn(check_world_loaded_admission_step);
    check_world_runtime_closure_step.dependOn(check_world_loaded_fabric_step);
    check_world_runtime_closure_step.dependOn(check_world_loaded_capsule_step);
    check_world_runtime_closure_step.dependOn(check_world_seed_migration_step);
    check_world_runtime_closure_step.dependOn(check_world_universal_step);

    const forged_descriptor_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/forged_descriptor_metadata.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
    });
    forged_descriptor_test.expect_errors = .{
        .contains = "World port descriptor metadata does not match target WorldPortTable",
    };
    const application_v1_missing_binding_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/application_v1_missing_binding.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "application_v1_fixtures", .module = application_v1_fixtures },
            },
        }),
    });
    application_v1_missing_binding_test.expect_errors = .{
        .contains = "World application has an unhandled operation site; declare an internal handler or explicit external effect",
    };
    const application_v1_ambiguous_binding_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/application_v1_ambiguous_binding.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "application_v1_fixtures", .module = application_v1_fixtures },
            },
        }),
    });
    application_v1_ambiguous_binding_test.expect_errors = .{
        .contains = "World application operation site has ambiguous handler ownership",
    };
    const application_v1_incompatible_provider_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/application_v1_incompatible_provider.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary_machine },
                .{ .name = "application_v1_fixtures", .module = application_v1_fixtures },
            },
        }),
    });
    application_v1_incompatible_provider_test.expect_errors = .{
        .contains = "World Machine provider InitialArgs must exactly match the parent payload type",
    };
    const application_v1_provider_cycle_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/application_v1_provider_cycle.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "application_v1_fixtures", .module = application_v1_fixtures },
            },
        }),
    });
    application_v1_provider_cycle_test.expect_errors = .{
        .contains = "World application internal provider graph contains a static cycle",
    };
    const application_v1_provider_depth_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/application_v1_provider_depth.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary_machine },
                .{ .name = "application_v1_fixtures", .module = application_v1_fixtures },
            },
        }),
    });
    application_v1_provider_depth_test.expect_errors = .{
        .contains = "World application internal provider graph exceeds maximum_provider_depth",
    };
    const application_v1_external_zero_result_limit_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/application_v1_external_zero_result_limit.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "application_v1_fixtures", .module = application_v1_fixtures },
            },
        }),
    });
    application_v1_external_zero_result_limit_test.expect_errors = .{
        .contains = "World external maximum_result_bytes must be positive",
    };
    const application_v1_external_oversized_result_limit_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/application_v1_external_oversized_result_limit.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "application_v1_fixtures", .module = application_v1_fixtures },
            },
        }),
    });
    application_v1_external_oversized_result_limit_test.expect_errors = .{
        .contains = "World external maximum_result_bytes exceeds the application maximum_result_bytes",
    };
    const application_v1_provider_state_capacity_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/application_v1_provider_state_capacity.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "application_v1_fixtures", .module = application_v1_fixtures },
            },
        }),
    });
    application_v1_provider_state_capacity_test.expect_errors = .{
        .contains = "World application provider stack exceeds maximum_state_bytes",
    };
    const application_v1_site_identity_mismatch_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/application_v1_site_identity_mismatch.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "application_v1_fixtures", .module = application_v1_fixtures },
            },
        }),
    });
    application_v1_site_identity_mismatch_test.expect_errors = .{
        .contains = "World Machine site_identity does not match the selected effect-site ordinal",
    };
    const application_v1_duplicate_site_identity_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/application_v1_duplicate_site_identity.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary_machine },
            },
        }),
    });
    application_v1_duplicate_site_identity_test.expect_errors = .{
        .contains = "World application requires unique semantic_identity values for every reachable Machine effect site",
    };
    const application_v1_build_decl_options = b.addOptions();
    application_v1_build_decl_options.addOption(
        []const u8,
        "application_decl",
        "Application",
    );
    const application_v1_build_decl_missing_source = b.createModule(.{
        .root_source_file = b.path(
            "test/compile_fail/application_v1_build_decl_missing_source.zig",
        ),
        .target = validation_target,
        .optimize = optimize,
    });
    const application_v1_build_decl_missing_selector = b.createModule(.{
        .root_source_file = b.path("src/application_selector_v1.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "world_application_source",
                .module = application_v1_build_decl_missing_source,
            },
            .{
                .name = "world_application_build_options",
                .module = application_v1_build_decl_options.createModule(),
            },
        },
    });
    const application_v1_build_decl_missing_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "test/compile_fail/application_v1_build_decl_selector.zig",
            ),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "world_application",
                    .module = application_v1_build_decl_missing_selector,
                },
            },
        }),
    });
    application_v1_build_decl_missing_test.expect_errors = .{
        .contains = "World application source is missing public declaration 'Application'",
    };
    const application_v1_build_decl_value_source = b.createModule(.{
        .root_source_file = b.path(
            "test/compile_fail/application_v1_build_decl_value_source.zig",
        ),
        .target = validation_target,
        .optimize = optimize,
    });
    const application_v1_build_decl_value_selector = b.createModule(.{
        .root_source_file = b.path("src/application_selector_v1.zig"),
        .target = validation_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "world_application_source",
                .module = application_v1_build_decl_value_source,
            },
            .{
                .name = "world_application_build_options",
                .module = application_v1_build_decl_options.createModule(),
            },
        },
    });
    const application_v1_build_decl_value_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "test/compile_fail/application_v1_build_decl_selector.zig",
            ),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "world_application",
                    .module = application_v1_build_decl_value_selector,
                },
            },
        }),
    });
    application_v1_build_decl_value_test.expect_errors = .{
        .contains = "World application declaration 'Application' must be a type returned by world.application",
    };
    const application_v1_wasm_region_too_small_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/application_v1_wasm_region_too_small.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "application_v1_fixtures", .module = application_v1_fixtures },
            },
        }),
    });
    application_v1_wasm_region_too_small_test.expect_errors = .{
        .contains = "World application WASM input region is smaller than the declared StepInput limits",
    };
    const appliance_missing_binding_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/appliance_missing_actuation_binding.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
    });
    appliance_missing_binding_test.expect_errors = .{
        .contains = "World Appliance strict closed-world definition requires explicit actuation binding for every unresolved external port",
    };
    const appliance_covered_port_bound_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/appliance_covered_port_also_bound.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
    });
    appliance_covered_port_bound_test.expect_errors = .{
        .contains = "World Appliance assembly-covered port must not also be exposed as external Actuation",
    };
    const appliance_invalid_capacity_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/appliance_invalid_capacity.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
    });
    appliance_invalid_capacity_test.expect_errors = .{
        .contains = "World Appliance capacity is invalid for profile",
    };
    const appliance_actuation_disabled_binding_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/appliance_actuation_disabled_binding.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
    });
    appliance_actuation_disabled_binding_test.expect_errors = .{
        .contains = "World Appliance actuation bindings require a profile with actuation enabled",
    };
    const appliance_zero_host_request_capacity_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/appliance_zero_host_request_capacity.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
    });
    appliance_zero_host_request_capacity_test.expect_errors = .{
        .contains = "World Appliance external Actuation bindings exceed Capacity.max_host_requests_per_turn",
    };
    const appliance_zero_host_reply_capacity_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/appliance_zero_host_reply_capacity.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
    });
    appliance_zero_host_reply_capacity_test.expect_errors = .{
        .contains = "World Appliance external Actuation bindings exceed Capacity.max_host_replies_per_turn",
    };
    const appliance_zero_actuation_record_capacity_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/appliance_zero_actuation_record_capacity.zig"),
            .target = validation_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
    });
    appliance_zero_actuation_record_capacity_test.expect_errors = .{
        .contains = "World Appliance external Actuation bindings exceed Capacity.max_actuation_records",
    };
    const compile_fail_step = b.step("compile-fail", "Run compile-fail tests.");
    compile_fail_step.dependOn(&forged_descriptor_test.step);
    compile_fail_step.dependOn(&application_v1_missing_binding_test.step);
    compile_fail_step.dependOn(&application_v1_ambiguous_binding_test.step);
    compile_fail_step.dependOn(&application_v1_incompatible_provider_test.step);
    compile_fail_step.dependOn(&application_v1_provider_cycle_test.step);
    compile_fail_step.dependOn(&application_v1_provider_depth_test.step);
    compile_fail_step.dependOn(&application_v1_external_zero_result_limit_test.step);
    compile_fail_step.dependOn(&application_v1_external_oversized_result_limit_test.step);
    compile_fail_step.dependOn(&application_v1_provider_state_capacity_test.step);
    compile_fail_step.dependOn(&application_v1_site_identity_mismatch_test.step);
    compile_fail_step.dependOn(&application_v1_duplicate_site_identity_test.step);
    compile_fail_step.dependOn(&application_v1_build_decl_missing_test.step);
    compile_fail_step.dependOn(&application_v1_build_decl_value_test.step);
    compile_fail_step.dependOn(&application_v1_wasm_region_too_small_test.step);
    compile_fail_step.dependOn(&appliance_missing_binding_test.step);
    compile_fail_step.dependOn(&appliance_covered_port_bound_test.step);
    compile_fail_step.dependOn(&appliance_invalid_capacity_test.step);
    compile_fail_step.dependOn(&appliance_actuation_disabled_binding_test.step);
    compile_fail_step.dependOn(&appliance_zero_host_request_capacity_test.step);
    compile_fail_step.dependOn(&appliance_zero_host_reply_capacity_test.step);
    compile_fail_step.dependOn(&appliance_zero_actuation_record_capacity_test.step);
    const check_world_application_v1_negative_step = b.step(
        "check-world-application-v1-negative",
        "Run malformed and compile-fail Application ABI v1 witnesses.",
    );
    check_world_application_v1_negative_step.dependOn(check_world_application_spec_step);
    check_world_application_v1_negative_step.dependOn(compile_fail_step);
    const check_world_machine_native_wasm_negative_step = b.step(
        "check-world-machine-native-wasm-negative",
        "Run target-neutral Machine application compile-fail witnesses.",
    );
    check_world_machine_native_wasm_negative_step.dependOn(compile_fail_step);

    const check_step = b.step("check", "Run tests, compile-fail tests, examples, and lint.");
    check_step.dependOn(check_world_machine_v2_step);
    check_step.dependOn(check_world_application_spec_step);
    check_step.dependOn(check_world_comptime_closure_step);
    check_step.dependOn(check_world_application_native_step);
    check_step.dependOn(check_world_application_wasm_step);
    check_step.dependOn(check_world_comptime_v0_v1_oracle_step);
    check_step.dependOn(test_step);
    check_step.dependOn(compile_fail_step);
    check_step.dependOn(check_world_target_step);
    check_step.dependOn(check_world_turn_closure_step);
    check_step.dependOn(check_world_executable_image_step);
    check_step.dependOn(check_world_loaded_runspace_step);
    check_step.dependOn(check_world_loaded_linker_step);
    check_step.dependOn(check_world_loaded_admission_step);
    check_step.dependOn(check_world_loaded_fabric_step);
    check_step.dependOn(check_world_loaded_capsule_step);
    check_step.dependOn(check_world_seed_migration_step);
    check_step.dependOn(check_world_universal_runtime_step);
    check_step.dependOn(check_world_seed_replay_step);
    check_step.dependOn(check_world_replay_positive_step);
    check_step.dependOn(check_world_appliance_batching_step);
    check_step.dependOn(check_world_deterministic_retry_step);
    check_step.dependOn(check_world_js_codec_step);
    check_step.dependOn(check_world_universal_step);
    check_step.dependOn(check_world_protocol_manifest_step);
    check_step.dependOn(check_boundary_world_compatibility_step);
    check_step.dependOn(check_world_conformance_corpus_step);
    check_step.dependOn(check_world_agent_closure_step);
    check_step.dependOn(check_world_agent_replay_step);
    check_step.dependOn(check_world_agent_migration_step);
    check_step.dependOn(check_world_agent_conformance_corpus_step);
    check_step.dependOn(check_world_agent_runtime_artifacts_step);
    check_step.dependOn(check_world_js_corpus_step);
    check_step.dependOn(check_world_js_malformed_corpus_step);
    check_step.dependOn(check_world_adversarial_codecs_step);
    check_step.dependOn(check_world_state_machine_differential_step);
    check_step.dependOn(check_world_release_receipt_step);
    check_step.dependOn(check_world_v0_budgets_step);
    check_step.dependOn(check_world_reproducible_wasm_step);
    const check_world_seed_step = b.step("check-world-seed", "Run World Seed killer examples and conformance checks.");
    const check_world_seed_malformed_step = b.step("check-world-seed-malformed", "Run World Seed malformed/rejection checks.");
    const check_world_active_fabric_restore_step = b.step("check-world-active-fabric-restore", "Run positive World active Fabric restore proof.");
    const check_world_v0_negative_step = b.step("check-world-v0-negative", "Run World v0 malformed and denial proof gates.");
    check_world_v0_negative_step.dependOn(check_world_seed_malformed_step);
    if (!target.query.isNative()) {
        const reject_non_native_release_receipt = b.addSystemCommand(&.{
            "sh",
            "-c",
            "echo 'World release receipt emission requires a native target so every proof gate runs instead of compiling only.' >&2; exit 1",
        });
        emit_world_proof_receipts_run.step.dependOn(&reject_non_native_release_receipt.step);
        emit_world_protocol_release_receipt_run.step.dependOn(&reject_non_native_release_receipt.step);
    } else {
        emit_world_proof_receipts_run.step.dependOn(check_boundary_world_compatibility_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_executable_image_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_universal_appliance_node_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_two_programs_one_wasm_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_universal_providers_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_loaded_runspace_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_active_fabric_restore_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_replay_positive_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_v0_negative_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_deterministic_retry_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_appliance_batching_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_js_codec_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_conformance_corpus_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_adversarial_codecs_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_state_machine_differential_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_universal_memory_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_js_malformed_corpus_step);
        emit_world_proof_receipts_run.step.dependOn(check_world_reproducible_wasm_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_boundary_world_compatibility_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_executable_image_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_universal_appliance_node_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_two_programs_one_wasm_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_universal_providers_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_loaded_runspace_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_active_fabric_restore_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_replay_positive_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_v0_negative_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_deterministic_retry_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_appliance_batching_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_js_codec_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_conformance_corpus_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_adversarial_codecs_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_state_machine_differential_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_universal_memory_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_js_malformed_corpus_step);
        emit_world_protocol_release_receipt_run.step.dependOn(check_world_reproducible_wasm_step);
    }
    const check_world_v0_step = b.step("check-world-v0", "Run the World v0 positive Turn Closure completion gate.");
    check_world_v0_step.dependOn(check_world_executable_image_step);
    check_world_v0_step.dependOn(check_world_turn_closure_step);
    check_world_v0_step.dependOn(check_world_runtime_closure_step);
    check_world_v0_step.dependOn(check_world_seed_step);
    check_world_v0_step.dependOn(check_world_wasm_step);
    check_world_v0_step.dependOn(check_world_universal_step);
    check_world_v0_step.dependOn(check_world_universal_providers_step);
    check_world_v0_step.dependOn(check_world_active_fabric_restore_step);
    check_world_v0_step.dependOn(check_world_replay_positive_step);
    check_world_v0_step.dependOn(check_world_deterministic_retry_step);
    check_world_v0_step.dependOn(check_world_appliance_batching_step);
    check_world_v0_step.dependOn(check_world_js_codec_step);
    check_world_v0_step.dependOn(check_world_js_corpus_step);
    check_world_v0_step.dependOn(check_world_js_malformed_corpus_step);
    check_world_v0_step.dependOn(check_world_two_programs_one_wasm_step);
    check_world_v0_step.dependOn(check_world_universal_memory_step);
    check_world_v0_step.dependOn(check_world_conformance_corpus_step);
    check_world_v0_step.dependOn(check_world_adversarial_codecs_step);
    check_world_v0_step.dependOn(check_world_state_machine_differential_step);
    check_world_v0_step.dependOn(check_world_release_receipt_step);
    check_world_v0_step.dependOn(check_world_v0_budgets_step);
    check_world_v0_step.dependOn(check_world_reproducible_wasm_step);
    check_step.dependOn(check_world_seed_step);
    check_step.dependOn(check_world_seed_malformed_step);
    check_step.dependOn(check_world_v0_negative_step);

    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
        step: []const u8,
        desc: []const u8,
        serial_after_tests: bool = false,
        expected_stdout: []const u8,
    }{
        .{
            .name = "world-seed-one-port",
            .path = "examples/world_seed_one_port.zig",
            .step = "run-world-seed-one-port",
            .desc = "Run the one-port World Seed example.",
            .expected_stdout =
            \\world_seed=one_port
            \\host_requests=1
            \\payload_bytes_present=true
            \\result_bytes_present=true
            \\completed=true
            \\
            ,
        },
        .{
            .name = "world-seed-agent",
            .path = "examples/world_seed_agent.zig",
            .step = "run-world-seed-agent",
            .desc = "Run the agent World Seed example.",
            .expected_stdout =
            \\world_seed=agent
            \\provider_modules=1
            \\fabric_plans=1
            \\external_requests=2
            \\completed=true
            \\
            ,
        },
        .{
            .name = "world-seed-two-images-one-wasm",
            .path = "examples/world_seed_two_images_one_wasm.zig",
            .step = "run-world-seed-two-images-one-wasm",
            .desc = "Run two unrelated World Seed images through one generic wasm Appliance implementation.",
            .expected_stdout =
            \\world_seed=two_images_one_wasm
            \\abi_version=4
            \\images=2
            \\images_loaded=true
            \\manifests_present=true
            \\turn_outputs_ready=true
            \\
            ,
        },
        .{
            .name = "world-seed-migrate",
            .path = "examples/world_seed_migrate.zig",
            .step = "run-world-seed-migrate",
            .desc = "Run the World Seed migration example.",
            .expected_stdout =
            \\reconstruction_equivalent=true
            \\resident_output=6d2787f7766186f9
            \\restored_output=6d2787f7766186f9
            \\
            ,
        },
        .{
            .name = "world-seed-active-fabric-restore",
            .path = "examples/world_seed_active_fabric_restore.zig",
            .step = "run-world-seed-active-fabric-restore",
            .desc = "Run the World Seed active Fabric restore example.",
            .expected_stdout =
            \\provider_parked=true
            \\source_destroyed=true
            \\restore_accepted=true
            \\active_fabric_restore_accepted=true
            \\provider_completed=true
            \\root_completed=true
            \\
            ,
        },
        .{
            .name = "world-seed-replay",
            .path = "examples/world_seed_replay.zig",
            .step = "run-world-seed-replay",
            .desc = "Run the World Seed replay example.",
            .expected_stdout =
            \\fresh_host_requests=1
            \\replay_supported=false
            \\actuated_replay_rejected=true
            \\
            ,
        },
        .{
            .name = "world-seed-reject",
            .path = "examples/world_seed_reject.zig",
            .step = "run-world-seed-reject",
            .desc = "Run the World Seed malformed/rejection example.",
            .expected_stdout =
            \\world_seed=reject
            \\oversized_rejected=true
            \\manifest_after_reject=0
            \\submit_without_image_rejected=true
            \\
            ,
        },
        .{
            .name = "world-run-strict",
            .path = "examples/world_run_strict.zig",
            .step = "run-world-strict",
            .desc = "Run the strict zero-port World example.",
            .expected_stdout =
            \\world_surface_fingerprint=bf39bfbae5e3bb8d
            \\target_certificate_fingerprint=67c91a7de6b021f5
            \\final_result=1
            \\
            ,
        },
        .{
            .name = "world-run-ports",
            .path = "examples/world_run_ports.zig",
            .step = "run-world-ports",
            .desc = "Run the one-port World example.",
            .expected_stdout =
            \\world_surface_fingerprint=1c56147f9e4ab2ff
            \\world_port_id=0
            \\request_fingerprint=1a84e84d29103ea4
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-replay-ports",
            .path = "examples/world_replay_ports.zig",
            .step = "run-world-replay-ports",
            .desc = "Run the one-port replay World example.",
            .expected_stdout =
            \\recorded_interaction_count=1
            \\replayed_interaction_count=1
            \\replay_verified=true
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-agent-loop",
            .path = "examples/world_agent_loop.zig",
            .step = "run-world-agent-loop",
            .desc = "Run the agent-shaped World port example.",
            .serial_after_tests = true,
            .expected_stdout =
            \\skeleton final=final=actuate skeleton complete events=6 tool_calls=1 responses=3
            \\fixture final=final=fixture updated events=10 tool_calls=2 responses=5
            \\fixture output=actuate updated the fixture
            \\replay fresh_handler_calls=0
            \\
            ,
        },
        .{
            .name = "world-agent-closure-fixture",
            .path = "examples/world_agent_loop.zig",
            .step = "run-world-agent-closure-fixture",
            .desc = "Run the World Agent Closure fixture proof surface.",
            .serial_after_tests = true,
            .expected_stdout =
            \\skeleton final=final=actuate skeleton complete events=6 tool_calls=1 responses=3
            \\fixture final=final=fixture updated events=10 tool_calls=2 responses=5
            \\fixture output=actuate updated the fixture
            \\replay fresh_handler_calls=0
            \\
            ,
        },
        .{
            .name = "world-frame-ports",
            .path = "examples/world_frame_ports.zig",
            .step = "run-world-frame-ports",
            .desc = "Run the frame-first one-port World example.",
            .expected_stdout =
            \\request_frame_fingerprint=a2e08a01b91af8f0
            \\response_frame_fingerprint=4cd51f91b59fafb3
            \\world_port_id=0
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-transcript-image-replay",
            .path = "examples/world_transcript_image_replay.zig",
            .step = "run-world-transcript-image-replay",
            .desc = "Run the transcript image replay World example.",
            .expected_stdout =
            \\transcript_image_fingerprint=64fea44e8213ec3
            \\replayed_response_count=1
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-byte-adapter",
            .path = "examples/world_byte_adapter.zig",
            .step = "run-world-byte-adapter",
            .desc = "Run the byte adapter frame World example.",
            .expected_stdout =
            \\request_frame_bytes=193
            \\response_frame_bytes=132
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-agent-timeline",
            .path = "examples/world_agent_timeline.zig",
            .step = "run-world-agent-timeline",
            .desc = "Run the agent timeline World example.",
            .expected_stdout =
            \\transcript_image_fingerprint=aa3dd05381fca5cb
            \\event_count=8
            \\tool_call_count=1
            \\replay_verified=true
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-agent-branch",
            .path = "examples/world_agent_branch.zig",
            .step = "run-world-agent-branch",
            .desc = "Run the agent branch World example.",
            .expected_stdout =
            \\checkpoint_fingerprint=2b11bbc8bca81ece
            \\baseline_transcript_fingerprint=aa3dd05381fca5cb
            \\branch_transcript_fingerprint=7cc91fbb223c4ca
            \\baseline_final_result=final=actuate skeleton complete
            \\branch_final_result=final=branch alternate
            \\
            ,
        },
        .{
            .name = "world-agent-closure-branch",
            .path = "examples/world_agent_branch.zig",
            .step = "run-world-agent-closure-branch",
            .desc = "Run the World Agent Closure branching proof surface.",
            .expected_stdout =
            \\checkpoint_fingerprint=2b11bbc8bca81ece
            \\baseline_transcript_fingerprint=aa3dd05381fca5cb
            \\branch_transcript_fingerprint=7cc91fbb223c4ca
            \\baseline_final_result=final=actuate skeleton complete
            \\branch_final_result=final=branch alternate
            \\
            ,
        },
        .{
            .name = "world-environment-preflight",
            .path = "examples/world_environment_preflight.zig",
            .step = "run-world-environment-preflight",
            .desc = "Run the World environment preflight example.",
            .expected_stdout =
            \\fresh_missing_accepted=false
            \\fresh_blocker=MissingBinding
            \\replay_without_handlers_accepted=true
            \\transcript_image_fingerprint=64fea44e8213ec3
            \\
            ,
        },
        .{
            .name = "world-handoff-parked",
            .path = "examples/world_handoff_parked.zig",
            .step = "run-world-handoff-parked",
            .desc = "Run the parked World handoff example.",
            .expected_stdout =
            \\run_image_fingerprint=3b943d1d096db557
            \\pending_request_fingerprint=a2e08a01b91af8f0
            \\environment_certificate_fingerprint=2fcdb56312f8df07
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-handoff-replay",
            .path = "examples/world_handoff_replay.zig",
            .step = "run-world-handoff-replay",
            .desc = "Run the replay World handoff example.",
            .expected_stdout =
            \\run_image_fingerprint=d8ee6082faeb801c
            \\replayed_response_count=1
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-handoff-verify",
            .path = "examples/world_handoff_verify.zig",
            .step = "run-world-handoff-verify",
            .desc = "Run the verify World handoff example.",
            .expected_stdout =
            \\verification_accepted=true
            \\divergence_detected=true
            \\
            ,
        },
        .{
            .name = "world-agent-handoff",
            .path = "examples/world_agent_handoff.zig",
            .step = "run-world-agent-handoff",
            .desc = "Run the agent World handoff example.",
            .expected_stdout =
            \\run_image_fingerprint=7948ea7d8f9c5e1a
            \\checkpoint_fingerprint=2b11bbc8bca81ece
            \\branch_id=1
            \\model_port_id=0
            \\tool_port_id=1
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-admission-reference",
            .path = "examples/world_admission_reference.zig",
            .step = "run-world-admission-reference",
            .desc = "Run the World admission target-reference example.",
            .expected_stdout =
            \\package_fingerprint=5a5e606018190afc
            \\target_match_fingerprint=c4108ddb5ef704d9
            \\admission_receipt_fingerprint=7a7abbf0a9a25c68
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-admission-full-module-inspect",
            .path = "examples/world_admission_full_module_inspect.zig",
            .step = "run-world-admission-full-module-inspect",
            .desc = "Run the World admission full-module inspect example.",
            .expected_stdout =
            \\module_ref_fingerprint=3a769c854978807e
            \\import_count=1
            \\loaded_execution_supported=false
            \\admission_accepted=true
            \\
            ,
        },
        .{
            .name = "world-admission-parked-handoff",
            .path = "examples/world_admission_parked_handoff.zig",
            .step = "run-world-admission-parked-handoff",
            .desc = "Run the World admission parked handoff example.",
            .expected_stdout =
            \\package_fingerprint=91d0e487f35697a
            \\admission_receipt_fingerprint=fb21a9f962d1b76
            \\receiver_permit_fingerprint=ecb3fc4d74abae17
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-admission-replay-verify",
            .path = "examples/world_admission_replay_verify.zig",
            .step = "run-world-admission-replay-verify",
            .desc = "Run the World admission replay/verify example.",
            .expected_stdout =
            \\replay_admission_receipt=cb717cf457411b58
            \\verify_admission_receipt=59fd3bf2875ada7d
            \\divergence_detected=true
            \\
            ,
        },
        .{
            .name = "world-admission-agent-transfer",
            .path = "examples/world_admission_agent_transfer.zig",
            .step = "run-world-admission-agent-transfer",
            .desc = "Run the World admission agent transfer example.",
            .expected_stdout =
            \\module_ref_fingerprint=8980705f83427fa6
            \\model_port_id=0
            \\tool_port_id=1
            \\admission_receipt=907354d317619aaa
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-runspace-basic",
            .path = "examples/world_runspace_basic.zig",
            .step = "run-world-runspace-basic",
            .desc = "Run the basic World runspace example.",
            .expected_stdout =
            \\run_handle=367cb72b9a8188ae
            \\pending_port_id=0
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-runspace-multi",
            .path = "examples/world_runspace_multi.zig",
            .step = "run-world-runspace-multi",
            .desc = "Run the multi-run World runspace example.",
            .expected_stdout =
            \\first_run=367cb72b9a8188ae
            \\second_run=8d63b7a77a33b921
            \\pending_count=0
            \\completed_count=2
            \\
            ,
        },
        .{
            .name = "world-runspace-handoff",
            .path = "examples/world_runspace_handoff.zig",
            .step = "run-world-runspace-handoff",
            .desc = "Run the handoff World runspace example.",
            .expected_stdout =
            \\admission_receipt=333d360ce96fc3f2
            \\run_handle=77ef6d866cdf5bbe
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-runspace-agent",
            .path = "examples/world_runspace_agent.zig",
            .step = "run-world-runspace-agent",
            .desc = "Run the agent-shaped World runspace example.",
            .expected_stdout =
            \\model_pending_count=2
            \\tool_pending_count=1
            \\event_count=18
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-runspace-supervised",
            .path = "examples/world_runspace_supervised.zig",
            .step = "run-world-runspace-supervised",
            .desc = "Run the supervised World runspace example.",
            .expected_stdout =
            \\run_permit=db74c678137262cd
            \\budget_exceeded=true
            \\event_fingerprint=24d33eb3409f28db
            \\
            ,
        },
        .{
            .name = "world-guest-one-port",
            .path = "examples/world_guest_one_port.zig",
            .step = "run-world-guest-one-port",
            .desc = "Run the World native guest one-port ABI example.",
            .expected_stdout =
            \\request_frame_fingerprint=a2e08a01b91af8f0
            \\response_frame_fingerprint=736978f58eeb5450
            \\result_fingerprint=707f431597801ff8
            \\
            ,
        },
        .{
            .name = "world-guest-conformance",
            .path = "examples/world_guest_conformance.zig",
            .step = "run-world-guest-conformance",
            .desc = "Run the World native guest conformance report example.",
            .expected_stdout =
            \\vector_fingerprint=ba744df419ffe0a0
            \\report_fingerprint=855e9ead253a2060
            \\conformance=true
            \\
            ,
        },
        .{
            .name = "world-guest-agent-conformance",
            .path = "examples/world_guest_agent_conformance.zig",
            .step = "run-world-guest-agent-conformance",
            .desc = "Run the World native guest agent conformance example.",
            .expected_stdout =
            \\model_pending_count=2
            \\tool_pending_count=1
            \\result_fingerprint=367ecd765d905903
            \\conformance=true
            \\
            ,
        },
        .{
            .name = "world-fabric-target-provider",
            .path = "examples/world_fabric_target_provider.zig",
            .step = "run-world-fabric-target-provider",
            .desc = "Run the World Fabric target provider example.",
            .expected_stdout =
            \\parent_run_handle=367cb72b9a8188ae
            \\provider_run_handle=a53ebdcc0976217b
            \\fabric_receipt_fingerprint=679117b4393682a8
            \\final_result=7
            \\native_handler_calls=0
            \\
            ,
        },
        .{
            .name = "world-fabric-agent-tool",
            .path = "examples/world_fabric_agent_tool.zig",
            .step = "run-world-fabric-agent-tool",
            .desc = "Run the World Fabric agent tool example.",
            .expected_stdout =
            \\tool_port_id=1
            \\provider_target_ref=5fd6e98eae4c7db0
            \\fabric_invocation_count=1
            \\native_tool_calls=0
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-fabric-nested",
            .path = "examples/world_fabric_nested.zig",
            .step = "run-world-fabric-nested",
            .desc = "Run the World Fabric nested provider example.",
            .expected_stdout =
            \\fabric_depth=1
            \\parent_result=final=actuate skeleton complete
            \\provider_result=actuate
            \\
            ,
        },
        .{
            .name = "world-fabric-supervised",
            .path = "examples/world_fabric_supervised.zig",
            .step = "run-world-fabric-supervised",
            .desc = "Run the World Fabric supervised denial example.",
            .expected_stdout =
            \\fabric_invocation_count=1
            \\budget_exceeded=true
            \\run_receipt_fingerprint=9a06590f8d75d5eb
            \\
            ,
        },
        .{
            .name = "world-fabric-cycle-blocked",
            .path = "examples/world_fabric_cycle_blocked.zig",
            .step = "run-world-fabric-cycle-blocked",
            .desc = "Run the World Fabric cycle rejection example.",
            .expected_stdout =
            \\cycle_blocked=true
            \\report_fingerprint=6d79f4a5c08b55a8
            \\
            ,
        },
        .{
            .name = "world-linker-one-provider",
            .path = "examples/world_linker_one_provider.zig",
            .step = "run-world-linker-one-provider",
            .desc = "Run the World Linker one-provider example.",
            .expected_stdout =
            \\link_plan_fingerprint=1ba238a635990090
            \\fabric_route_count=1
            \\assembly_fingerprint=bb15a8935e2760db
            \\final_result=7
            \\native_handler_calls=0
            \\
            ,
        },
        .{
            .name = "world-linker-agent-tool",
            .path = "examples/world_linker_agent_tool.zig",
            .step = "run-world-linker-agent-tool",
            .desc = "Run the World Linker agent tool example.",
            .expected_stdout =
            \\resolved_import_count=1
            \\residual_import_count=1
            \\tool_provider_target_ref=eba3f3808cffc694
            \\native_tool_calls=0
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-linker-nested-provider",
            .path = "examples/world_linker_nested_provider.zig",
            .step = "run-world-linker-nested-provider",
            .desc = "Run the World Linker nested provider example.",
            .expected_stdout =
            \\link_depth=2
            \\route_count=2
            \\final_result=7
            \\native_handler_calls=0
            \\
            ,
        },
        .{
            .name = "world-linker-ambiguity",
            .path = "examples/world_linker_ambiguity.zig",
            .step = "run-world-linker-ambiguity",
            .desc = "Run the World Linker ambiguity example.",
            .expected_stdout =
            \\ambiguous_rejected=true
            \\hinted_accepted=true
            \\
            ,
        },
        .{
            .name = "world-linker-cycle-blocked",
            .path = "examples/world_linker_cycle_blocked.zig",
            .step = "run-world-linker-cycle-blocked",
            .desc = "Run the World Linker cycle rejection example.",
            .expected_stdout =
            \\cycle_blocked=true
            \\report_fingerprint=5147d66427118ec5
            \\
            ,
        },
        .{
            .name = "world-linker-guest-conformance",
            .path = "examples/world_linker_guest_conformance.zig",
            .step = "run-world-linker-guest-conformance",
            .desc = "Run the World Linker guest conformance example.",
            .expected_stdout =
            \\assembly_fingerprint=9dd84e749e687387
            \\conformance_report_fingerprint=2656e2c63825bfdb
            \\conformance=true
            \\
            ,
        },
        .{
            .name = "world-capsule-linked-restore",
            .path = "examples/world_capsule_linked_restore.zig",
            .step = "run-world-capsule-linked-restore",
            .desc = "Run the World Assembly Capsule linked restore example.",
            .expected_stdout =
            \\capsule_fingerprint=751785b147113438
            \\link_certificate_fingerprint=2045220a5ff7a9fd
            \\restore_report_fingerprint=7c82875ce3c30859
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-capsule-active-fabric",
            .path = "examples/world_capsule_active_fabric.zig",
            .step = "run-world-capsule-active-fabric",
            .desc = "Run the World Assembly Capsule active Fabric restore example.",
            .expected_stdout =
            \\provider_parked=true
            \\source_destroyed=true
            \\restore_accepted=true
            \\active_fabric_restore_accepted=true
            \\provider_completed=true
            \\root_completed=true
            \\
            ,
        },
        .{
            .name = "world-capsule-agent-transfer",
            .path = "examples/world_capsule_agent_transfer.zig",
            .step = "run-world-capsule-agent-transfer",
            .desc = "Run the World Assembly Capsule agent transfer example.",
            .expected_stdout =
            \\capsule_fingerprint=d80b2f18596b9840
            \\residual_external_import_count=1
            \\receiver_permit_fingerprint=345c1f6beb778a77
            \\restore_accepted=false
            \\final_result=parked-restore-denied
            \\
            ,
        },
        .{
            .name = "world-capsule-relink-mismatch",
            .path = "examples/world_capsule_relink_mismatch.zig",
            .step = "run-world-capsule-relink-mismatch",
            .desc = "Run the World Assembly Capsule relink mismatch example.",
            .expected_stdout =
            \\relink_rejected=true
            \\blocker_tag=relink_drift_rejected
            \\thaw_plan_fingerprint=2b46501661f7345d
            \\
            ,
        },
        .{
            .name = "world-capsule-guest-verify",
            .path = "examples/world_capsule_guest_verify.zig",
            .step = "run-world-capsule-guest-verify",
            .desc = "Run the World Assembly Capsule guest verify example.",
            .expected_stdout =
            \\guest_report_fingerprint=51763d4dbbec2098
            \\restore_report_fingerprint=123fdd3f05347c5
            \\conformance=true
            \\
            ,
        },
        .{
            .name = "world-capsule-supervised-restore",
            .path = "examples/world_capsule_supervised_restore.zig",
            .step = "run-world-capsule-supervised-restore",
            .desc = "Run the World Assembly Capsule supervised restore example.",
            .expected_stdout =
            \\sender_permit_fingerprint=73a49bb41ad4fd0c
            \\receiver_permit_fingerprint=ecb3fc4d74abae17
            \\restore_allowed=false
            \\
            ,
        },
        .{
            .name = "world-actuation-fixture-tool",
            .path = "examples/world_actuation_fixture_tool.zig",
            .step = "run-world-actuation-fixture-tool",
            .desc = "Run the World Actuation fixture tool example.",
            .expected_stdout =
            \\actuator_ref=10721e5b053f1ab3
            \\actuation_receipt_fingerprint=270733fa9b59c508
            \\final_result=fixture-tool-ok
            \\
            ,
        },
        .{
            .name = "world-actuation-agent",
            .path = "examples/world_actuation_agent.zig",
            .step = "run-world-actuation-agent",
            .desc = "Run the World Actuation agent example.",
            .expected_stdout =
            \\model_actuation_calls=1
            \\tool_actuation_calls=1
            \\final_result=agent-actuation-complete
            \\
            ,
        },
        .{
            .name = "world-actuation-replay-verify",
            .path = "examples/world_actuation_replay_verify.zig",
            .step = "run-world-actuation-replay-verify",
            .desc = "Run the World Actuation replay/verify example.",
            .expected_stdout =
            \\fresh_receipt_count=1
            \\replay_fresh_called=false
            \\divergence_detected=true
            \\
            ,
        },
        .{
            .name = "world-actuation-pending-capsule",
            .path = "examples/world_actuation_pending_capsule.zig",
            .step = "run-world-actuation-pending-capsule",
            .desc = "Run the World Actuation pending Capsule example.",
            .expected_stdout =
            \\pending_actuation_intent_fingerprint=b0f6e22106da6b81
            \\capsule_fingerprint=36fd9fe6a214a37f
            \\restore_report_fingerprint=288d2e68c8677716
            \\final_result=true
            \\
            ,
        },
        .{
            .name = "world-actuation-supervised-denial",
            .path = "examples/world_actuation_supervised_denial.zig",
            .step = "run-world-actuation-supervised-denial",
            .desc = "Run the World Actuation supervised denial example.",
            .expected_stdout =
            \\denied_before_call=true
            \\run_receipt_fingerprint=e793c867b110b09a
            \\
            ,
        },
        .{
            .name = "world-actuation-guest-bridge",
            .path = "examples/world_actuation_guest_bridge.zig",
            .step = "run-world-actuation-guest-bridge",
            .desc = "Run the World Actuation guest bridge example.",
            .expected_stdout =
            \\guest_request_fingerprint=acc76001
            \\actuation_receipt_fingerprint=866caf188039e1fe
            \\conformance=true
            \\
            ,
        },
        .{
            .name = "world-actuation-idempotent-retry",
            .path = "examples/world_actuation_idempotent_retry.zig",
            .step = "run-world-actuation-idempotent-retry",
            .desc = "Run the World Actuation idempotent retry example.",
            .expected_stdout =
            \\idempotency_key=7afeff8877b52537
            \\fresh_call_count=1
            \\retry_replayed=true
            \\
            ,
        },
        .{
            .name = "world-appliance-one-port",
            .path = "examples/world_appliance_one_port.zig",
            .step = "run-world-appliance-one-port",
            .desc = "Run the World Appliance one-port example.",
            .expected_stdout =
            \\appliance=one_port
            \\turn_state=waiting_host
            \\actuation_bindings=1
            \\checkpoint_every_turn=true
            \\output_bytes=9000
            \\turn_receipt=b7f4e333a51579cb
            \\
            ,
        },
        .{
            .name = "world-appliance-agent",
            .path = "examples/world_appliance_agent.zig",
            .step = "run-world-appliance-agent",
            .desc = "Run the World Appliance agent protocol example.",
            .expected_stdout =
            \\agent_appliance=core-protocol
            \\external_model_requests=2
            \\internal_tool_provider_targets=1
            \\fabric_plans=1
            \\finalized_actuation_receipts=1
            \\archive_objects=3
            \\final_result=true
            \\
            ,
        },
        .{
            .name = "world-appliance-reconstruct",
            .path = "examples/world_appliance_reconstruct.zig",
            .step = "run-world-appliance-reconstruct",
            .desc = "Run the World Appliance reconstruction example.",
            .expected_stdout =
            \\reconstruction_equivalent=true
            \\resident_output=6d2787f7766186f9
            \\restored_output=6d2787f7766186f9
            \\
            ,
        },
        .{
            .name = "world-appliance-archive",
            .path = "examples/world_appliance_archive.zig",
            .step = "run-world-appliance-archive",
            .desc = "Run the World Appliance archive example.",
            .expected_stdout =
            \\archive_batches=1
            \\output_archive_request=f92ac1845c38f100
            \\archive_objects=3
            \\retention_ack=579149e5679d9de0
            \\moment=5de8f61f92b66d71
            \\
            ,
        },
        .{
            .name = "world-appliance-replay",
            .path = "examples/world_appliance_replay.zig",
            .step = "run-world-appliance-replay",
            .desc = "Run the World Appliance replay example.",
            .expected_stdout =
            \\fresh_host_requests=1
            \\replay_supported=false
            \\actuated_replay_rejected=true
            \\
            ,
        },
        .{
            .name = "world-turn-closure-one-port",
            .path = "examples/world_turn_closure_one_port.zig",
            .step = "run-world-turn-closure-one-port",
            .desc = "Run the World Turn Closure one-port example.",
            .expected_stdout =
            \\closure_valid=true
            \\host_requests=1
            \\result_bytes_present=true
            \\archive_append_present=true
            \\
            ,
        },
        .{
            .name = "world-turn-closure-agent",
            .path = "examples/world_turn_closure_agent.zig",
            .step = "run-world-turn-closure-agent",
            .desc = "Run the World Turn Closure loaded-agent example.",
            .expected_stdout =
            \\root_loaded=true
            \\provider_loaded=true
            \\external_model_requests=2
            \\internal_tool_invocations=1
            \\final_result=final=actuate skeleton complete
            \\closure_valid=true
            \\
            ,
        },
        .{
            .name = "world-agent-closure-skeleton",
            .path = "examples/world_turn_closure_agent.zig",
            .step = "run-world-agent-closure-skeleton",
            .desc = "Run the World Agent Closure skeleton proof surface.",
            .expected_stdout =
            \\root_loaded=true
            \\provider_loaded=true
            \\external_model_requests=2
            \\internal_tool_invocations=1
            \\final_result=final=actuate skeleton complete
            \\closure_valid=true
            \\
            ,
        },
        .{
            .name = "world-turn-closure-active-fabric-migrate",
            .path = "examples/world_turn_closure_active_fabric_migrate.zig",
            .step = "run-world-turn-closure-active-fabric-migrate",
            .desc = "Run the World Turn Closure active Fabric migration example.",
            .expected_stdout =
            \\provider_parked=true
            \\source_destroyed=true
            \\restore_accepted=true
            \\active_fabric_restore_accepted=true
            \\provider_completed=true
            \\root_completed=true
            \\
            ,
        },
        .{
            .name = "world-agent-closure-migrate",
            .path = "examples/world_turn_closure_active_fabric_migrate.zig",
            .step = "run-world-agent-closure-migrate",
            .desc = "Run the World Agent Closure migration proof surface.",
            .expected_stdout =
            \\provider_parked=true
            \\source_destroyed=true
            \\restore_accepted=true
            \\active_fabric_restore_accepted=true
            \\provider_completed=true
            \\root_completed=true
            \\
            ,
        },
        .{
            .name = "world-turn-closure-replay",
            .path = "examples/world_turn_closure_replay.zig",
            .step = "run-world-turn-closure-replay",
            .desc = "Run the World Turn Closure actuated replay rejection example.",
            .expected_stdout =
            \\fresh_host_requests=1
            \\replay_supported=false
            \\actuated_replay_rejected=true
            \\
            ,
        },
        .{
            .name = "world-agent-closure-replay",
            .path = "examples/world_turn_closure_replay.zig",
            .step = "run-world-agent-closure-replay",
            .desc = "Run the World Agent Closure replay proof surface.",
            .expected_stdout =
            \\fresh_host_requests=1
            \\replay_supported=false
            \\actuated_replay_rejected=true
            \\
            ,
        },
        .{
            .name = "world-turn-closure-batch",
            .path = "examples/world_turn_closure_batch.zig",
            .step = "run-world-turn-closure-batch",
            .desc = "Run the World Turn Closure batched host turn example.",
            .expected_stdout =
            \\initial_requests=2
            \\reverse_replies_accepted=true
            \\partial_batch_preserved=true
            \\completed=true
            \\
            ,
        },
        .{
            .name = "world-turn-closure-retry",
            .path = "examples/world_turn_closure_retry.zig",
            .step = "run-world-turn-closure-retry",
            .desc = "Run the World Turn Closure deterministic retry example.",
            .expected_stdout =
            \\effect_call_count=1
            \\closure_retry_equal=true
            \\archive_batch_retry_equal=true
            \\
            ,
        },
        .{
            .name = "world-agent-closure-retry",
            .path = "examples/world_turn_closure_retry.zig",
            .step = "run-world-agent-closure-retry",
            .desc = "Run the World Agent Closure deterministic retry proof surface.",
            .expected_stdout =
            \\effect_call_count=1
            \\closure_retry_equal=true
            \\archive_batch_retry_equal=true
            \\
            ,
        },
        .{
            .name = "world-turn-closure-two-programs-one-wasm",
            .path = "examples/world_turn_closure_two_programs_one_wasm.zig",
            .step = "run-world-turn-closure-two-programs-one-wasm",
            .desc = "Run the World Turn Closure two-programs-one-WASM proof surface.",
            .expected_stdout =
            \\wasm_sha_equal=true
            \\program_plan_a_not_equal_b=true
            \\image_a_completed=true
            \\image_b_completed=true
            \\fresh_instance_repeat=true
            \\
            ,
        },
        .{
            .name = "world-turn-closure-js-host",
            .path = "examples/world_turn_closure_js_host.zig",
            .step = "run-world-turn-closure-js-host",
            .desc = "Run the World Turn Closure independent JavaScript host proof surface.",
            .expected_stdout =
            \\native_helper_used=false
            \\javascript_codec_independent=true
            \\loaded_agent_completed=true
            \\
            ,
        },
        .{
            .name = "world-v0-report",
            .path = "examples/world_v0_report.zig",
            .step = "run-world-v0-report",
            .desc = "Run the World v0 fail-closed proof report.",
            .expected_stdout =
            \\world_v0_complete=false
            \\two_program_plans_one_wasm=false
            \\loaded_internal_provider_executed=false
            \\active_fabric_restore_accepted=false
            \\verified_replay_without_fresh_effect=false
            \\actuated_replay_supported=false
            \\unsupported_actuated_replay_rejected=false
            \\javascript_codec_independent=false
            \\deterministic_retry=false
            \\universal_memory_bound_passed=false
            \\
            ,
        },
        .{
            .name = "world-appliance-wasm-probe",
            .path = "examples/world_appliance_wasm_probe.zig",
            .step = "run-world-appliance-wasm-probe",
            .desc = "Run the World Appliance WASM probe example.",
            .expected_stdout =
            \\appliance_abi_version=4
            \\manifest=1cd97157f2d1ac8e
            \\capacity=5fcf964fbaa4a66b
            \\memory_plan=ed1c9222ab3bed1d
            \\required_exports=9
            \\forbidden_import_count=0
            \\
            ,
        },
        .{
            .name = "world-continuity-capsule-basic",
            .path = "examples/world_continuity_capsule_basic.zig",
            .step = "run-world-continuity-capsule-basic",
            .desc = "Run the World Continuity capsule basic example.",
            .expected_stdout =
            \\stored_object_count=1
            \\capsule_ref=4e304187d2f4f22a
            \\capsule_certificate_ref=0
            \\graph_restorable=true
            \\graph_replayable=false
            \\
            ,
        },
        .{
            .name = "world-continuity-actuation",
            .path = "examples/world_continuity_actuation.zig",
            .step = "run-world-continuity-actuation",
            .desc = "Run the World Continuity actuation example.",
            .expected_stdout =
            \\actuation_receipt_ref=2e34efed86e4104e
            \\idempotency_key_ref=99a8c7e8fafb160c
            \\lookup_matches=true
            \\replay_fresh_called=false
            \\
            ,
        },
        .{
            .name = "world-continuity-bundle-roundtrip",
            .path = "examples/world_continuity_bundle_roundtrip.zig",
            .step = "run-world-continuity-bundle-roundtrip",
            .desc = "Run the World Continuity bundle roundtrip example.",
            .expected_stdout =
            \\bundle_fingerprint=9fa869dd110a951d
            \\imported_object_count=2
            \\capsule_restored_to_inspectable_state=true
            \\
            ,
        },
        .{
            .name = "world-continuity-pending-actuation",
            .path = "examples/world_continuity_pending_actuation.zig",
            .step = "run-world-continuity-pending-actuation",
            .desc = "Run the World Continuity pending actuation example.",
            .expected_stdout =
            \\capsule_ref=db8cf7a211f5e66f
            \\pending_actuation_count=1
            \\local_fresh_actuation_required=true
            \\
            ,
        },
        .{
            .name = "world-continuity-agent-evidence",
            .path = "examples/world_continuity_agent_evidence.zig",
            .step = "run-world-continuity-agent-evidence",
            .desc = "Run the World Continuity agent evidence example.",
            .expected_stdout =
            \\capsule_ref=4e304187d2f4f22a
            \\model_receipt_count=1
            \\tool_receipt_count=1
            \\final_result=continuity-agent-evidence-ok
            \\
            ,
        },
        .{
            .name = "world-chronicle-capsule-commit",
            .path = "examples/world_chronicle_capsule_commit.zig",
            .step = "run-world-chronicle-capsule-commit",
            .desc = "Run the World Chronicle capsule commit example.",
            .expected_stdout =
            \\capsule_ref=4e304187d2f4f22a
            \\commit_fingerprint=6f80cd831effde0f
            \\cursor_fingerprint=386a1edab305e25e
            \\final_result=chronicle-capsule-commit-ok
            \\
            ,
        },
        .{
            .name = "world-chronicle-actuation-idempotency",
            .path = "examples/world_chronicle_actuation_idempotency.zig",
            .step = "run-world-chronicle-actuation-idempotency",
            .desc = "Run the World Chronicle actuation idempotency example.",
            .expected_stdout =
            \\idempotency_key=e3245b76f64e8a52
            \\first_receipt_ref=b9f7c4e98ad23f57
            \\duplicate_fresh_rejected=true
            \\replay_fresh_called=false
            \\
            ,
        },
        .{
            .name = "world-chronicle-replay-projection",
            .path = "examples/world_chronicle_replay_projection.zig",
            .step = "run-world-chronicle-replay-projection",
            .desc = "Run the World Chronicle replay projection example.",
            .expected_stdout =
            \\event_count=7
            \\replay_report_fingerprint=e9c3783fb57b22ed
            \\projection_match=true
            \\
            ,
        },
        .{
            .name = "world-chronicle-bundle-inbox",
            .path = "examples/world_chronicle_bundle_inbox.zig",
            .step = "run-world-chronicle-bundle-inbox",
            .desc = "Run the World Chronicle bundle inbox example.",
            .expected_stdout =
            \\outbound_envelope_ref=c3116af50c6f6b44
            \\inbound_envelope_ref=7c47ab7fa67d5ce5
            \\accepted=true
            \\
            ,
        },
        .{
            .name = "world-chronicle-recovery",
            .path = "examples/world_chronicle_recovery.zig",
            .step = "run-world-chronicle-recovery",
            .desc = "Run the World Chronicle recovery example.",
            .expected_stdout =
            \\recovery_plan_fingerprint=27938c27164edc83
            \\recovery_report_fingerprint=3998020aaa985f10
            \\restored=true
            \\final_result=chronicle-recovery-ok
            \\
            ,
        },
        .{
            .name = "world-chronicle-agent-evidence",
            .path = "examples/world_chronicle_agent_evidence.zig",
            .step = "run-world-chronicle-agent-evidence",
            .desc = "Run the World Chronicle agent evidence example.",
            .expected_stdout =
            \\capsule_ref=4e304187d2f4f22a
            \\model_receipt_count=1
            \\tool_receipt_count=1
            \\bundle_fingerprint=62e288ea95e3976e
            \\projection_replay=true
            \\
            ,
        },
        .{
            .name = "world-supervised-budget",
            .path = "examples/world_supervised_budget.zig",
            .step = "run-world-supervised-budget",
            .desc = "Run the supervised budget World example.",
            .expected_stdout =
            \\permit_fingerprint=c11a8a7cc7e075e3
            \\receipt_fingerprint=4ee32606a3a26370
            \\budget_exceeded=false
            \\denied_budget_exceeded=true
            \\
            ,
        },
        .{
            .name = "world-supervised-agent",
            .path = "examples/world_supervised_agent.zig",
            .step = "run-world-supervised-agent",
            .desc = "Run the supervised agent World example.",
            .expected_stdout =
            \\model_port_calls=2
            \\tool_port_calls=1
            \\total_cost_units=13
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-supervised-handoff",
            .path = "examples/world_supervised_handoff.zig",
            .step = "run-world-supervised-handoff",
            .desc = "Run the supervised handoff World example.",
            .expected_stdout =
            \\received_run_image_fingerprint=8df1c085adc3793c
            \\receiver_permit_fingerprint=ecb3fc4d74abae17
            \\receiver_receipt_fingerprint=3c533ec8543aadff
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-supervised-branch",
            .path = "examples/world_supervised_branch.zig",
            .step = "run-world-supervised-branch",
            .desc = "Run the supervised branch World example.",
            .expected_stdout =
            \\checkpoint_fingerprint=287104bce23139a9
            \\first_branch_result=allowed
            \\second_branch_denied=true
            \\
            ,
        },
        .{
            .name = "world-supervised-replay-verify",
            .path = "examples/world_supervised_replay_verify.zig",
            .step = "run-world-supervised-replay-verify",
            .desc = "Run the supervised replay/verify World example.",
            .expected_stdout =
            \\fresh_receipt=3b6c735821d53445
            \\replay_receipt=a8342ecb285cd279
            \\verify_divergence_detected=true
            \\
            ,
        },
    };
    var previous_serial_example_step: ?*std.Build.Step = null;
    inline for (examples) |example| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = validation_target,
            .optimize = optimize,
        });
        exe_mod.addImport("world", world);
        exe_mod.addImport("boundary", boundary);
        exe_mod.addImport("world_fixtures", fixtures);
        const exe = b.addExecutable(.{ .name = example.name, .root_module = exe_mod });
        const run_step = b.step(example.step, example.desc);
        if (validation_target.query.isNative()) {
            const run = addRunArtifactWithArgs(b, exe, if (b.args) |args| args else &.{});
            run.expectStdOutEqual(example.expected_stdout);
            if (example.serial_after_tests) {
                run.step.dependOn(test_step);
                if (previous_serial_example_step) |previous| {
                    run.step.dependOn(previous);
                }
                previous_serial_example_step = &run.step;
            }
            run_step.dependOn(&run.step);
        } else {
            run_step.dependOn(&exe.step);
            b.default_step.dependOn(&exe.step);
        }
        check_step.dependOn(run_step);
        if (std.mem.startsWith(u8, example.step, "run-world-seed-")) {
            check_world_seed_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-seed-reject")) {
            check_world_seed_malformed_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-capsule-active-fabric")) {
            check_world_active_fabric_restore_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-turn-closure-one-port")) {
            check_world_turn_closure_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-turn-closure-agent")) {
            check_world_turn_closure_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-turn-closure-active-fabric-migrate")) {
            check_world_active_fabric_restore_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-turn-closure-batch")) {
            check_world_appliance_batching_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-turn-closure-retry")) {
            check_world_deterministic_retry_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-turn-closure-replay")) {
            check_world_replay_positive_step.dependOn(run_step);
            check_world_v0_negative_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-turn-closure-two-programs-one-wasm")) {
            check_world_two_programs_one_wasm_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-turn-closure-js-host")) {
            check_world_js_codec_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-agent-closure-skeleton") or
            std.mem.eql(u8, example.step, "run-world-agent-closure-fixture"))
        {
            check_world_agent_closure_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-agent-closure-replay") or
            std.mem.eql(u8, example.step, "run-world-agent-closure-retry"))
        {
            check_world_agent_replay_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-agent-closure-migrate") or
            std.mem.eql(u8, example.step, "run-world-agent-closure-branch"))
        {
            check_world_agent_migration_step.dependOn(run_step);
        }
        if (std.mem.eql(u8, example.step, "run-world-v0-report")) {
            check_world_v0_step.dependOn(run_step);
        }
    }

    const wasm_export_check_mod = b.createModule(.{
        .root_source_file = b.path("examples/world_wasm_export_check.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    wasm_export_check_mod.addImport("world", host_world);
    const wasm_export_check = b.addExecutable(.{ .name = "world-wasm-export-check", .root_module = wasm_export_check_mod });
    const run_wasm_export_check = b.addRunArtifact(wasm_export_check);
    run_wasm_export_check.addFileArg(wasm_guest.getEmittedBin());
    const wasm_export_check_step = b.step("run-world-wasm-export-check", "Inspect World wasm guest exports and imports.");
    wasm_export_check_step.dependOn(&run_wasm_export_check.step);
    check_world_wasm_step.dependOn(&run_wasm_export_check.step);
    check_step.dependOn(check_world_wasm_step);
    const appliance_wasm_export_check_mod = b.createModule(.{
        .root_source_file = b.path("examples/world_appliance_wasm_export_check.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    appliance_wasm_export_check_mod.addImport("world", host_world);
    appliance_wasm_export_check_mod.addImport("world_fixtures", host_fixtures);
    const appliance_wasm_export_check = b.addExecutable(.{ .name = "world-appliance-wasm-export-check", .root_module = appliance_wasm_export_check_mod });
    const run_appliance_wasm_export_check = b.addRunArtifact(appliance_wasm_export_check);
    run_appliance_wasm_export_check.addFileArg(appliance_wasm.getEmittedBin());
    const appliance_wasm_export_check_step = b.step("run-world-appliance-wasm-export-check", "Inspect World Appliance wasm exports and imports.");
    appliance_wasm_export_check_step.dependOn(&run_appliance_wasm_export_check.step);
    check_world_appliance_wasm_step.dependOn(&run_appliance_wasm_export_check.step);
    check_step.dependOn(check_world_appliance_wasm_step);
    const universal_appliance_wasm_export_check_mod = b.createModule(.{
        .root_source_file = b.path("examples/world_universal_appliance_wasm_export_check.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    universal_appliance_wasm_export_check_mod.addImport("world", host_world);
    const universal_appliance_wasm_export_check = b.addExecutable(.{ .name = "world-universal-appliance-wasm-export-check", .root_module = universal_appliance_wasm_export_check_mod });
    const run_universal_appliance_wasm_export_check = b.addRunArtifact(universal_appliance_wasm_export_check);
    run_universal_appliance_wasm_export_check.addFileArg(universal_appliance_wasm.getEmittedBin());
    const universal_appliance_wasm_export_check_step = b.step("run-world-universal-appliance-wasm-export-check", "Inspect World universal Appliance ABI conformance wasm exports and imports.");
    universal_appliance_wasm_export_check_step.dependOn(&run_universal_appliance_wasm_export_check.step);
    check_world_universal_appliance_wasm_step.dependOn(&run_universal_appliance_wasm_export_check.step);
    check_world_universal_step.dependOn(check_world_universal_appliance_wasm_step);
    check_step.dependOn(check_world_universal_appliance_wasm_step);
    const run_wasm_one_port_step = b.step("run-world-wasm-one-port", "Optionally run the World wasm one-port guest with an external runtime.");
    const skip_wasm_runtime = b.addSystemCommand(&.{
        "sh",
        "-c",
        "echo 'wasm_runtime=skipped'; echo 'reason=external runtime host not configured'",
    });
    skip_wasm_runtime.step.dependOn(&wasm_guest.step);
    run_wasm_one_port_step.dependOn(&skip_wasm_runtime.step);

    const lint_step = b.step("lint", "Run formatting and hot-path source guards.");
    const fmt_check = b.addSystemCommand(&.{
        "zig",
        "fmt",
        "--check",
        "build.zig",
        "src",
        "examples",
        "test",
    });
    lint_step.dependOn(&fmt_check.step);
    const hot_path_guard = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\if grep -n -E 'TreatyResolver|ProviderHarness|provider_catalog|morphism_catalog|closure_graph|normalize|operation_label_dispatch|string_match_dispatch|transcript_image.*StoredValue|StoredValue.*transcript_image|request_token|thread_id' src/world.zig; then
        \\  echo "forbidden hot-path surface reference found" >&2
        \\  exit 1
        \\fi
    });
    lint_step.dependOn(&hot_path_guard.step);
    check_step.dependOn(lint_step);
}
