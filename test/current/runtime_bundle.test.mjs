import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtemp, mkdir, writeFile, rm, symlink, chmod, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { inventory, packageInventory, sha256, verifyInventory, readVerifiedFile,
  withVerifiedInventory } from "../../src/node/runtime-bundle.mjs";
import runtimeProfile from "../../src/node/runtime-profile.json" with { type: "json" };

async function failingCompiler(tools, delay = 0) {
  const library = join(tools, "lib");
  await mkdir(library);
  await writeFile(join(library, "std.zig"), "fixture library");
  const executable = join(tools, "zig");
  await writeFile(executable, `#!/usr/bin/env node
const fs=require("node:fs");
if(process.argv[2]==="version"){console.log("0.17.0");process.exit(0)}
if(process.argv[2]==="env"){console.log('.{\\n .lib_dir = '+JSON.stringify(${JSON.stringify(library)})+',\\n}');process.exit(0)}
if(process.env.WORLD_TEST_CAPTURE)fs.writeFileSync(process.env.WORLD_TEST_CAPTURE,fs.readFileSync("archive-marker"));
setTimeout(()=>process.exit(42),${delay});
`, {mode:0o755});
  return executable;
}

const required = ["runtime/world-kernel.wasm", "runtime/package.json", "runtime/bin/world.mjs",
  "runtime/src/node/runtime-bundle.mjs", "runtime/src/embedding/index.mjs", "qualification.json",
  "runtime/LICENSE", "smoke/pure.bpi3", "smoke/effect.bpi3"];
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "world bundle "));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const file of required) {
    await mkdir(join(root, file, ".."), { recursive: true });
    await writeFile(join(root, file), "fixture");
  }
  const manifest = { format: "world-runtime-bundle/v1", files: await inventory(root) };
  const seal = async () => {
    const bytes = JSON.stringify(manifest);
    await writeFile(join(root, "manifest.json"), bytes);
    return sha256(bytes);
  };
  return { root, manifest, seal, hash: await seal() };
}
test("external identity and complete file inventory survive spaces", async t => {
  const f = await fixture(t);
  await verifyInventory(f.root, f.hash);
  await assert.rejects(verifyInventory(f.root, "0".repeat(64)), { code: "WORLD_BUNDLE_IDENTITY_INVALID" });
  await writeFile(join(f.root, "runtime/src/node/runtime-bundle.mjs"), "substituted");
  await assert.rejects(verifyInventory(f.root, f.hash), { code: "WORLD_BUNDLE_CORRUPT" });
});

test("executable mode is bound before admission and preserved in the private snapshot", async t => {
  const f = await fixture(t), path = join(f.root, "runtime/bin/world.mjs");
  const original = (await stat(path)).mode & 0o777;
  await chmod(path, original ^ 0o100);
  await assert.rejects(verifyInventory(f.root, f.hash), {code:"WORLD_BUNDLE_CORRUPT"});
  await chmod(path, original);
  await verifyInventory(f.root, f.hash);
  await withVerifiedInventory(f.root, f.hash, async copy => {
    await chmod(path, original ^ 0o100);
    assert.equal(((await stat(join(copy, "runtime/bin/world.mjs"))).mode & 0o111) !== 0, (original & 0o111) !== 0);
  });
});
test("missing and additional modules reject", async t => {
  const f = await fixture(t);
  await writeFile(join(f.root, "runtime/extra.mjs"), "unexpected");
  await assert.rejects(verifyInventory(f.root, f.hash), { code: "WORLD_BUNDLE_CORRUPT" });
  await rm(join(f.root, "runtime/extra.mjs"));
  await rm(join(f.root, "runtime/world-kernel.wasm"));
  await assert.rejects(verifyInventory(f.root, f.hash), { code: "WORLD_BUNDLE_CORRUPT" });
});

test("metadata reads bind the parsed generation to its inventory record", async t => {
  const f = await fixture(t);
  for (const path of ["qualification.json", "runtime/package.json"]) {
    await writeFile(join(f.root, path), '{"status":"skipped"}');
    f.manifest.files = (await inventory(f.root)).filter(file => file.path !== "manifest.json");
    const manifest = await verifyInventory(f.root, await f.seal());
    assert.equal(JSON.parse(await readVerifiedFile(f.root, manifest, path)).status, "skipped");
    // Same-length replacement after the inventory scan must not become evidence.
    await writeFile(join(f.root, path), '{"status":"passed!"}');
    await assert.rejects(readVerifiedFile(f.root, manifest, path), {code: "WORLD_BUNDLE_CORRUPT"});
  }
});

