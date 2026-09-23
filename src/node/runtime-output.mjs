import { mkdir, lstat, rm } from "node:fs/promises";
import { dirname } from "node:path";
import { reject } from "./runtime-bundle.mjs";

// Both public creators own the destination through this one reservation.
export async function reserveOutput(output, additionalDestinations = []) {
  await mkdir(dirname(output), { recursive: true });
  const stage = `${output}.preparing`;
  try { await mkdir(stage); } catch (error) {
    if (error.code === "EEXIST")
      reject("WORLD_BUNDLE_COLLISION", `creation already active/interrupted: ${stage}`);
    throw error;
  }
  try {
    for (const path of [output, ...additionalDestinations]) {
      try { await lstat(path); } catch (error) {
        if (error.code === "ENOENT") continue;
        throw error;
      }
      reject("WORLD_BUNDLE_COLLISION", `destination exists; choose a new output or verify it: ${path}`);
    }
    return stage;
  } catch (error) {
    await rm(stage, { recursive: true });
    throw error;
  }
}
