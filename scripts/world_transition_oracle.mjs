#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { TextDecoder } from 'node:util';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

const expectedCases = [
  'one-port-execution',
  'internal-provider-execution',
  'provider-parked-externally',
  'active-provider-restore',
  'replay-without-fresh-effect',
  'lost-output-retry',
  'migration',
  'branching',
  'partial-response-batch',
  'deterministic-failure',
  'capacity-exhaustion',
  'malformed-records',
];

const requiredTranscriptFacts = {
  'one-port-execution': [
    'case_id: one-port-execution',
    'owner_surface: Appliance/TurnClosure',
    'waiting_status: needs_host',
    'completed_status: completed',
    'request_count: 1',
  ],
  'internal-provider-execution': [
    'case_id: internal-provider-execution',
    'owner_surface: Executable/Runspace/Fabric/TurnClosure',
    'status: completed',
    'provider_module_count: 1',
    'external_request_count: 0',
  ],
  'provider-parked-externally': [
    'case_id: provider-parked-externally',
    'owner_surface: Runspace/Fabric/Capsule',
    'fixture_provenance: synthetic-owner-state',
    'fabric_invocation_status: provider_parked',
  ],
  'active-provider-restore': [
    'case_id: active-provider-restore',
    'owner_surface: Capsule/Runspace/Fabric',
    'fixture_provenance: synthetic-owner-state',
    'restore_accepted: true',
    'restore_evidence_scope: metadata_relocation_only',
    'restore_warning: metadata_only',
    'require_local_permit: false',
    'require_link_match: false',
    'receiver_authority_claimed: false',
    'provider_completed: true',
    'root_completed: true',
    'completed_state_artifact: artifacts/states/active-provider.completed.capsule',
  ],
  'replay-without-fresh-effect': [
    'case_id: replay-without-fresh-effect',
    'owner_surface: Machine/Transcript',
    'turn_closure_authority: false',
    'fresh_handler_calls: 1',
    'replay_handler_calls: 0',
  ],
  'lost-output-retry': [
    'case_id: lost-output-retry',
    'owner_surface: Appliance/TurnClosure',
    'effect_call_count: 1',
    'result_persisted_before_step: true',
    'fresh_runtime_count: 2',
    'fresh_runtimes_restored_from_authoritative_parent: true',
    'identical_turn_input_resubmitted: true',
    'persisted_resolution_input_reused: true',
    'first_retry_output_byte_equal: true',
    'first_retry_closure_byte_equal: true',
    'wire_restore_equivalence_claimed: false',
  ],
  'migration': [
    'case_id: migration',
    'owner_surface: Capsule/Runspace/Fabric',
    'fixture_provenance: synthetic-owner-state',
    'source_destroyed: true',
    'receiver_fresh_instance: true',
    'migration_evidence_scope: metadata_relocation_only',
    'restore_warning: metadata_only',
    'require_local_permit: false',
    'require_link_match: false',
    'receiver_authority_claimed: false',
    'completed_after_migration: true',
    'completed_state_artifact: artifacts/states/active-provider.completed.capsule',
  ],
  branching: [
    'case_id: branching',
    'owner_surface: Machine/Transcript/Timeline/RunImage',
    'turn_closure_authority: false',
    'parent_unchanged: true',
  ],
  'partial-response-batch': [
    'case_id: partial-response-batch',
    'owner_surface: Appliance/TurnClosure',
    'initial_request_count: 2',
    'supplied_first_batch_count: 1',
    'remaining_request_count: 1',
    'remaining_request_identity_preserved: true',
    'closure_chain_validated: true',
    'final_status: completed',
  ],
  'deterministic-failure': [
    'case_id: deterministic-failure',
    'owner_surface: Appliance/TurnClosure',
    'accepted_result_status: failed',
    'transition_status: failed',
    'next_state_status: failed',
    'root_result_present: false',
    'parent_state_published: true',
    'parent_output_artifact: artifacts/outputs/failure.parent.turn-output',
    'parent_closure_artifact: artifacts/transitions/failure.parent.turn-closure',
    'parent_checkpoint_artifact: artifacts/states/failure.parent.checkpoint',
  ],
  'capacity-exhaustion': [
    'case_id: capacity-exhaustion',
    'owner_surface: Appliance/Core',
    'turn_closure_produced: false',
    'error: CapacityExceeded',
    'state_unchanged: true',
    'pending_command_preserved: true',
  ],
  'malformed-records': [
    'case_id: malformed-records',
    'owner_surface: Executable.Image + Appliance/TurnClosure + Appliance/Wire',
    'wrong_target_result_status: unknown_request',
    'duplicate_result_status: invalid_command',
    'stale_result_status: stale_turn',
    'semantic_state_unchanged_after_wrong_result: true',
    'semantic_state_unchanged_after_duplicate_result: true',
    'semantic_state_unchanged_after_stale_result: true',
    'diagnostic_error_published_after_wrong_result: true',
    'diagnostic_error_published_after_duplicate_result: true',
    'diagnostic_error_published_after_stale_result: true',
  ],
};

const transcriptTurnClosureClaims = {
  'one-port-execution': {
    parent_closure_fingerprint: 'artifacts/transitions/one-port.waiting.turn-closure',
    completed_closure_fingerprint: 'artifacts/transitions/one-port.completed.turn-closure',
  },
  'internal-provider-execution': {
    closure_fingerprint: 'artifacts/transitions/internal-provider.completed.turn-closure',
  },
  'lost-output-retry': {
    parent_closure_fingerprint: 'artifacts/transitions/retry.parent.turn-closure',
    result_closure_fingerprint: 'artifacts/transitions/retry.first.turn-closure',
  },
  'partial-response-batch': {
    parent_closure_fingerprint: 'artifacts/transitions/partial-batch.parent.turn-closure',
    partial_closure_fingerprint: 'artifacts/transitions/partial-batch.remaining.turn-closure',
  },
  'deterministic-failure': {
    parent_closure_fingerprint: 'artifacts/transitions/failure.parent.turn-closure',
    failed_closure_fingerprint: 'artifacts/transitions/failure.failed.turn-closure',
  },
};

const expectedArtifacts = [
  'artifacts/effects/active-provider.external.request-frame',
  'artifacts/effects/failure.failed.resolution-input',
  'artifacts/effects/one-port.pending.host-requests',
  'artifacts/effects/one-port.responded.resolution-input',
  'artifacts/effects/retry.persisted.resolution-input',
  'artifacts/history/one-port.archive-append-batch',
  'artifacts/images/internal-provider.executable-image',
  'artifacts/inputs/capacity-exhaustion.boot.command',
  'artifacts/inputs/failure.failed-result.turn-input',
  'artifacts/inputs/internal-provider.boot.turn-input',
  'artifacts/inputs/one-port.boot.turn-input',
  'artifacts/inputs/one-port.continue.turn-input',
  'artifacts/inputs/partial-batch.boot.turn-input',
  'artifacts/inputs/partial-batch.final-result.turn-input',
  'artifacts/inputs/partial-batch.one-result.turn-input',
  'artifacts/inputs/retry.continue.turn-input',
  'artifacts/malformed/executable-image.trailing-byte',
  'artifacts/malformed/result.duplicate-target.turn-input',
  'artifacts/malformed/result.stale-replay.turn-input',
  'artifacts/malformed/result.wrong-target.turn-input',
  'artifacts/malformed/state.turn-closure.trailing-byte',
  'artifacts/manifests/internal-provider.appliance-manifest',
  'artifacts/manifests/one-port.appliance-manifest',
  'artifacts/outputs/failure.failed.turn-output',
  'artifacts/outputs/failure.parent.turn-output',
  'artifacts/outputs/internal-provider.completed.turn-output',
  'artifacts/outputs/one-port.completed.turn-output',
  'artifacts/outputs/one-port.waiting.turn-output',
  'artifacts/outputs/partial-batch.completed.turn-output',
  'artifacts/outputs/partial-batch.parent.turn-output',
  'artifacts/outputs/partial-batch.remaining.turn-output',
  'artifacts/outputs/retry.first.turn-output',
  'artifacts/outputs/retry.repeated.turn-output',
  'artifacts/results/internal-provider.root-result',
  'artifacts/results/one-port.root-result',
  'artifacts/states/active-provider.completed.capsule',
  'artifacts/states/active-provider.migrated.capsule',
  'artifacts/states/active-provider.source.capsule',
  'artifacts/states/branch.alternate.run-image',
  'artifacts/states/branch.alternate.transcript-image',
  'artifacts/states/branch.baseline.run-image',
  'artifacts/states/branch.baseline.transcript-image',
  'artifacts/states/capacity-exhaustion.after.txt',
  'artifacts/states/failure.failed.checkpoint',
  'artifacts/states/failure.parent.checkpoint',
  'artifacts/states/internal-provider.completed.capsule',
  'artifacts/states/one-port.completed.capsule',
  'artifacts/states/one-port.completed.checkpoint',
  'artifacts/states/one-port.waiting.capsule',
  'artifacts/states/one-port.waiting.checkpoint',
  'artifacts/states/partial-batch.remaining.checkpoint',
  'artifacts/states/replay.completed.run-image',
  'artifacts/states/replay.transcript-image',
  'artifacts/states/retry.parent.checkpoint',
  'artifacts/transitions/failure.failed.turn-closure',
  'artifacts/transitions/failure.parent.turn-closure',
  'artifacts/transitions/internal-provider.completed.turn-closure',
  'artifacts/transitions/one-port.completed.turn-closure',
  'artifacts/transitions/one-port.waiting.turn-closure',
  'artifacts/transitions/partial-batch.completed.turn-closure',
  'artifacts/transitions/partial-batch.parent.turn-closure',
  'artifacts/transitions/partial-batch.remaining.turn-closure',
  'artifacts/transitions/retry.first.turn-closure',
  'artifacts/transitions/retry.parent.turn-closure',
  'artifacts/transitions/retry.repeated.turn-closure',
  'cases/active-provider-restore.txt',
  'cases/branching.txt',
  'cases/capacity-exhaustion.txt',
  'cases/deterministic-failure.txt',
  'cases/internal-provider-execution.txt',
  'cases/lost-output-retry.txt',
  'cases/malformed-records.txt',
  'cases/migration.txt',
  'cases/one-port-execution.txt',
  'cases/partial-response-batch.txt',
  'cases/provider-parked-externally.txt',
  'cases/replay-without-fresh-effect.txt',
];

