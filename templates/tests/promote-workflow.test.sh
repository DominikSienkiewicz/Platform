#!/usr/bin/env bash
# promote.yml i wejście ssh-deploy w deploy.yml: promocja buduje przez deploy.yml bez SSH i zapisuje tagi w repozytorium
# GitOps; konsument SSH bez nowego wejścia działa jak dotąd. Blok preflightu jest wycinany między znacznikami i uruchamiany.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
deploy="$root/.github/workflows/deploy.yml"
promote="$root/.github/workflows/promote.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" 2>/dev/null >&2 || true; exit 1; }

[[ -f "$promote" ]] || fail 'promote.yml does not exist'

# --- deploy.yml: ssh-deploy ---
grep -qE '^      ssh-deploy:$' "$deploy" || fail 'deploy.yml must declare the ssh-deploy input'
grep -qE '^        default: true$' <(sed -n '/^      ssh-deploy:$/,/^      [a-z-]*:$/p' "$deploy") \
  || fail 'ssh-deploy must default to true, so an SSH consumer without the input behaves as before'
grep -qE '^        type: boolean$' <(sed -n '/^      ssh-deploy:$/,/^      [a-z-]*:$/p' "$deploy") || fail 'ssh-deploy must be a boolean'
grep -qF 'inputs.ssh-deploy' <(sed -n '/^  deploy:/,/^    runs-on:/p' "$deploy") || fail 'the deploy job must be gated by inputs.ssh-deploy'
for output in backend-tag frontend-tag; do
  grep -qE "^      $output:$" "$deploy" || fail "deploy.yml must expose the $output output"
done
grep -qF 'value: ${{ jobs.versions.outputs.backend }}' "$deploy" || fail 'backend-tag must come from jobs.versions.outputs.backend'
grep -qF 'value: ${{ jobs.versions.outputs.frontend }}' "$deploy" || fail 'frontend-tag must come from jobs.versions.outputs.frontend'

deploy_job=$(sed -n '/^  deploy:$/,/^    runs-on:/p' "$deploy")
grep -qFx "    if: \${{ !cancelled() && inputs.ssh-deploy && needs.versions.result == 'success' && (needs.build-push.result == 'success' || needs.build-push.result == 'skipped') }}" <<< "$deploy_job" \
  || fail 'the deploy job must run exactly when ssh-deploy is true, the versions succeeded and the build succeeded or was skipped'
[[ "$(grep -cFx '          fail-build: true' "$deploy")" == 2 ]] || fail 'both Grype steps must keep fail-build: true: the scan is the gate of every promotion'
grep -q 'fail-build: false' "$deploy" && fail 'no Grype step may set fail-build: false'

# --- deploy.yml: preflight ---
preflight_job=$(sed -n '/^  preflight:$/,/^  versions:$/p' "$deploy")
grep -qFx '          SSH_DEPLOY: ${{ inputs.ssh-deploy }}' <<< "$preflight_job" || fail 'the preflight step must pass inputs.ssh-deploy as SSH_DEPLOY in its env:'

awk 'index($0, "# >>> preflight") { inside = 1; next } index($0, "# <<< preflight") { inside = 0 } inside { sub(/^          /, ""); print }' \
  "$deploy" > "$tmp/preflight.sh"
[[ -s "$tmp/preflight.sh" ]] || fail 'deploy.yml has no preflight block between its markers'
preflight() {
  (env -u DEPLOY_PATH GPR_USER=u GPR_KEY=k NPM_GH_TOKEN=n GHCR_OWNER=o SSH_DEPLOY="$1" bash "$tmp/preflight.sh") > "$tmp/out" 2>&1
}
preflight false || fail 'without SSH the preflight must not require DEPLOY_PATH'
preflight true && fail 'with SSH the preflight must still require DEPLOY_PATH'
grep -qF 'DEPLOY_PATH' "$tmp/out" || fail 'the preflight must name DEPLOY_PATH when it is missing'
(env -u GPR_KEY GPR_USER=u NPM_GH_TOKEN=n GHCR_OWNER=o SSH_DEPLOY=false bash "$tmp/preflight.sh") > "$tmp/out" 2>&1 \
  && fail 'the preflight must require GPR_KEY in both modes'
grep -qF 'GPR_KEY' "$tmp/out" || fail 'the preflight must name GPR_KEY when it is missing'

# --- promote.yml ---
grep -qE '^    uses: \./\.github/workflows/deploy\.yml$' "$promote" || fail 'promote.yml must call ./.github/workflows/deploy.yml'
grep -qE '^      ssh-deploy: false$' "$promote" || fail 'promote.yml must call deploy.yml with ssh-deploy: false'
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

echo 'OK: promote.yml builds through deploy.yml without SSH and commits the tags; SSH consumers are unchanged'
