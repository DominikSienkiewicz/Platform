#!/usr/bin/env bash
# Renovate, przypadek po przypadku: wspólny preset aktualizuje wszystko poza ramą (zależności aplikacji Gradle i npm
# pinowane dokładnie, akcje, Docker), a reguły ramy generuje scripts/renovate-preset.py; własna konfiguracja Platform
# pilnuje kanonów; preset opóźnia świeże wydania, a poprawki bezpieczeństwa przechodzą od razu.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- config ---
# Wspólny preset Renovate zostawia menedżery gradle i npm włączone dla zależności aplikacji (rangeStrategy pin,
# poza zakresami peerDependencies i engines); wrapper Gradle należy do ramy i platform-bump. Własny renovate.json
# Platform pilnuje obu kanonów, a jego regexy pasują do każdego wpisu versions.json i obu wierszy obrazu Snyka
# przypiętego po digeście.
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
// Reguła „całego menedżera”: poza opisem i matchManagers nie zawęża niczego (pakietów, plików, typów zależności).
const wholeManager = (rule, manager) =>
  (rule.matchManagers ?? []).includes(manager) &&
  Object.keys(rule).every((key) => ["description", "matchManagers", "enabled", "rangeStrategy"].includes(key));
const rules = preset.packageRules ?? [];

expect(rules.some((rule) => wholeManager(rule, "gradle-wrapper") && rule.enabled === false),
  "default.json must disable the gradle-wrapper manager: the Gradle version belongs to the frame");
for (const manager of ["npm", "gradle"]) {
  expect(!rules.some((rule) => wholeManager(rule, manager) && rule.enabled === false),
    `default.json must leave the ${manager} manager on for the application's own dependencies`);
  expect(rules.some((rule) => wholeManager(rule, manager) && rule.rangeStrategy === "pin"),
    `default.json must pin ${manager} versions exactly`);
  expect(!rules.some((rule) => rule.groupName && (rule.matchManagers ?? []).includes(manager)),
    `default.json must not group ${manager} updates`);
}
expect(rules.some((rule) => (rule.matchManagers ?? []).includes("npm") && rule.rangeStrategy === "auto"
    && ["peerDependencies", "engines"].every((type) => (rule.matchDepTypes ?? []).includes(type))),
  "default.json must keep peerDependencies and engines ranges unpinned");
expect(!JSON.stringify(preset.customManagers ?? []).includes("platform-catalog"), "default.json must not bump Platform pins");
expect(!JSON.stringify(preset).includes("hostRules"), "default.json needs no registry credentials");
expect((preset.customManagers ?? []).some((m) => m.managerFilePatterns.some((p) => p.includes("PlatformImages"))),
  "default.json keeps the Docker manager for PlatformImages.java");
expect((platform.extends ?? []).includes("github>SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform"), "renovate.json must extend the shared preset");

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
console.log("OK: the shared preset pins the application's Gradle and npm versions, and Platform's config manages both canons");
NODE
)

