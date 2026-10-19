#!/usr/bin/env node
// platform-openapi-gen — writes the TypeScript types of the committed OpenAPI spec (package.json platform.openapi).
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { CONFIG_ERROR, generate, readConfig } from "./openapi.mjs";

const config = readConfig(process.cwd());
if (config.error) {
  console.error(`platform-openapi-gen: ${config.error}`);
  process.exit(CONFIG_ERROR);
}
mkdirSync(dirname(config.output), { recursive: true });
writeFileSync(config.output, await generate(config.spec));
console.log(`platform-openapi-gen: wrote ${config.outputName} from ${config.specName}`);
