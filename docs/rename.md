# World → Kronos

Use the `kronos` Zig module, `-Dhoros-source`, `@tkersey/kronos`,
`bin/kronos.mjs` and newly built `kronos-kernel.wasm`. The JavaScript error
class is `KronosHostError`. Boundary and Agent are now Horos and Protean.
No legacy source aliases or duplicate executables are installed.

ABI 3 export strings `world_*`, `WORLD_*` error codes, the
`world-kernel-inspection/v3` record format, Horos's `boundary.*` hash domains,
and all binary grammars and numeric tags are unchanged. Local Zig entry names
are independent of their fixed WASM export strings. Copyright and adapted-source
attribution retain their original spelling.

The existing `world-runtime-bundle/v1` verifier still binds the original
World 6.0.0 profile, `boundary` profile field, repository/package names and
`runtime/world-kernel.wasm` / `runtime/bin/world.mjs` members. Its fixtures
exercise that historical contract. Published assets and tags are untouched;
this does not certify renamed source as an old release. The current optional
JS package is built and checked with its matching new kernel.

Zig's name-derived fingerprint checksum is now `5a86bb04`; the lineage ID
`074dc2bd` and version 6.0.0 are unchanged. Package hashes are computed by Zig.
New scratch and output locations use Kronos names. No old user state is discovered,
moved or deleted. Existing saved tasks retain their original build bindings;
use the original pinned build where restoration is incompatible.