const generatorSourceIdentityAlgorithm = 'sha256-domain-u32le-path-u64le-canonical-lf-bytes-v1';
const generatorSourceNormalization = 'crlf-to-lf;bare-cr-reject';
const generatorSourceIdentityDomain = Buffer.from('world.oracle.generator-source-identity.v1\0', 'utf8');
const candidateAdmissionIdentityDomain = Buffer.from('world.oracle.candidate-admission.v1\0', 'utf8');
const sourcePackagePaths = rootPackagePaths();
const generatorSourceExcludedPrefix = 'conformance/world-image-v1/v0/world/';
const generatorSourceFiles = generatorSourceInventory(repositoryRoot);

const expectedBinaryFamilyPolicy = {
  scope: 'exhaustive-top-level-binary-artifacts',
  nested_authority: 'top-level-owner+world-generator-source-identity+boundary-package-hash',
  unclassified: 'reject',
  binary_artifact_count: 64,
};

const expectedBinaryFamilies = [
  {
    id: 'world_executable_image',
    owner: 'world.Executable.Image',
    versioning: 'header',
    expected_count: 2,
    magic: 'world.Executable.Image.v2\0',
    header_fields: [
      { name: 'format_version', constant: 'world_executable_image_format_version', offset: 26, value: 2 },
      { name: 'fingerprint_version', constant: 'world_executable_image_fingerprint_version', offset: 30, value: 2 },
      { name: 'codec_version', constant: 'world_executable_image_codec_version', offset: 34, value: 1 },
    ],
  },
  {
    id: 'world_appliance_manifest',
    owner: 'world.Appliance.Manifest',
    versioning: 'header',
    expected_count: 2,
    header_fields: [
      { name: 'format_version', constant: 'world_appliance_manifest_format_version', offset: 0, value: 3 },
      { name: 'fingerprint_version', constant: 'world_appliance_manifest_fingerprint_version', offset: 4, value: 3 },
      { name: 'appliance_abi_version', constant: 'world_appliance_abi_version', offset: 16, value: 4 },
    ],
  },
  {
    id: 'world_appliance_command',
    owner: 'world.Appliance.Command',
    versioning: 'header',
    expected_count: 1,
    header_fields: [
      { name: 'format_version', constant: 'world_appliance_command_format_version', offset: 0, value: 1 },
      { name: 'fingerprint_version', constant: 'world_appliance_command_fingerprint_version', offset: 4, value: 1 },
    ],
  },
  {
    id: 'world_appliance_wire_turn_input',
    owner: 'world.Appliance.Wire.TurnInput',
    versioning: 'format-only',
    expected_count: 11,
    header_fields: [
      { name: 'format_version', constant: 'world_appliance_wire_turn_input_format_version', offset: 0, value: 2 },
    ],
  },
  {
    id: 'world_appliance_wire_resolution_input',
    owner: 'world.Appliance.Wire.ResolutionInput',
    versioning: 'format-only',
    expected_count: 3,
    header_fields: [
      { name: 'format_version', constant: 'world_appliance_wire_resolution_input_format_version', offset: 0, value: 1 },
    ],
  },
  {
    id: 'world_appliance_turn_output',
    owner: 'world.Appliance.TurnOutput',
    versioning: 'header',
    expected_count: 10,
    header_fields: [
      { name: 'format_version', constant: 'world_appliance_turn_output_format_version', offset: 0, value: 3 },
      { name: 'fingerprint_version', constant: 'world_appliance_turn_output_fingerprint_version', offset: 4, value: 2 },
    ],
  },
  {
    id: 'world_appliance_turn_closure',
    owner: 'world.Appliance.TurnClosure',
    versioning: 'header',
    expected_count: 12,
    header_fields: [
      { name: 'format_version', constant: 'world_appliance_turn_closure_format_version', offset: 0, value: 1 },
      { name: 'fingerprint_version', constant: 'world_appliance_turn_closure_fingerprint_version', offset: 4, value: 1 },
    ],
  },
  {
    id: 'world_appliance_checkpoint',
    owner: 'world.Appliance.Checkpoint',
    versioning: 'header',
    expected_count: 6,
    header_fields: [
      { name: 'format_version', constant: 'world_appliance_checkpoint_format_version', offset: 0, value: 1 },
      { name: 'fingerprint_version', constant: 'world_appliance_checkpoint_fingerprint_version', offset: 4, value: 1 },
    ],
  },
  {
    id: 'world_capsule_image',
    owner: 'world.Capsule.Image',
    versioning: 'header',
    expected_count: 6,
    header_fields: [
      { name: 'format_version', constant: 'world_capsule_image_format_version', offset: 0, value: 3 },
      { name: 'fingerprint_version', constant: 'world_capsule_image_fingerprint_version', offset: 4, value: 1 },
    ],
  },
  {
    id: 'world_appliance_host_request_batch',
    owner: 'world.Appliance.encodeHostRequestsImageOwned',
    versioning: 'member-versioned-container',
    expected_count: 1,
    container_count_offset: 0,
    expected_member_count: 1,
    member_header_fields: [
      { name: 'format_version', constant: 'world_appliance_host_request_format_version', offset: 8, value: 4 },
      { name: 'fingerprint_version', constant: 'world_appliance_host_request_fingerprint_version', offset: 12, value: 4 },
    ],
  },
  {
    id: 'world_frame_request',
    owner: 'world.Frame.Request',
    versioning: 'header',
    expected_count: 1,
    header_fields: [
      { name: 'format_version', constant: 'world_frame_request_format_version', offset: 0, value: 1 },
      { name: 'fingerprint_version', constant: 'world_frame_request_fingerprint_version', offset: 4, value: 1 },
    ],
  },
  {
    id: 'world_archive_append_batch',
    owner: 'world.Archive.AppendBatch',
    versioning: 'header',
    expected_count: 1,
    header_fields: [
      { name: 'format_version', constant: 'world_archive_append_batch_format_version', offset: 0, value: 1 },
      {
        name: 'fingerprint_version',
        constant: 'world_archive_append_batch_fingerprint_version',
        offset: 4,
        value: 1,
      },
    ],
  },
  {
    id: 'world_run_image',
    owner: 'world.RunImage',
    versioning: 'header',
    expected_count: 3,
    header_fields: [
      { name: 'format_version', constant: 'world_run_image_format_version', offset: 0, value: 3 },
      { name: 'fingerprint_version', constant: 'world_run_image_fingerprint_version', offset: 4, value: 1 },
    ],
  },
  {
    id: 'world_transcript_image',
    owner: 'world.TranscriptImage',
    versioning: 'header',
    expected_count: 3,
    header_fields: [
      { name: 'format_version', constant: 'world_transcript_image_format_version', offset: 0, value: 3 },
      { name: 'fingerprint_version', constant: 'world_transcript_image_fingerprint_version', offset: 4, value: 1 },
    ],
  },
  {
    id: 'world_appliance_root_result_value_image',
    owner: 'world.Appliance.validateRootResultValueImageBytes',
    versioning: 'unversioned-container-owned',
    expected_count: 2,
    label: 'world.appliance.root_result.value_image',
    label_length_offset: 0,
    label_offset: 4,
    value_fingerprint_offset: 43,
  },
];

