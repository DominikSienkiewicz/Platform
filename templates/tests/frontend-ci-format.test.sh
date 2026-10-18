#!/usr/bin/env bash
# Strict frontend-ci wymaga skryptu format:check i go uruchamia; bez strict krok nie istnieje dla callera.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/frontend-ci.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

awk '
  $0 == "      - name: Format check" { selected = 1; next }
  selected && /^        if: / { print > "/dev/stderr"; next }
  selected && /^        run: \|$/ { body = 1; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$workflow" > "$tmp/format.sh" 2> "$tmp/if.txt"
[[ -s "$tmp/format.sh" ]] || fail 'frontend-ci.yml has no "Format check" step'
# shellcheck disable=SC2016 # ${{ inputs.strict }} is a literal GitHub expression, not a shell expansion
grep -qx '        if: ${{ inputs.strict }}' "$tmp/if.txt" || fail 'the format check must run only with strict: true'

cd "$tmp"
printf '{"scripts":{"lint":"eslint ."}}\n' > package.json
if bash -e format.sh > out.txt 2>&1; then fail 'a strict caller without format:check must fail'; fi
grep -q 'Missing required scripts: format:check' out.txt || fail "unexpected message: $(cat out.txt)"

printf '{"scripts":{"format:check":" "}}\n' > package.json
if bash -e format.sh > out.txt 2>&1; then fail 'a whitespace-only format:check must fail'; fi

printf '{"scripts":{"format:check":"node -e \\"process.exit(3)\\""}}\n' > package.json
if bash -e format.sh > out.txt 2>&1; then fail 'an unformatted tree (format:check exits non-zero) must fail the step'; fi

printf '{"scripts":{"format:check":"node -e \\"process.exit(0)\\""}}\n' > package.json
bash -e format.sh > out.txt 2>&1 || fail "a formatted tree must pass: $(cat out.txt)"

echo 'OK: strict frontend-ci requires format:check and fails on unformatted files'
