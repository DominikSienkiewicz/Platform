#!/usr/bin/env bash
# Publikacja i odczyt pakietów Platform muszą wskazywać tego samego właściciela.
set -euo pipefail
cd "$(dirname "$0")/../.."
owner=SeniorDeveloper-pl-Dominik-Sienkiewicz
scope=@seniordeveloper-pl-dominik-sienkiewicz
fail() { echo "FAIL: $*" >&2; exit 1; }

while read -r module _; do
  [[ -n "$module" && "$module" != \#* ]] || continue
  grep -qxF "gpr.owner=${scope#@}" "gradle/$module/gradle.properties" || fail "$module publishes to the wrong Maven owner"
done < gradle/maven-modules.txt
grep -qF "https://maven.pkg.github.com/${scope#@}/Platform" \
  gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts || fail 'the settings plugin uses the wrong Maven repository'
grep -qxF "$scope:registry=https://npm.pkg.github.com" frontend/.npmrc || fail 'workspace npm registry scope'

node - "$scope" "$owner" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");
const [scope, owner] = process.argv.slice(2);
for (const pkg of fs.readdirSync("frontend/packages")) {
  const manifest = JSON.parse(fs.readFileSync(`frontend/packages/${pkg}/package.json`));
  if (manifest.private) continue;
  assert.equal(manifest.name, `${scope}/${pkg}`);
  assert.equal(manifest.repository.url, `git+https://github.com/${owner}/Platform.git`);
  assert.equal(manifest.publishConfig.registry, "https://npm.pkg.github.com");
}
NODE
# shellcheck disable=SC2016 # dosłowne flagi Gradle z workflowu
grep -qF -- '-Pgpr.owner="$GPR_OWNER"' .github/workflows/release.yml || fail 'release must override the checked-in owner'
if grep -qF '/users/$GPR_OWNER/packages/maven/' .github/workflows/{release,ci}.yml; then fail 'Maven releases use organization Packages endpoints'; fi
echo 'OK: Maven and npm resolve and publish under the Platform organization'

grep -qF -- '--bundle "$assets/platform-1.13.1-assets.sigstore.json"' .github/workflows/ci.yml ||
  fail 'the first organization release must authenticate the historical npm checksum manifest'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/assets" "$tmp/frontend"
asset=dominiksienkiewicz-versions-1.13.1.tgz
printf 'synthetic tarball bytes' > "$tmp/assets/$asset"
(cd "$tmp/assets" && shasum -a 256 "$asset") > "$tmp/assets/SHA256SUMS"
printf '{"devDependencies":{"@dominiksienkiewicz/versions":"1.13.1","typescript":"6.0.0"}}\n' > "$tmp/frontend/package.json"
bridge() { node scripts/legacy-frontend-smoke.mjs "$1" "$tmp/frontend" "$tmp/assets"; }
cp "$tmp/frontend/package.json" "$tmp/original"
node -e 'const fs=require("node:fs"),p=process.argv[1],m=JSON.parse(fs.readFileSync(p)); m.dependencies={[process.argv[2]+"/tsconfig"]:"1.13.1"}; fs.writeFileSync(p,JSON.stringify(m))' "$tmp/frontend/package.json" "$scope"
if bridge prepare > /dev/null 2>&1; then fail 'the historical image must reject mixed Platform scopes'; fi
cp "$tmp/original" "$tmp/frontend/package.json"
bridge prepare
node - "$tmp" "$asset" <<'NODE'
const { readFileSync, writeFileSync } = require("node:fs");
const { createHash } = require("node:crypto");
const assert = require("node:assert/strict");
const [tmp, asset] = process.argv.slice(2);
const manifest = JSON.parse(readFileSync(tmp + "/frontend/package.json"));
const name = "@dominiksienkiewicz/versions";
const resolved = "https://github.com/SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/releases/download/v1.13.1/" + asset;
assert.equal(manifest.devDependencies[name], resolved);
assert.equal(manifest.devDependencies.typescript, "6.0.0");
const integrity = "sha512-" + createHash("sha512").update(readFileSync(tmp + "/assets/" + asset)).digest("base64");
writeFileSync(tmp + "/frontend/package-lock.json", JSON.stringify({packages:{["node_modules/" + name]: {resolved, version:"1.13.1",integrity}}}));
NODE
bridge verify-lock
sed -i.bak 's/sha512-/sha512-wrong/' "$tmp/frontend/package-lock.json"
if bridge verify-lock > /dev/null 2>&1; then fail 'the image must reject a lock with a different tarball digest'; fi
cp "$tmp/original" "$tmp/frontend/package.json"
printf 'changed' > "$tmp/assets/$asset"
if bridge prepare > /dev/null 2>&1; then fail 'a changed tarball must fail its signed checksum'; fi
cmp "$tmp/original" "$tmp/frontend/package.json"
echo 'OK: the image smoke consumes authenticated 1.13.1 assets and verifies the install lock'