# --- frame ---
# Reguły ramy w default.json generuje scripts/renovate-preset.py (--check w CI przez ten test): Renovate nie rusza
# żadnej współrzędnej katalogu (biblioteki i pluginy), klucza versions.json, pl.seniordeveloper:*, seniordev.*,
# @seniordeveloper-pl-dominik-sienkiewicz/* ani referencji SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform, a zależności aplikacji aktualizuje. Własne reguły
# Platform (renovate.json) dalej włączają aktualizacje kanonów w samej Platform. Dopasowanie liczy uproszczony
# model Renovate: ostatnia pasująca reguła z `enabled` wygrywa; matchPackageNames patrzy na packageName, a bez
# niego na depName; `*` w globie nie przechodzi przez `/`. Plugin sprawdzamy w obu postaciach (z packageName
# markera i bez), więc wynik nie zależy od tego, jak Renovate nazwie zależność pluginu.
(
python3 - "$root" <<'PY'
import json
import os
import re
import sys
import tomllib

root = sys.argv[1]
preset = json.load(open(os.path.join(root, "default.json"), encoding="utf-8"))
platform = json.load(open(os.path.join(root, "renovate.json"), encoding="utf-8"))
with open(os.path.join(root, "gradle/catalog/libs.versions.toml"), "rb") as handle:
    catalog = tomllib.load(handle)
canon = json.load(open(os.path.join(root, "frontend/packages/versions/versions.json"), encoding="utf-8"))["versions"]
failures = []


def glob(pattern):
    parts = re.split(r"(\*\*|\*)", pattern)
    return re.compile("".join(".*" if p == "**" else "[^/]*" if p == "*" else re.escape(p) for p in parts) + r"\Z")


def names_match(patterns, name):
    return any(glob(pattern).match(name) if "*" in pattern else pattern == name for pattern in patterns)


def applies(rule, dep):
    if "matchManagers" in rule and dep["manager"] not in rule["matchManagers"]:
        return False
    if "matchPackageNames" in rule and not names_match(rule["matchPackageNames"], dep.get("packageName", dep["depName"])):
        return False
    if "matchDepNames" in rule and not names_match(rule["matchDepNames"], dep["depName"]):
        return False
    if "matchFileNames" in rule and not names_match(rule["matchFileNames"], dep.get("file", "")):
        return False
    if "matchDepTypes" in rule and dep.get("depType") not in rule["matchDepTypes"]:
        return False
    return True


def enabled(rules, dep):
    verdict = True
    for rule in rules:
        if "enabled" in rule and applies(rule, dep):
            verdict = rule["enabled"]
    return verdict


def expect(ok, message):
    if not ok:
        failures.append(message)


def coordinate(entry):
    if isinstance(entry, str):
        return ":".join(entry.split(":")[:2])
    return entry.get("module") or f"{entry['group']}:{entry['name']}"


libraries = sorted(coordinate(entry) for entry in catalog.get("libraries", {}).values())
plugins = sorted(entry.split(":")[0] if isinstance(entry, str) else entry["id"] for entry in catalog.get("plugins", {}).values())
expect(libraries and plugins and canon, "the catalog and versions.json must not be empty")

shared = preset["packageRules"]
for library in libraries + ["pl.seniordeveloper:platform-catalog"]:
    expect(not enabled(shared, {"manager": "gradle", "depName": library}), f"Renovate must leave the frame library {library} alone")
for plugin in plugins + ["seniordev.settings-conventions", "seniordev.future-conventions"]:
    for dep in ({"manager": "gradle", "depName": plugin, "packageName": f"{plugin}:{plugin}.gradle.plugin"},
                {"manager": "gradle", "depName": plugin}):
        expect(not enabled(shared, dep), f"Renovate must leave the frame plugin {plugin} alone ({dep.get('packageName', 'by id')})")
for package in sorted(canon) + ["@seniordeveloper-pl-dominik-sienkiewicz/versions", "@seniordeveloper-pl-dominik-sienkiewicz/eslint-config",
                                "@dominiksienkiewicz/versions"]:
    expect(not enabled(shared, {"manager": "npm", "depName": package}), f"Renovate must leave the frame package {package} alone")
for owner in ["SeniorDeveloper-pl-Dominik-Sienkiewicz", "DominikSienkiewicz"]:
    expect(not enabled(shared, {"manager": "github-actions", "depName": f"{owner}/Platform"}),
           "Renovate must leave the references to Platform's reusable workflows alone")
expect(not enabled(shared, {"manager": "gradle-wrapper", "depName": "gradle"}), "Renovate must leave the Gradle wrapper alone")

application = (
    {"manager": "gradle", "depName": "com.example:application-library"},
    {"manager": "gradle", "depName": "com.example.plugin",
     "packageName": "com.example.plugin:com.example.plugin.gradle.plugin"},
    {"manager": "npm", "depName": "left-pad"},
    {"manager": "github-actions", "depName": "actions/checkout"},
    {"manager": "dockerfile", "depName": "postgres"},
)
for dep in application:
    expect(enabled(shared, dep), f"Renovate must update the application's own {dep['manager']} dependency {dep['depName']}")

own = shared + platform["packageRules"]
expect(enabled(own, {"manager": "gradle", "depName": libraries[0], "file": "gradle/catalog/libs.versions.toml"}),
       "Platform's renovate.json must keep updating its catalog")
expect(enabled(own, {"manager": "npm", "depName": sorted(canon)[0], "file": "frontend/packages/eslint-config/package.json"}),
       "Platform's renovate.json must keep updating its frontend canon")

if failures:
    print("\n".join(f"FAIL: {failure}" for failure in failures), file=sys.stderr)
    sys.exit(1)
print(f"OK: Renovate leaves {len(libraries)} catalog libraries, {len(plugins)} plugins and {len(canon)} canon packages to platform-bump")
PY
)

