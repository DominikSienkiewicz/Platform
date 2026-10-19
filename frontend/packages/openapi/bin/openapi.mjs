// Wspólna logika binów: konfiguracja z package.json konsumenta (platform.openapi.{spec,output}) i generacja
// typów z commitowanego specu przez programowe API openapi-typescript (wzorzec Azimutha).
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import openapiTS, { astToString, COMMENT_HEADER } from "openapi-typescript";

/** Exit code for a missing or invalid configuration, distinct from "types are stale" (1). */
export const CONFIG_ERROR = 2;

export function readConfig(cwd) {
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(resolve(cwd, "package.json"), "utf8"));
  } catch (error) {
    return { error: `No readable package.json in ${cwd}: ${error.message}` };
  }
  const { spec, output } = manifest.platform?.openapi ?? {};
  if (typeof spec !== "string" || typeof output !== "string") {
    return {
      error:
        'Configure the contract in package.json: "platform": { "openapi": { "spec": "<path to the committed spec>", "output": "<path of the generated .d.ts>" } }.',
    };
  }
  return { spec: resolve(cwd, spec), output: resolve(cwd, output), specName: spec, outputName: output };
}

export async function generate(specPath) {
  return COMMENT_HEADER + astToString(await openapiTS(pathToFileURL(specPath)));
}
