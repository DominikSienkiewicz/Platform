import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const bin = (name) => fileURLToPath(new URL(`../bin/${name}.mjs`, import.meta.url));
const dir = mkdtempSync(join(tmpdir(), "platform-openapi-"));
after(() => rmSync(dir, { recursive: true, force: true }));
const run = (name, cwd = dir) => spawnSync(process.execPath, [bin(name)], { cwd, encoding: "utf8" });

const spec = (extraPath) => `openapi: 3.1.0
info: { title: Pets, version: "1" }
paths:
  /pets/{id}:
    get:
      operationId: getPet
      parameters: [{ name: id, in: path, required: true, schema: { type: string } }]
      responses:
        "200":
          description: ok
          content: { application/json: { schema: { type: object, properties: { name: { type: string } } } } }
${extraPath}`;

writeFileSync(join(dir, "package.json"), JSON.stringify({ platform: { openapi: { spec: "contract/openapi.yaml", output: "lib/api/schema.d.ts" } } }));
const contract = join(dir, "contract");
spawnSync("mkdir", ["-p", contract]);
writeFileSync(join(contract, "openapi.yaml"), spec(""));

test("platform-openapi-check fails when the types were never generated", () => {
  const result = run("check");
  assert.equal(result.status, 1);
  assert.match(result.stderr, /lib\/api\/schema\.d\.ts is missing/);
});

test("platform-openapi-gen writes the types and platform-openapi-check accepts them", () => {
  assert.equal(run("gen").status, 0);
  assert.match(readFileSync(join(dir, "lib/api/schema.d.ts"), "utf8"), /"\/pets\/\{id\}"/);
  const check = run("check");
  assert.equal(check.status, 0, check.stderr);
});

test("platform-openapi-check fails on types that the spec has moved past", () => {
  writeFileSync(join(contract, "openapi.yaml"), spec("  /owners:\n    get:\n      operationId: owners\n      responses: { \"204\": { description: none } }\n"));
  const result = run("check");
  assert.equal(result.status, 1);
  assert.match(result.stderr, /is stale for contract\/openapi\.yaml\. Run platform-openapi-gen/);
});

test("both bins name the configuration they need when it is missing", () => {
  const bare = mkdtempSync(join(tmpdir(), "platform-openapi-bare-"));
  try {
    writeFileSync(join(bare, "package.json"), "{}");
    for (const name of ["gen", "check"]) {
      const result = run(name, bare);
      assert.equal(result.status, 2);
      assert.match(result.stderr, /"platform": \{ "openapi"/);
    }
  } finally {
    rmSync(bare, { recursive: true, force: true });
  }
});
