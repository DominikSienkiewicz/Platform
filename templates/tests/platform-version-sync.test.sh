#!/usr/bin/env bash
# Every version-bearing file must carry the single platformVersion of
# gradle/build-logic/gradle.properties, and no build script may fall back to a hard-coded version.
#
# Published artifacts stay consistent only because release.yml overrides versions at publish
# time. A stale value anywhere else surfaces locally: publishToMavenLocal of a module at an old
# version, a JVM template that starts one release behind, or a catalog placeholder that silently
# resolves to a real, older artifact when version injection regresses.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)

fail() {
  local message="$1"
  echo "FAIL: $message" >&2
  exit 1
}

tracked() {
  local pattern="$1"
  git -C "$root" ls-files -- ":(glob)$pattern"
}

property_version() {
  local file="$1"
  sed -n -E 's/^platformVersion=[[:space:]]*([^[:space:]]+).*/\1/p' "$root/$file"
}

package_version() {
  local file="$1"
  sed -n -E 's/^  "version": "([^"]*)".*/\1/p' "$root/$file"
}

expected=$(property_version gradle/build-logic/gradle.properties)
[[ "$expected" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "gradle/build-logic/gradle.properties must hold platformVersion=X.Y.Z, got '$expected'"

mismatches=()
check_files() {
  local pattern="$1"
  local reader="$2"
  local files file actual
  files=$(tracked "$pattern")
  [[ -n "$files" ]] || fail "no tracked file matches $pattern"
  while IFS= read -r file; do
    actual=$("$reader" "$file")
    [[ "$actual" == "$expected" ]] || mismatches+=("$file: ${actual:-<no version>}")
  done <<<"$files"
}

check_files 'gradle/*/gradle.properties' property_version
check_files 'templates/jvm/*/gradle.properties' property_version
check_files 'frontend/packages/*/package.json' package_version
if [[ "${#mismatches[@]}" -gt 0 ]]; then
  fail "every version file must equal platformVersion $expected:
$(printf '  %s\n' "${mismatches[@]}")"
fi

fallbacks=$(git -C "$root" grep -n -E 'getOrElse\("[0-9]' -- ':(glob)gradle/*/build.gradle.kts' || true)
[[ -z "$fallbacks" ]] || fail "build scripts must read platformVersion with .get(), not a hard-coded fallback:
$fallbacks"

placeholder=$(sed -n -E 's/^platform[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$root/gradle/catalog/libs.versions.toml")
[[ -n "$placeholder" ]] || fail 'gradle/catalog/libs.versions.toml must declare the platform placeholder'
if [[ "$placeholder" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "the catalog platform placeholder '$placeholder' is a resolvable release; use a version that cannot resolve"
fi

echo "OK: every version file carries platformVersion $expected; no hard-coded fallback remains"
