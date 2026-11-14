// Lint własnych paczek Platform: to biblioteki ESM dla Node i bundlerów, nie aplikacja Next, więc preset
// z @dominiksienkiewicz/eslint-config (wymaga `next` w roocie i reguł aplikacji) tu nie pasuje.
// TypeScript (.d.ts, rejestr .tsx, testy typów) sprawdza `pnpm typecheck`.
import js from "@eslint/js";
import { defineConfig, globalIgnores } from "eslint/config";
import globals from "globals";

export default defineConfig([
  globalIgnores(["**/node_modules/**", "packages/ui-registry/public/**"]),
  {
    files: ["**/*.{js,mjs}"],
    extends: [js.configs.recommended],
    languageOptions: { globals: globals.node },
  },
]);
