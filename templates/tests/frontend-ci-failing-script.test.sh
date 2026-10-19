#!/usr/bin/env bash
# frontend-ci.yml nazywa skrypt, który czerwieni job: adnotacja i wiersz podsumowania dla każdego nieudanego kroku.
# shellcheck disable=SC2016 # literal GitHub expressions and Markdown backticks
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/frontend-ci.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" "$tmp/summary" >&2 2>/dev/null; exit 1; }

awk '
  $0 == "      - name: Name the failing script" { selected = 1; next }
  selected && /^        if: / { print > "/dev/stderr"; next }
  selected && /^        run: \|$/ { body = 1; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$workflow" > "$tmp/name.sh" 2> "$tmp/if.txt"
[[ -s "$tmp/name.sh" ]] || fail 'frontend-ci.yml has no "Name the failing script" step'
grep -qx '        if: ${{ failure() }}' "$tmp/if.txt" || fail 'the step must run only on failure'
for check in lint typecheck test build; do
  grep -qx "      - id: $check" "$workflow" || fail "the $check step needs id: $check"
done

: > "$tmp/summary"
OUTCOMES='lint=success typecheck=failure test=skipped build=skipped' GITHUB_STEP_SUMMARY="$tmp/summary" bash "$tmp/name.sh" > "$tmp/out"
grep -qxF '::error title=npm run typecheck failed::The typecheck script failed; its step log has the details.' "$tmp/out" || fail 'the failing script must be annotated'
[[ $(grep -c '^::error' "$tmp/out") -eq 1 ]] || fail 'only the failing script is annotated'
grep -qxF -- '- `npm run typecheck` failed' "$tmp/summary" || fail 'the summary must name the failing script'

echo 'OK: frontend-ci names the script that failed the job'
