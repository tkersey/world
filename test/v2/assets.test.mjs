import test from 'node:test';
import assert from 'node:assert/strict';
import { gunzipSync, gzipSync } from 'node:zlib';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { tarGzip, readTarGzip, indexedBundle, readBundle, writeAssets, verifyAssets, readSource, sha256, json } from '../../scripts/v2/assets.mjs';

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
