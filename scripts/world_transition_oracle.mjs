#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

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
const generatorSourceFiles = [
  'build.zig',
  'build.zig.zon',
  'examples/world_appliance_common.zig',
  'examples/world_transition_oracle_emit.zig',
  'examples/world_universal_appliance_wasm.zig',
  'scripts/world_transition_oracle.mjs',
  'src/appliance.zig',
  'src/archive.zig',
  'src/executable.zig',
  'src/linker.zig',
  'src/protocol.zig',
  'src/world.zig',
  'test/fixtures.zig',
];
const generatorSourceSrcFiles = generatorSourceFiles
  .filter((path) => path.startsWith('src/'))
  .map((path) => path.slice('src/'.length));

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

if (args.mode === 'compare') {
  requireArg(args.expected, '--expected');
  requireArg(args.first, '--first');
  requireArg(args.second, '--second');
  requireArg(args.zigVersion, '--zig-version');
  validateCorpus(args.expected, args.zigVersion);
  validateCorpus(args.first, args.zigVersion);
  validateCorpus(args.second, args.zigVersion);
  compareTrees(args.expected, args.first, 'tracked/first');
  compareTrees(args.expected, args.second, 'tracked/second');
  compareTrees(args.first, args.second, 'first/second');
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
  validateCorpus(args.expected, args.zigVersion);
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
    else throw new Error(`unknown argument ${arg}`);
  }
  return parsed;
}

function requireArg(value, name) {
  if (typeof value !== 'string' || value.length === 0) throw new Error(`missing ${name}`);
}

function packageVersionFromZon(zon) {
  const source = zonWithoutComments(zon);
  const matches = [...source.matchAll(/(?:^|[,{])\s*\.version\s*=\s*"([^"\\\r\n]+)"\s*,/g)];
  if (matches.length !== 1) throw new Error(`expected exactly one root package version, got ${matches.length}`);
  return matches[0][1];
}

function zonWithoutComments(zon) {
  let result = '';
  let quote = null;
  let escaped = false;
  for (let index = 0; index < zon.length; index += 1) {
    const character = zon[index];
    const next = zon[index + 1];
    if (quote !== null) {
      result += character;
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
      result += character;
      continue;
    }
    if (character === '/' && next === '/') {
      result += '  ';
      index += 2;
      while (index < zon.length && zon[index] !== '\n') {
        result += ' ';
        index += 1;
      }
      if (index < zon.length) result += '\n';
      continue;
    }
    if (character === '/' && next === '*') {
      result += '  ';
      index += 2;
      while (index < zon.length && !(zon[index] === '*' && zon[index + 1] === '/')) {
        result += zon[index] === '\n' ? '\n' : ' ';
        index += 1;
      }
      if (index >= zon.length) throw new Error('unterminated block comment in build.zig.zon');
      result += '  ';
      index += 1;
      continue;
    }
    result += character;
  }
  if (quote !== null) throw new Error('unterminated literal in build.zig.zon');
  return result;
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

function validateCorpus(root, expectedZigVersion) {
  const files = listFiles(root);
  if (files.length === 0) throw new Error(`empty oracle corpus: ${root}`);
  if (!files.includes('manifest.json')) throw new Error(`missing manifest.json: ${root}`);
  if (!files.includes('checksums.sha256')) throw new Error(`missing checksums.sha256: ${root}`);

  const manifestBytes = readFileSync(join(root, 'manifest.json'));
  const manifest = JSON.parse(manifestBytes.toString('utf8'));
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
    const transcript = readFileSync(join(root, `cases/${caseId}.txt`), 'utf8');
    const transcriptLines = new Set(transcript.split('\n'));
    for (const fact of facts) {
      if (!transcriptLines.has(fact)) throw new Error(`missing provenance fact for ${caseId}: ${fact}`);
    }
  }

  const contentFiles = files.filter((path) => path !== 'manifest.json' && path !== 'checksums.sha256');
  assertArrayEqual(contentFiles, expectedArtifacts, 'expected artifact inventory');
  validateBinaryFamilies(root, contentFiles, manifest);
  const manifestArtifacts = manifest.artifacts.map((entry) => entry.path);
  assertArrayEqual(manifestArtifacts, contentFiles, 'manifest artifact inventory');

  const artifactHasher = createHash('sha256');
  for (const entry of manifest.artifacts) {
    const bytes = readFileSync(join(root, entry.path));
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
    readFileSync(join(root, 'checksums.sha256'), 'utf8'),
    files.filter((path) => path !== 'checksums.sha256'),
  );
}

function validateChecksums(root, checksumText, expectedPaths, read = readFileSync) {
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
    assertEqual(digest, sha256(read(join(root, path))), `checksums.sha256 ${path}`);
  }
}

function rootBoundaryPackage() {
  return boundaryPackageFromZon(readFileSync(new URL('../build.zig.zon', import.meta.url), 'utf8'));
}

function boundaryPackageFromZon(zon) {
  const source = zonWithoutComments(zon);
  const dependencyMatches = [
    ...source.matchAll(/(?:^|[,{])\s*\.boundary\s*=\s*\.\{([^{}]*)\}\s*,/g),
  ];
  if (dependencyMatches.length !== 1) {
    throw new Error(`expected exactly one .boundary dependency, got ${dependencyMatches.length}`);
  }
  const body = dependencyMatches[0][1];
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

function zonStringField(body, field, label) {
  const matches = [
    ...body.matchAll(new RegExp(`(?:^|,)\\s*\\.${field}\\s*=\\s*"([^"\\\\\\r\\n]+)"\\s*,`, 'g')),
  ];
  if (matches.length !== 1) throw new Error(`expected exactly one ${label}, got ${matches.length}`);
  return matches[0][1];
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
  assertArrayEqual(listFiles(join(root, 'src')), generatorSourceSrcFiles, 'generator source src inventory');
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
    return;
  }
  throw new Error('checksum traversal path accepted');
}

function validateBinaryFamilies(root, contentFiles, manifest) {
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
    validateBinaryFamilyHeader(root, path, family);
  }
  for (const family of expectedBinaryFamilies) {
    assertEqual(familyCounts.get(family.id), family.expected_count, `binary family count ${family.id}`);
  }
}

function validateBinaryFamilyHeader(root, path, family) {
  const bytes = readFileSync(join(root, path));
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
  files.sort(compareAscii);
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
  entries.sort((left, right) => compareAscii(left.name, right.name));
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

function compareAscii(left, right) {
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
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
