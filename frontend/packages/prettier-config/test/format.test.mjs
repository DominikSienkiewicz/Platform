import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import * as prettier from "prettier";

const config = createRequire(import.meta.url)("@dominiksienkiewicz/prettier-config");

test("the preset loads the Tailwind plugin, which sorts class lists", async () => {
  const formatted = await prettier.format('export const a = <div className="p-4 flex" />;\n', {
    ...config,
    parser: "babel",
  });

  assert.equal(formatted, 'export const a = <div className="flex p-4" />;\n');
});
