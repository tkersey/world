import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtemp, mkdir, writeFile, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { inventory, sha256, verifyInventory } from "../../src/node/runtime-bundle.mjs";

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
test("missing and additional modules reject", async t => {
  const f = await fixture(t);
  await writeFile(join(f.root, "runtime/extra.mjs"), "unexpected");
  await assert.rejects(verifyInventory(f.root, f.hash), { code: "WORLD_BUNDLE_CORRUPT" });
  await rm(join(f.root, "runtime/extra.mjs"));
  await rm(join(f.root, "runtime/world-kernel.wasm"));
  await assert.rejects(verifyInventory(f.root, f.hash), { code: "WORLD_BUNDLE_CORRUPT" });
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

test("unsupported profile and unexecuted qualification cannot pass", async t => {
  const { verifyBundle, requiredChecks } = await import("../../src/node/runtime-bundle.mjs");
  const f = await fixture(t);
  await assert.rejects(verifyBundle(f.root, f.hash), { code: "WORLD_BUNDLE_INCOMPATIBLE" });
  f.manifest.kernel = { abi: 3, path: "runtime/world-kernel.wasm" };
  f.manifest.packageVersion = "6.0.0-dev.0";
  f.manifest.build = { target: "wasm32-freestanding", kernelMode: "ReleaseSmall", zig: "0.16.0", hostMode: "ReleaseSafe", stackBytes: 65536, maximumMemoryBytes: 268435456, defaults: {input:65536,working:1048576,output:65536} };
  f.manifest.source = {repository:"https://github.com/tkersey/world",commit:"a".repeat(40),tree:"b".repeat(40),clean:true,dependency:{commit:"1b00c8c159f0cb490a1223fac8d3d208cef41cb1",package:"boundary-3.0.0-dev.0-flclaCJBFQCNUnFJK019OyLBDLZdg6_eTW1rzBpwImGA",lockSha256:"c".repeat(64)}};
  await writeFile(join(f.root,"runtime/package.json"), JSON.stringify({name:"@tkersey/world",version:"6.0.0-dev.0",type:"module",exports:{".":"./src/embedding/index.mjs"},bin:{world:"./bin/world.mjs"}}));
  f.manifest.requiredChecks = requiredChecks;
  await writeFile(join(f.root, "qualification.json"), JSON.stringify({ checks: requiredChecks.map(name => ({ name, status: "skipped" })) }));
  f.manifest.files = (await inventory(f.root)).filter(file => file.path !== "manifest.json");
  await assert.rejects(verifyBundle(f.root, await f.seal()), { code: "WORLD_BUNDLE_INCOMPLETE" });
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
  await writeFile(join(tools,"zig"),'#!/bin/sh\nif [ "$1" = version ]; then echo 0.16.0; exit 0; fi\nsleep 2\nexit 42\n',{mode:0o755});
  const args = [join(source,"bin/world.mjs"),"runtime","prepare","--source",source,"--output",output];
  const options = {cwd:root,env:{...process.env,PATH:tools+":"+process.env.PATH}};
  const launch = (extra = []) => new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,[...extra,...args],options); let stderr="";
    child.stderr.on("data",b=>stderr+=b); child.on("error",reject);
    child.on("close",code=>resolve({code,stderr}));
  });
  const first=launch();
  for(let i=0;;i++){
    try{await access(output+".preparing");break;}catch{assert.ok(i<100);await new Promise(r=>setTimeout(r,20));}
  }
  const second=await launch();
  assert.notEqual(second.code,0);assert.match(second.stderr,/WORLD_BUNDLE_COLLISION/);
  const failed=await first;assert.notEqual(failed.code,0);assert.match(failed.stderr,/WORLD_BUNDLE_QUALIFICATION_FAILED/);
  await assert.rejects(access(output),{code:"ENOENT"});
  await assert.rejects(access(output+".delivery.json"),{code:"ENOENT"});
  // Deterministically model A publishing just before delayed B acquires the lock.
  const turnover=join(root,"turnover"),preload=join(root,"publish-before-lock.mjs");
  await writeFile(preload,`import fs from "node:fs"; import {syncBuiltinESMExports} from "node:module";
const original=fs.promises.mkdir; const output=${JSON.stringify(turnover)};
fs.promises.mkdir=async(path,...args)=>{
 if(path===output+".preparing"){
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
  await writeFile(join(source,"uncommitted"),"dirty");
  const dirty=await launch();assert.match(dirty.stderr,/WORLD_BUNDLE_SOURCE_DIRTY/);
  await rm(join(source,"uncommitted"));
  const zon=await (await import("node:fs/promises")).readFile(join(source,"build.zig.zon"),"utf8");
  await writeFile(join(source,"build.zig.zon"),zon.replace("1b00c8c159f0cb490a1223fac8d3d208cef41cb1","0".repeat(40)));
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
