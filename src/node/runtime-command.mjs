import { isAbsolute } from "node:path";
import { verifyBundle } from "./runtime-bundle.mjs";
export async function runtimeCommand(args) {
  const operation = args.shift(), options = new Map();
  const allowed = operation === "prepare" ? ["--source", "--output"] : operation === "acquire"
    ? ["--archive", "--archive-sha256", "--manifest-sha256", "--output"]
    : ["--root", "--manifest-sha256", "--smoke"];
  if (!["prepare", "verify", "acquire"].includes(operation)) throw new Error("expected runtime prepare, acquire or verify");
  while (args.length) {
    const flag = args.shift();
    const value = flag === "--smoke" ? true : args.shift();
    if (!allowed.includes(flag) || options.has(flag) || !value || String(value).startsWith("--"))
      throw new Error(`invalid runtime option ${flag}`);
    options.set(flag, value);
  }
  for (const flag of allowed.filter(flag => flag !== "--smoke"))
    if (!options.has(flag)) throw new Error(`missing ${flag}`);
  if (operation === "verify") return verifyBundle(options.get("--root"), options.get("--manifest-sha256"), options.has("--smoke"));
  if (operation === "acquire") {
    const { acquireBundle } = await import("./runtime-acquire.mjs");
    return acquireBundle(options.get("--archive"), options.get("--archive-sha256"), options.get("--manifest-sha256"), options.get("--output"));
  }
  if (![options.get("--source"), options.get("--output")].every(isAbsolute))
    throw new Error("prepare requires absolute source and output paths");
  const { prepareBundle } = await import("./runtime-prepare.mjs");
  return prepareBundle(options.get("--source"), options.get("--output"));
}
