#!/usr/bin/env node
import { executeCli } from "../src/process_v2/cli.mjs";

try { await executeCli(process.argv.slice(2)); }
catch (error) {
  process.stderr.write(`${error.code ?? "WORLD_PROCESS_REJECTED"}: ${error.message}\n`);
  process.exitCode = error.code === "WORLD_CLI_USAGE" ? 2 : 1;
}
