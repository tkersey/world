const std = @import("std");

const wasm_page_bytes: u64 = 64 * 1024;
const wasm_maximum_pages: u32 = 65_536;
const minimum_initial_pages: u32 = 512;

pub const Memory = struct {
    initial_pages: u32 = 512,
    maximum_pages: u32 = 512,
};

pub const Options = struct {
    name: []const u8,
    root_source_file: std.Build.LazyPath,
    application_decl: []const u8 = "Application",
    optimize: std.builtin.OptimizeMode = .ReleaseSmall,
    stack_size_bytes: u64 = 1024 * 1024,
    memory: Memory = .{},
    install_human_readable_manifest: bool = false,
};

pub const ApplicationWasm = struct {
    wasm: *std.Build.Step.Compile,
    manifest: std.Build.LazyPath,
    human_readable_manifest: std.Build.LazyPath,
    check_step: *std.Build.Step,
    install_step: *std.Build.Step,
};

pub fn add(
    b: *std.Build,
    comptime world_build_zig: type,
    options: Options,
) ApplicationWasm {
    validateOptions(options);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const wasm_world_dependency = b.dependencyFromBuildZig(world_build_zig, .{
        .target = wasm_target,
        .optimize = options.optimize,
    });
    const wasm_world = wasm_world_dependency.module("world");
    const wasm_boundary = wasm_world_dependency.builder.dependency("boundary_machine", .{
        .target = wasm_target,
        .optimize = options.optimize,
    }).module("boundary");

    const host_world_dependency = b.dependencyFromBuildZig(world_build_zig, .{
        .target = b.graph.host,
        .optimize = options.optimize,
    });
    const host_world = host_world_dependency.module("world");
    const host_boundary = host_world_dependency.builder.dependency("boundary_machine", .{
        .target = b.graph.host,
        .optimize = options.optimize,
    }).module("boundary");

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "application_decl", options.application_decl);

    const wasm_application_source = b.createModule(.{
        .root_source_file = options.root_source_file,
        .target = wasm_target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "world", .module = wasm_world },
            .{ .name = "boundary", .module = wasm_boundary },
        },
    });
    const wasm_application = b.createModule(.{
        .root_source_file = wasm_world_dependency.path("src/application_selector_v1.zig"),
        .target = wasm_target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "world_application_source", .module = wasm_application_source },
            .{ .name = "world_application_build_options", .module = build_options.createModule() },
        },
    });
    const wasm = b.addExecutable(.{
        .name = b.fmt("{s}.world", .{options.name}),
        .root_module = b.createModule(.{
            .root_source_file = wasm_world_dependency.path("src/application_wasm_main_v1.zig"),
            .target = wasm_target,
            .optimize = options.optimize,
            .imports = &.{
                .{ .name = "world", .module = wasm_world },
                .{ .name = "world_application", .module = wasm_application },
            },
        }),
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.export_memory = true;
    wasm.stack_size = options.stack_size_bytes;
    wasm.initial_memory = pagesToBytes(options.memory.initial_pages);
    wasm.max_memory = pagesToBytes(options.memory.maximum_pages);

    const host_application_source = b.createModule(.{
        .root_source_file = options.root_source_file,
        .target = b.graph.host,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "world", .module = host_world },
            .{ .name = "boundary", .module = host_boundary },
        },
    });
    const host_application = b.createModule(.{
        .root_source_file = host_world_dependency.path("src/application_selector_v1.zig"),
        .target = b.graph.host,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "world_application_source", .module = host_application_source },
            .{ .name = "world_application_build_options", .module = build_options.createModule() },
        },
    });
    const manifest_emitter = b.addExecutable(.{
        .name = b.fmt("{s}-world-manifest", .{options.name}),
        .root_module = b.createModule(.{
            .root_source_file = host_world_dependency.path("src/application_manifest_emit_v1.zig"),
            .target = b.graph.host,
            .optimize = options.optimize,
            .imports = &.{
                .{ .name = "world_application", .module = host_application },
            },
        }),
    });
    const run_manifest_emitter = b.addRunArtifact(manifest_emitter);
    const manifest = run_manifest_emitter.addOutputFileArg(
        b.fmt("{s}.manifest.bin", .{options.name}),
    );
    const human_manifest = run_manifest_emitter.addOutputFileArg(
        b.fmt("{s}.manifest.txt", .{options.name}),
    );

    const check = b.addSystemCommand(&.{
        "node",
    });
    check.addFileArg(wasm_world_dependency.path(
        "scripts/world_application_v1_artifact_check.mjs",
    ));
    check.addFileArg(wasm.getEmittedBin());
    check.addFileArg(manifest);
    check.addArg(b.fmt("{d}", .{options.memory.initial_pages}));
    check.addArg(b.fmt("{d}", .{options.memory.maximum_pages}));
    const check_step = b.step(
        b.fmt("check-{s}-world-application", .{options.name}),
        b.fmt("Inspect {s}.world.wasm and verify its canonical manifest.", .{options.name}),
    );
    check_step.dependOn(&check.step);

    const install_wasm = b.addInstallFile(
        wasm.getEmittedBin(),
        b.fmt("world-apps/{s}.world.wasm", .{options.name}),
    );
    install_wasm.step.dependOn(&check.step);
    const install_manifest = b.addInstallFile(
        manifest,
        b.fmt("world-apps/{s}.manifest.bin", .{options.name}),
    );
    install_manifest.step.dependOn(&check.step);
    const install_step = b.step(
        b.fmt("install-{s}-world-application", .{options.name}),
        b.fmt("Install the checked {s} World application artifacts.", .{options.name}),
    );
    install_step.dependOn(&install_wasm.step);
    install_step.dependOn(&install_manifest.step);
    if (options.install_human_readable_manifest) {
        const install_human_manifest = b.addInstallFile(
            human_manifest,
            b.fmt("world-apps/{s}.manifest.txt", .{options.name}),
        );
        install_human_manifest.step.dependOn(&check.step);
        install_step.dependOn(&install_human_manifest.step);
    }
    b.getInstallStep().dependOn(install_step);

    return .{
        .wasm = wasm,
        .manifest = manifest,
        .human_readable_manifest = human_manifest,
        .check_step = check_step,
        .install_step = install_step,
    };
}

