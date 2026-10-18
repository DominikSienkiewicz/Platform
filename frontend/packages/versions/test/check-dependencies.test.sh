#!/usr/bin/env bash
# platform-versions-check (bin/check.mjs): the core rule for dependencies and devDependencies.
#
# Hermetic like check-overrides.test.sh: a stub of the installed package (bin/check.mjs, its own
# versions.json and package.json) in a temporary directory, run from a stub consumer. No npm, no network.
# Assertions use stable fragments (package name, declared and canon versions), not the wording.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/bin/check.mjs"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PKG="$WORK/versions"
mkdir -p "$PKG/bin"
cp "$SRC" "$PKG/bin/check.mjs"
cat > "$PKG/package.json" <<'JSON'
{ "name": "@dominiksienkiewicz/versions", "version": "1.6.0" }
JSON
cat > "$PKG/versions.json" <<'JSON'
{
  "versions": {
    "next": "16.2.12",
    "react": "19.2.7",
    "typescript": "6.0.3"
  }
}
JSON

fails=0

# run_case <name> <package.json>: runs the guard in a stub consumer; sets RC and OUT.
run_case() {
  local name="$1" json="$2"
  local dir="$WORK/case-$name"
  mkdir -p "$dir"
  printf '%s\n' "$json" > "$dir/package.json"
  RC=0
  OUT="$( ( cd "$dir" && node "$PKG/bin/check.mjs" ) 2>&1 )" || RC=$?
}

fail() { local message="$1"; echo "FAIL: $message"; echo "--- output ---"; echo "$OUT"; fails=1; }

# (a) a caret on a dependency is drift, and the report names the declared and the canon version
run_case caret '{ "dependencies": { "next": "^16.2.12" } }'
[[ $RC -ne 0 ]] || fail "a caret in dependencies must fail the guard"
grep -q 'next' <<<"$OUT" || fail "the report must name next"
grep -qF '^16.2.12' <<<"$OUT" || fail "the report must show the declared ^16.2.12"
grep -qF '"16.2.12"' <<<"$OUT" || fail "the report must show the canon 16.2.12"

# (b) another exact version in devDependencies is drift
run_case dev-drift '{ "devDependencies": { "typescript": "6.0.2" } }'
[[ $RC -ne 0 ]] || fail "a devDependency off the canon must fail the guard"
grep -qF '6.0.2' <<<"$OUT" || fail "the report must show the declared 6.0.2"
grep -qF '6.0.3' <<<"$OUT" || fail "the report must show the canon 6.0.3"

# (c) a dependency without a canon entry fails
run_case missing '{ "dependencies": { "left-pad": "1.3.0" } }'
[[ $RC -ne 0 ]] || fail "a dependency without a canon entry must fail the guard"
grep -q 'left-pad.*1.3.0' <<<"$OUT" || fail "the report must name left-pad and its 1.3.0"

# (d) an npm: alias is not the canon version, so the guard fails closed
run_case alias '{ "dependencies": { "react": "npm:react@19.2.7" } }'
[[ $RC -ne 0 ]] || fail "an npm: alias must fail closed"

[[ $fails -eq 0 ]] || exit 1
echo "OK: the guard fails on drift, carets, missing canon entries and npm: aliases in dependencies and devDependencies"
