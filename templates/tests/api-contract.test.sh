#!/usr/bin/env bash
# Kroki api-contract.yml na stubie dockera (zamiast oasdiff): rozwiązanie specu bazy, mapowanie kodu
# wyjścia oasdiff na output breaking oraz bramka z etykietą. Prawdziwy oasdiff ćwiczy self-test w ci.yml.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/api-contract.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

extract() {
  awk -v name="      - name: $1" '
    $0 == name { selected = 1; next }
    selected && /^        run: \|$/ { body = 1; next }
    body && (/^          / || /^$/) { sub(/^          /, ""); print; next }
    body { exit }
  ' "$workflow"
}
for step in "Resolve the base spec:resolve" "Compare with oasdiff:compare" "Gate breaking changes:gate"; do
  extract "${step%%:*}" > "$tmp/${step##*:}.sh"
  [[ -s "$tmp/${step##*:}.sh" ]] || fail "api-contract.yml has no \"${step%%:*}\" step"
done

mkdir -p "$tmp/bin" "$tmp/work/head/contract" "$tmp/work/base/contract"
# Stub: zapisuje wywołanie i odgrywa oasdiff — `changelog` wypisuje zmiany, `breaking` kończy się STUB_RC.
cat > "$tmp/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$DOCKER_LOG"
for arg in "$@"; do case "$arg" in changelog) echo "- removed GET /pets/{id}"; exit 0 ;; breaking) echo "error api-path-removed"; exit "${STUB_RC:-0}" ;; esac; done
exit 64
STUB
chmod +x "$tmp/bin/docker"
cd "$tmp/work"
echo "openapi: 3.1.0" > head/contract/openapi.yaml
echo "openapi: 3.1.0" > head/contract/base.yaml
export PATH="$tmp/bin:$PATH" DOCKER_LOG="$tmp/docker.log" GITHUB_OUTPUT="$tmp/output" GITHUB_STEP_SUMMARY="$tmp/summary"
run() { : > "$GITHUB_OUTPUT"; : > "$GITHUB_STEP_SUMMARY"; bash "$tmp/$1.sh" > "$tmp/out.txt" 2>&1; }
# Runner GitHuba odpala `run:` bez jawnego `shell:` jako `bash -e {0}` — errexit jest włączony, zanim skrypt
# cokolwiek ustawi, a `set -uo pipefail` go nie zdejmuje.
run_on_runner() { : > "$GITHUB_OUTPUT"; : > "$GITHUB_STEP_SUMMARY"; bash -e "$tmp/$1.sh" > "$tmp/out.txt" 2>&1; }

# Rozwiązanie bazy.
SPEC=contract/openapi.yaml BASE_SPEC=contract/base.yaml BASE_SHA='' run resolve || fail "base-spec-path must resolve: $(cat "$tmp/out.txt")"
grep -qx 'base=head/contract/base.yaml' "$GITHUB_OUTPUT" || fail 'base-spec-path must be read from the checked-out revision'
if SPEC=contract/missing.yaml BASE_SPEC='' BASE_SHA=abc run resolve; then fail 'a missing spec-path must fail'; fi
grep -q 'spec-path contract/missing.yaml does not exist' "$tmp/out.txt" || fail "unexpected message: $(cat "$tmp/out.txt")"
if SPEC=contract/openapi.yaml BASE_SPEC='' BASE_SHA='' run resolve; then fail 'outside a pull request without base-spec-path the step must fail'; fi
grep -q 'call it on pull_request or pass base-spec-path' "$tmp/out.txt" || fail "unexpected message: $(cat "$tmp/out.txt")"
SPEC=contract/openapi.yaml BASE_SPEC='' BASE_SHA=abc run resolve || fail "a spec new in this pull request must not fail: $(cat "$tmp/out.txt")"
grep -qx 'skip=true' "$GITHUB_OUTPUT" || fail 'a spec absent at the base must skip the comparison'
echo "openapi: 3.1.0" > base/contract/openapi.yaml
SPEC=contract/openapi.yaml BASE_SPEC='' BASE_SHA=abc run resolve || fail "the base checkout must resolve: $(cat "$tmp/out.txt")"
grep -qx 'base=base/contract/openapi.yaml' "$GITHUB_OUTPUT" || fail 'the spec must be read from the base checkout'

