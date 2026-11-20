#!/usr/bin/env bash
# Renovate, case by case: the shared preset covers actions and Docker only and Platform's own config manages the canons,
# and the preset delays fresh releases while security fixes pass at once.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- config ---
# The shared Renovate preset covers GitHub Actions and Docker only (Decision 5): Gradle, npm and the
# Platform pins belong to platform-bump. Platform's own renovate.json manages the two canons, and its
# regexes match every entry of versions.json and both lines of the digest-pinned Snyk image.
(
node --input-type=module - "$root" <<'NODE'
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = process.argv[2];
const read = (path) => readFileSync(join(root, path), "utf8");
const preset = JSON.parse(read("default.json"));
const platform = JSON.parse(read("renovate.json"));
const failures = [];
const expect = (ok, message) => { if (!ok) failures.push(message); };
const disables = (config, manager) =>
  (config.packageRules ?? []).some((rule) => rule.enabled === false && (rule.matchManagers ?? []).includes(manager) && !rule.matchFileNames);

for (const manager of ["npm", "gradle", "gradle-wrapper"]) {
  expect(disables(preset, manager), `default.json must disable the ${manager} manager`);
  expect(
    !(preset.packageRules ?? []).some((rule) => rule.groupName && (rule.matchManagers ?? []).includes(manager)),
    `default.json must not group ${manager} updates`,
  );
}
expect(!JSON.stringify(preset.customManagers ?? []).includes("platform-catalog"), "default.json must not bump Platform pins");
expect(!JSON.stringify(preset).includes("hostRules"), "default.json needs no registry credentials");
expect((preset.customManagers ?? []).some((m) => m.managerFilePatterns.some((p) => p.includes("PlatformImages"))),
  "default.json keeps the Docker manager for PlatformImages.java");
expect((platform.extends ?? []).includes("github>DominikSienkiewicz/Platform"), "renovate.json must extend the shared preset");

const managerFor = (fragment) => (platform.customManagers ?? []).find((m) => m.managerFilePatterns.some((p) => p.includes(fragment)));
const regex = (manager) => new RegExp(manager.matchStrings[0], "g");

const canonManager = managerFor("versions");
expect(canonManager, "renovate.json must manage frontend/packages/versions/versions.json");
if (canonManager) {
  const canon = read("frontend/packages/versions/versions.json");
  const matched = [...canon.matchAll(regex(canonManager))].map((m) => m.groups.depName);
  const keys = Object.keys(JSON.parse(canon).versions);
  expect(JSON.stringify(matched.sort()) === JSON.stringify([...keys].sort()),
    `the canon regex must match every key of versions.json and nothing else; unmatched: ${keys.filter((k) => !matched.includes(k))}`);
}
const snykManager = managerFor("container-scan");
expect(snykManager, "renovate.json must manage the Snyk image digest");
if (snykManager) {
  for (const workflow of [".github/workflows/deploy.yml", ".github/workflows/container-scan.yml"]) {
    const hits = [...read(workflow).matchAll(regex(snykManager))];
    expect(hits.length === 1 && hits[0].groups.currentDigest, `the Snyk regex must match the SNYK_IMAGE line of ${workflow} once`);
  }
}

if (failures.length) {
  console.error(failures.map((f) => `FAIL: ${f}`).join("\n"));
  process.exit(1);
}
console.log("OK: the shared preset covers actions and Docker only, and Platform's config manages both canons");
NODE
)

# --- security ---
# Preset Renovate czeka 3 dni na świeże wydania akcji i obrazów (internalChecksFilter strict), a poprawki
# bezpieczeństwa omijają i ten okres, i poniedziałkowe okno (G-16).
(
preset="$(cd "$(dirname "$0")/../.." && pwd)/default.json"

[[ "$(jq -r '.minimumReleaseAge' "$preset")" == "3 days" ]] || fail 'updates wait three days after a release'
[[ "$(jq -r '.internalChecksFilter' "$preset")" == strict ]] || fail 'a pending release age holds the pull request back'
[[ "$(jq -r '.osvVulnerabilityAlerts' "$preset")" == true ]] || fail 'OSV vulnerability alerts are on'
[[ "$(jq -r '.vulnerabilityAlerts | has("minimumReleaseAge") and .minimumReleaseAge == null' "$preset")" == true ]] \
  || fail 'security fixes skip the cooling-off period'
[[ "$(jq -c '.vulnerabilityAlerts.schedule' "$preset")" == '["at any time"]' ]] || fail 'security fixes skip the Monday window'
jq -e '.vulnerabilityAlerts.labels | index("security")' "$preset" > /dev/null || fail 'security fixes carry the security label'

echo 'OK: the Renovate preset delays fresh releases and lets security fixes through at once'
)
