#!/usr/bin/env bash
# frontend-ci.yml, case by case: the steps cut out of the workflow run on a throwaway package.json. The cases: the
# script that failed the job is named, strict mode requires format:check and the OpenAPI types check, and the standard
# scripts and the version guard. Shared helpers (extract_step, step_condition) live in lib/workflow.sh.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/workflow.sh
source "$(dirname "$0")/lib/workflow.sh"
# shellcheck disable=SC2034 # workflow czyta lib/workflow.sh
workflow="$root/.github/workflows/frontend-ci.yml"

# --- failing-script ---
# frontend-ci.yml nazywa skrypt, który czerwieni job: adnotacja i wiersz podsumowania dla każdego nieudanego kroku.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" "$tmp/summary" >&2 2>/dev/null; exit 1; }

extract_step "$workflow" 'Name the failing script' > "$tmp/name.sh"
step_condition "$workflow" 'Name the failing script' > "$tmp/if.txt"
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
)

# --- format ---
# Strict frontend-ci wymaga skryptu format:check i go uruchamia; bez strict krok nie istnieje dla callera.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

extract_step "$workflow" 'Format check' > "$tmp/format.sh"
step_condition "$workflow" 'Format check' > "$tmp/if.txt"
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
)

# --- openapi ---
# Strict frontend-ci sprawdza typy OpenAPI tylko u repo z platform.openapi; bez strict krok nie istnieje.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

extract_step "$workflow" 'OpenAPI types check' > "$tmp/openapi.sh"
step_condition "$workflow" 'OpenAPI types check' > "$tmp/if.txt"
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
)

# --- strict ---
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
extract_step "$workflow" 'Require standard scripts' > "$tmp/scripts.sh"
extract_step "$workflow" 'Platform versions guard' > "$tmp/guard.sh"
[[ -s "$tmp/scripts.sh" && -s "$tmp/guard.sh" ]] || exit 1
cd "$tmp"
cat > package.json <<'JSON'
{"scripts":{"lint":"eslint .","typecheck":"tsc","test":"vitest run","build":"next build"}}
JSON
REQUIRE_E2E=false bash -e scripts.sh
if REQUIRE_E2E=true bash -e scripts.sh; then
  echo 'Strict E2E must require test:e2e' >&2; exit 1
fi
node -e 'const fs=require("node:fs");const p=require("./package.json");p.scripts["test:e2e"]="playwright test";fs.writeFileSync("package.json",JSON.stringify(p))'
REQUIRE_E2E=true bash -e scripts.sh
node -e 'const fs=require("node:fs");const p=require("./package.json");p.scripts.lint=" ";fs.writeFileSync("package.json",JSON.stringify(p))'
if REQUIRE_E2E=false bash -e scripts.sh; then
  echo 'Whitespace-only scripts must be rejected' >&2; exit 1
fi
STRICT=false bash -e guard.sh
if STRICT=true bash -e guard.sh; then
  echo 'Strict mode must require the version guard' >&2; exit 1
fi
mkdir -p node_modules/.bin node_modules/@dominiksienkiewicz/versions/bin
touch node_modules/.bin/platform-versions-check
printf 'process.exit(0);\n' > node_modules/@dominiksienkiewicz/versions/bin/check.mjs
STRICT=true bash -e guard.sh
printf 'process.exit(7);\n' > node_modules/@dominiksienkiewicz/versions/bin/check.mjs
if STRICT=false bash -e guard.sh; then
  echo 'An installed failing guard must block both profiles' >&2; exit 1
fi
)
