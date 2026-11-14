import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import * as prettier from "prettier";

const config = createRequire(import.meta.url)("@dominiksienkiewicz/prettier-config");
const root = fileURLToPath(new URL("../../../../", import.meta.url));
const versions = join(root, "frontend/packages/versions");

// platform-bump writes these blocks into AGENTS.md files that a consumer's `prettier --check .` reads, such as
// frontend/AGENTS.md, so the rendered block must already be in the form this preset gives it.
const blocks = [
  ["platform-block.md", []],
  ["backend-block.md", [join(versions, "agents/stack.json")]],
  ["frontend-block.md", [join(versions, "versions.json")]],
];

for (const [block, values] of blocks) {
  test(`the ${block} platform-bump writes passes prettier --check`, async () => {
    const dir = mkdtempSync(join(tmpdir(), "agent-block-"));
    try {
      const agents = join(dir, "AGENTS.md");
      execFileSync("python3", [
        join(versions, "bin/sync-agents-block.py"),
        join(root, "templates/agents", block),
        "9.9.9",
        agents,
        ...values,
      ]);
      const rendered = readFileSync(agents, "utf8");
      const formatted = await prettier.format(rendered, { ...config, parser: "markdown" });

      assert.equal(rendered, formatted);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
