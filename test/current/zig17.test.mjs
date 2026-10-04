import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, writeFile, readFile, rm, rename, symlink, unlink, chmod, access, realpath } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir, homedir } from 'node:os';
import { packageInventory, sha256 } from '../../src/node/runtime-bundle.mjs';
import { verifyPackage, copyVerifiedPackage, packageStore } from '../../src/node/runtime-prepare.mjs';
import { reserveOutput } from '../../src/node/runtime-output.mjs';

async function area(t) {
  const root = await mkdtemp(join(tmpdir(), 'world zig17 Ω '));
  t.after(() => rm(root, { recursive: true, force: true }));
  return root;
}
async function packageFixture(root) {
  await mkdir(join(root, 'src'), {recursive:true});
  await writeFile(join(root, 'build.zig'), 'selected build bytes');
  await writeFile(join(root, 'src/root.zig'), 'selected module bytes');
  return sha256(JSON.stringify(await packageInventory(root)));
}

test('package authentication detects contents, membership, permission and alias changes', async t => {
  const root = await area(t);
  for (const change of ['contents', 'added', 'renamed', 'removed', 'mode', 'link']) {
    const source = join(root, change), expected = await packageFixture(source);
    await verifyPackage(source, expected);
    if (change === 'contents') await writeFile(join(source, 'build.zig'), 'different code');
    if (change === 'added') await writeFile(join(source, 'new.zig'), 'new');
    if (change === 'renamed') await rename(join(source, 'src/root.zig'), join(source, 'src/renamed.zig'));
    if (change === 'removed') await unlink(join(source, 'src/root.zig'));
    if (change === 'mode') await chmod(join(source, 'build.zig'), 0o755);
    if (change === 'link') await symlink(join(root, 'contents'), join(source, 'alias'));
    await assert.rejects(verifyPackage(source, expected));
    const destination = join(root, 'rejected-' + change);
    await assert.rejects(copyVerifiedPackage(source, destination, expected));
    await assert.rejects(access(destination), {code:'ENOENT'});
  }
});

test('private package copy survives later source replacement without overwriting destinations', async t => {
  const root = await area(t), source = join(root, 'external store'), destination = join(root, 'owned/package');
  const expected = await packageFixture(source);
  await copyVerifiedPackage(source, destination, expected);
  await writeFile(join(source, 'build.zig'), 'replacement');
  await assert.rejects(verifyPackage(source, expected));
  await verifyPackage(destination, expected);
  assert.equal(await readFile(join(destination, 'build.zig'), 'utf8'), 'selected build bytes');
  await assert.rejects(copyVerifiedPackage(destination, source, expected), {code:'ERR_FS_CP_EEXIST'});
  assert.equal(await readFile(join(source, 'build.zig'), 'utf8'), 'replacement');
  const alias = join(root, 'package alias');
  await symlink(destination, alias, 'dir');
  await assert.rejects(verifyPackage(alias, expected), {code:'WORLD_BUNDLE_DEPENDENCY_INVALID'});
});

test('explicit and symlinked stores retain caller ownership; unsafe cleanup locations reject', async t => {
  const root = await area(t), source = join(root, 'source'), external = join(root, 'external store'), output = join(root, 'ready');
  await mkdir(source); await mkdir(external);
  await writeFile(join(external, 'sentinel'), 'keep');
  const alias = join(root, 'store alias');
  await symlink(external, alias, 'dir');
  const owned = join(output + '.preparing', 'packages');
  assert.deepEqual(await packageStore(null, source, output, owned), {root:owned,owned:true});
  for (const selected of [external, alias])
    assert.deepEqual(await packageStore(selected, source, output, owned), {root:await realpath(external),owned:false});
  for (const forbidden of ['/', homedir(), source, output, owned, join(output + '.preparing', '..nested')])
    await assert.rejects(packageStore(forbidden, source, output, owned), {code:'WORLD_BUNDLE_DESTINATION_INVALID'});
  const reservation = await reserveOutput(output);
  await symlink(external, join(reservation.stage, 'external alias'), 'dir');
  await reservation.cleanup();
  assert.equal(await readFile(join(external, 'sentinel'), 'utf8'), 'keep');
});

test('reservation cleanup follows its selected parent and rejects directory replacement', async t => {
  const root = await area(t), first = join(root, 'first'), second = join(root, 'second'), alias = join(root, 'parent alias');
  await mkdir(first); await mkdir(second); await symlink(first, alias, 'dir');
  const reservation = await reserveOutput(join(alias, 'output'));
  await mkdir(join(second, 'output.preparing'));
  await writeFile(join(second, 'output.preparing/sentinel'), 'keep');
  await unlink(alias); await symlink(second, alias, 'dir');
  await reservation.cleanup();
  assert.equal(await readFile(join(second, 'output.preparing/sentinel'), 'utf8'), 'keep');
  const replaced = await reserveOutput(join(root, 'replacement'));
  await rename(replaced.stage, join(root, 'old owned stage'));
  await mkdir(replaced.stage);
  await writeFile(join(replaced.stage, 'sentinel'), 'keep');
  await assert.rejects(replaced.cleanup(), {code:'WORLD_BUNDLE_OUTPUT_CHANGED'});
  await assert.rejects(replaced.cleanup(), {code:'WORLD_BUNDLE_OUTPUT_CHANGED'});
  assert.equal(await readFile(join(replaced.stage, 'sentinel'), 'utf8'), 'keep');
});

test('nested toolchain selection preserves the inherited library', async t => {
  const { execFileSync: run } = await import('node:child_process');
  const { realpath, symlink } = await import('node:fs/promises');
  const { selectZig: select } = await import('../../src/node/toolchain.mjs');
  const root = await mkdtemp(join(tmpdir(), 'nested zig library '));
  t.after(() => rm(root, { recursive: true, force: true }));
  const a = join(root, 'a'), b = join(root, 'b'), alias = join(root, 'alias');
  await mkdir(a); await mkdir(b); await symlink(a, alias);
  await writeFile(join(a, 'std.zig'), '// selected\n');
  await writeFile(join(b, 'std.zig'), '// alternate\n');
  const zig = join(root, 'zig');
  await writeFile(zig, '#!/bin/sh\ncase "$1" in\nversion) echo 0.17.0;;\nenv) printf ".{\\n    .lib_dir = \\\"%s\\\",\\n}\\n" "$ZIG_LIB_DIR";;\nesac\n');
  await chmod(zig, 0o755);
  const parent = select(['--zig-exe', zig, '--zig-lib', a], { inherited: null });
  const moduleUrl = new URL('../../src/node/toolchain.mjs', import.meta.url).href;
  const child = (args, env = parent.env) => run(process.execPath, ['--input-type=module', '-e',
    'import {selectZig} from ' + JSON.stringify(moduleUrl) + '; const c=selectZig(' + JSON.stringify(args) + '); console.log(c.identity.library);'],
    { env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  assert.equal(child([]), await realpath(a));
  assert.equal(child(['--zig-lib', alias]), await realpath(a));
  assert.throws(() => child(['--zig-lib', b]), error => /Conflicting Zig library/.test(error.stderr));
  assert.throws(() => child([], { ...parent.env, ZIG_LIB_DIR: b }), error => /Conflicting Zig library/.test(error.stderr));
  assert.equal(parent.env.WORLD_ZIG_LIB, await realpath(a));
  parent.assertUnchanged();
});
