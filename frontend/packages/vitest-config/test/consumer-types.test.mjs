// Konsument importuje preset z node_modules, a tsc nie czyta tam plików .js: bez deklaracji w paczce import
// kończy się błędem TS7016 pod `strict`. Wewnątrz workspace'u tego nie widać (index.js leży w `include`
// frontend/tsconfig.json), a paczka podlinkowana symlinkiem jest czytana spod swojej prawdziwej ścieżki, poza
// node_modules. Dlatego fixture to konsument w katalogu tymczasowym z RZECZYWISTĄ paczką (npm pack) rozpakowaną do
// jego node_modules, z tym samym vitest.config.ts, który renderuje scripts/new-consumer.sh --frontend next;
// to sprawdza też pole `files` i mapę `exports`.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const packageDir = fileURLToPath(new URL("..", import.meta.url));
const require = createRequire(import.meta.url);
const tsc = require.resolve("typescript/bin/tsc");
const consumers = [];
after(() => consumers.forEach((dir) => rmSync(dir, { recursive: true, force: true })));

const vitestConfig = `import { defineConfig, mergeConfig } from "vitest/config";
import { fileURLToPath } from "node:url";
import { baseConfig } from "@dominiksienkiewicz/vitest-config";

export default mergeConfig(
  baseConfig,
  defineConfig({
    resolve: {
      alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
    },
  }),
);
`;

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: "utf8", ...options });
  assert.equal(result.status, 0, `${command} ${args.join(" ")}\n${result.stdout}${result.stderr}`);
  return result.stdout;
}

function link(consumer, name, target) {
  const path = join(consumer, "node_modules", name);
  mkdirSync(dirname(path), { recursive: true });
  symlinkSync(target, path, "dir");
}

function installPublishedPackage(consumer) {
  const [{ filename }] = JSON.parse(run("npm", ["pack", "--json", "--ignore-scripts", "--pack-destination", consumer], { cwd: packageDir }));
  const target = join(consumer, "node_modules", "@dominiksienkiewicz", "vitest-config");
  mkdirSync(target, { recursive: true });
  run("tar", ["-xzf", join(consumer, filename), "-C", target, "--strip-components=1"]);
}

function typeCheckConsumer() {
  const consumer = mkdtempSync(join(tmpdir(), "platform-vitest-config-"));
  consumers.push(consumer);
  installPublishedPackage(consumer);
  link(consumer, "@dominiksienkiewicz/tsconfig", join(packageDir, "..", "tsconfig"));
  link(consumer, "@types/node", dirname(require.resolve("@types/node/package.json")));
  link(consumer, "vitest", join(packageDir, "node_modules", "vitest"));
  writeFileSync(join(consumer, "vitest.config.ts"), vitestConfig);
  writeFileSync(
    join(consumer, "tsconfig.json"),
    JSON.stringify({ extends: "@dominiksienkiewicz/tsconfig/next.json", include: ["**/*.ts"], exclude: ["node_modules"] }),
  );
  return spawnSync(process.execPath, [tsc, "--noEmit", "-p", consumer], { encoding: "utf8" });
}

test("a strict consumer vitest.config.ts type-checks against the published preset", () => {
  const check = typeCheckConsumer();

  assert.doesNotMatch(check.stdout, /TS7016/, "the published package ships no declarations for its entry point:\n" + check.stdout);
  assert.equal(check.status, 0, check.stdout + check.stderr);
});
