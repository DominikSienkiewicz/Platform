import assert from "node:assert/strict";
import test from "node:test";
import { ESLint } from "eslint";
import config from "../next.js";

const eslint = new ESLint({ overrideConfigFile: true, overrideConfig: config });

test("Next TypeScript rules remain active through the compatibility preset", async () => {
  const [result] = await eslint.lintText(
    "export const value: any = 1;\n",
    { filePath: "src/value.ts" },
  );

  assert.ok(result.messages.some(({ ruleId }) => ruleId === "@typescript-eslint/no-explicit-any"));
});

test("React rules can report JSX violations through the ESLint compatibility shim", async () => {
  const [result] = await eslint.lintText(
    "export default function List() { return [1, 2].map(value => <span>{value}</span>); }\n",
    { filePath: "src/List.tsx" },
  );

  assert.ok(result.messages.some(({ ruleId }) => ruleId === "react/jsx-key"));
  assert.ok(result.messages.every(({ fatal }) => !fatal));
});
