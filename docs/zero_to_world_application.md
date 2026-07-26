# Zero to a World Application

This guide starts in an empty directory and ends with a completed,
source-independent hosted run. It uses reviewed release-candidate artifacts;
the stable `v1.0.0` release process replaces only the pinned tags, package
hashes, and archive checksums after this gate passes.

Required tools:

- Zig `0.16.0` to author and build the application;
- Node.js to copy the official template and run the World build checks;
- Bun to run the released host and capability conformance.

Zig, Boundary source, and World source are not runtime dependencies.

## 1. Materialize the reviewed releases

Begin in an empty directory:

```sh
mkdir world-external-consumer
cd world-external-consumer

curl -L \
  https://github.com/tkersey/boundary/archive/refs/tags/v0.7.0.tar.gz \
  -o boundary-v0.7.0.tar.gz
curl -L \
  https://github.com/tkersey/world/archive/refs/tags/v1.0.0-rc.2.tar.gz \
  -o world-v1.0.0-rc.2.tar.gz
curl -L \
  https://github.com/tkersey/world-host/releases/download/v1.0.0-rc.2/world-host-v1.0.0-rc.2.tar.gz \
  -o world-host-v1.0.0-rc.2.tar.gz
curl -L \
  https://github.com/tkersey/world-capabilities/releases/download/v1.0.0-rc.4/world-capabilities-v1-runtime-v1.0.0-rc.4.tar.gz \
  -o world-capabilities-v1-runtime-v1.0.0-rc.4.tar.gz
```

Verify the downloaded bytes before extracting or executing them:

```text
25e5bd5ed45aac023ef99beee93f675ea4efb3f6eb1e98d2a13040d7451f0e9a  boundary-v0.7.0.tar.gz
56eb9471b83e97d60c6fb0da5725fdeac77cf5b82151e8f5137a356e94ec32b4  world-v1.0.0-rc.2.tar.gz
6ca3580cdd1e594aae650ebafc9add660d3c131816900f144bc4ee3b93d27def  world-host-v1.0.0-rc.2.tar.gz
b6b87dc78e90d5ba626f20489016bab4c0f3ff39ae1e9ce77c2ab76ed1150cfc  world-capabilities-v1-runtime-v1.0.0-rc.4.tar.gz
```

The corresponding Zig package identities are:

```text
boundary-0.7.0-flclaCnjkABOSWaiSkxMBDQZsBEeA-Niai-l1u0q3A7_
world-1.0.0-rc.2-XXTUeOXYhwC1anDePj7Lr4SfwDCxG-ofPw92_-PGGyKv
```

## 2. Create the application

Extract the World package archive. This is release materialization, not a
source checkout:

```sh
mkdir world-release
tar -xzf world-v1.0.0-rc.2.tar.gz -C world-release --strip-components=1

node world-release/scripts/init_world_application.mjs \
  --output research-digest-agent \
  --world-url https://github.com/tkersey/world/archive/refs/tags/v1.0.0-rc.2.tar.gz \
  --world-hash world-1.0.0-rc.2-XXTUeOXYhwC1anDePj7Lr4SfwDCxG-ofPw92_-PGGyKv
```

The generated project uses only public APIs:

```text
research-digest-agent/
  build.zig
  build.zig.zon
  src/
    effects.zig
    agent.zig
    provider.zig
    application.zig
```

`effects.zig` declares `research.lookup.v1` and its typed request and response
schemas. `agent.zig` constructs the semantic Boundary plan.
`provider.zig` implements the statically compiled formatter provider, which
parks on the residual research effect. `application.zig` closes that graph
with `world.application`.

## 3. Build the import-free application

Build with isolated caches:

```sh
cd research-digest-agent
mkdir .zig-global-cache

zig fetch \
  --global-cache-dir .zig-global-cache \
  ../boundary-v0.7.0.tar.gz
zig fetch \
  --global-cache-dir .zig-global-cache \
  ../world-v1.0.0-rc.2.tar.gz

zig build \
  --cache-dir .zig-cache \
  --global-cache-dir .zig-global-cache \
  --summary all
cd ..
```

