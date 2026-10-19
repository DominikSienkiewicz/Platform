#!/usr/bin/env bash
# Strict frontend-ci sprawdza typy OpenAPI tylko u repo z platform.openapi; bez strict krok nie istnieje.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/frontend-ci.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

awk '
  $0 == "      - name: OpenAPI types check" { selected = 1; next }
  selected && /^        if: / { print > "/dev/stderr"; next }
  selected && /^        run: \|$/ { body = 1; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$workflow" > "$tmp/openapi.sh" 2> "$tmp/if.txt"
[[ -s "$tmp/openapi.sh" ]] || fail 'frontend-ci.yml has no "OpenAPI types check" step'
# shellcheck disable=SC2016 # ${{ inputs.strict }} is a literal GitHub expression, not a shell expansion
grep -qx '        if: ${{ inputs.strict }}' "$tmp/if.txt" || fail 'the OpenAPI types check must run only with strict: true'

cd "$tmp"
stub() {
  mkdir -p node_modules/@dominiksienkiewicz/openapi/bin
  printf 'console.log("checked"); process.exit(%s);\n' "$1" > node_modules/@dominiksienkiewicz/openapi/bin/check.mjs
}
contract='{"platform":{"openapi":{"spec":"contract/openapi.yaml","output":"src/api/schema.d.ts"}}}'

printf '{"scripts":{}}\n' > package.json
bash -e openapi.sh > out.txt 2>&1 || fail "a repo without platform.openapi must pass: $(cat out.txt)"
grep -q '::notice::package.json configures no platform.openapi contract' out.txt || fail "no skip notice: $(cat out.txt)"

printf '%s\n' "$contract" > package.json
if bash -e openapi.sh > out.txt 2>&1; then fail 'a configured contract without @dominiksienkiewicz/openapi must fail'; fi
grep -q '@dominiksienkiewicz/openapi is not installed' out.txt || fail "unexpected message: $(cat out.txt)"

stub 1
if bash -e openapi.sh > out.txt 2>&1; then fail 'stale types (platform-openapi-check exits 1) must fail the step'; fi

stub 0
bash -e openapi.sh > out.txt 2>&1 || fail "current types must pass: $(cat out.txt)"
grep -qx 'checked' out.txt || fail 'the step must run platform-openapi-check'

echo 'OK: strict frontend-ci checks the OpenAPI types of repos that configure platform.openapi'