# Porównanie: kod wyjścia oasdiff breaking -> output breaking.
export BASE=base/contract/openapi.yaml SPEC=contract/openapi.yaml IMAGE=tufin/oasdiff@sha256:stub
: > "$DOCKER_LOG"
SKIP=true FAIL_ON=ERR run compare || fail "a skipped comparison must pass: $(cat "$tmp/out.txt")"
grep -qx 'breaking=false' "$GITHUB_OUTPUT" || fail 'a skipped comparison is not breaking'
[[ ! -s "$DOCKER_LOG" ]] || fail 'a skipped comparison must not run oasdiff'
STUB_RC=0 SKIP='' FAIL_ON=ERR run compare || fail "a compatible change must pass: $(cat "$tmp/out.txt")"
grep -qx 'breaking=false' "$GITHUB_OUTPUT" || fail 'exit code 0 means not breaking'
grep -qF "## OpenAPI changes in \`contract/openapi.yaml\`" "$GITHUB_STEP_SUMMARY" || fail 'the changelog must reach the job summary'
grep -q 'removed GET /pets/{id}' "$GITHUB_STEP_SUMMARY" || fail 'the summary must carry the oasdiff changelog'
grep -q -- '--network none' "$DOCKER_LOG" || fail 'oasdiff must run without network access'
grep -q -- 'tufin/oasdiff@sha256:stub breaking base/contract/openapi.yaml head/contract/openapi.yaml --fail-on ERR' "$DOCKER_LOG" \
  || fail "unexpected oasdiff call: $(cat "$DOCKER_LOG")"
STUB_RC=1 SKIP='' FAIL_ON=WARN run compare || fail "the comparison itself must pass on a breaking change: $(cat "$tmp/out.txt")"
grep -qx 'breaking=true' "$GITHUB_OUTPUT" || fail 'exit code 1 means breaking'
if STUB_RC=2 SKIP='' FAIL_ON=ERR run compare; then fail 'an oasdiff error must fail the step'; fi
grep -q 'oasdiff breaking failed with exit code 2' "$tmp/out.txt" || fail "unexpected message: $(cat "$tmp/out.txt")"
if SKIP='' FAIL_ON=error run compare; then fail 'an unknown fail-on level must fail'; fi
grep -q 'fail-on must be ERR, WARN or INFO' "$tmp/out.txt" || fail "unexpected message: $(cat "$tmp/out.txt")"

# Regresja: pod `bash -e` runnera kod wyjścia 1 ubijał krok bez komunikatu, zanim `rc=$?` go odczytał,
# więc para łamiąca w ci.yml (fail-on-breaking: false) kończyła się czerwono, a etykieta nie miała szans.
STUB_RC=1 SKIP='' FAIL_ON=ERR run_on_runner compare \
  || fail "under the runner's bash -e a breaking change must still pass the comparison: $(cat "$tmp/out.txt")"
grep -qx 'breaking=true' "$GITHUB_OUTPUT" || fail "under the runner's bash -e exit code 1 must still mean breaking"
grep -q 'error api-path-removed' "$tmp/out.txt" || fail 'the breaking changes must reach the log'
if STUB_RC=2 SKIP='' FAIL_ON=ERR run_on_runner compare; then fail "under the runner's bash -e an oasdiff error must fail the step"; fi
grep -q 'oasdiff breaking failed with exit code 2' "$tmp/out.txt" || fail "an oasdiff error must be named under bash -e: $(cat "$tmp/out.txt")"

# Bramka: etykieta przepuszcza zmianę łamiącą, brak etykiety ją blokuje.
export FAIL_ON=ERR ALLOW_LABEL=api-breaking
LABELS='["api-breaking","docs"]' run gate || fail "the allow label must let the change through: $(cat "$tmp/out.txt")"
grep -q '::warning::Breaking OpenAPI change at level ERR or above, allowed by the api-breaking label' "$tmp/out.txt" || fail 'an allowed break must still warn'
if LABELS='["docs"]' run gate; then fail 'a breaking change without the label must fail'; fi
grep -q 'label the pull request api-breaking and say why' "$tmp/out.txt" || fail "unexpected message: $(cat "$tmp/out.txt")"
if LABELS='null' run gate; then fail 'a run outside a pull request has no labels and must fail'; fi
if LABELS='["api-breaking"]' ALLOW_LABEL='' run gate; then fail 'an empty allow-label must not let anything through'; fi

echo 'OK: api-contract.yml resolves the base spec, maps oasdiff results and gates breaking changes on the label'
