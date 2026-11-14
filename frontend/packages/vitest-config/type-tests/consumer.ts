// Type test from a consumer's side, checked by `pnpm typecheck` and never run: the preset is imported by name, as
// a consumer's vitest.config.ts imports it (the file scripts/new-consumer.sh --frontend next renders), and
// resolves to index.d.ts, which this workspace checks without skipLibCheck. TS7016 itself cannot show up here,
// because index.js is part of this program; test/consumer-types.test.mjs reproduces it from an installed package.
import { defineConfig, mergeConfig, type ViteUserConfig } from "vitest/config";
import { fileURLToPath } from "node:url";
import defaultExport, { baseConfig } from "@dominiksienkiewicz/vitest-config";

export const merged: ViteUserConfig = mergeConfig(
  baseConfig,
  defineConfig({
    resolve: {
      alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
    },
  }),
);

export const preset: ViteUserConfig = baseConfig;
export const sameAsNamed: typeof baseConfig = defaultExport;

// A preset typed `any` would accept this; the declaration types `test` with Vitest's own config type.
// @ts-expect-error the environment is a string, not a number
export const notAny: number | undefined = baseConfig.test?.environment;
