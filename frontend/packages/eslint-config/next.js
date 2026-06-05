// Współdzielony ESLint flat config — najlepsza wersja z SkillSprintPlus
// (core-web-vitals + typescript), zamiast słabszego `...next` z Attestate
// i braku ESLint w BookOfStyling.
import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const config = defineConfig([
  ...nextVitals,
  ...nextTs,
  globalIgnores([".next/**", "out/**", "build/**", "next-env.d.ts"]),
]);

export default config;