fn validateOptions(options: Options) void {
    if (options.name.len == 0 or !std.ascii.isAlphanumeric(options.name[0])) {
        std.debug.panic(
            "World application artifact name must start with an ASCII letter or digit",
            .{},
        );
    }
    for (options.name) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '-' and byte != '_') {
            std.debug.panic(
                "World application artifact name may contain only ASCII letters, digits, '-' and '_'",
                .{},
            );
        }
    }
    if (options.application_decl.len == 0) {
        std.debug.panic("World application declaration name must not be empty", .{});
    }
    if (options.stack_size_bytes == 0 or
        options.stack_size_bytes > wasm_maximum_pages * wasm_page_bytes)
    {
        std.debug.panic(
            "World application stack size ({d} bytes) must fit a non-empty wasm32 memory",
            .{options.stack_size_bytes},
        );
    }
    if (options.memory.initial_pages < minimum_initial_pages) {
        std.debug.panic(
            "World application initial memory ({d} pages) is smaller than the supported ABI layout ({d} pages)",
            .{ options.memory.initial_pages, minimum_initial_pages },
        );
    }
    if (options.memory.maximum_pages < options.memory.initial_pages) {
        std.debug.panic(
            "World application maximum memory ({d} pages) is smaller than initial memory ({d} pages)",
            .{ options.memory.maximum_pages, options.memory.initial_pages },
        );
    }
    if (options.memory.maximum_pages > wasm_maximum_pages) {
        std.debug.panic(
            "World application maximum memory ({d} pages) exceeds the wasm32 limit ({d} pages)",
            .{ options.memory.maximum_pages, wasm_maximum_pages },
        );
    }
}

fn pagesToBytes(pages: u32) u64 {
    return @as(u64, pages) * wasm_page_bytes;
}
