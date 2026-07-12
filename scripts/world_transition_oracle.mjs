#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

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
    'first_retry_output_byte_equal: true',
    'first_retry_closure_byte_equal: true',
    'cold_restore_completed: true',
  ],
  'migration': [
    'case_id: migration',
    'owner_surface: Capsule/Runspace/Fabric',
    'fixture_provenance: synthetic-owner-state',
    'source_destroyed: true',
    'receiver_fresh_instance: true',
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
    'final_status: completed',
  ],
  'deterministic-failure': [
    'case_id: deterministic-failure',
    'owner_surface: Appliance/TurnClosure',
    'accepted_result_status: failed',
    'transition_status: failed',
    'next_state_status: failed',
    'root_result_present: false',
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
    'state_unchanged_after_wrong_result: true',
    'state_unchanged_after_duplicate_result: true',
    'state_unchanged_after_stale_result: true',
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
  'artifacts/inputs/retry.cold-restore.turn-input',
  'artifacts/inputs/retry.continue.turn-input',
  'artifacts/malformed/executable-image.trailing-byte',
  'artifacts/malformed/result.duplicate-target.turn-input',
  'artifacts/malformed/result.stale-replay.turn-input',
  'artifacts/malformed/result.wrong-target.turn-input',
  'artifacts/malformed/state.turn-closure.trailing-byte',
  'artifacts/manifests/internal-provider.appliance-manifest',
  'artifacts/manifests/one-port.appliance-manifest',
  'artifacts/outputs/failure.failed.turn-output',
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
  'artifacts/transitions/internal-provider.completed.turn-closure',
  'artifacts/transitions/one-port.completed.turn-closure',
  'artifacts/transitions/one-port.waiting.turn-closure',
  'artifacts/transitions/partial-batch.completed.turn-closure',
  'artifacts/transitions/partial-batch.parent.turn-closure',
  'artifacts/transitions/partial-batch.remaining.turn-closure',
  'artifacts/transitions/retry.cold-restore.turn-closure',
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

const expectedBoundaryPackageHash = boundaryPackageHashFromZon();

const args = parseArgs(process.argv.slice(2));

if (args.mode === 'compare') {
  requireArg(args.expected, '--expected');
  requireArg(args.first, '--first');
  requireArg(args.second, '--second');
  validateCorpus(args.expected);
  validateCorpus(args.first);
  validateCorpus(args.second);
  compareTrees(args.expected, args.first, 'tracked/first');
  compareTrees(args.expected, args.second, 'tracked/second');
  compareTrees(args.first, args.second, 'first/second');
} else if (args.mode === 'verify') {
  requireArg(args.expected, '--expected');
  requireArg(args.actual, '--actual');
  validateCorpus(args.expected);
  validateCorpus(args.actual);
  compareTrees(args.expected, args.actual, 'expected/actual');
} else if (args.mode === 'check') {
  requireArg(args.expected, '--expected');
  validateCorpus(args.expected);
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
    else throw new Error(`unknown argument ${arg}`);
  }
  return parsed;
}

function requireArg(value, name) {
  if (typeof value !== 'string' || value.length === 0) throw new Error(`missing ${name}`);
}

function validateCorpus(root) {
  const files = listFiles(root);
  if (files.length === 0) throw new Error(`empty oracle corpus: ${root}`);
  if (!files.includes('manifest.json')) throw new Error(`missing manifest.json: ${root}`);
  if (!files.includes('checksums.sha256')) throw new Error(`missing checksums.sha256: ${root}`);

  const manifestBytes = readFileSync(join(root, 'manifest.json'));
  const manifest = JSON.parse(manifestBytes.toString('utf8'));
  assertEqual(manifest.format, 'world-image-v1-rewrite-world-oracle-v0', 'manifest.format');
  assertEqual(manifest.format_version, 1, 'manifest.format_version');
  assertEqual(manifest.semantic_source?.package, 'world', 'manifest.semantic_source.package');
  assertEqual(manifest.semantic_source?.package_version, '0.1.0', 'manifest.semantic_source.package_version');
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
  assertEqual(manifest.semantic_source?.boundary_package, '0.6.2', 'manifest.semantic_source.boundary_package');
  assertEqual(
    manifest.semantic_source?.boundary_package_hash,
    expectedBoundaryPackageHash,
    'manifest.semantic_source.boundary_package_hash',
  );
  assertEqual(manifest.semantic_source?.world_executable_image_format, 2, 'manifest executable image format');
  assertEqual(manifest.semantic_source?.world_turn_closure_format, 1, 'manifest TurnClosure format');
  assertEqual(manifest.semantic_source?.world_archive_format, 1, 'manifest Archive format');
  assertEqual(manifest.semantic_source?.world_appliance_abi, 4, 'manifest Appliance ABI');
  assertEqual(manifest.semantic_source?.world_appliance_command_format, 1, 'manifest Appliance Command format');
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
  assertArtifactFormatPrefixes(
    root,
    contentFiles,
    '.boot.command',
    manifest.semantic_source.world_appliance_command_format,
    'Appliance Command',
  );
  assertArtifactFormatPrefixes(
    root,
    contentFiles,
    '.turn-input',
    manifest.semantic_source.world_appliance_wire_turn_input_format,
    'Wire.TurnInput',
  );
  assertArtifactFormatPrefixes(
    root,
    contentFiles,
    '.resolution-input',
    manifest.semantic_source.world_appliance_wire_resolution_input_format,
    'Wire.ResolutionInput',
  );
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

  const checksumLines = readFileSync(join(root, 'checksums.sha256'), 'utf8')
    .trimEnd()
    .split('\n')
    .filter(Boolean);
  const checksumPaths = [];
  for (const line of checksumLines) {
    const match = /^([0-9a-f]{64})  conformance\/world-image-v1\/v0\/world\/(.+)$/.exec(line);
    if (!match) throw new Error(`invalid checksum line: ${line}`);
    const [, digest, path] = match;
    checksumPaths.push(path);
    assertEqual(digest, sha256(readFileSync(join(root, path))), `checksums.sha256 ${path}`);
  }
  assertArrayEqual(checksumPaths, files.filter((path) => path !== 'checksums.sha256'), 'checksum inventory');
}

function boundaryPackageHashFromZon() {
  const zon = readFileSync(new URL('../build.zig.zon', import.meta.url), 'utf8');
  const boundaryDependency = /\.boundary\s*=\s*\.\{([\s\S]*?)\n\s*\},/.exec(zon);
  if (!boundaryDependency) throw new Error('missing .boundary dependency in build.zig.zon');
  const hash = /\.hash\s*=\s*"([^"]+)"/.exec(boundaryDependency[1]);
  if (!hash) throw new Error('missing .boundary.hash in build.zig.zon');
  return hash[1];
}

function assertArtifactFormatPrefixes(root, files, suffix, expectedFormat, label) {
  const matching = files.filter((path) => path.endsWith(suffix));
  if (matching.length === 0) throw new Error(`missing ${label} artifacts`);
  for (const path of matching) {
    const bytes = readFileSync(join(root, path));
    if (bytes.length < 4) throw new Error(`${label} artifact too short: ${path}`);
    assertEqual(bytes.readUInt32LE(0), expectedFormat, `${label} format prefix ${path}`);
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
  if (!statSync(root).isDirectory()) throw new Error(`not a directory: ${root}`);
  const files = [];
  walk(root, root, files);
  files.sort(compareAscii);
  return files;
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
