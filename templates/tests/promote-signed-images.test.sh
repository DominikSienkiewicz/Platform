#!/usr/bin/env bash
# Promocja podpisuje obrazy (ADR-0036): job build w promote.yml woła deploy.yml z wydania, które ma job sign, i nadaje
# mu id-token: write, bo GitHub sprawdza uprawnienia każdego zagnieżdżonego joba, zanim run ruszy. Tożsamość podpisu
# ma tylko job sign w deploy.yml: preflight i promote w promote.yml nie dostają id-token.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/promote.yml"
fail() { echo "FAIL: $*" >&2; exit 1; }
job() { awk -v start="  $1:" '$0 == start { p = 1; next } /^  [a-z-]+:$/ { p = 0 } p' "$workflow"; }
# grants TEKST WCIĘCIE: wpisy bloku permissions (joba albo workflowu), którego nagłówek ma podane wcięcie.
grants() { awk -v head="${2}permissions:" '$0 == head { p = 1; next } p && /^ +[a-z-]+: / { sub(/^ +/, ""); print; next } p { exit }' <<< "$1"; }

# --- build: deploy.yml z wydania, które podpisuje, z uprawnieniami joba sign ---
build=$(job build)
pin=$(grep -E '^    uses: DominikSienkiewicz/Platform/\.github/workflows/deploy\.yml@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' <<< "$build" \
  | sed 's/.*# v//' || true)
[[ -n "$pin" ]] || fail 'build must call deploy.yml at a commit SHA with a # vX.Y.Z comment'
printf '1.9.0\n%s\n' "$pin" | sort -C -V \
  || fail "deploy.yml signs the scanned images since v1.9.0: promote.yml must not pin an older one, got v$pin"
# Do 1.10.0 sign tracił referencje obrazów, gdy właściciel był wartością sekretu (GPR_USER konsumenta), a Trivy tracił
# miejsce na dysku przy czterech obrazach; obie poprawki ma deploy.yml od v1.10.1.
printf '1.10.1\n%s\n' "$pin" | sort -C -V \
  || fail "deploy.yml signs when the owner is a secret value and frees the disk for Trivy since v1.10.1: promote.yml must not pin an older one, got v$pin"
grep -qFx '      scan-images: true' <<< "$build" || fail 'build must call deploy.yml with scan-images: true, or nothing is signed'
build_grants=$(grants "$build" '    ')
for grant in 'contents: read' 'packages: write' 'id-token: write'; do
  grep -qFx "$grant" <<< "$build_grants" \
    || fail "the build job must grant $grant: the sign job of deploy.yml requests id-token: write and packages: write"
done

# --- nikt poza build nie dostaje id-token ---
for name in preflight promote; do
  grep -q 'id-token' <<< "$(job "$name")" && fail "the $name job must not get id-token: write; only the sign job of deploy.yml signs"
done
grep -q 'id-token' <<< "$(grants "$(cat "$workflow")" '')" && fail 'the top-level permissions of promote.yml must not grant id-token: write'

# --- kontrakt dla platform-workflows-check: caller nadaje id-token: write ---
for contract in "$root/frontend/packages/versions/workflow-contract.txt" "$root/templates/tests/fixtures/workflow-contract.txt"; do
  grep -qFx 'promote.yml job build permissions id-token: write' "$contract" \
    || fail "${contract#"$root"/} must list id-token: write for the build job of promote.yml"
done

echo 'OK: promote.yml pins a deploy.yml that signs, and only its build job grants id-token: write'
