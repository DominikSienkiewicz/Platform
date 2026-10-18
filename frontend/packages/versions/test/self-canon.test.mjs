// Platform's own manifests follow the rule it imposes on consumers (CLAUDE.md rule 6): the guard passes
// for the workspace root and every package, so Platform tests its packages on the canon versions.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const versionsDir = fileURLToPath(new URL("..", import.meta.url));
const frontendDir = join(versionsDir, "..", "..");
const check = join(versionsDir, "bin", "check.mjs");
const canon = JSON.parse(readFileSync(join(versionsDir, "versions.json"), "utf8")).versions;
const packagesDir = join(frontendDir, "packages");
const manifestDirs = [
  frontendDir,
  ...readdirSync(packagesDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => join(packagesDir, entry.name)),
];

for (const dir of manifestDirs) {
  test(`platform-versions-check passes in ${relative(frontendDir, dir) || "the workspace root"}`, () => {
    const run = spawnSync(process.execPath, [check], { cwd: dir, encoding: "utf8" });
    assert.equal(run.status, 0, run.stderr);
  });
}

// Peers stay ranges where the package supports several majors, but a range that excludes the canon
// would make every consumer's install warn or fail. Only exact versions and ^N or ^N.M.P (N > 0) occur.
function admits(range, version) {
  const [major, minor, patch] = version.split(/[.-]/).map(Number);
  return range
    .split("||")
    .map((part) => part.trim())
    .some((part) => {
      if (part === version) return true;
      const caret = /^\^([1-9]\d*)(?:\.(\d+)\.(\d+))?$/.exec(part);
      assert.ok(caret, `unsupported peer range "${part}"; use an exact version or ^N`);
      const [, floorMajor, floorMinor = "0", floorPatch = "0"] = caret;
      if (Number(floorMajor) !== major) return false;
      return minor > Number(floorMinor) || (minor === Number(floorMinor) && patch >= Number(floorPatch));
    });
}

test("every peer range of a Platform package admits the canon version", () => {
  const rejected = [];
  for (const dir of manifestDirs) {
    const manifest = JSON.parse(readFileSync(join(dir, "package.json"), "utf8"));
    for (const [name, range] of Object.entries(manifest.peerDependencies ?? {})) {
      const want = canon[name];
      if (want === undefined || !admits(range, want)) {
        rejected.push(`${manifest.name}: ${name} "${range}" (canon ${want ?? "has no entry"})`);
      }
    }
  }
  assert.deepEqual(rejected, []);
});
