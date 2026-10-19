// Bazowa konfiguracja Vitest (jsdom + React + setup Testing Library), przeniesiona z Attestate.
// Konsument dokłada własny alias "@" przez mergeConfig (ścieżka src jest per-repo):
//
//   import { defineConfig, mergeConfig } from "vitest/config";
//   import { fileURLToPath } from "node:url";
//   import { baseConfig } from "@dominiksienkiewicz/vitest-config";
//
//   export default mergeConfig(
//     baseConfig,
//     defineConfig({
//       resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
//     }),
//   );
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// Profil agenta (docs/agent-profile.md): AI_AGENT=1/true ogranicza workery do AI_AGENT_MAX_WORKERS (domyślnie 2),
// tej samej zmiennej, którą czyta scripts/agent-gradle.sh.
const agentMode = process.env.AI_AGENT === "1" || process.env.AI_AGENT === "true";

function agentMaxWorkers() {
  const value = process.env.AI_AGENT_MAX_WORKERS ?? "2";
  if (!/^[1-9][0-9]*$/.test(value)) {
    throw new Error(`AI_AGENT_MAX_WORKERS must be a positive integer, got '${value}'.`);
  }
  return Number(value);
}

export const baseConfig = defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    setupFiles: ["@dominiksienkiewicz/vitest-config/setup"],
    include: ["src/**/*.{test,spec}.{ts,tsx}"],
    css: false,
    ...(agentMode ? { maxWorkers: agentMaxWorkers() } : {}),
  },
});

export default baseConfig;
