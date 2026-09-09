import test from 'node:test';
import assert from 'node:assert/strict';
import { gunzipSync, gzipSync } from 'node:zlib';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { tarGzip, readTarGzip, indexedBundle, readBundle, writeAssets, verifyAssets, sourceIdentity, readSource, verifyExampleSources, verifyRuntimeSources, sha256, json } from '../../scripts/v2/assets.mjs';

const files = [{ name: 'z/data.bin', bytes: Buffer.from([0, 255]) }, { name: 'a/run', bytes: Buffer.from('hello'), executable: true }];
function repairChecksum(bytes) {
  bytes.fill(32, 148, 156);
  const sum = bytes.subarray(0, 512).reduce((a, b) => a + b, 0);
  bytes.write(sum.toString(8).padStart(6, '0') + '\0 ', 148, 8, 'ascii');
}

test('deterministic archives round-trip regular files and executable mode', () => {
  const archive = tarGzip(files);
  assert.deepEqual(archive, tarGzip([...files].reverse()));
  assert.deepEqual(readTarGzip(archive), [{ ...files[1] }, { ...files[0], executable: false }]);
});

test('archive admission rejects unsafe paths, links, bad framing and padding', () => {
  const valid = gunzipSync(tarGzip([files[1]]));
  for (const mutate of [
    b => { b.fill(0, 0, 100); b.write('../escape', 0); },
    b => { b[156] = 50; b.write('/outside', 157); },
    b => { b[156] = 49; },
    b => { b[345] = 97; },
    b => { b.write('0000777\0', 100, 8, 'ascii'); },
    b => { b.write('77777777777\0', 124, 12, 'ascii'); },
    b => { b[517] = 1; },
  ]) {
    const bytes = Buffer.from(valid); mutate(bytes); repairChecksum(bytes);
    assert.throws(() => readTarGzip(gzipSync(bytes)));
  }
  const broken = Buffer.from(valid); broken[0] ^= 1;
  assert.throws(() => readTarGzip(gzipSync(broken)), /checksum/);
  assert.throws(() => readTarGzip(gzipSync(valid.subarray(0, valid.length - 512))), /terminator/);
  assert.throws(() => readTarGzip(gzipSync(Buffer.concat([valid, Buffer.from([1])]))), /terminator/);
  assert.throws(() => readTarGzip(gzipSync(Buffer.concat([valid.subarray(0, 1024), valid]))), /entry/);
});

test('container producers reject duplicate and escaping names', () => {
  for (const name of ['../x', '/x', 'a/../x', 'a//b', 'a\\b', './x']) {
    assert.throws(() => tarGzip([{ name, bytes: Buffer.alloc(0) }]));
    assert.throws(() => indexedBundle([{ name, bytes: Buffer.alloc(0) }]));
  }
  assert.throws(() => tarGzip([files[0], files[0]]));
  assert.throws(() => indexedBundle([files[0], files[0]]));
});

test('self-consistent example archives cannot replace any executable source input', () => {
  const inputs = [
    ['build.zig', 'tools/v2/examples/build.zig', 'trusted build instructions'],
    ['build.zig.zon', 'tools/v2/examples/build.zig.zon', 'trusted dependency paths'],
    ['main.zig', 'test/v2/emit_source.zig', 'trusted example program'],
    ['LICENSE', 'LICENSE', 'license'],
  ];
  const source = inputs.map(([, name, text]) => ({ name, bytes: Buffer.from(text) }));
  const fixtureFiles = new Map([['fixtures.json', Buffer.from('{}')], ['cases/example.bin', Buffer.from([1, 2])]]);
  const archive = [...inputs.map(([name, , text]) => ({ name, bytes: Buffer.from(text) })),
    { name: 'README.md', bytes: Buffer.from('generated guide') },
    ...[...fixtureFiles].map(([name, bytes]) => ({ name, bytes }))];
  const verify = (entries, files = source) => verifyExampleSources(readTarGzip(tarGzip(entries)), files, fixtureFiles);
  verify(archive);
  assert.throws(() => verify([...archive, { name: 'extra.mjs', bytes: Buffer.from('unaccounted source') }]), /example source mismatch/);
  for (let index = 0; index < archive.length; index++) {
    const changed = archive.map(entry => ({ ...entry }));
    changed[index].bytes = Buffer.from('replacement with fresh archive checksums');
    // The tar writer repairs container checksums; independent source binding
    // must still reject the changed file before any compiler invocation.
    if (archive[index].name !== 'README.md') assert.throws(() => verify(changed), /example source mismatch/);
    assert.throws(() => verify(archive.filter((_, i) => i !== index)), /example source mismatch/);
    if (index < source.length) assert.throws(() => verify(archive, source.filter((_, i) => i !== index)), /example source mismatch/);
    assert.throws(() => verify(archive.map((row, i) => i === index ? { ...row, executable: true } : row)), /example source mismatch/);
  }
});

