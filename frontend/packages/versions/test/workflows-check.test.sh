#!/usr/bin/env bash
# platform-workflows-check: callerzy reusable workflowów Platform kontra snapshot kontraktu wydania. Kopia
# snapshotu w paczce musi równać się templates/tests/fixtures/workflow-contract.txt (źródło, które pilnuje
# workflow-contract.test.sh).
# shellcheck disable=SC2016 # the fixtures carry literal GitHub ${{ }} expressions
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "--- output ---" >&2; cat "$tmp/out" >&2; exit 1; }
: > "$tmp/out"
cmp -s "$here/../workflow-contract.txt" "$here/../../../../templates/tests/fixtures/workflow-contract.txt" \
  || fail 'frontend/packages/versions/workflow-contract.txt differs from the snapshot; copy templates/tests/fixtures/workflow-contract.txt over it'

# repo <name> <file> <content>: katalog z jednym workflowem
repo() { mkdir -p "$tmp/$1/.github/workflows"; printf '%s\n' "$3" > "$tmp/$1/.github/workflows/$2"; }
check() {
  set +e
  python3 "$here/../bin/workflows-check.py" --ref v1.5.31 --root "$tmp/$1" > "$tmp/out" 2>&1
  rc=$?
  set -e
}

repo attestate ci.yml 'name: CI
permissions:
  contents: read
jobs:
  backend:
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.5.31
    secrets: inherit'
check attestate
[[ $rc -eq 1 ]] || fail "Attestate's caller must fail, got $rc"
grep -qF 'ERROR .github/workflows/ci.yml:6 job backend calls backend-ci.yml@v1.5.31: grants packages: none, the workflow needs packages: read' "$tmp/out" \
  || fail 'the missing packages: read must be named with file and line'
grep -qF 'WARN .github/workflows/ci.yml:6 job backend calls backend-ci.yml@v1.5.31: secrets: inherit' "$tmp/out" || fail 'secrets: inherit must warn'

repo touchstone ci.yml 'permissions:
  contents: read
  packages: read
jobs:
  backend:
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.5.31
    with:
      working-directory: backend
    secrets:
      gpr_token: ${{ secrets.GPR_TOKEN }}
  contract:
    permissions: { contents: read }
    uses: DominikSienkiewicz/Platform/.github/workflows/api-contract.yml@v1.5.31
    with:
      spec-path: contract/openapi.yaml'
check touchstone
[[ $rc -eq 0 ]] || fail "Touchstone's caller must pass, got $rc"
if grep -q '^WARN\|^ERROR' "$tmp/out"; then fail 'an exact, complete caller must pass without findings'; fi

repo drift ci.yml 'jobs:
  backend:
    permissions: read-all
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1
    with:
      workdir: backend
    secrets:
      GPR_TOKEN: ${{ secrets.GPR_TOKEN }}
  contract:
    uses: DominikSienkiewicz/Platform/.github/workflows/api-contract.yml@v1.5.31
  bump:
    permissions: read-all
    uses: DominikSienkiewicz/Platform/.github/workflows/platform-bump.yml@v1.5.31
  missing:
    uses: DominikSienkiewicz/Platform/.github/workflows/no-such.yml@v1.5.31'
check drift
[[ $rc -eq 1 ]] || fail "a drifted caller must fail, got $rc"
for expected in \
  'ERROR .github/workflows/ci.yml:4 job backend calls backend-ci.yml@v1: input workdir is not declared by backend-ci.yml' \
  'ERROR .github/workflows/ci.yml:4 job backend calls backend-ci.yml@v1: secret GPR_TOKEN is not declared by backend-ci.yml' \
  'WARN .github/workflows/ci.yml:4 job backend calls backend-ci.yml@v1: checked against the contract of v1.5.31' \
  'ERROR .github/workflows/ci.yml:10 job contract calls api-contract.yml@v1.5.31: required input spec-path is missing' \
  "WARN .github/workflows/ci.yml:10 job contract calls api-contract.yml@v1.5.31: no permissions block, so it depends on the repository's default token permissions" \
  'ERROR .github/workflows/ci.yml:13 job bump calls platform-bump.yml@v1.5.31: grants contents: read, the workflow needs contents: write' \
  'ERROR .github/workflows/ci.yml:15 job missing calls no-such.yml@v1.5.31: v1.5.31 has no reusable workflow no-such.yml'; do
  grep -qF "$expected" "$tmp/out" || fail "missing finding: $expected"
done
if grep -qF 'job backend calls backend-ci.yml@v1: grants' "$tmp/out"; then fail 'read-all covers the read permissions of backend-ci'; fi

echo 'OK: platform-workflows-check holds callers to the permissions, inputs and secrets of the reusable workflow contract'
