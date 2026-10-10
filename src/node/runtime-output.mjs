import { mkdir, lstat, rm, rmdir, realpath, open } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, basename, join, resolve } from "node:path";
import { reject } from "./runtime-bundle.mjs";

// Archive acquisition owns its output through this reservation.
export async function reserveOutput(output) {
  output = resolve(output);
  const requestedParent = dirname(output);
  await mkdir(requestedParent, { recursive: true });
  const parent = await realpath(requestedParent);
  output = join(parent, basename(output));
  const stage = `${output}.preparing`;
  try { await mkdir(stage); } catch (error) {
    if (error.code === "EEXIST")
      reject("WORLD_BUNDLE_COLLISION", `creation already active/interrupted: ${stage}`);
    throw error;
  }
  let handle, owner;
  try {
    handle = await open(stage, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
    owner = await handle.stat({ bigint: true });
  } catch (error) {
    await handle?.close().catch(() => {});
    // Initialization has written no contents. Never recursively delete a path
    // whose directory identity could not be established; retain the first error.
    await rmdir(stage).catch(() => {});
    throw error;
  }
  let closed = false, cleaning;
  const check = async () => {
    const named = await lstat(stage, { bigint: true });
    if (!named.isDirectory() || named.dev !== owner.dev || named.ino !== owner.ino)
      reject("WORLD_BUNDLE_OUTPUT_CHANGED", "output reservation no longer names this run's directory");
  };
  const close = async () => { if (!closed) { closed = true; await handle.close(); } };
  const reservation = Object.freeze({
    output, stage,
    async assertOwned() {
      if (closed || cleaning) reject("WORLD_BUNDLE_OUTPUT_CHANGED", "output reservation is closed");
      await check();
    },
    close() { return cleaning ? cleaning.then(() => {}, () => {}) : close(); },
    cleanup() {
      if (cleaning) return cleaning;
      if (closed) reject("WORLD_BUNDLE_OUTPUT_CHANGED", "output reservation is closed");
      cleaning = (async () => {
        try { await check(); await rm(stage, { recursive: true }); }
        finally { await close(); }
      })();
      return cleaning;
    },
  });
  try {
    try { await lstat(output); } catch (error) {
      if (error.code === "ENOENT") return reservation;
      throw error;
    }
    reject("WORLD_BUNDLE_COLLISION", `destination exists; choose a new output or verify it: ${output}`);
  } catch (error) {
    await reservation.cleanup();
    throw error;
  }
}
