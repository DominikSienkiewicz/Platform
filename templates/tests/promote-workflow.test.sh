#!/usr/bin/env bash
# deploy.yml z drzewa nie ma ścieżki SSH: tylko buduje, skanuje i podpisuje. promote.yml buduje przez deploy.yml
# przypięty po SHA (1.10.1, z ssh-deploy: false) i zapisuje tagi w repozytorium GitOps. Blok preflightu jest wycinany
# między znacznikami i uruchamiany.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
deploy="$root/.github/workflows/deploy.yml"
promote="$root/.github/workflows/promote.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" 2>/dev/null >&2 || true; exit 1; }

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
[[ "$build_uses" =~ ^\ {4}uses:\ DominikSienkiewicz/Platform/\.github/workflows/deploy\.yml@[0-9a-f]{40}\ \#\ v([0-9]+\.[0-9]+\.[0-9]+)$ ]] \
  || fail 'promote.yml must call deploy.yml by its full reference at a commit SHA with a # vX.Y.Z comment'
# Przypięty deploy.yml deklaruje ssh-deploy (domyślnie true) i platform-ref od v1.8.9 do 1.13.0, które je usuwa. Pin
# i wejścia przesuwa razem późniejsze wydanie, gdy tag 1.13.0 już istnieje (action-pins, RELEASING.md). Płytki
# checkout CI nie ma przypiętego pliku, więc wejścia to dokładny blok with: z 1.12.0, a nie deploy.yml z drzewa.
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
  || fail "the build job must pass the pinned deploy.yml exactly the inputs of 1.12.0, got: $(paste -sd'|' - <<< "$build_with")"
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
grep -qE '^        default: "v1"$' <(sed -n '/^      platform-ref:$/,/^      [a-z-]*:$/p' "$promote") || fail 'platform-ref must default to v1'

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
