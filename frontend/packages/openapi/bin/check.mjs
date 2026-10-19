#!/usr/bin/env node
// platform-openapi-check — fails when the committed types differ from what the committed spec generates.
import { existsSync, readFileSync } from "node:fs";
import { CONFIG_ERROR, generate, readConfig } from "./openapi.mjs";

const config = readConfig(process.cwd());
if (config.error) {
  console.error(`platform-openapi-check: ${config.error}`);
  process.exit(CONFIG_ERROR);
}
const expected = await generate(config.spec);
const actual = existsSync(config.output) ? readFileSync(config.output, "utf8") : null;
if (actual !== expected) {
  console.error(
    `platform-openapi-check: ${config.outputName} is ${actual === null ? "missing" : "stale"} for ${config.specName}. ` +
      "Run platform-openapi-gen and commit the result.",
  );
  process.exit(1);
}
console.log(`platform-openapi-check: ${config.outputName} matches ${config.specName}`);