The supported World build helper installs:

```text
research-digest-agent/zig-out/world-apps/research-digest-agent.world.wasm
research-digest-agent/zig-out/world-apps/research-digest-agent.manifest.bin
research-digest-agent/zig-out/world-apps/research-digest-agent.manifest.txt
```

The build fails if the module imports anything, omits required Application ABI
v1 exports, declares incompatible application semantics, exceeds its memory
bounds, or disagrees with its canonical manifest.

## 4. Inspect and run the released host

Extract the runtime distributions into a directory that contains no source
checkout:

```sh
mkdir runtime
tar -xzf world-host-v1.0.0-rc.2.tar.gz -C runtime
tar -xzf world-capabilities-v1-runtime-v1.0.0-rc.4.tar.gz -C runtime

HOST=runtime/world-host-v1.0.0-rc.2
CAP=runtime/world-capabilities-v1-runtime-v1.0.0-rc.4
APP=research-digest-agent/zig-out/world-apps/research-digest-agent.world.wasm

(cd "$CAP" && bun run proof)
bun "$HOST/host/bin/world-host-v1.mjs" inspect-app "$APP"
bun "$HOST/conformance/check-pack.mjs"
bun "$HOST/conformance/run.mjs"
```

The capability proof validates the independently released
`research.lookup.v1` pack. The host pack checker validates its embedded
capability projection against the pinned release identities. The final command
performs the complete Research Digest lifecycle: fresh run, fresh-instance
resume, retained-result retry, replay with zero fresh effects, two-child
branching, export/import with receiver preflight, and all required negative
cases. Its JSON receipt reports:

```text
sourceCheckoutRequired: false
sourceIndependentHost: true
researchCustomEffect: true
researchInternalProvider: true
researchExternalCapability: true
researchFreshInstanceResume: true
researchDeterministicRetry: true
researchCapabilityInvocations: 1
researchReplayFreshEffects: 0
researchBranchingChildren: 2
researchMigrationReceiverPreflight: true
```

For direct operator flows, the released CLI accepts canonical application
bytes:

```sh
bun "$HOST/host/bin/world-host-v1.mjs" install \
  --store STORE \
  --name research-digest-agent \
  --wasm "$APP"
bun "$HOST/host/bin/world-host-v1.mjs" run \
  --store STORE \
  --app research-digest-agent \
  --run run-1 \
  --initial-args input.bin
bun "$HOST/host/bin/world-host-v1.mjs" resume \
  --store STORE \
  --run run-1 \
  --effect-result lookup-result.bin
bun "$HOST/host/bin/world-host-v1.mjs" inspect \
  --store STORE \
  --run run-1
```

Applications and capability packs own their typed codecs. The generic host
does not translate application-specific text, author Frames, or inspect
payload bytes.

## 5. Revalidate offline

After the four archives have been downloaded once, the aggregate gate needs no
network and no sibling checkout:

```sh
cd world-release
zig build check-world-1.0-externality -- \
  --world-archive ../world-v1.0.0-rc.2.tar.gz \
  --world-url https://github.com/tkersey/world/archive/refs/tags/v1.0.0-rc.2.tar.gz \
  --boundary-archive ../boundary-v0.7.0.tar.gz \
  --world-host-archive ../world-host-v1.0.0-rc.2.tar.gz \
  --world-capabilities-runtime-archive ../world-capabilities-v1-runtime-v1.0.0-rc.4.tar.gz
```

The gate rebuilds the application in a fresh directory with isolated Zig
caches, copies only application and release artifacts into a second runtime
directory, compares the host's executable capability projection byte-for-byte
with the capability runtime release, checks every cross-release identity,
removes Zig from the runtime `PATH`, and emits the World 1.0 externality
completion receipt.