test('runtime source authentication preserves bytes and executable modes', () => {
  const source = [
    { name: 'bin/world.mjs', bytes: Buffer.from('#!/usr/bin/env node\n'), executable: true },
    { name: 'package.json', bytes: json({ files: ['bin/'] }), executable: false },
  ];
  const generated = ['world-process-kernel-v2.wasm', 'world-runtime-identity.json', 'SHA256SUMS']
    .map(name => ({ name, bytes: Buffer.from('generated'), executable: false }));
  const entries = [...source, ...generated];
  verifyRuntimeSources(readTarGzip(tarGzip(entries)), source);
  for (let index = 0; index < entries.length; index++) {
    const changed = entries.map(entry => ({ ...entry }));
    changed[index].executable = !changed[index].executable;
    assert.throws(() => verifyRuntimeSources(readTarGzip(tarGzip(changed)), source),
      /runtime source mismatch/);
  }
  const altered = source.map(entry => ({ ...entry }));
  altered[0].bytes = Buffer.from('substituted executable');
  assert.throws(() => verifyRuntimeSources(readTarGzip(tarGzip(altered)), source),
    /runtime source mismatch/);
  assert.throws(() => verifyRuntimeSources(readTarGzip(tarGzip(entries)), source.slice(1)),
    /runtime source mismatch/);
});

test('runtime distribution admits exactly the authenticated package inventory', () => {
  const source = [
    { name: 'package.json', bytes: json({ files: ['bin/', 'src/process_v2/', 'docs/abi.md'] }), executable: false },
    { name: 'bin/world.mjs', bytes: Buffer.from('CLI'), executable: true },
    { name: 'src/process_v2/index.mjs', bytes: Buffer.from('runtime'), executable: false },
    { name: 'src/process_v2/nested/value.mjs', bytes: Buffer.from('codec'), executable: false },
    { name: 'docs/abi.md', bytes: Buffer.from('API'), executable: false },
    { name: 'test/v2/legacy/process_v1/kernel.mjs', bytes: Buffer.from('legacy evaluator'), executable: false },
    { name: 'src/process_v2-extra/leak.mjs', bytes: Buffer.from('prefix sibling'), executable: false },
    { name: 'docs/private.md', bytes: Buffer.from('unselected documentation'), executable: false },
  ];
  const entries = [...source.slice(0, 5), ...['world-process-kernel-v2.wasm', 'world-runtime-identity.json', 'SHA256SUMS']
    .map(name => ({ name, bytes: Buffer.from('generated'), executable: false }))];
  const verify = rows => verifyRuntimeSources(readTarGzip(tarGzip(rows)), source);
  verify(entries);
  // Each extra file has authentic source bytes and modes, but is not distributed.
  for (const extra of source.slice(5)) assert.throws(() => verify([...entries, extra]), /runtime source mismatch/);
  for (const omitted of entries) assert.throws(() => verify(entries.filter(row => row !== omitted)), /runtime source mismatch/);
  const broadened = entries.map(row => row.name === 'package.json'
    ? { ...row, bytes: json({ files: ['bin/', 'src/', 'docs/', 'test/'] }) } : row);
  assert.throws(() => verify([...broadened, source[5]]), /runtime source mismatch/);
});

test('indexed data requires exact offsets, names, lengths and byte digests', () => {
  const bundle = indexedBundle(files);
  assert.deepEqual([...readBundle(bundle, bundle.bytes).keys()], ['a/run', 'z/data.bin']);
  for (const change of [
    b => { b.files[0].offset = 1; }, b => { b.files[1].name = b.files[0].name; },
    b => { b.files[0].length = Number.MAX_SAFE_INTEGER; }, b => { b.files[0].length = -1; },
    b => { b.files[0].sha256 = '0'.repeat(64); }, b => { b.files[0].name = '../x'; },
  ]) {
    const bad = structuredClone(bundle); change(bad);
    assert.throws(() => readBundle(bad, bundle.bytes));
  }
  assert.throws(() => readBundle(bundle, Buffer.concat([bundle.bytes, Buffer.from([0])])));
});

