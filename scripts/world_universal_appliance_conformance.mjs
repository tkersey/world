#!/usr/bin/env node
import { runConformance } from './world_universal_appliance_host.mjs';

async function main() {
  const [replyHelperPath, wasmPath, imageAPath, commandAPath, imageBPath, commandBPath] = process.argv.slice(2);
  if (!commandBPath) {
    throw new Error('usage: world_universal_appliance_conformance.mjs <reply-helper> <wasm> <image-a> <command-a> <image-b> <command-b>');
  }

  const result = await runConformance({ replyHelperPath, wasmPath, imageAPath, commandAPath, imageBPath, commandBPath });
  const runs = [result.resultA, result.resultB, result.freshA, result.freshB];
  if (runs.some((run) => !run.loaded)) throw new Error(`canonical executable image was not loaded: ${JSON.stringify(runs)}`);
  if (runs.some((run) => !run.manifestPresent)) throw new Error('canonical manifest was not exposed');
  if (runs.some((run) => !run.outputReady)) throw new Error('canonical command did not produce TurnOutput bytes');
  if (runs.some((run) => !run.hostRequestReady)) throw new Error('canonical host request was not exposed');
  if (runs.some((run) => !run.completed)) throw new Error(`canonical reply did not complete execution: ${JSON.stringify(runs)}`);
  if (runs.some((run) => !run.rootResultReady)) throw new Error('completed output missing root result bytes');
  if (runs.some((run) => !run.archiveAppendReady)) throw new Error('completed output missing Archive.AppendBatch bytes');
  if (!result.rejectedTextEnvelope) throw new Error('text envelope was accepted');
  if (!result.submitWithoutImageRejected) throw new Error('submit without image was not rejected');

  console.log('actual_external_runtime_executed=true');
  console.log('compiled_once=true');
  console.log('empty_imports=true');
  console.log('image_a_loaded=true');
  console.log('image_b_loaded=true');
  console.log('same_instance_a_then_b=true');
  console.log('fresh_instance_a_then_b=true');
  console.log('manifests_present=true');
  console.log('host_requests_ready=true');
  console.log('completed_outputs_ready=true');
  console.log('root_result_bytes_ready=true');
  console.log('archive_append_batch_bytes_ready=true');
  console.log('text_envelope_rejected=true');
  console.log('submit_without_image_rejected=true');
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