const binaryFamilyMatchers = {
  world_executable_image: [
    /^artifacts\/images\/[^/]+\.executable-image$/,
    /^artifacts\/malformed\/executable-image\.trailing-byte$/,
  ],
  world_appliance_manifest: [/^artifacts\/manifests\/[^/]+\.appliance-manifest$/],
  world_appliance_command: [/^artifacts\/inputs\/[^/]+\.command$/],
  world_appliance_wire_turn_input: [
    /^artifacts\/inputs\/[^/]+\.turn-input$/,
    /^artifacts\/malformed\/result\.[^/]+\.turn-input$/,
  ],
  world_appliance_wire_resolution_input: [/^artifacts\/effects\/[^/]+\.resolution-input$/],
  world_appliance_turn_output: [/^artifacts\/outputs\/[^/]+\.turn-output$/],
  world_appliance_turn_closure: [
    /^artifacts\/transitions\/[^/]+\.turn-closure$/,
    /^artifacts\/malformed\/state\.turn-closure\.trailing-byte$/,
  ],
  world_appliance_checkpoint: [/^artifacts\/states\/[^/]+\.checkpoint$/],
  world_capsule_image: [/^artifacts\/states\/[^/]+\.capsule$/],
  world_appliance_host_request_batch: [/^artifacts\/effects\/[^/]+\.host-requests$/],
  world_frame_request: [/^artifacts\/effects\/[^/]+\.request-frame$/],
  world_archive_append_batch: [/^artifacts\/history\/[^/]+\.archive-append-batch$/],
  world_run_image: [/^artifacts\/states\/[^/]+\.run-image$/],
  world_transcript_image: [/^artifacts\/states\/[^/]+\.transcript-image$/],
  world_appliance_root_result_value_image: [/^artifacts\/results\/[^/]+\.root-result$/],
};

const expectedBoundaryPackage = rootBoundaryPackage();

const args = parseArgs(process.argv.slice(2));

if (args.mode === 'publish') {
  requireArg(args.publisher, '--publisher');
  requireArg(args.sourceDir, '--source-dir');
  requireArg(args.admissionDigest, '--admission-digest');
  requireArg(args.trustedPrefix, '--trusted-prefix');
  requireArg(args.coordinationDir, '--coordination-dir');
  withCorpusCoordination(args.coordinationDir, 'publish', () => {
    requireNoPriorValidationFailure(args.coordinationDir);
    const result = spawnSync(
      args.publisher,
      [
        'publish',
        '--source-dir',
        args.sourceDir,
        '--admission-digest',
        args.admissionDigest,
        '--trusted-prefix',
        args.trustedPrefix,
      ],
      { stdio: 'inherit' },
    );
    if (result.error !== undefined) throw result.error;
    if (result.status !== 0) {
      throw new Error(`oracle publisher exited with ${result.status === null ? String(result.signal) : String(result.status)}`);
    }
  });
} else if (args.mode === 'compare') {
  requireArg(args.expected, '--expected');
  requireArg(args.first, '--first');
  requireArg(args.second, '--second');
  requireArg(args.zigVersion, '--zig-version');
  const compare = () => {
    validateCorpus(args.expected, args.zigVersion);
    validateCorpus(args.first, args.zigVersion);
    validateCorpus(args.second, args.zigVersion);
    compareTrees(args.expected, args.first, 'tracked/first');
    compareTrees(args.expected, args.second, 'tracked/second');
    compareTrees(args.first, args.second, 'first/second');
  };
  if (args.coordinationDir === undefined) compare();
  else withCorpusCoordination(args.coordinationDir, 'check', compare);
} else if (args.mode === 'verify') {
  requireArg(args.expected, '--expected');
  requireArg(args.actual, '--actual');
  requireArg(args.zigVersion, '--zig-version');
  validateCorpus(args.expected, args.zigVersion);
  validateCorpus(args.actual, args.zigVersion);
  compareTrees(args.expected, args.actual, 'expected/actual');
} else if (args.mode === 'check') {
  requireArg(args.expected, '--expected');
  requireArg(args.zigVersion, '--zig-version');
  const snapshot = validateCorpus(args.expected, args.zigVersion);
  if (args.admissionDigest !== undefined) {
    requireArg(args.admissionDigest, '--admission-digest');
    writeFileSync(args.admissionDigest, `${candidateTreeIdentity(snapshot)}\n`, 'utf8');
  }
} else if (args.mode === 'self-test-root-symlink') {
  testRootSymlinkRejection();
} else if (args.mode === 'self-test-generator-source') {
  testGeneratorSourceIdentity();
} else if (args.mode === 'self-test-checksum-inventory') {
  testChecksumInventoryAdmission();
} else {
  throw new Error(`unsupported --mode ${String(args.mode)}`);
}

function parseArgs(raw) {
  const parsed = {};
  for (let index = 0; index < raw.length; index += 1) {
    const arg = raw[index];
    if (arg === '--mode') parsed.mode = raw[++index];
    else if (arg === '--expected') parsed.expected = raw[++index];
    else if (arg === '--first') parsed.first = raw[++index];
    else if (arg === '--second') parsed.second = raw[++index];
    else if (arg === '--actual') parsed.actual = raw[++index];
    else if (arg === '--zig-version') parsed.zigVersion = raw[++index];
    else if (arg === '--admission-digest') parsed.admissionDigest = raw[++index];
    else if (arg === '--publisher') parsed.publisher = raw[++index];
    else if (arg === '--source-dir') parsed.sourceDir = raw[++index];
    else if (arg === '--trusted-prefix') parsed.trustedPrefix = raw[++index];
    else if (arg === '--coordination-dir') parsed.coordinationDir = raw[++index];
    else throw new Error(`unknown argument ${arg}`);
  }
  return parsed;
}

function withCorpusCoordination(root, role, action) {
  mkdirSync(root, { recursive: true });
  const lock = join(root, 'trusted-corpus-lock');
  for (;;) {
    try {
      mkdirSync(lock);
      break;
    } catch (error) {
      if (!(error instanceof Error) || error.code !== 'EEXIST') throw error;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 10);
    }
  }
  try {
    return action();
  } catch (error) {
    if (role === 'check') mkdirSync(join(root, 'tracked-validation-failed'), { recursive: true });
    throw error;
  } finally {
    rmSync(lock, { recursive: true, force: true });
  }
}

function requireNoPriorValidationFailure(root) {
  if (existsSync(join(root, 'tracked-validation-failed'))) {
    throw new Error('tracked oracle validation failed before publication');
  }
}

function requireArg(value, name) {
  if (typeof value !== 'string' || value.length === 0) throw new Error(`missing ${name}`);
}

function packageVersionFromZon(zon) {
  return zonStringField(zonRootStructBody(zon), 'version', 'root package version');
}

function packagePathsFromZon(zon) {
  const paths = zonStringListField(zonRootStructBody(zon), 'paths', 'root package paths');
  if (paths.length === 0) throw new Error('root package paths must not be empty');
  const seen = new Set();
  for (const path of paths) {
    validateSourcePackagePath(path);
    if (seen.has(path)) throw new Error(`duplicate root package path: ${path}`);
    seen.add(path);
  }
  return paths;
}

function validateSourcePackagePath(path) {
  if (
    path.length === 0 ||
    path.startsWith('/') ||
    /^[A-Za-z]:/.test(path) ||
    path.includes('\\') ||
    path.split('/').some((component) => component.length === 0 || component === '.' || component === '..')
  ) {
    throw new Error(`invalid root package path: ${path}`);
  }
}

