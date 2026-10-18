// Every Platform package declares the Node range the workspace builds on, so npm warns a consumer on an
// older Node at install time instead of the package failing at runtime (docs/compatibility.md, Node).
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const frontendDir = fileURLToPath(new URL("../../..", import.meta.url));
const packagesDir = join(frontendDir, "packages");
const read = (dir) => JSON.parse(readFileSync(join(dir, "package.json"), "utf8"));
const workspaceNode = read(frontendDir).engines?.node;

test("every package declares the workspace's engines.node", () => {
  assert.ok(workspaceNode, "frontend/package.json must declare engines.node");
  const drifted = readdirSync(packagesDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => read(join(packagesDir, entry.name)))
    .filter((manifest) => manifest.engines?.node !== workspaceNode)
    .map((manifest) => `${manifest.name}: ${manifest.engines?.node ?? "no engines.node"}`);
  assert.deepEqual(drifted, []);
});
