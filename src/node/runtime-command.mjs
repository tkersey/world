import { verifyBundle } from "./runtime-bundle.mjs";
export async function runtimeCommand(args) {
  const operation = args.shift(), options = new Map();
  const allowed = operation === "acquire" ? ["--archive", "--archive-sha256", "--manifest-sha256", "--output"] : ["--root", "--manifest-sha256", "--smoke"];
  if (!["verify", "acquire"].includes(operation)) throw new Error("expected runtime acquire or verify; source packages are built with zig build build-runtime");
  while (args.length) {
    const flag = args.shift();
    const value = flag === "--smoke" || flag === "--offline" ? true : args.shift();
    if (!allowed.includes(flag) || options.has(flag) || !value || String(value).startsWith("--"))
      throw new Error(`invalid runtime option ${flag}`);
    options.set(flag, value);
  }
  const required = allowed.filter(flag => flag !== "--smoke");
  for (const flag of required)
    if (!options.has(flag)) throw new Error(`missing ${flag}`);
  if (operation === "verify") return verifyBundle(options.get("--root"), options.get("--manifest-sha256"), options.has("--smoke"));
  if (operation === "acquire") {
    const { acquireBundle } = await import("./runtime-acquire.mjs");
    return acquireBundle(options.get("--archive"), options.get("--archive-sha256"), options.get("--manifest-sha256"), options.get("--output"));
  }
}