function testPackageVersionProjection() {
  const zon = `.{
    .name = .world,
    // owner field
    .version   =   "1.2.3", // retained provenance
    .url = "https://example.invalid/archive.tar.gz",
  }`;
  assertEqual(packageVersionFromZon(zon), '1.2.3', 'commented package version projection');
  assertEqual(packageVersionFromZon('.{ .version = "2.0.0", }'), '2.0.0', 'inline package version projection');

  const dependencyZon = `.{
    .dependencies = .{
      .boundary = .{
        // selected package owner
        .url = "https://github.com/tkersey/boundary/archive/refs/tags/v1.2.3.tar.gz",
        .hash = "boundary-1.2.3-fixture",
      },
    },
  }`;
  const boundaryPackage = boundaryPackageFromZon(dependencyZon);
  assertEqual(boundaryPackage.version, '1.2.3', 'Boundary dependency version projection');
  assertEqual(boundaryPackage.hash, 'boundary-1.2.3-fixture', 'Boundary dependency hash projection');

  const escapedDependencyZon = `.{
    .@"dependencies" = .{
      .@"boundary" = .{
        .@"url" = "https://github.com/tkersey/boundary/archive/refs/tags/v1.2.3.tar.gz",
        .@"hash" = "boundary-1.2.3-fixture"
      }
    },
  }`;
  assertJsonEqual(
    boundaryPackageFromZon(escapedDependencyZon),
    boundaryPackage,
    'escaped Boundary dependency without trailing commas',
  );

  const multilineZon = String.raw`.{
    .note =
        \\literal { } // not a comment

        \\.version = "not a field"
    ,
    .version =
        \\1.2.3
    ,
    .paths = .{
        \\README.md
    ,
        "src",
    },
    .dependencies = .{
        .boundary = .{
            .url =
                \\https://github.com/tkersey/boundary/archive/refs/tags/v1.2.3.tar.gz
            ,
            .hash =
                \\boundary-1.2.3-fixture
            ,
        },
    },
  }`;
  assertEqual(packageVersionFromZon(multilineZon), '1.2.3', 'multiline package version projection');
  assertJsonEqual(
    packagePathsFromZon(multilineZon),
    ['README.md', 'src'],
    'multiline package paths projection',
  );
  assertJsonEqual(
    boundaryPackageFromZon(multilineZon),
    boundaryPackage,
    'multiline Boundary dependency projection',
  );
  assertJsonEqual(
    packagePathsFromZon(String.raw`.{ .paths = .{ "src/\xC3\xA9" } }`),
    ['src/é'],
    'hexadecimal byte escape package path',
  );
  assertJsonEqual(
    packagePathsFromZon(String.raw`.{ .paths = .{ "\xEF\xBB\xBFsrc" } }`),
    ['\uFEFFsrc'],
    'leading UTF-8 byte-order mark path',
  );
  let invalidUtf8Rejected = false;
  try {
    packagePathsFromZon(String.raw`.{ .paths = .{ "src/\xFF" } }`);
  } catch (error) {
    if (!(error instanceof Error) || error.message !== 'invalid UTF-8 in root package paths item') throw error;
    invalidUtf8Rejected = true;
  }
  if (!invalidUtf8Rejected) throw new Error('invalid UTF-8 package path accepted');

  try {
    boundaryPackageFromZon(
      dependencyZon.replace('v1.2.3.tar.gz', 'v1.2.4.tar.gz'),
    );
  } catch (error) {
    if (error instanceof Error && error.message === 'Boundary dependency URL/hash version mismatch') return;
    throw error;
  }
  throw new Error('Boundary dependency URL/hash version mismatch accepted');
}

function rootPackageVersion() {
  return packageVersionFromZon(readFileSync(new URL('../build.zig.zon', import.meta.url), 'utf8'));
}

function rootPackagePaths() {
  return packagePathsFromZon(readFileSync(new URL('../build.zig.zon', import.meta.url), 'utf8'));
}

function validateCorpus(root, expectedZigVersion) {
  const snapshot = captureCorpus(root);
  const files = snapshot.files;
  const read = snapshot.read;
  if (files.length === 0) throw new Error(`empty oracle corpus: ${root}`);
  if (!files.includes('manifest.json')) throw new Error(`missing manifest.json: ${root}`);
  if (!files.includes('checksums.sha256')) throw new Error(`missing checksums.sha256: ${root}`);

  const manifestBytes = read('manifest.json');
  const manifest = parseJsonDocument(manifestBytes, 'manifest.json');
  assertEqual(manifest.format, 'world-image-v1-rewrite-world-oracle-v0', 'manifest.format');
  assertEqual(manifest.format_version, 1, 'manifest.format_version');
  assertEqual(manifest.semantic_source?.package, 'world', 'manifest.semantic_source.package');
  assertEqual(manifest.semantic_source?.package_version, rootPackageVersion(), 'manifest.semantic_source.package_version');
  assertEqual(
    manifest.semantic_source?.baseline_commit,
    '969f23f6bad87ca9d535d92d62b6418612891699',
    'manifest.semantic_source.baseline_commit',
  );
  assertEqual(
    manifest.semantic_source?.baseline_tree,
    'b2bd776125bc17215916e2a48bc7102a861788db',
    'manifest.semantic_source.baseline_tree',
  );
  assertEqual(
    manifest.semantic_source?.boundary_package,
    expectedBoundaryPackage.version,
    'manifest.semantic_source.boundary_package',
  );
  assertEqual(
    manifest.semantic_source?.boundary_package_hash,
    expectedBoundaryPackage.hash,
    'manifest.semantic_source.boundary_package_hash',
  );
  assertEqual(
    manifest.semantic_source?.baseline_scope,
    'historical-reference-parent',
    'manifest.semantic_source.baseline_scope',
  );
  assertJsonEqual(
    manifest.semantic_source?.generator_source_identity,
    {
      algorithm: generatorSourceIdentityAlgorithm,
      normalization: generatorSourceNormalization,
      sha256: generatorSourceIdentity(repositoryRoot),
      files: generatorSourceFiles,
    },
    'manifest.semantic_source.generator_source_identity',
  );
  assertEqual(
    manifest.semantic_source?.version_fields_scope,
    'selected-compatibility-cut-lines',
    'manifest.semantic_source.version_fields_scope',
  );
  assertEqual(manifest.semantic_source?.world_executable_image_format, 2, 'manifest executable image format');
  assertEqual(
    manifest.semantic_source?.world_executable_image_fingerprint,
    2,
    'manifest executable image fingerprint',
  );
  assertEqual(manifest.semantic_source?.world_executable_image_codec, 1, 'manifest executable image codec');
  assertEqual(manifest.semantic_source?.world_turn_closure_format, 1, 'manifest TurnClosure format');
  assertEqual(manifest.semantic_source?.world_turn_closure_fingerprint, 1, 'manifest TurnClosure fingerprint');
  assertEqual(
    manifest.semantic_source?.world_archive_append_batch_format,
    1,
    'manifest Archive.AppendBatch format',
  );
  assertEqual(
    manifest.semantic_source?.world_archive_append_batch_fingerprint,
    1,
    'manifest Archive.AppendBatch fingerprint',
  );
  assertEqual(manifest.semantic_source?.world_appliance_abi, 4, 'manifest Appliance ABI');
  assertEqual(manifest.semantic_source?.world_appliance_manifest_format, 3, 'manifest Appliance Manifest format');
  assertEqual(
    manifest.semantic_source?.world_appliance_manifest_fingerprint,
    3,
    'manifest Appliance Manifest fingerprint',
  );
  assertEqual(manifest.semantic_source?.world_appliance_command_format, 1, 'manifest Appliance Command format');
  assertEqual(
    manifest.semantic_source?.world_appliance_command_fingerprint,
    1,
    'manifest Appliance Command fingerprint',
  );
  assertEqual(
    manifest.semantic_source?.world_appliance_wire_turn_input_format,
    2,
    'manifest Wire.TurnInput format',
  );
  assertEqual(
    manifest.semantic_source?.world_appliance_wire_resolution_input_format,
    1,
    'manifest Wire.ResolutionInput format',
  );
  assertEqual(manifest.semantic_source?.zig_version, expectedZigVersion, 'manifest.semantic_source.zig_version');
  assertEqual(
    manifest.offline_regeneration,
    'requires-preseeded-boundary-package-cache',
    'manifest.offline_regeneration',
  );
  assertEqual(manifest.case_count, expectedCases.length, 'manifest.case_count');
  assertArrayEqual(manifest.cases.map((entry) => entry.id), expectedCases, 'manifest.cases');
  assertArrayEqual(Object.keys(requiredTranscriptFacts), expectedCases, 'required transcript fact cases');

  const transcriptPaths = manifest.cases.map((entry) => entry.transcript);
  assertArrayEqual(
    transcriptPaths,
    expectedCases.map((id) => `cases/${id}.txt`),
    'manifest case transcripts',
  );
  for (const transcript of transcriptPaths) {
    if (!files.includes(transcript)) throw new Error(`missing transcript ${transcript}`);
  }
  for (const [caseId, facts] of Object.entries(requiredTranscriptFacts)) {
    const transcript = decodeSemanticUtf8(read(`cases/${caseId}.txt`), `cases/${caseId}.txt`);
    const transcriptFields = parseTranscript(transcript, caseId);
    for (const fact of facts) {
      const separator = fact.indexOf(': ');
      const key = fact.slice(0, separator);
      const expected = fact.slice(separator + 2);
      assertEqual(transcriptFields.get(key), expected, `provenance fact ${caseId}.${key}`);
    }
    validateTranscriptTurnClosureClaims(caseId, transcriptFields, read);
  }

  const contentFiles = files.filter((path) => path !== 'manifest.json' && path !== 'checksums.sha256');
  assertArrayEqual(contentFiles, expectedArtifacts, 'expected artifact inventory');
  validateBinaryFamilies(contentFiles, manifest, read);
  const manifestArtifacts = manifest.artifacts.map((entry) => entry.path);
  assertArrayEqual(manifestArtifacts, contentFiles, 'manifest artifact inventory');

  const artifactHasher = createHash('sha256');
  for (const entry of manifest.artifacts) {
    const bytes = read(entry.path);
    assertEqual(entry.length, bytes.length, `manifest length ${entry.path}`);
    assertEqual(entry.sha256, sha256(bytes), `manifest sha256 ${entry.path}`);
    const length = Buffer.alloc(8);
    length.writeBigUInt64LE(BigInt(bytes.length));
    artifactHasher.update(entry.path);
    artifactHasher.update(Buffer.from([0]));
    artifactHasher.update(length);
    artifactHasher.update(Buffer.from(entry.sha256, 'hex'));
  }
  assertEqual(manifest.artifact_count, contentFiles.length, 'manifest.artifact_count');
  assertEqual(manifest.artifact_set_sha256, artifactHasher.digest('hex'), 'manifest.artifact_set_sha256');

  validateChecksums(
    root,
    decodeSemanticUtf8(read('checksums.sha256'), 'checksums.sha256'),
    files.filter((path) => path !== 'checksums.sha256'),
    read,
  );
  return snapshot;
}

