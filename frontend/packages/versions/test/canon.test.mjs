// The real versions.json, not a fixture: a syntax error, a range or a Platform package in the canon
// would pass Platform CI and break or silently loosen the guard in every consumer after a bump.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const read = (name) => JSON.parse(readFileSync(new URL(`../${name}`, import.meta.url), "utf8"));
const canon = read("versions.json").versions;
const manifest = read("package.json");

test("versions.json parses to a non-empty versions object", () => {
  assert.equal(typeof canon, "object");
  assert.ok(Object.keys(canon).length > 0);
});

test("every canon version is exact", () => {
  const exact = /^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/;
  const loose = Object.entries(canon).filter(([, version]) => !exact.test(version));
  assert.deepEqual(loose, [], "versions.json must hold exact versions, without ^, ~ or ranges");
});

test("the canon holds no Platform package", () => {
  const platform = Object.keys(canon).filter((name) => name.startsWith("@dominiksienkiewicz/"));
  assert.deepEqual(platform, [], "Platform packages are pinned by platform-bump, not by the canon");
});

test("the published files carry versions.json and every bin", () => {
  assert.ok(manifest.files.includes("versions.json"));
  const unpublished = Object.values(manifest.bin).filter((target) => !manifest.files.includes(target));
  assert.deepEqual(unpublished, [], "every bin target must be listed in files");
});
