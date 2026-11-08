#!/usr/bin/env bash
# Tryb jednego obrazu w promote.yml (single-image): build idzie przez deploy.yml w tym samym trybie, a promocja zapisuje
# jeden tag w values.yaml. Bez wejścia promote.yml działa jak dotąd (dwa pliki, promote-workflow.test.sh). Blok commitu
# jednego obrazu jest wycinany między znacznikami i uruchamiany z atrapą promote-image.sh.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/promote.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" 2>/dev/null >&2 || true; exit 1; }
job() { awk -v start="  $1:" '$0 == start { p = 1; next } /^  [a-z-]+:$/ { p = 0 } p' "$workflow"; }
# step JOB NAME: krok o dokładnie tej nazwie, do następnego kroku.
step() { awk -v name="      - name: $2" '$0 == name { p = 1; print; next } p && /^      - / { p = 0 } p' <<< "$(job "$1")"; }

# --- wejście ---
input=$(sed -n '/^      single-image:$/,/^      [a-z-]*:$/p' "$workflow")
[[ -n "$input" ]] || fail 'promote.yml must declare the single-image input'
grep -qFx '        type: boolean' <<< "$input" || fail 'single-image must be a boolean'
grep -qFx '        default: false' <<< "$input" || fail 'single-image must default to false, so a consumer of two images behaves as before'

# --- build: deploy.yml w tym samym trybie, z wydania, które go ma ---
build=$(job build)
grep -qFx '      single-image: ${{ inputs.single-image }}' <<< "$build" || fail 'build must pass inputs.single-image to deploy.yml'
pin=$(grep -E '^    uses: DominikSienkiewicz/Platform/\.github/workflows/deploy\.yml@[0-9a-f]{40} # v' <<< "$build" | sed 's/.*# v//' || true)
[[ -n "$pin" ]] || fail 'build must call deploy.yml at a commit SHA with a # vX.Y.Z comment'
printf '1.8.11\n%s\n' "$pin" | sort -C -V \
  || fail "deploy.yml has the single-image input since v1.8.11: promote.yml must not pin an older one, got v$pin"

# --- promote: dwa obrazy jak dotąd, jeden obraz do values.yaml ---
two=$(step promote 'Commit the new image tags')
[[ -n "$two" ]] || fail "promote must keep the step 'Commit the new image tags'"
grep -qFx '        if: ${{ !inputs.single-image }}' <<< "$two" || fail 'the commit of two tags must run only without single-image'
one=$(step promote 'Commit the new image tag')
[[ -n "$one" ]] || fail "promote must have the step 'Commit the new image tag'"
grep -qFx '        if: ${{ inputs.single-image }}' <<< "$one" || fail 'the commit of one tag must run only with single-image'

awk 'index($0, "# >>> promote-single") { inside = 1; next } index($0, "# <<< promote-single") { inside = 0 } inside { sub(/^          /, ""); print }' \
  <<< "$one" > "$tmp/promote-single.sh"
[[ -s "$tmp/promote-single.sh" ]] || fail "the step 'Commit the new image tag' has no promote-single block between its markers"
grep -qF 'FRONTEND_TAG' "$tmp/promote-single.sh" && fail 'the commit of one tag must not read the empty frontend tag'
mkdir -p "$tmp/work/_platform/scripts"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$ARGS"\n' > "$tmp/work/_platform/scripts/promote-image.sh"
(cd "$tmp/work" && env ARGS="$tmp/args" APP_NAME=training BACKEND_TAG=0.1.0 FRONTEND_TAG='' \
  VALUES_DIR=clusters/prod/training bash "$tmp/promote-single.sh") > "$tmp/out" 2>&1 || fail 'the promote-single block must run'
expected=$'chore: promote training to 0.1.0\nclusters/prod/training/values.yaml=0.1.0'
[[ "$(cat "$tmp/args")" == "$expected" ]] \
  || fail "one image must commit only values.yaml with its tag, got: $(paste -sd'|' - < "$tmp/args")"

# --- kontrakt dla platform-workflows-check ---
for contract in "$root/frontend/packages/versions/workflow-contract.txt" "$root/templates/tests/fixtures/workflow-contract.txt"; do
  grep -qFx 'promote.yml input single-image type=boolean default=false' "$contract" \
    || fail "${contract#"$root"/} must list the single-image input of promote.yml"
done

echo 'OK: single-image promotes one tag to values.yaml through deploy.yml in the same mode; two images are unchanged'