function decodeSemanticUtf8(bytes, label) {
  try {
    return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
  } catch (error) {
    throw new Error(`invalid UTF-8 in ${label}`, { cause: error });
  }
}

function parseJsonDocument(bytes, label) {
  return JSON.parse(decodeSemanticUtf8(bytes, label));
}

function parseTranscript(text, caseId) {
  const fields = new Map();
  for (const line of text.split('\n')) {
    if (line.length === 0) continue;
    const separator = line.indexOf(': ');
    if (separator <= 0) throw new Error(`invalid transcript line for ${caseId}: ${line}`);
    const key = line.slice(0, separator);
    if (!/^[a-z][a-z0-9_]*$/.test(key)) throw new Error(`invalid transcript key for ${caseId}: ${key}`);
    if (fields.has(key)) throw new Error(`duplicate transcript key for ${caseId}: ${key}`);
    fields.set(key, line.slice(separator + 2));
  }
  return fields;
}

function validateTranscriptTurnClosureClaims(caseId, fields, read) {
  for (const [key, artifactPath] of Object.entries(transcriptTurnClosureClaims[caseId] ?? {})) {
    const bytes = read(artifactPath);
    if (bytes.length < 16) throw new Error(`TurnClosure too short for transcript claim: ${artifactPath}`);
    const expected = `0x${bytes.readBigUInt64LE(8).toString(16).padStart(16, '0')}`;
    assertEqual(fields.get(key), expected, `artifact-bound transcript fact ${caseId}.${key}`);
  }
}

function validateChecksums(root, checksumText, expectedPaths, read = (path) => readFileSync(join(root, path))) {
  const checksumLines = checksumText
    .trimEnd()
    .split('\n')
    .filter(Boolean);
  const checksumEntries = checksumLines.map((line) => {
    const match = /^([0-9a-f]{64})  conformance\/world-image-v1\/v0\/world\/(.+)$/.exec(line);
    if (!match) throw new Error(`invalid checksum line: ${line}`);
    const [, digest, path] = match;
    return { digest, path };
  });
  assertArrayEqual(
    checksumEntries.map((entry) => entry.path),
    expectedPaths,
    'checksum inventory',
  );
  for (const { digest, path } of checksumEntries) {
    assertEqual(digest, sha256(read(path)), `checksums.sha256 ${path}`);
  }
}

function rootBoundaryPackage() {
  return boundaryPackageFromZon(readFileSync(new URL('../build.zig.zon', import.meta.url), 'utf8'));
}

function boundaryPackageFromZon(zon) {
  const root = zonRootStructBody(zon);
  const dependencies = zonStructFieldBody(root, 'dependencies', '.dependencies');
  const body = zonStructFieldBody(dependencies, 'boundary', '.dependencies.boundary');
  const url = zonStringField(body, 'url', '.boundary.url');
  const hash = zonStringField(body, 'hash', '.boundary.hash');
  const urlPrefix = 'https://github.com/tkersey/boundary/archive/refs/tags/v';
  const urlSuffix = '.tar.gz';
  if (!url.startsWith(urlPrefix) || !url.endsWith(urlSuffix)) {
    throw new Error('unsupported Boundary dependency URL');
  }
  const version = url.slice(urlPrefix.length, -urlSuffix.length);
  if (version.length === 0 || version.includes('/')) throw new Error('invalid Boundary dependency version');
  const hashPrefix = `boundary-${version}-`;
  if (!hash.startsWith(hashPrefix) || hash.length === hashPrefix.length) {
    throw new Error('Boundary dependency URL/hash version mismatch');
  }
  return { version, hash };
}

function zonRootStructBody(source) {
  let index = zonSkipTrivia(source, 0);
  if (source[index] !== '.') throw new Error('expected root ZON struct literal');
  index = zonSkipTrivia(source, index + 1);
  if (source[index] !== '{') throw new Error('expected root ZON struct literal');
  const openingBrace = index;
  const closingBrace = findClosingZonBrace(source, openingBrace);
  if (zonSkipTrivia(source, closingBrace + 1) !== source.length) throw new Error('trailing root ZON tokens');
  return source.slice(openingBrace + 1, closingBrace);
}

function zonStructFieldBody(source, field, label) {
  const value = zonFieldValue(source, field, label);
  let index = zonSkipTrivia(source, value.start);
  if (source[index] !== '.') throw new Error(`expected ${label} struct literal`);
  index = zonSkipTrivia(source, index + 1);
  if (source[index] !== '{') throw new Error(`expected ${label} struct literal`);
  const openingBrace = index;
  const closingBrace = findClosingZonBrace(source, openingBrace);
  if (zonSkipTrivia(source, closingBrace + 1) !== value.end) {
    throw new Error(`trailing ${label} value tokens`);
  }
  return source.slice(openingBrace + 1, closingBrace);
}

function zonStringField(body, field, label) {
  const value = zonFieldValue(body, field, label);
  const parsed = zonStringAt(body, zonSkipTrivia(body, value.start), label);
  if (zonSkipTrivia(body, parsed.end) !== value.end) throw new Error(`trailing ${label} value tokens`);
  return parsed.value;
}