test("verified copy executes captured code and retains metadata after source replacement", async t => {
  const { execFileSync } = await import("node:child_process");
  const { readFile, chmod, access } = await import("node:fs/promises");
  const f = await fixture(t);
  const cli = join(f.root, "runtime/bin/world.mjs");
  await writeFile(cli, '#!/usr/bin/env node\nconsole.log("original generation");\n');
  await chmod(cli, 0o755);
  await writeFile(join(f.root, "runtime/package.json"), '{"type":"module"}');
  await writeFile(join(f.root, "qualification.json"), '{"status":"original"}');
  f.manifest.files = (await inventory(f.root)).filter(file => file.path !== "manifest.json");
  let copiedRoot;
  await withVerifiedInventory(f.root, await f.seal(), async copy => {
    copiedRoot = copy;
    assert.notEqual(copy, f.root);
    await writeFile(cli, '#!/usr/bin/env node\nconsole.log("replacement generation");\n');
    await writeFile(join(f.root, "qualification.json"), '{"status":"replacement"}');
    const copiedCli = join(copy, "runtime/bin/world.mjs");
    assert.equal(execFileSync(process.execPath, [copiedCli], {encoding: "utf8"}).trim(),
      "original generation");
    if (process.platform !== "win32")
      assert.equal(execFileSync(copiedCli, [], {encoding: "utf8"}).trim(), "original generation");
    assert.equal(JSON.parse(await readFile(join(copy, "qualification.json"))).status, "original");
  });
  await assert.rejects(access(copiedRoot), {code: "ENOENT"});
});
test("traversal, duplicate entries, and links reject", async t => {
  const f = await fixture(t);
  f.manifest.files.push(f.manifest.files[0]);
  await assert.rejects(verifyInventory(f.root, await f.seal()), { code: "WORLD_BUNDLE_INVALID" });
  f.manifest.files.pop();
  f.manifest.files[0].path = "../escape";
  await assert.rejects(verifyInventory(f.root, await f.seal()), { code: "WORLD_BUNDLE_INVALID" });
  await symlink(tmpdir(), join(f.root, "link"));
  await assert.rejects(inventory(f.root), { code: "WORLD_BUNDLE_INVALID" });
});

test("safe acquisition binds archive before extraction and refuses destination collision", async t => {
  const { execFileSync } = await import("node:child_process");
  const { readFile } = await import("node:fs/promises");
  const { acquireBundle, unpackArchive } = await import("../../src/node/runtime-acquire.mjs");
  const f = await fixture(t);
  const scratch = await mkdtemp(join(tmpdir(), "world acquisition "));
  t.after(() => rm(scratch, { recursive: true, force: true }));
  const archive = join(scratch, "bundle.tar.gz"), output = join(scratch, "relocated bundle");
  const {chmod,stat} = await import("node:fs/promises");
  await writeFile(join(f.root,"runtime/bin/world.mjs"),'#!/usr/bin/env node\nconsole.log("acquired CLI");\n');
  await writeFile(join(f.root,"runtime/package.json"),'{"type":"module"}');
  await chmod(join(f.root,"runtime/bin/world.mjs"),0o755);
  f.manifest.files=(await inventory(f.root)).filter(file=>file.path!=="manifest.json");
  f.hash=await f.seal();
  execFileSync("tar", ["--format=ustar", "-czf", archive, "-C", f.root, "."]);
  const bytes = await readFile(archive), digest = sha256(bytes);
  await assert.rejects(acquireBundle(archive, "0".repeat(64), f.hash, output), { code: "WORLD_BUNDLE_IDENTITY_INVALID" });
  await acquireBundle(archive, digest, f.hash, output);
  await verifyInventory(output, f.hash);
  if(process.platform!=="win32"){
    assert.ok((await stat(join(output,"runtime/bin/world.mjs"))).mode & 0o100);
    assert.equal(execFileSync(join(output,"runtime/bin/world.mjs"),[],{encoding:"utf8"}).trim(),"acquired CLI");
  }
  await assert.rejects(acquireBundle(archive, digest, f.hash, output), { code: "WORLD_BUNDLE_COLLISION" });
  await symlink("/tmp", join(f.root, "escape"));
  execFileSync("tar", ["--format=ustar", "-czf", archive, "-C", f.root, "."]);
  const badArchive = await readFile(archive);
  assert.throws(() => unpackArchive(badArchive), { code: "WORLD_BUNDLE_ARCHIVE_INVALID" });
});

