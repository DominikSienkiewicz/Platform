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

export const baseConfig = defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    setupFiles: ["@dominiksienkiewicz/vitest-config/setup"],
    include: ["src/**/*.{test,spec}.{ts,tsx}"],
    css: false,
  },
});

export default baseConfig;