function zonStringListField(body, field, label) {
  const value = zonFieldValue(body, field, label);
  let index = zonSkipTrivia(body, value.start);
  if (body[index] !== '.') throw new Error(`expected ${label} tuple literal`);
  index = zonSkipTrivia(body, index + 1);
  if (body[index] !== '{') throw new Error(`expected ${label} tuple literal`);
  const openingBrace = index;
  const closingBrace = findClosingZonBrace(body, openingBrace);
  if (zonSkipTrivia(body, closingBrace + 1) !== value.end) throw new Error(`trailing ${label} value tokens`);

  const source = body.slice(openingBrace + 1, closingBrace);
  const items = [];
  index = 0;
  while (true) {
    index = zonSkipTrivia(source, index);
    if (index === source.length) break;
    const item = zonStringAt(source, index, `${label} item`);
    const itemEnd = zonValueEnd(source, index);
    if (zonSkipTrivia(source, item.end) !== itemEnd) throw new Error(`non-string ${label} item`);
    items.push(item.value);
    index = zonSkipTrivia(source, itemEnd);
    if (index === source.length) break;
    if (source[index] !== ',') throw new Error(`expected comma in ${label}`);
    index += 1;
  }
  return items;
}

function zonFieldValue(source, field, label) {
  const matches = [];
  let index = 0;
  while (true) {
    index = zonSkipTrivia(source, index);
    if (index === source.length) break;
    const name = zonFieldNameAt(source, index);
    index = zonSkipTrivia(source, name.end);
    if (source[index] !== '=') throw new Error(`expected assignment for ZON field ${name.value}`);
    const valueStart = zonSkipTrivia(source, index + 1);
    const valueEnd = zonValueEnd(source, valueStart);
    if (name.value === field) matches.push({ start: valueStart, end: valueEnd });
    index = zonSkipTrivia(source, valueEnd);
    if (index === source.length) break;
    if (source[index] !== ',') throw new Error(`expected comma after ZON field ${name.value}`);
    index += 1;
  }
  if (matches.length !== 1) throw new Error(`expected exactly one ${label}, got ${matches.length}`);
  return matches[0];
}

function zonFieldNameAt(source, start) {
  let index = start;
  if (source[index] !== '.') throw new Error('expected ZON struct field');
  index += 1;
  if (source[index] === '@') {
    const quoted = zonQuotedStringAt(source, index + 1, 'ZON field name');
    return { value: quoted.value, end: quoted.end };
  }
  const match = /^[A-Za-z_][A-Za-z0-9_]*/.exec(source.slice(index));
  if (!match) throw new Error('invalid ZON struct field');
  return { value: match[0], end: index + match[0].length };
}

function zonValueEnd(source, start) {
  const stack = [];
  let index = start;
  while (index < source.length) {
    const triviaEnd = zonSkipTrivia(source, index);
    if (triviaEnd !== index) {
      index = triviaEnd;
      continue;
    }
    if (source[index] === '"' || source[index] === "'") {
      index = zonSkipQuoted(source, index);
      continue;
    }
    if (source.startsWith('\\\\', index)) {
      index = zonMultilineStringAt(source, index).end;
      continue;
    }
    const character = source[index];
    if (character === '{' || character === '[' || character === '(') stack.push(character);
    else if (character === '}' || character === ']' || character === ')') {
      const opening = stack.pop();
      const expected = character === '}' ? '{' : character === ']' ? '[' : '(';
      if (opening !== expected) throw new Error('unbalanced ZON value delimiter');
    } else if (character === ',' && stack.length === 0) {
      return index;
    }
    index += 1;
  }
  if (stack.length !== 0) throw new Error('unterminated ZON value');
  return source.length;
}

function findClosingZonBrace(source, openingBrace) {
  let depth = 0;
  let index = openingBrace;
  while (index < source.length) {
    const triviaEnd = zonSkipTrivia(source, index);
    if (triviaEnd !== index) {
      index = triviaEnd;
      continue;
    }
    if (source[index] === '"' || source[index] === "'") {
      index = zonSkipQuoted(source, index);
      continue;
    }
    if (source.startsWith('\\\\', index)) {
      index = zonMultilineStringAt(source, index).end;
      continue;
    }
    const character = source[index];
    if (character === '{') depth += 1;
    else if (character === '}') {
      depth -= 1;
      if (depth === 0) return index;
      if (depth < 0) break;
    }
    index += 1;
  }
  throw new Error('unterminated ZON struct literal');
}

function zonSkipTrivia(source, start) {
  let index = start;
  while (index < source.length) {
    if (/\s/.test(source[index])) {
      index += 1;
      continue;
    }
    if (source[index] === '/' && source[index + 1] === '/') {
      index += 2;
      while (index < source.length && source[index] !== '\n') index += 1;
      continue;
    }
    if (source[index] === '/' && source[index + 1] === '*') {
      const closing = source.indexOf('*/', index + 2);
      if (closing === -1) throw new Error('unterminated block comment in build.zig.zon');
      index = closing + 2;
      continue;
    }
    break;
  }
  return index;
}

function zonSkipQuoted(source, start) {
  const quote = source[start];
  let escaped = false;
  for (let index = start + 1; index < source.length; index += 1) {
    const character = source[index];
    if (character === '\n' || character === '\r') throw new Error('newline in quoted ZON literal');
    if (escaped) escaped = false;
    else if (character === '\\') escaped = true;
    else if (character === quote) return index + 1;
  }
  throw new Error('unterminated quoted ZON literal');
}

function zonQuotedStringAt(source, start, label) {
  if (source[start] !== '"') throw new Error(`expected quoted ${label}`);
  const end = zonSkipQuoted(source, start);
  return {
    value: decodeZonString(source.slice(start + 1, end - 1), label),
    end,
  };
}

function zonStringAt(source, start, label) {
  if (source[start] === '"') return zonQuotedStringAt(source, start, label);
  if (source.startsWith('\\\\', start)) return zonMultilineStringAt(source, start);
  throw new Error(`expected string ${label}`);
}

function zonMultilineStringAt(source, start) {
  const lines = [];
  let lineStart = start;
  let end = start;
  while (true) {
    if (!source.startsWith('\\\\', lineStart)) throw new Error('invalid ZON multiline string');
    const newline = source.indexOf('\n', lineStart + 2);
    const lineEnd = newline === -1 ? source.length : newline;
    const contentEnd = lineEnd > lineStart + 2 && source[lineEnd - 1] === '\r' ? lineEnd - 1 : lineEnd;
    lines.push(source.slice(lineStart + 2, contentEnd));
    end = lineEnd;
    if (newline === -1) break;

    let probe = newline + 1;
    let nextLine = null;
    while (probe < source.length) {
      while (source[probe] === ' ' || source[probe] === '\t' || source[probe] === '\r') probe += 1;
      if (source[probe] === '\n') {
        probe += 1;
        continue;
      }
      if (source.startsWith('\\\\', probe)) nextLine = probe;
      break;
    }
    if (nextLine === null) break;
    lineStart = nextLine;
  }
  return { value: lines.join('\n'), end };
}