test('outer asset admission rejects inventory or content changes before consumers run', async () => {
  const cache = resolve(import.meta.dirname, '../../.cache/v2/assets-tests');
  await mkdir(cache, { recursive: true });
  const directory = await mkdtemp(join(cache, 'case-'));
  try {
    const entries = [{ name: 'first.bin', bytes: Buffer.from([1, 2, 3]) }];
    await writeAssets(directory, entries);
    assert.deepEqual((await verifyAssets(directory, ['first.bin'])).get('first.bin'), entries[0].bytes);
    await assert.rejects(verifyAssets(directory, ['first.bin', 'absent.bin']), /inventory/);
    await writeFile(join(directory, 'first.bin'), Buffer.from([1, 2, 4]));
    await assert.rejects(verifyAssets(directory, ['first.bin']), /digest/);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test('a clean source claim cannot substitute receipt-controlled files for its Git commit', async () => {
  const root = resolve(import.meta.dirname, '../..');
  const git = (...args) => execFileSync('git', args, { cwd: root, maxBuffer: 64 << 20 });
  const head = git('rev-parse', 'HEAD').toString().trim(), tree = git('rev-parse', 'HEAD^{tree}').toString().trim();
  const files = [];
  for (const row of git('ls-tree', '-r', '--full-tree', '-z', head).toString().split('\0').filter(Boolean)) {
    const path = row.slice(row.indexOf('\t') + 1);
    if (path === '.learnings.jsonl' || path.startsWith('.ledger/')) continue;
    const match = /^(100644|100755) blob ([a-f0-9]{40})\t(.+)$/.exec(row);
    assert.ok(match);
    files.push({ name: match[3], sha256: sha256(git('cat-file', 'blob', match[2])) });
  }
  files.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
  const identity = { git: { head, tree, dirty: false }, files, filesSha256: sha256(json(files)) };
  const valid = await readSource(root, identity, head);
  assert.equal(valid.length, files.length);
  const forged = structuredClone(identity);
  forged.files[0].sha256 = sha256(Buffer.from('replacement source with the same claimed clean commit'));
  forged.filesSha256 = sha256(json(forged.files));
  await assert.rejects(readSource(root, forged, head), /source content mismatch/);
  forged.files.pop(); forged.filesSha256 = sha256(json(forged.files));
  await assert.rejects(readSource(root, forged, head), /inventory mismatch/);
  await assert.rejects(readSource(root, { ...identity, git: { ...identity.git, dirty: true } }, head), /commit mismatch/);
});

test('replacement refs cannot change the tree certified under an immutable commit id', async () => {
  const root = resolve(import.meta.dirname, '../..');
  const git = (cwd, ...args) => execFileSync('git', args, { cwd, maxBuffer: 64 << 20 });
  const head = git(root, 'rev-parse', 'HEAD').toString().trim();
  const base = 'a55154eb43d19cba83c0bf1869cfd38704905ff1';
  const files = [];
  for (const row of git(root, 'ls-tree', '-r', '--full-tree', '-z', base).toString().split('\0').filter(Boolean)) {
    const path = row.slice(row.indexOf('\t') + 1);
    if (path === '.learnings.jsonl' || path.startsWith('.ledger/')) continue;
    const match = /^(100644|100755) blob ([a-f0-9]{40})\t(.+)$/.exec(row);
    assert.ok(match);
    files.push({ name: path, sha256: sha256(git(root, 'cat-file', 'blob', match[2])) });
  }
  files.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
  const forged = { git: { head, tree: git(root, 'rev-parse', `${base}^{tree}`).toString().trim(), dirty: false }, files, filesSha256: sha256(json(files)) };
  const cache = resolve(root, '.cache/v2/assets-tests');
  await mkdir(cache, { recursive: true });
  const temporary = await mkdtemp(join(cache, 'replacement-'));
  try {
    const checkout = join(temporary, 'checkout');
    git(root, 'clone', '--quiet', '--no-local', root, checkout);
    const actual = await sourceIdentity(checkout);
    git(checkout, 'replace', head, base);
    await assert.rejects(readSource(checkout, forged, head), /source tree mismatch/);
    assert.deepEqual(await sourceIdentity(checkout), actual);
    const savedGitDir = process.env.GIT_DIR, savedWorkTree = process.env.GIT_WORK_TREE;
    try {
      process.env.GIT_DIR = join(temporary, 'absent.git');
      process.env.GIT_WORK_TREE = root;
      assert.deepEqual(await sourceIdentity(checkout), actual);
      const verified = await readSource(checkout, actual, head);
      assert.equal(verified.length, actual.files.length);
      await assert.rejects(sourceIdentity(join(checkout, 'src')), /repository root/);
    } finally {
      if (savedGitDir === undefined) delete process.env.GIT_DIR; else process.env.GIT_DIR = savedGitDir;
      if (savedWorkTree === undefined) delete process.env.GIT_WORK_TREE; else process.env.GIT_WORK_TREE = savedWorkTree;
    }
    await writeFile(join(checkout, '.git/info/exclude'), 'src/process_v2/private-note.txt\n');
    await writeFile(join(checkout, 'src/process_v2/private-note.txt'), 'ignored source must not enter the package');
    assert.deepEqual(await sourceIdentity(checkout), actual);
    await writeFile(join(checkout, 'README.md'), 'development snapshot');
    const development = await sourceIdentity(checkout);
    assert.equal(development.git.dirty, true);
    const retained = await readSource(checkout, development);
    await writeFile(join(checkout, 'README.md'), 'later source generation');
    assert.equal(retained.find(row => row.name === 'README.md').bytes.toString(), 'development snapshot');
    assert.ok(!retained.some(row => row.name.endsWith('private-note.txt')));
    await assert.rejects(readSource(checkout, development), /source content mismatch/);
  } finally { await rm(temporary, { recursive: true, force: true }); }
});
