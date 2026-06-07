// Współdzielony ESLint flat config — najlepsza wersja z SkillSprintPlus
// (core-web-vitals + typescript), zamiast słabszego `...next` z Attestate
// i braku ESLint w BookOfStyling.
import { defineConfig, globalIgnores } from "eslint/config";
import { fixupConfigRules } from "@eslint/compat";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

// TYMCZASOWY shim ESLint 10: eslint-plugin-react (bundlowany przez eslint-config-next,
// nawet latest 7.37.5) używa usuniętego w v10 API context.getFilename().
// fixupConfigRules (@eslint/compat, oficjalne narzędzie zespołu ESLint) łata to w locie;
// pod ESLint 9 jest no-opem. Usuń wrapper, gdy eslint-config-next wesprze v10 natywnie
// (śledź: github.com/jsx-eslint/eslint-plugin-react/issues/3977).
const config = defineConfig([
  ...fixupConfigRules(nextVitals),
  ...fixupConfigRules(nextTs),
  globalIgnores([".next/**", "out/**", "build/**", "next-env.d.ts"]),
]);

export default config;