function decodeZonString(raw, label) {
  const chunks = [];
  let segmentStart = 0;
  for (let index = 0; index < raw.length; index += 1) {
    if (raw[index] !== '\\') continue;
    if (segmentStart < index) chunks.push(Buffer.from(raw.slice(segmentStart, index), 'utf8'));
    const escape = raw[++index];
    if (escape === undefined) throw new Error(`unterminated escape in ${label}`);
    if (escape === 'n') chunks.push(Buffer.from([0x0a]));
    else if (escape === 'r') chunks.push(Buffer.from([0x0d]));
    else if (escape === 't') chunks.push(Buffer.from([0x09]));
    else if (escape === '\\' || escape === '"' || escape === "'") chunks.push(Buffer.from(escape, 'utf8'));
    else if (escape === 'x') {
      const hex = raw.slice(index + 1, index + 3);
      if (!/^[0-9a-fA-F]{2}$/.test(hex)) throw new Error(`invalid hexadecimal escape in ${label}`);
      chunks.push(Buffer.from([Number.parseInt(hex, 16)]));
      index += 2;
    } else if (escape === 'u' && raw[index + 1] === '{') {
      const close = raw.indexOf('}', index + 2);
      if (close === -1) throw new Error(`unterminated Unicode escape in ${label}`);
      const hex = raw.slice(index + 2, close);
      if (!/^[0-9a-fA-F]{1,6}$/.test(hex)) throw new Error(`invalid Unicode escape in ${label}`);
      const codePoint = Number.parseInt(hex, 16);
      if (codePoint > 0x10ffff || (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
        throw new Error(`invalid Unicode escape in ${label}`);
      }
      chunks.push(Buffer.from(String.fromCodePoint(codePoint), 'utf8'));
      index = close;
    } else {
      throw new Error(`unsupported escape in ${label}`);
    }
    segmentStart = index + 1;
  }
  if (segmentStart < raw.length) chunks.push(Buffer.from(raw.slice(segmentStart), 'utf8'));
  try {
    return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(Buffer.concat(chunks));
  } catch {
    throw new Error(`invalid UTF-8 in ${label}`);
  }
}

function canonicalSourceBytes(bytes, path) {
  const canonical = Buffer.allocUnsafe(bytes.length);
  let inputIndex = 0;
  let outputIndex = 0;
  while (inputIndex < bytes.length) {
    if (bytes[inputIndex] === 0x0d) {
      if (inputIndex + 1 >= bytes.length || bytes[inputIndex + 1] !== 0x0a) {
        throw new Error(`bare carriage return in generator source: ${path}`);
      }
      canonical[outputIndex++] = 0x0a;
      inputIndex += 2;
      continue;
    }
    canonical[outputIndex++] = bytes[inputIndex++];
  }
  return canonical.subarray(0, outputIndex);
}

function generatorSourceIdentity(root, overrides = new Map()) {
  const hasher = createHash('sha256');
  hasher.update(generatorSourceIdentityDomain);
  for (const path of generatorSourceFiles) {
    const fullPath = join(root, path);
    if (!lstatSync(fullPath).isFile()) throw new Error(`invalid generator source entry: ${path}`);
    const bytes = canonicalSourceBytes(overrides.get(path) ?? readFileSync(fullPath), path);
    const pathLength = Buffer.alloc(4);
    pathLength.writeUInt32LE(Buffer.byteLength(path, 'utf8'));
    const contentLength = Buffer.alloc(8);
    contentLength.writeBigUInt64LE(BigInt(bytes.length));
    hasher.update(pathLength);
    hasher.update(path, 'utf8');
    hasher.update(contentLength);
    hasher.update(bytes);
  }
  return hasher.digest('hex');
}

function candidateTreeIdentity(snapshot) {
  const hasher = createHash('sha256');
  hasher.update(candidateAdmissionIdentityDomain);
  for (const path of snapshot.files) {
    const pathBytes = Buffer.from(path, 'utf8');
    const bytes = snapshot.read(path);
    const pathLength = Buffer.alloc(4);
    pathLength.writeUInt32LE(pathBytes.length);
    const contentLength = Buffer.alloc(8);
    contentLength.writeBigUInt64LE(BigInt(bytes.length));
    hasher.update(pathLength);
    hasher.update(pathBytes);
    hasher.update(contentLength);
    hasher.update(bytes);
  }
  return hasher.digest('hex');
}

function withCrlf(bytes) {
  let lineFeedCount = 0;
  for (const byte of bytes) if (byte === 0x0a) lineFeedCount += 1;
  const result = Buffer.alloc(bytes.length + lineFeedCount);
  let outputIndex = 0;
  for (const byte of bytes) {
    if (byte === 0x0a) result[outputIndex++] = 0x0d;
    result[outputIndex++] = byte;
  }
  return result;
}

function testGeneratorSourceIdentity() {
  testPackageVersionProjection();
  assertJsonEqual(
    ['\u{10000}', '\uE000'].sort(compareUtf8Bytes),
    ['\uE000', '\u{10000}'],
    'UTF-8 byte path order',
  );
  const path = 'build.zig';
  const canonical = canonicalSourceBytes(readFileSync(join(repositoryRoot, path)), path);
  const expected = generatorSourceIdentity(repositoryRoot);
  const crlfIdentity = generatorSourceIdentity(repositoryRoot, new Map([[path, withCrlf(canonical)]]));
  assertEqual(crlfIdentity, expected, 'generator source CRLF equivalence');

  const mutatedIdentity = generatorSourceIdentity(
    repositoryRoot,
    new Map([[path, Buffer.concat([canonical, Buffer.from('// generator source mutation\n')])]]),
  );
  if (mutatedIdentity === expected) throw new Error('generator source mutation did not change identity');

  try {
    generatorSourceIdentity(repositoryRoot, new Map([[path, Buffer.concat([canonical, Buffer.from('\r')])]]));
  } catch (error) {
    if (error instanceof Error && error.message === `bare carriage return in generator source: ${path}`) return;
    throw error;
  }
  throw new Error('bare carriage return accepted in generator source');
}

function testChecksumInventoryAdmission() {
  const outsideBytes = Buffer.from('outside-root-sentinel');
  const outsideDigest = sha256(outsideBytes);
  const traversalPath = '../../../../outside/sentinel';
  const checksumText = `${outsideDigest}  conformance/world-image-v1/v0/world/${traversalPath}\n`;
  let readCount = 0;
  try {
    validateChecksums('/corpus', checksumText, ['manifest.json'], () => {
      readCount += 1;
      return outsideBytes;
    });
  } catch (error) {
    assertEqual(readCount, 0, 'checksum target reads before inventory validation');
    if (!(error instanceof Error) || !error.message.startsWith('checksum inventory')) throw error;
    if (error.message.includes(outsideDigest)) throw new Error('outside-root digest leaked before checksum admission');
    testCandidateSnapshotIdentity();
    testSemanticTextAdmission();
    testTranscriptClaimAdmission();
    testCorpusCoordination();
    return;
  }
  throw new Error('checksum traversal path accepted');
}

function testSemanticTextAdmission() {
  const invalidUtf8 = Buffer.concat([Buffer.from('{"ignored":"'), Buffer.from([0xff]), Buffer.from('"}')]);
  let invalidRejected = false;
  try {
    parseJsonDocument(invalidUtf8, 'manifest.json');
  } catch (error) {
    if (!(error instanceof Error) || error.message !== 'invalid UTF-8 in manifest.json') throw error;
    invalidRejected = true;
  }
  if (!invalidRejected) throw new Error('malformed UTF-8 manifest accepted');

  let bomRejected = false;
  try {
    parseJsonDocument(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from('{}')]), 'manifest.json');
  } catch {
    bomRejected = true;
  }
  if (!bomRejected) throw new Error('BOM-prefixed manifest accepted');
}

function testTranscriptClaimAdmission() {
  let duplicateRejected = false;
  try {
    parseTranscript('state_unchanged: true\nstate_unchanged: false\n', 'fixture');
  } catch (error) {
    if (!(error instanceof Error) || error.message !== 'duplicate transcript key for fixture: state_unchanged') throw error;
    duplicateRejected = true;
  }
  if (!duplicateRejected) throw new Error('duplicate transcript key accepted');

  const closureBytes = Buffer.alloc(16);
  closureBytes.writeUInt32LE(1, 0);
  closureBytes.writeUInt32LE(1, 4);
  closureBytes.writeBigUInt64LE(0x0123456789abcdefn, 8);
  const fields = new Map([['closure_fingerprint', '0x0123456789abcdef']]);
  validateTranscriptTurnClosureClaims('internal-provider-execution', fields, () => closureBytes);
  fields.set('closure_fingerprint', '0xfedcba9876543210');
  let forgedRejected = false;
  try {
    validateTranscriptTurnClosureClaims('internal-provider-execution', fields, () => closureBytes);
  } catch (error) {
    if (!(error instanceof Error) || !error.message.startsWith('artifact-bound transcript fact')) throw error;
    forgedRejected = true;
  }
  if (!forgedRejected) throw new Error('forged transcript closure fingerprint accepted');
}