test("bundle mode normalization preserves package identity and safe archive round trips", async t => {
  const { execFileSync } = await import("node:child_process");
  const { readFile } = await import("node:fs/promises");
  const { acquireBundle, unpackArchive } = await import("../../src/node/runtime-acquire.mjs");
  const f = await fixture(t), file = "runtime/bin/world.mjs";
  const scratch = await mkdtemp(join(tmpdir(), "world archive modes "));
  t.after(() => rm(scratch, { recursive: true, force: true }));
  for (const [mode, delivered] of [[0o600, 0o644], [0o640, 0o644], [0o664, 0o644],
    [0o601, 0o755], [0o610, 0o755], [0o700, 0o755], [0o750, 0o755],
    [0o777, 0o755], [0o4755, 0o755]]) {
    await chmod(join(f.root, file), mode);
    const contents = await packageInventory(f.root);
    assert.equal(contents.files.find(entry => entry.path === file).mode, mode & 0o777,
      "source-package identity retains actual permissions");
    f.manifest.files = (await inventory(f.root)).filter(entry => entry.path !== "manifest.json");
    assert.equal(f.manifest.files.find(entry => entry.path === file).mode, delivered);
    const hash = await f.seal();
    await verifyInventory(f.root, hash);
    const archive = join(scratch, `${mode}.tar.gz`), output = join(scratch, `${mode}`);
    execFileSync("tar", ["--format=ustar", "-czf", archive, "-C", f.root, "."]);
    const bytes = await readFile(archive);
    assert.equal(unpackArchive(bytes).find(entry => entry.path === file).mode, delivered);
    await acquireBundle(archive, sha256(bytes), hash, output);
    assert.equal((await stat(join(output, file))).mode & 0o7777, delivered,
      "extraction cannot restore set-id or group/other write permissions");
    await withVerifiedInventory(output, hash, async copy => {
      assert.equal((await stat(join(copy, file))).mode & 0o777,
        delivered === 0o755 ? 0o500 : 0o400);
      await verifyInventory(copy, hash);
    });
    await chmod(join(output, file), delivered === 0o755 ? 0o644 : 0o755);
    await assert.rejects(verifyInventory(output, hash), { code: "WORLD_BUNDLE_CORRUPT" });
  }
});

