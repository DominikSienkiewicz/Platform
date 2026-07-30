import assert from "node:assert/strict";
import test from "node:test";

test("public configs load with the package development dependencies", async () => {
  const [defaultConfig, nextConfig] = await Promise.all([
    import("../index.js"),
    import("../next.js"),
  ]);

  assert.ok(Array.isArray(defaultConfig.default));
  assert.ok(Array.isArray(nextConfig.default));
});
