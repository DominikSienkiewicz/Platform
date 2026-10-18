// A preset's include, exclude and paths resolve against the preset's own directory, which in a consumer
// is node_modules/@dominiksienkiewicz/tsconfig. The fixture is a consumer in the system temp directory with
// the package linked into its node_modules; inside the package the bug would not show.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const packageDir = fileURLToPath(new URL("..", import.meta.url));
const tsc = createRequire(import.meta.url).resolve("typescript/bin/tsc");
const consumers = [];
after(() => consumers.forEach((dir) => rmSync(dir, { recursive: true, force: true })));

function showConfig(tsconfig) {
  const dir = mkdtempSync(join(tmpdir(), "platform-tsconfig-"));
  consumers.push(dir);
  mkdirSync(join(dir, "node_modules", "@dominiksienkiewicz"), { recursive: true });
  symlinkSync(packageDir, join(dir, "node_modules", "@dominiksienkiewicz", "tsconfig"), "dir");
  mkdirSync(join(dir, "src"));
  writeFileSync(join(dir, "src", "a.ts"), "export const a = 1;\n");
  writeFileSync(join(dir, "tsconfig.json"), JSON.stringify(tsconfig));
  const run = spawnSync(process.execPath, [tsc, "--showConfig", "-p", dir], { encoding: "utf8" });
  assert.equal(run.status, 0, run.stdout + run.stderr);
  return JSON.parse(run.stdout);
}

test("a consumer without its own include compiles its own files", () => {
  const config = showConfig({ extends: "@dominiksienkiewicz/tsconfig/next.json" });
  assert.ok(config.files.includes("./src/a.ts"), JSON.stringify(config.files));
  assert.deepEqual((config.exclude ?? []).filter((path) => path.startsWith("..")), []);
});

test("next.json leaves paths to the consumer and adds the next plugin", () => {
  const config = showConfig({ extends: "@dominiksienkiewicz/tsconfig/next.json", include: ["src"] });
  assert.equal(config.compilerOptions.paths, undefined, "paths in a preset resolve against node_modules");
  assert.ok(config.compilerOptions.plugins.some((plugin) => plugin.name === "next"));
});
