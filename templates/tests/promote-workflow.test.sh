#!/usr/bin/env bash
# promote.yml i przypięty przez niego deploy.yml, przypadek po przypadku: preflight i pin wołanego deploy.yml, uprawnienia
# podpisu (id-token może nadać tylko job build) i tryb jednego obrazu. Bloki wycięte z workflowów biegną na atrapach.
# Wspólne helpery (fail, job) są w lib/workflow.sh.
# shellcheck disable=SC2016 # dosłowne wyrażenia GitHuba
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/workflow.sh
source "$(dirname "$0")/lib/workflow.sh"
# shellcheck disable=SC2034 # workflow czyta lib/workflow.sh
workflow="$root/.github/workflows/promote.yml"

# --- deploy-and-promote ---
# deploy.yml z drzewa nie ma ścieżki SSH: tylko buduje, skanuje i podpisuje. promote.yml buduje przez deploy.yml
# przypięty po SHA (1.10.1, z ssh-deploy: false) i zapisuje tagi w repozytorium GitOps. Blok preflightu jest wycinany
# między znacznikami i uruchamiany.
(
deploy="$root/.github/workflows/deploy.yml"
promote="$root/.github/workflows/promote.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

[[ -f "$promote" ]] || fail 'promote.yml does not exist'

# --- deploy.yml z drzewa (nie ten przypięty w promote.yml): build, skan i podpis, bez wdrożenia SSH ---
grep -qE '^  deploy:$' "$deploy" && fail 'deploy.yml must have no deploy job: Argo CD deploys what promote.yml commits'
grep -qE '^      ssh-deploy:$' "$deploy" && fail 'deploy.yml must not declare the ssh-deploy input: it deploys nothing over SSH'
grep -q 'SSH_' "$deploy" && fail 'deploy.yml must not declare or read SSH_ secrets'
grep -qE '^    environment:' "$deploy" && fail 'no job of deploy.yml runs in an environment: none deploys'
for output in backend-tag frontend-tag; do
  grep -qE "^      $output:$" "$deploy" || fail "deploy.yml must expose the $output output"
done
grep -qF 'value: ${{ jobs.versions.outputs.backend }}' "$deploy" || fail 'backend-tag must come from jobs.versions.outputs.backend'
grep -qF 'value: ${{ jobs.versions.outputs.frontend }}' "$deploy" || fail 'frontend-tag must come from jobs.versions.outputs.frontend'

[[ "$(grep -cFx '          fail-build: true' "$deploy")" == 2 ]] || fail 'both Grype steps must keep fail-build: true: the scan is the gate of every promotion'
grep -q 'fail-build: false' "$deploy" && fail 'no Grype step may set fail-build: false'

# --- deploy.yml: preflight ---
awk 'index($0, "# >>> preflight") { inside = 1; next } index($0, "# <<< preflight") { inside = 0 } inside { sub(/^          /, ""); print }' \
  "$deploy" > "$tmp/preflight.sh"
[[ -s "$tmp/preflight.sh" ]] || fail 'deploy.yml has no preflight block between its markers'
(env -u DEPLOY_PATH GPR_USER=u GPR_KEY=k NPM_GH_TOKEN=n GHCR_OWNER=o bash "$tmp/preflight.sh") > "$tmp/out" 2>&1 \
  || fail 'the preflight must not require DEPLOY_PATH: nothing deploys over SSH'
(env -u GPR_KEY GPR_USER=u NPM_GH_TOKEN=n GHCR_OWNER=o bash "$tmp/preflight.sh") > "$tmp/out" 2>&1 \
  && fail 'the preflight must require GPR_KEY'
grep -qF 'GPR_KEY' "$tmp/out" || fail 'the preflight must name GPR_KEY when it is missing'

# --- promote.yml ---
# A caller pins promote.yml to an annotated tag. GitHub looks a relative reference in the called workflow up at the tag
# object instead of its commit, and the run fails at startup with "workflow was not found" (ADR-0035).
grep -qE '^[[:space:]]+(- )?uses: *(\./|\$/)' "$promote" \
  && fail 'promote.yml must not use a relative reference: called through an annotated tag it fails with "workflow was not found"'
build_uses=$(sed -n '/^  build:$/,/^  promote:$/p' "$promote" | grep -E '^    uses: ' || true)
[[ "$build_uses" =~ ^\ {4}uses:\ SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/\.github/workflows/deploy\.yml@[0-9a-f]{40}\ \#\ v([0-9]+\.[0-9]+\.[0-9]+)$ ]] \
  || fail 'promote.yml must call deploy.yml by its full reference at a commit SHA with a # vX.Y.Z comment'
# Przypięty deploy.yml deklaruje ssh-deploy (domyślnie true) i platform-ref od v1.8.9 do 1.13.0, które je usuwa. Pin
# i wejścia przesuwa razem późniejsze wydanie, gdy tag 1.13.0 już istnieje (action-pins, RELEASING.md). Płytki
# checkout CI nie ma przypiętego pliku, więc wejścia to dokładny blok with: przypiętego deploy.yml, a nie deploy.yml z drzewa.
pinned=${BASH_REMATCH[1]}
printf '1.8.9\n%s\n' "$pinned" | sort -C -V || fail 'deploy.yml has the ssh-deploy input since v1.8.9: promote.yml must not pin an older one'
if [[ "$pinned" == 1.13.0 ]] || ! printf '%s\n1.13.0\n' "$pinned" | sort -C -V; then
  fail "promote.yml passes ssh-deploy and platform-ref, which deploy.yml drops in v1.13.0: move the pin (v$pinned) together with the build inputs"
fi
grep -qE '^      ssh-deploy: false$' "$promote" || fail 'promote.yml must call deploy.yml with ssh-deploy: false, or the pinned deploy.yml deploys over SSH'
build_with=$(sed -n '/^  build:$/,/^  promote:$/p' "$promote" | awk '/^    with:$/ { p = 1; next } p && /^      / { print; next } p { exit }')
expected_with='      app-name: ${{ inputs.app-name }}
      ssh-deploy: false
      scan-images: true
      has-migrate: false
      single-image: ${{ inputs.single-image }}
      platform-ref: ${{ inputs.platform-ref }}
      build-timeout-minutes: ${{ inputs.build-timeout-minutes }}'
[[ "$build_with" == "$expected_with" ]] \
  || fail "the build job must pass the pinned deploy.yml exactly the inputs of the pinned deploy.yml, got: $(paste -sd'|' - <<< "$build_with")"
grep -qE '^      scan-images: true$' "$promote" || fail 'promote.yml must scan the images'
grep -qE '^      has-migrate: false$' "$promote" || fail 'promote.yml must build without a migration image'
grep -qE 'secrets:[[:space:]]*inherit' "$promote" && fail 'promote.yml must pass secrets explicitly, never inherit'
grep -q 'SSH_' "$promote" && fail 'promote.yml must not mention SSH_ secrets'
grep -q 'rollback-to' "$promote" && fail 'promote.yml has no rollback inputs: a rollback is a revert of the commit'
grep -qE '^concurrency:' "$promote" && fail 'promote.yml must not set concurrency: deploy.yml has its own group, and the same one would deadlock'
grep -qE 'java-version' "$promote" && fail 'promote.yml declares no Java inputs'
for input in app-name infra-repository values-dir promote-app-id platform-ref build-timeout-minutes promote-timeout-minutes; do
  grep -qE "^      $input:$" "$promote" || fail "promote.yml must declare the $input input"
done
for secret in GPR_USER GPR_KEY NPM_GH_TOKEN SNYK_TOKEN PROMOTE_APP_KEY; do
  grep -qE "^      $secret:$" "$promote" || fail "promote.yml must declare the $secret secret"
done
platform_ref=$(sed -n '/^      platform-ref:$/,/^      [a-z-]*:$/p' "$promote")
grep -qE '^        required: true$' <<<"$platform_ref" || fail 'platform-ref must be required'
if grep -qE '^        default:' <<<"$platform_ref"; then fail 'platform-ref must have no default (no floating v1)'; fi

# --- promote.yml: preflight ustawień promocji, zanim ruszy build ---
promote_preflight_job=$(sed -n '/^  preflight:$/,/^  build:$/p' "$promote")
[[ -n "$promote_preflight_job" ]] || fail 'promote.yml must have a preflight job before build'
grep -qE '^    timeout-minutes: [0-9]+$' <<< "$promote_preflight_job" || fail 'the promote preflight job needs a time limit'
grep -qFx '          PROMOTE_APP_ID: ${{ inputs.promote-app-id }}' <<< "$promote_preflight_job" || fail 'the promote preflight must pass inputs.promote-app-id as PROMOTE_APP_ID in its env:'
grep -qFx '          PROMOTE_APP_KEY: ${{ secrets.PROMOTE_APP_KEY }}' <<< "$promote_preflight_job" || fail 'the promote preflight must pass secrets.PROMOTE_APP_KEY as PROMOTE_APP_KEY in its env:'
grep -qE '^    needs: preflight$' <(sed -n '/^  build:$/,/^  promote:$/p' "$promote") || fail 'build must wait for the promote preflight'

awk 'index($0, "# >>> promote-preflight") { inside = 1; next } index($0, "# <<< promote-preflight") { inside = 0 } inside { sub(/^          /, ""); print }' \
  "$promote" > "$tmp/promote-preflight.sh"
[[ -s "$tmp/promote-preflight.sh" ]] || fail 'promote.yml has no promote-preflight block between its markers'
promote_preflight() {
  (env PROMOTE_APP_ID="$1" PROMOTE_APP_KEY="$2" bash "$tmp/promote-preflight.sh") > "$tmp/out" 2>&1
}
promote_preflight id secret-key-value || fail 'the promote preflight must pass when both settings are set'
promote_preflight '' secret-key-value && fail 'the promote preflight must fail without promote-app-id'
grep -qF 'PROMOTE_APP_ID' "$tmp/out" || fail 'the promote preflight must name PROMOTE_APP_ID when it is missing'
promote_preflight id '' && fail 'the promote preflight must fail without PROMOTE_APP_KEY'
grep -qF 'PROMOTE_APP_KEY' "$tmp/out" || fail 'the promote preflight must name PROMOTE_APP_KEY when it is missing'
promote_preflight '' '' && fail 'the promote preflight must fail when both are missing'
promote_preflight id secret-key-value || true
grep -qF 'secret-key-value' "$tmp/out" && fail 'the promote preflight must not print the key'
promote_preflight '' secret-key-value || true
grep -qF 'secret-key-value' "$tmp/out" && fail 'the promote preflight must not print the key on failure'

build_job=$(sed -n '/^  build:$/,/^  promote:$/p' "$promote")
promote_job=$(sed -n '/^  promote:$/,$p' "$promote")
[[ "$(grep -cE '^      (contents: read|packages: write)$' <<< "$build_job")" == 2 ]] \
  || fail 'the build job needs permissions contents: read and packages: write'
grep -qE '^    needs: build$' <<< "$promote_job" || fail 'promote must wait for build'
grep -qFx "    if: \${{ needs.build.result == 'success' }}" <<< "$promote_job" || fail 'promote must run only when build succeeded, with no other way in'
grep -qE '^      contents: read$' <<< "$promote_job" || fail 'the promote job needs contents: read'
grep -qE '^      contents: write' <<< "$promote_job" && fail 'the workflow token of promote must not write; the App token does'

token_pin=$(grep -E 'uses: actions/create-github-app-token@' "$promote" || true)
[[ "$token_pin" =~ @[0-9a-f]{40}\ \#\ v[0-9]+\.[0-9]+\.[0-9]+ ]] || fail 'the token action must be pinned to a commit SHA with a # vX.Y.Z comment'
grep -qE '^          repositories: ' "$promote" || fail 'the App token must be limited to one repository'
grep -qE '^          permission-contents: write$' "$promote" || fail 'the App token must carry only contents: write'
grep -qFx '      BACKEND_TAG: ${{ needs.build.outputs.backend-tag }}' <<< "$promote_job" || fail 'BACKEND_TAG must be the backend-tag output of build'
grep -qFx '      FRONTEND_TAG: ${{ needs.build.outputs.frontend-tag }}' <<< "$promote_job" || fail 'FRONTEND_TAG must be the frontend-tag output of build'
# shellcheck disable=SC1003 # a backslash, not an escaped quote
continued=$(printf ' \\') # a shell line continuation, spelled once to keep the quoting readable
grep -qFx "            \"\$VALUES_DIR/values-backend.yaml=\$BACKEND_TAG\"$continued" "$promote" || fail 'values-backend.yaml must get the backend tag'
grep -qFx '            "$VALUES_DIR/values-frontend.yaml=$FRONTEND_TAG"' "$promote" || fail 'values-frontend.yaml must get the frontend tag'
grep -qFx "            \"chore: promote \$APP_NAME to backend \$BACKEND_TAG, frontend \$FRONTEND_TAG\"$continued" "$promote" || fail 'the commit message must name both tags'
target_checkout=$(sed -n '/^      - name: Check out the GitOps repository$/,/^      - name: Fetch promote-image.sh/p' "$promote")
grep -qFx '          repository: ${{ inputs.infra-repository }}' <<< "$target_checkout" || fail 'the target checkout must take infra-repository'
grep -qFx '          token: ${{ steps.app-token.outputs.token }}' <<< "$target_checkout" || fail 'the target checkout must use the App token, which the script pushes with'
grep -q 'persist-credentials' <<< "$target_checkout" && fail 'the target checkout must keep its credentials: the script pushes'
grep -qE '^          path: _platform$' "$promote" || fail 'the scripts must come from a _platform checkout'
grep -qE 'persist-credentials: false' <(sed -n '/path: _platform/,/^      - /p' "$promote") || fail 'the _platform checkout must not keep credentials'
grep -qF 'scripts/promote-image.sh' "$promote" || fail 'promote must run scripts/promote-image.sh'
for file in values-backend.yaml values-frontend.yaml; do
  grep -qF "$file=" "$promote" || fail "promote must write $file"
done
awk '/^        run: \|$/ { r = 1; next } /^      - |^        [a-z-]+:/ { r = 0 } r' "$promote" | grep -qE '\$\{\{ *inputs\.' \
  && fail 'values reach run steps through env:, never expanded inside a script'

echo 'OK: deploy.yml deploys nothing over SSH; promote.yml builds through its pinned deploy.yml with ssh-deploy: false and commits the tags'
)

# --- signed-images ---
# Promocja podpisuje obrazy (ADR-0036): job build w promote.yml woła deploy.yml z wydania, które ma job sign, i nadaje
# mu id-token: write, bo GitHub sprawdza uprawnienia każdego zagnieżdżonego joba, zanim run ruszy. Tożsamość podpisu
# ma tylko job sign w deploy.yml: preflight i promote w promote.yml nie dostają id-token.
(
# grants TEKST WCIĘCIE: wpisy bloku permissions (joba albo workflowu), którego nagłówek ma podane wcięcie.
grants() { awk -v head="${2}permissions:" '$0 == head { p = 1; next } p && /^ +[a-z-]+: / { sub(/^ +/, ""); print; next } p { exit }' <<< "$1"; }

# --- build: deploy.yml z wydania, które podpisuje, z uprawnieniami joba sign ---
build=$(job build)
pin=$(grep -E '^    uses: SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/\.github/workflows/deploy\.yml@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' <<< "$build" \
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
)

# --- single-image ---
# Tryb jednego obrazu w promote.yml (single-image): build idzie przez deploy.yml w tym samym trybie, a promocja zapisuje
# jeden tag w values.yaml. Bez wejścia promote.yml działa jak dotąd (dwa pliki, promote-workflow.test.sh). Blok commitu
# jednego obrazu jest wycinany między znacznikami i uruchamiany z atrapą promote-image.sh.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
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
pin=$(grep -E '^    uses: SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/\.github/workflows/deploy\.yml@[0-9a-f]{40} # v' <<< "$build" | sed 's/.*# v//' || true)
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
)