test("archive acquisition survives restrictive and shared-group producer umasks", async () => {
  const { spawnSync } = await import("node:child_process");
  const env = { ...process.env };
  delete env.NODE_TEST_CONTEXT;
  for (const mask of ["002", "027", "077"]) {
    const run = spawnSync("/bin/sh", ["-c", 'umask "$1"; shift; exec "$@"', "world-umask-test", mask,
      process.execPath, "--test", "--test-reporter=tap",
      "--test-name-pattern=^safe acquisition binds archive before extraction and refuses destination collision$",
      import.meta.filename], { env, encoding: "utf8", timeout: 20_000 });
    assert.equal(run.status, 0, `umask ${mask}: ${run.error ?? ""}\n${run.stdout}\n${run.stderr}`);
    assert.match(run.stdout, /^# tests 1$/m);
    assert.match(run.stdout, /^# pass 1$/m);
  }
});

test("manifest modes must describe the canonical delivery representation", async t => {
  const f = await fixture(t);
  for (const mode of [0o600, 0o775]) {
    f.manifest.files[0].mode = mode;
    await assert.rejects(verifyInventory(f.root, await f.seal()), { code: "WORLD_BUNDLE_INVALID" });
  }
});

test("unsupported profile and unexecuted qualification cannot pass", async t => {
  const { verifyBundle, requiredChecks } = await import("../../src/node/runtime-bundle.mjs");
  const f = await fixture(t);
  await assert.rejects(verifyBundle(f.root, f.hash), { code: "WORLD_BUNDLE_INCOMPATIBLE" });
  f.manifest.kernel = { abi: 3, path: "runtime/world-kernel.wasm" };
  f.manifest.packageVersion = "6.0.0-dev.0";
  f.manifest.build = { target: runtimeProfile.target, kernelMode: runtimeProfile.kernelMode, zig: runtimeProfile.zig,
    hostMode: runtimeProfile.hostMode, stackBytes: runtimeProfile.stackBytes, maximumMemoryBytes: runtimeProfile.maximumMemoryBytes,
    defaults: {...runtimeProfile.defaults}, backend: runtimeProfile.wasmBackend, linker: runtimeProfile.wasmLinker,
    cpu: runtimeProfile.cpu, features: [...runtimeProfile.features], toolchain: {version:runtimeProfile.zig,executableIdentity:{sha256:"d".repeat(64)},libraryInventorySha256:"e".repeat(64)} };
  f.manifest.source = {repository:"https://github.com/tkersey/world",commit:"a".repeat(40),tree:"b".repeat(40),clean:true,
    dependency:{...runtimeProfile.boundary,lockSha256:"c".repeat(64)}};
  await writeFile(join(f.root,"runtime/package.json"), JSON.stringify({name:"@tkersey/world",version:"6.0.0-dev.0",type:"module",exports:{".":"./src/embedding/index.mjs"},bin:{world:"./bin/world.mjs"}}));
  f.manifest.requiredChecks = requiredChecks;
  await writeFile(join(f.root, "qualification.json"), JSON.stringify({ checks: requiredChecks.map(name => ({ name, status: "skipped" })) }));
  f.manifest.files = (await inventory(f.root)).filter(file => file.path !== "manifest.json");
  await assert.rejects(verifyBundle(f.root, await f.seal()), { code: "WORLD_BUNDLE_INCOMPLETE" });
  const valid = structuredClone(f.manifest);
  for (const mutate of [
    m => {m.build.zig="0.17.0-dev.1";}, m => {m.build.hostMode="unknown";}, m => {m.build.kernelMode="fast";},
    m => {m.build.target="wasm64-freestanding";}, m => {m.build.stackBytes++;}, m => {m.build.maximumMemoryBytes++;},
    m => {m.build.defaults.working++;}, m => {m.build.backend="unknown";}, m => {m.build.linker="unknown";},
    m => {m.build.cpu="unknown";}, m => {m.source.dependency.commit="0".repeat(40);},
    m => {m.build.features.push("unknown");},
    m => {m.source.dependency.inventorySha256="0".repeat(64);}, m => {m.build.toolchain.libraryInventorySha256="unknown";},
  ]) {
    Object.assign(f.manifest, structuredClone(valid));
    mutate(f.manifest);
    await assert.rejects(verifyBundle(f.root, await f.seal()), {code:"WORLD_BUNDLE_INCOMPATIBLE"});
  }
});

test("failed preparation never publishes and concurrent preparation cannot mix outputs", async t => {
  const { cp, access } = await import("node:fs/promises");
  const { execFileSync, spawn } = await import("node:child_process");
  const { dirname, resolve } = await import("node:path");
  const root = await mkdtemp(join(tmpdir(), "world producer "));
  t.after(() => rm(root, {recursive:true,force:true}));
  const source = join(root,"source"), tools = join(root,"tools"), output = join(root,"bundle");
  await mkdir(source); await mkdir(tools);
  const repo = resolve(import.meta.dirname,"../..");
  for(const path of ["bin","src/node","src/embedding","package.json","build.zig.zon"]){
    await mkdir(dirname(join(source,path)),{recursive:true});
    await cp(join(repo,path),join(source,path),{recursive:true});
  }
  const git = args => execFileSync("git",args,{cwd:source,stdio:"ignore"});
  git(["init"]); git(["add","."]);
  git(["-c","user.name=Fixture","-c","user.email=fixture@example.invalid","-c","commit.gpgsign=false","commit","-m","fixture"]);
  const compiler = await failingCompiler(tools, 2000);
  const args = [join(source,"bin/world.mjs"),"runtime","prepare","--source",source,"--output",output];
  const options = {cwd:root,env:{...process.env,PATH:tools+":"+process.env.PATH,WORLD_ZIG_EXE:compiler}};
  const launch = (extra = []) => new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,[...extra,...args],options); let stderr="";
    child.stderr.on("data",b=>stderr+=b); child.on("error",reject);
    child.on("close",code=>resolve({code,stderr}));
  });
  const acquisition=await fixture(t),transport=join(root,"acquire.tar.gz");
  execFileSync("tar",["--format=ustar","-czf",transport,"-C",acquisition.root,"."]);
  const transportBytes=await (await import("node:fs/promises")).readFile(transport);
  const {acquireBundle}=await import("../../src/node/runtime-acquire.mjs");
  const first=launch();
  for(let i=0;;i++){
    try{await access(output+".preparing");break;}catch{assert.ok(i<100);await new Promise(r=>setTimeout(r,20));}
  }
  const second=await launch();
  assert.notEqual(second.code,0);assert.match(second.stderr,/WORLD_BUNDLE_COLLISION/);
  let acquisitionError;
  try{await acquireBundle(transport,sha256(transportBytes),acquisition.hash,output);}catch(error){acquisitionError=error;}
  const failed=await first;assert.notEqual(failed.code,0);assert.match(failed.stderr,/WORLD_BUNDLE_QUALIFICATION_FAILED/);
  assert.equal(acquisitionError?.code,"WORLD_BUNDLE_COLLISION","acquisition must share the producer reservation");
  await assert.rejects(access(output),{code:"ENOENT"});
  await assert.rejects(access(output+".delivery.json"),{code:"ENOENT"});
  // Deterministically model A publishing just before delayed B acquires the lock.
  const turnover=join(root,"turnover"),preload=join(root,"publish-before-lock.mjs");
  await writeFile(preload,`import fs from "node:fs"; import {syncBuiltinESMExports} from "node:module";
const original=fs.promises.mkdir; const output=${JSON.stringify(turnover)};
const path=await import("node:path"); const stage=path.join(fs.realpathSync(path.dirname(output)),path.basename(output)+".preparing");
fs.promises.mkdir=async(path,...args)=>{
 if(path===stage){
  await original(output); await fs.promises.writeFile(output+"/previous","bundle A");
  await fs.promises.writeFile(output+".tar.gz","archive A");
  await fs.promises.writeFile(output+".delivery.json","descriptor A");
 }
 return original(path,...args);
}; syncBuiltinESMExports();`);
  args[args.length-1]=turnover;
  const stale=await launch(["--import",preload]);
  assert.match(stale.stderr,/WORLD_BUNDLE_COLLISION/);
  const read=await import("node:fs/promises");
  assert.equal(await read.readFile(turnover+".tar.gz","utf8"),"archive A");
  assert.equal(await read.readFile(turnover+".delivery.json","utf8"),"descriptor A");
  assert.equal(await read.readFile(turnover+"/previous","utf8"),"bundle A");
  const realGit=execFileSync("which",["git"],{encoding:"utf8"}).trim();
  const marker=join(root,"selection-switched");
  await writeFile(join(tools,"git"),`#!/usr/bin/env node
import fs from "node:fs";import {spawnSync} from "node:child_process";
const git=${JSON.stringify(realGit)},args=process.argv.slice(2),marker=${JSON.stringify(marker)};
const result=spawnSync(git,args);
if(args.join(" ")==="rev-parse HEAD"&&!fs.existsSync(marker)){
 fs.writeFileSync(marker,"");fs.writeFileSync("selection-change","new commit");
 for(const command of [["add","selection-change"],["-c","user.name=Fixture","-c","user.email=fixture@example.invalid","-c","commit.gpgsign=false","commit","-m","selection changed"]]){
  const changed=spawnSync(git,command);if(changed.status!==0)throw Error("fixture commit failed");
 }
}
process.stdout.write(result.stdout??"");process.stderr.write(result.stderr??"");process.exit(result.status??1);
`,{mode:0o755});
  args[args.length-1]=join(root,"selection-output");
  const selected=await launch();assert.match(selected.stderr,/WORLD_BUNDLE_SOURCE_CHANGED/);
  await rm(join(tools,"git"));
  await writeFile(join(source,"uncommitted"),"dirty");
  const dirty=await launch();assert.match(dirty.stderr,/WORLD_BUNDLE_SOURCE_DIRTY/);
  await rm(join(source,"uncommitted"));
  const zon=await (await import("node:fs/promises")).readFile(join(source,"build.zig.zon"),"utf8");
  await writeFile(join(source,"build.zig.zon"),zon.replace(runtimeProfile.boundary.commit,"0".repeat(40)));
  git(["add","build.zig.zon"]);
  git(["-c","user.name=Fixture","-c","user.email=fixture@example.invalid","-c","commit.gpgsign=false","commit","-m","wrong dependency"]);
  const wrong=await launch();assert.match(wrong.stderr,/WORLD_BUNDLE_DEPENDENCY_INVALID/);
});

