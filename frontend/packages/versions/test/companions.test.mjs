import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const source = fileURLToPath(new URL("..", import.meta.url));
const versions = {
  typescript: "npm:@typescript/typescript6@6.0.2",
  "typescript-native": "npm:typescript@7.0.2",
  vitest: "5.1.2",
  vite: "8.3.8",
};
const companions = { typescript: "typescript-native", vitest: "vite" };

function fixture(t, pkg) {
  const root = mkdtempSync(join(tmpdir(), "platform-toolchain-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const target = join(root, "target");
  const frontend = join(root, "frontend");
  mkdirSync(frontend);
  cpSync(join(source, "bin"), join(target, "bin"), { recursive: true });
  cpSync(join(source, "migrations"), join(target, "migrations"), {
    recursive: true,
  });
  writeFileSync(
    join(target, "versions.json"),
    JSON.stringify({ versions, companions }),
  );
  const manifest = join(frontend, "package.json");
  writeFileSync(manifest, JSON.stringify(pkg));
  return {
    read: () => JSON.parse(readFileSync(manifest)),
    raw: () => readFileSync(manifest, "utf8"),
    check: (...args) =>
      spawnSync(process.execPath, [join(target, "bin/check.mjs"), ...args], {
        cwd: frontend,
        encoding: "utf8",
      }),
    migrate: () =>
      spawnSync(
        "bash",
        [join(target, "migrations/run.sh"), "apply", "2.0.1", "2.0.2"],
        { cwd: root, encoding: "utf8" },
      ),
  };
}

test("a frontend declaring the TypeScript API and Vitest can apply their missing compiler and Vite pins", (t) => {
  const project = fixture(t, {
    dependencies: { typescript: versions.typescript },
    devDependencies: { vitest: versions.vitest },
  });
  const drift = project.check();
  assert.equal(
    drift.status,
    1,
    "a project without the native tsc and Vite must fail the dependency guard",
  );
  assert.match(drift.stderr, /typescript-native/);
  assert.match(drift.stderr, /vite:/);
  const fixed = project.check("--fix");
  assert.equal(fixed.status, 0, fixed.stderr);
  assert.deepEqual(project.read(), {
    dependencies: {
      typescript: versions.typescript,
      "typescript-native": versions["typescript-native"],
    },
    devDependencies: { vitest: versions.vitest, vite: versions.vite },
  });
  assert.equal(project.check().status, 0);
});

test("the target release adds only missing toolchain companions in the section that needs them", (t) => {
  const project = fixture(t, {
    dependencies: { other: "1.0.0", vite: versions.vite },
    devDependencies: {
      typescript: versions.typescript,
      vitest: versions.vitest,
    },
  });
  const migrated = project.migrate();
  assert.equal(migrated.status, 0, migrated.stderr);
  assert.deepEqual(project.read(), {
    dependencies: { other: "1.0.0", vite: versions.vite },
    devDependencies: {
      typescript: versions.typescript,
      vitest: versions.vitest,
      "typescript-native": versions["typescript-native"],
    },
  });
  const once = project.raw();
  assert.equal(project.migrate().status, 0);
  assert.equal(project.raw(), once);
  const withoutToolchain = fixture(t, { dependencies: { other: "1.0.0" } });
  const initial = withoutToolchain.raw();
  assert.equal(withoutToolchain.migrate().status, 0);
  assert.equal(withoutToolchain.raw(), initial);
});

test("frontend agent instructions name the native TypeScript compiler version while preserving plain historic pins", (t) => {
  const root = mkdtempSync(join(tmpdir(), "platform-compiler-version-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const template = join(root, "template.md");
  writeFileSync(
    template,
    "<!-- BEGIN platform-agents-frontend v{{VERSION}} -->\nTypeScript {{typescript}}\n<!-- END platform-agents-frontend -->\n",
  );
  const target = join(root, "AGENTS.md");
  const canon = join(root, "versions.json");
  for (const [pins, expected] of [
    [versions, "7.0.2"],
    [{ typescript: "6.0.3" }, "6.0.3"],
  ]) {
    writeFileSync(canon, JSON.stringify({ versions: pins }));
    const synced = spawnSync("python3", [
      join(source, "bin/sync-agents-block.py"),
      template,
      "2.0.2",
      target,
      canon,
    ]);
    assert.equal(synced.status, 0, synced.stderr.toString());
    assert.equal(
      readFileSync(target, "utf8").split("\n")[1],
      `TypeScript ${expected}`,
    );
  }
});
