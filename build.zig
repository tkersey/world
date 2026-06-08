const std = @import("std");

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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_args = parseTestArgs(b);

    const boundary_dep = b.dependency("boundary", .{
        .target = target,
        .optimize = optimize,
    });
    const boundary = boundary_dep.module("boundary");

    const world = b.addModule("world", .{
        .root_source_file = b.path("src/world.zig"),
        .target = target,
        .optimize = optimize,
    });
    world.addImport("boundary", boundary);

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

    const fixtures = b.createModule(.{
        .root_source_file = b.path("test/fixtures.zig"),
        .target = target,
        .optimize = optimize,
    });
    fixtures.addImport("world", world);
    fixtures.addImport("boundary", boundary);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/world_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = test_args.filters,
    });
    const wasm_guest_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/world_wasm_guest_one_port.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
        .filters = test_args.filters,
    });
    const test_step = b.step("test", "Run world tests.");
    test_step.dependOn(&addRunArtifactWithArgs(b, wasm_guest_tests, test_args.passthrough).step);
    if (target.query.isNative()) {
        test_step.dependOn(&addRunArtifactWithArgs(b, tests, test_args.passthrough).step);
        b.default_step.dependOn(test_step);
    } else {
        test_step.dependOn(&tests.step);
        b.default_step.dependOn(&tests.step);
    }

    const forged_descriptor_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/forged_descriptor_metadata.zig"),
            .target = target,
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
    const compile_fail_step = b.step("compile-fail", "Run compile-fail tests.");
    compile_fail_step.dependOn(&forged_descriptor_test.step);

    const check_step = b.step("check", "Run tests, compile-fail tests, examples, and lint.");
    check_step.dependOn(test_step);
    check_step.dependOn(compile_fail_step);

    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
        step: []const u8,
        desc: []const u8,
        expected_stdout: []const u8,
    }{
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
            \\run_image_fingerprint=2a756533ff6b01a0
            \\pending_request_fingerprint=a2e08a01b91af8f0
            \\environment_certificate_fingerprint=60e3e121377e684b
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
            \\admission_receipt_fingerprint=9e30a4644cb44726
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
            \\module_ref_fingerprint=88a2146555397dad
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
            \\admission_receipt_fingerprint=7f75ea1ee291546c
            \\receiver_permit_fingerprint=30ffec689f79edcb
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
            \\replay_admission_receipt=136a9faa9634a2c1
            \\verify_admission_receipt=2959f3764807556f
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
            \\admission_receipt=41dea35ff8f5c5a9
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
            \\admission_receipt=6785461ae1ab7c6e
            \\run_handle=6b117952acd3ba08
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
            \\run_permit=5b0b15a25142501a
            \\budget_exceeded=true
            \\event_fingerprint=2f1ee9cd165c5584
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
            \\result_fingerprint=ea09e4f1b61811a2
            \\
            ,
        },
        .{
            .name = "world-guest-conformance",
            .path = "examples/world_guest_conformance.zig",
            .step = "run-world-guest-conformance",
            .desc = "Run the World native guest conformance report example.",
            .expected_stdout =
            \\vector_fingerprint=b769d2f98dc5f015
            \\report_fingerprint=999b3f8415c77e85
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
            \\result_fingerprint=706c81aa38b274da
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
            \\fabric_receipt_fingerprint=33d8e8ba055c1f54
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
            \\run_receipt_fingerprint=5a1a3633c012b161
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
            \\conformance_report_fingerprint=2a041350c9148d51
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
            \\capsule_fingerprint=6449041ef0225991
            \\link_certificate_fingerprint=2045220a5ff7a9fd
            \\restore_report_fingerprint=6d09ac90404384a3
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
            \\active_fabric_invocation_fingerprint=6e1ba40ac216edb1
            \\pending_provider_port_fingerprint=423eef2930e63077
            \\restore_report_fingerprint=9332065ccdd19729
            \\restore_accepted=false
            \\final_result=active-fabric-restore-denied
            \\
            ,
        },
        .{
            .name = "world-capsule-agent-transfer",
            .path = "examples/world_capsule_agent_transfer.zig",
            .step = "run-world-capsule-agent-transfer",
            .desc = "Run the World Assembly Capsule agent transfer example.",
            .expected_stdout =
            \\capsule_fingerprint=32c33e5c253635b2
            \\residual_external_import_count=1
            \\receiver_permit_fingerprint=aaf08a876eb0a575
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
            \\guest_report_fingerprint=dc1c585b58e0b71c
            \\restore_report_fingerprint=4dda9c0bab78f2fb
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
            \\sender_permit_fingerprint=48eabe6cda74e08
            \\receiver_permit_fingerprint=30ffec689f79edcb
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
            \\actuation_receipt_fingerprint=c19b7c207ab0fd9
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
            \\pending_actuation_intent_fingerprint=a62d585903daa774
            \\capsule_fingerprint=7142da3924c9f5b4
            \\restore_report_fingerprint=135cd309b4c8f7c0
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
            \\run_receipt_fingerprint=f0144260342dfa89
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
            \\actuation_receipt_fingerprint=a0a54725dfe664bb
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
            .name = "world-supervised-budget",
            .path = "examples/world_supervised_budget.zig",
            .step = "run-world-supervised-budget",
            .desc = "Run the supervised budget World example.",
            .expected_stdout =
            \\permit_fingerprint=8b39b7019b7be7a9
            \\receipt_fingerprint=2dd236c102a55aa
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
            \\received_run_image_fingerprint=6cea7d4323c86325
            \\receiver_permit_fingerprint=30ffec689f79edcb
            \\receiver_receipt_fingerprint=8c004f433956a051
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
            \\fresh_receipt=71aa6b249c07f6c1
            \\replay_receipt=a8d5b2162d792f1d
            \\verify_divergence_detected=true
            \\
            ,
        },
    };
    inline for (examples) |example| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport("world", world);
        exe_mod.addImport("boundary", boundary);
        exe_mod.addImport("world_fixtures", fixtures);
        const exe = b.addExecutable(.{ .name = example.name, .root_module = exe_mod });
        const run_step = b.step(example.step, example.desc);
        if (target.query.isNative()) {
            const run = addRunArtifactWithArgs(b, exe, if (b.args) |args| args else &.{});
            run.expectStdOutEqual(example.expected_stdout);
            run_step.dependOn(&run.step);
        } else {
            run_step.dependOn(&exe.step);
            b.default_step.dependOn(&exe.step);
        }
        check_step.dependOn(run_step);
    }

    const host_boundary_dep = b.dependency("boundary", .{
        .target = b.graph.host,
        .optimize = optimize,
    });
    const host_boundary = host_boundary_dep.module("boundary");
    const host_world = b.createModule(.{
        .root_source_file = b.path("src/world.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    host_world.addImport("boundary", host_boundary);
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