function testCorpusCoordination() {
  const root = mkdtempSync(join(tmpdir(), 'world-oracle-coordination-'));
  try {
    let checkFailed = false;
    try {
      withCorpusCoordination(root, 'check', () => {
        throw new Error('expected tracked validation failure');
      });
    } catch (error) {
      if (!(error instanceof Error) || error.message !== 'expected tracked validation failure') throw error;
      checkFailed = true;
    }
    if (!checkFailed) throw new Error('coordination check failure not observed');

    let publisherRan = false;
    let publicationRejected = false;
    try {
      withCorpusCoordination(root, 'publish', () => {
        requireNoPriorValidationFailure(root);
        publisherRan = true;
      });
    } catch (error) {
      if (!(error instanceof Error) || error.message !== 'tracked oracle validation failed before publication') throw error;
      publicationRejected = true;
    }
    if (!publicationRejected || publisherRan) throw new Error('publication ran after tracked validation failure');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function testCandidateSnapshotIdentity() {
  const root = mkdtempSync(join(tmpdir(), 'world-oracle-candidate-snapshot-'));
  try {
    writeFileSync(join(root, 'manifest.json'), 'admitted manifest\n');
    writeFileSync(join(root, 'checksums.sha256'), 'admitted checksums\n');
    const snapshot = captureCorpus(root);
    const admitted = candidateTreeIdentity(snapshot);
    writeFileSync(join(root, 'manifest.json'), 'mutated after capture\n');
    assertEqual(candidateTreeIdentity(snapshot), admitted, 'captured candidate identity');
    if (candidateTreeIdentity(captureCorpus(root)) === admitted) {
      throw new Error('live candidate mutation did not change identity');
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function validateBinaryFamilies(contentFiles, manifest, read) {
  assertJsonEqual(manifest.binary_family_policy, expectedBinaryFamilyPolicy, 'manifest.binary_family_policy');
  assertJsonEqual(manifest.binary_families, expectedBinaryFamilies, 'manifest.binary_families');

  const textArtifacts = contentFiles.filter((path) => path.startsWith('artifacts/') && path.endsWith('.txt'));
  assertArrayEqual(textArtifacts, ['artifacts/states/capacity-exhaustion.after.txt'], 'text artifact inventory');
  const binaryArtifacts = contentFiles.filter((path) => path.startsWith('artifacts/') && !path.endsWith('.txt'));
  assertEqual(
    binaryArtifacts.length,
    expectedBinaryFamilyPolicy.binary_artifact_count,
    'binary artifact inventory length',
  );

  const familyCounts = new Map(expectedBinaryFamilies.map((family) => [family.id, 0]));
  for (const path of binaryArtifacts) {
    const matchingFamilies = expectedBinaryFamilies.filter((family) =>
      binaryFamilyMatchers[family.id].some((pattern) => pattern.test(path)),
    );
    assertEqual(matchingFamilies.length, 1, `binary family classification ${path}`);
    const family = matchingFamilies[0];
    familyCounts.set(family.id, familyCounts.get(family.id) + 1);
    validateBinaryFamilyHeader(path, family, read);
  }
  for (const family of expectedBinaryFamilies) {
    assertEqual(familyCounts.get(family.id), family.expected_count, `binary family count ${family.id}`);
  }
}

function validateBinaryFamilyHeader(path, family, read) {
  const bytes = read(path);
  if (family.magic !== undefined) {
    const magic = Buffer.from(family.magic, 'utf8');
    if (bytes.length < magic.length || !bytes.subarray(0, magic.length).equals(magic)) {
      throw new Error(`binary family magic ${family.id}: ${path}`);
    }
  }
  for (const field of family.header_fields ?? []) {
    assertU32Field(bytes, field, family.id, path);
  }
  if (family.versioning === 'member-versioned-container') {
    if (bytes.length < family.container_count_offset + 8) throw new Error(`binary family too short ${family.id}: ${path}`);
    assertEqual(
      bytes.readBigUInt64LE(family.container_count_offset),
      BigInt(family.expected_member_count),
      `binary family member count ${family.id}: ${path}`,
    );
    for (const field of family.member_header_fields) {
      assertU32Field(bytes, field, family.id, path);
    }
  }
  if (family.versioning === 'unversioned-container-owned') {
    const label = Buffer.from(family.label, 'utf8');
    if (bytes.length < family.value_fingerprint_offset + 8) throw new Error(`binary family too short ${family.id}: ${path}`);
    assertEqual(
      bytes.readUInt32LE(family.label_length_offset),
      label.length,
      `binary family label length ${family.id}: ${path}`,
    );
    if (!bytes.subarray(family.label_offset, family.label_offset + label.length).equals(label)) {
      throw new Error(`binary family label ${family.id}: ${path}`);
    }
    assertEqual(bytes.length, family.value_fingerprint_offset + 8, `binary family length ${family.id}: ${path}`);
  }
}

function assertU32Field(bytes, field, familyId, path) {
  if (bytes.length < field.offset + 4) throw new Error(`binary family too short ${familyId}: ${path}`);
  assertEqual(bytes.readUInt32LE(field.offset), field.value, `binary family ${field.name} ${familyId}: ${path}`);
}

function assertJsonEqual(actual, expected, label) {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`${label}: expected ${expectedJson}, got ${actualJson}`);
  }
}

function compareTrees(expectedRoot, actualRoot, label) {
  const expected = listFiles(expectedRoot);
  const actual = listFiles(actualRoot);
  assertArrayEqual(actual, expected, `${label} file inventory`);
  for (const path of expected) {
    const expectedBytes = readFileSync(join(expectedRoot, path));
    const actualBytes = readFileSync(join(actualRoot, path));
    if (!expectedBytes.equals(actualBytes)) {
      throw new Error(`${label} byte mismatch: ${path}`);
    }
  }
}

function listFiles(root) {
  const inspectedRoot = resolve(root);
  if (!lstatSync(inspectedRoot).isDirectory()) throw new Error(`not a directory: ${root}`);
  const files = [];
  walk(inspectedRoot, inspectedRoot, files);
  files.sort(compareUtf8Bytes);
  return files;
}

function captureCorpus(root) {
  const files = listFiles(root);
  const bytesByPath = new Map();
  for (const path of files) bytesByPath.set(path, readFileSync(join(root, path)));
  return {
    files,
    read(path, encoding) {
      const bytes = bytesByPath.get(path);
      if (bytes === undefined) throw new Error(`missing captured corpus path: ${path}`);
      return encoding === undefined ? bytes : bytes.toString(encoding);
    },
  };
}

function generatorSourceInventory(root) {
  const files = [];
  for (const packagePath of sourcePackagePaths) {
    const absolutePath = join(root, packagePath);
    const stat = lstatSync(absolutePath);
    if (stat.isFile()) {
      if (!packagePath.startsWith(generatorSourceExcludedPrefix)) files.push(packagePath);
    } else if (stat.isDirectory()) {
      for (const relativePath of listFiles(absolutePath)) {
        const path = `${packagePath}/${relativePath}`;
        if (!path.startsWith(generatorSourceExcludedPrefix)) files.push(path);
      }
    } else {
      throw new Error(`unsupported root package path: ${packagePath}`);
    }
  }
  files.sort(compareUtf8Bytes);
  for (let index = 1; index < files.length; index += 1) {
    if (files[index] === files[index - 1]) {
      throw new Error(`overlapping root package paths include ${files[index]} more than once`);
    }
  }
  return files;
}

function testRootSymlinkRejection() {
  if (process.platform === 'win32') return;

  const temporaryRoot = mkdtempSync(join(tmpdir(), 'world-oracle-root-symlink-'));
  try {
    const realParent = join(temporaryRoot, 'real-parent');
    const realCorpus = join(realParent, 'corpus');
    const linkedCorpus = join(temporaryRoot, 'corpus-link');
    const linkedParent = join(temporaryRoot, 'parent-link');
    mkdirSync(realCorpus, { recursive: true });
    symlinkSync(realCorpus, linkedCorpus, 'dir');
    symlinkSync(realParent, linkedParent, 'dir');

    expectRootRejected(linkedCorpus);
    expectRootRejected(`${linkedCorpus}${sep}`);
    assertArrayEqual(listFiles(join(linkedParent, 'corpus')), [], 'symlinked ancestor inventory');
  } finally {
    rmSync(temporaryRoot, { recursive: true, force: true });
  }
}

function expectRootRejected(root) {
  try {
    listFiles(root);
  } catch (error) {
    if (error instanceof Error && error.message === `not a directory: ${root}`) return;
    throw error;
  }
  throw new Error(`symlinked corpus root accepted: ${root}`);
}

function walk(root, current, files) {
  const entries = readdirSync(current, { withFileTypes: true });
  entries.sort((left, right) => compareUtf8Bytes(left.name, right.name));
  for (const entry of entries) {
    const path = join(current, entry.name);
    if (entry.isDirectory()) walk(root, path, files);
    else if (entry.isFile()) files.push(relative(root, path).split(sep).join('/'));
    else throw new Error(`unsupported filesystem entry: ${path}`);
  }
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function compareUtf8Bytes(left, right) {
  return Buffer.compare(Buffer.from(left, 'utf8'), Buffer.from(right, 'utf8'));
}

function assertArrayEqual(actual, expected, label) {
  assertEqual(actual.length, expected.length, `${label}.length`);
  for (let index = 0; index < expected.length; index += 1) {
    assertEqual(actual[index], expected[index], `${label}[${index}]`);
  }
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`);
}
