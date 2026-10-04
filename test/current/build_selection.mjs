import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { selectZig } from '../../src/node/toolchain.mjs';

const [executable, library, boundary] = process.argv.slice(2);
const compiler = selectZig(['--zig-exe', executable, '--zig-lib', library]);
const root = resolve(import.meta.dirname, '../..');
const cache = await mkdtemp(join(tmpdir(), 'world build selection Ω '));
try {
  for (const name of ['execution', 'replay', 'value', 'execution']) {
    const configuration = execFileSync(compiler.executable, ['build', '--build-file',
      join(root, `test/v2/build_${name}_bench.zig`), `-Dboundary-source=${boundary}`,
      `-Dworld-source=${root}`, '--cache-dir', cache, '--print-configuration'], {
      cwd: root, env: compiler.env, encoding: 'utf8', maxBuffer: 4 << 20, timeout: 120000,
    });
    const names = [...configuration.matchAll(/\.root_name = "([^"]+)"/g)].map(match => match[1]);
    assert.deepEqual(names, [`${name}-bench`], 'selected build file must own the configuration');
  }
  compiler.assertUnchanged();
  console.log('Standalone build-file selection preserved across a shared configuration cache');
} finally { await rm(cache, {recursive: true, force: true}); }
