// Lint własnych paczek Platform: to biblioteki ESM dla Node i bundlerów, nie aplikacja Next, więc preset
// z @seniordeveloper-pl-dominik-sienkiewicz/eslint-config (wymaga `next` w roocie i reguł aplikacji) tu nie pasuje.
// TypeScript (.d.ts, rejestr .tsx, testy typów) sprawdza `pnpm typecheck`.
import js from "@eslint/js";
import { defineConfig, globalIgnores } from "eslint/config";
import globals from "globals";

// Drzewa before/after testów migracji to migawki repozytoriów konsumentów: ESLint 10 bierze najbliższy
// eslint.config.* każdego pliku, a ich konfiguracja importuje paczki, których workspace nie instaluje.
export default defineConfig([
  globalIgnores([
    "**/node_modules/**",
    "packages/ui-registry/public/**",
    "packages/versions/test/migrations/*/before/**",
    "packages/versions/test/migrations/*/after/**",
  ]),
  {
    files: ["**/*.{js,mjs}"],
    extends: [js.configs.recommended],
    languageOptions: { globals: globals.node },
  },
]);