# --- generator ---
# --check przechodzi na drzewie repo, wykrywa nową współrzędną katalogu i ręczną zmianę reguły ramy, a regeneracja
# zostawia ręczne reguły (akcje, pinowanie) i resztę presetu bez zmian.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
script="$root/scripts/renovate-preset.py"
[[ -f "$script" ]] || fail 'missing scripts/renovate-preset.py'
python3 "$script" --check > "$tmp/out.txt" 2>&1 || fail "default.json is stale: $(cat "$tmp/out.txt")"

mkdir -p "$tmp/repo/gradle/catalog" "$tmp/repo/frontend/packages/versions"
cp "$root/default.json" "$tmp/repo/default.json"
cp "$root/gradle/catalog/libs.versions.toml" "$tmp/repo/gradle/catalog/"
cp "$root/frontend/packages/versions/versions.json" "$tmp/repo/frontend/packages/versions/"
hand() { jq -c '[.packageRules[] | select((.description // "") | startswith("Frame:") | not)], del(.packageRules)' "$1"; }
hand "$tmp/repo/default.json" > "$tmp/hand.before"

awk '{ print } /^\[libraries\]$/ { print "probe-library = { group = \"org.example.probe\", name = \"probe-core\", version = \"1.0.0\" }" }' \
  "$root/gradle/catalog/libs.versions.toml" > "$tmp/repo/gradle/catalog/libs.versions.toml"
if python3 "$script" --check --root "$tmp/repo" > "$tmp/out.txt" 2>&1; then fail '--check must fail on a new catalog coordinate'; fi
grep -qF 'python3 scripts/renovate-preset.py' "$tmp/out.txt" || fail "--check must say how to regenerate: $(cat "$tmp/out.txt")"
python3 "$script" --root "$tmp/repo" > /dev/null
python3 "$script" --check --root "$tmp/repo" > /dev/null || fail 'a regenerated default.json must pass --check'
jq -e '[.packageRules[].matchPackageNames // [] | .[]] | index("org.example.probe:probe-core")' "$tmp/repo/default.json" > /dev/null \
  || fail 'the new catalog coordinate must reach default.json'
hand "$tmp/repo/default.json" > "$tmp/hand.after"
cmp -s "$tmp/hand.before" "$tmp/hand.after" || fail 'regeneration must keep the hand-written rules and the rest of the preset'

jq '(.packageRules[] | select(.matchManagers == ["npm"] and .enabled == false) | .matchPackageNames) |= .[1:]' \
  "$tmp/repo/default.json" > "$tmp/edited.json"
mv "$tmp/edited.json" "$tmp/repo/default.json"
if python3 "$script" --check --root "$tmp/repo" > /dev/null 2>&1; then fail '--check must fail on a hand-edited frame rule'; fi

echo 'OK: scripts/renovate-preset.py --check holds default.json to the catalog and the canon'
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