test("worker entry detection survives ancestor aliases and importing stays inert", async t => {
  const { spawnSync } = await import("node:child_process");
  const { resolve } = await import("node:path");
  const { pathToFileURL } = await import("node:url");
  const root = await mkdtemp(join(tmpdir(), "world worker alias "));
  t.after(() => rm(root, {recursive:true,force:true}));
  const repo = resolve(import.meta.dirname,"../..");
  await symlink(repo,join(root,"source alias"),"dir");
  for(const source of [repo,join(root,"source alias")]){
    const worker=join(source,"src/node/runtime-smoke.mjs");
    const result=spawnSync(process.execPath,[worker,join(root,"missing bundle"),"0".repeat(64),"start"],{encoding:"utf8",timeout:30000});
    assert.notEqual(result.status,0,"a direct worker must execute and reject the missing kernel, never silently skip");
    assert.match(result.stderr,/ENOENT/);
    const imported=spawnSync(process.execPath,["--input-type=module","-e",`await import(${JSON.stringify(pathToFileURL(worker).href)})`],{encoding:"utf8",timeout:30000});
    assert.equal(imported.status,0,imported.stderr);assert.equal(imported.stdout,"");
  }
});

test("preparation binds raw commit contents despite Git replacement refs", async t => {
  const { cp, readFile, access } = await import("node:fs/promises");
  const { execFileSync, spawnSync } = await import("node:child_process");
  const { dirname, resolve } = await import("node:path");
  const root = await mkdtemp(join(tmpdir(), "world raw commit "));
  t.after(() => rm(root, {recursive: true, force: true}));
  const source = join(root, "source"), tools = join(root, "tools");
  await mkdir(source); await mkdir(tools);
  const repo = resolve(import.meta.dirname, "../..");
  for (const path of ["bin", "src/node", "src/embedding", "package.json", "build.zig.zon"]) {
    await mkdir(dirname(join(source, path)), {recursive: true});
    await cp(join(repo, path), join(source, path), {recursive: true});
  }
  const git = args => execFileSync("git", args, {cwd: source, encoding: "utf8"}).trim();
  const commit = () => git(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
    "-c", "commit.gpgsign=false", "commit", "-m", "fixture"]);
  git(["init", "-q"]);
  await writeFile(join(source, "archive-marker"), "original");
  git(["add", "."]); commit();
  const original = git(["rev-parse", "HEAD"]);
  await writeFile(join(source, "archive-marker"), "replacement");
  git(["add", "."]); commit();
  const replacement = git(["rev-parse", "HEAD"]);
  git(["reset", "--hard", original]);
  git(["replace", original, replacement]);
  const captured = join(root, "captured");
  const compiler = await failingCompiler(tools);
  const run = () => spawnSync(process.execPath, [join(source, "bin/world.mjs"), "runtime", "prepare",
    "--source", source, "--output", join(root, "bundle")], {
    encoding: "utf8", env: {...process.env, PATH: tools + ":" + process.env.PATH,
      WORLD_TEST_CAPTURE: captured, WORLD_ZIG_EXE: compiler},
  });
  await writeFile(join(source, "archive-marker"), "replacement");
  git(["add", "archive-marker"]);
  assert.equal(git(["status", "--porcelain"]), "", "fixture must be clean only in the replaced view");
  const substituted = run();
  assert.notEqual(substituted.status, 0);
  assert.match(substituted.stderr, /WORLD_BUNDLE_SOURCE_DIRTY/);
  await assert.rejects(access(captured), {code: "ENOENT"});
  git(["--no-replace-objects", "reset", "--hard", original]);
  const selected = run();
  assert.match(selected.stderr, /WORLD_BUNDLE_QUALIFICATION_FAILED/);
  assert.equal(await readFile(captured, "utf8"), "original");
});
