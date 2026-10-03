import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

const [executable] = process.argv.slice(2);
assert(executable && process.argv.length === 3);
for (const mode of ['valid', 'oom', 'retire', 'owner_move', 'grow', 'shift']) {
  const result = spawnSync(executable, [mode], { encoding:'utf8', timeout:30000, maxBuffer:1<<20 });
  assert.ifError(result.error);
  if (mode === 'grow' || mode === 'shift') {
    assert.notEqual(result.status, 0, mode);
    assert.match(result.stderr, new RegExp(`Z17 injected ${mode} before invalidation`));
    assert.match(result.stderr, /SafetyLock|assertUnlocked/);
    assert.doesNotMatch(result.stderr, /Z17 invalidation escaped/);
  } else {
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, new RegExp(`Z17 valid ${mode}; leaks=0`));
  }
}
console.log(JSON.stringify({check:'actual activation-view pointer diagnostics',faults:['grow','shift'],
  valid:['ordinary growth','allocation failure retry','retired generation','owner move'],validCaseLeaks:0}));
