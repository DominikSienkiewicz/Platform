#!/usr/bin/env bash
# Tryb jednego obrazu w deploy.yml (single-image): eksport frontendu trafia do jara przed bootJar, a budowany, skanowany
# i wypychany jest tylko obraz backendu, z pustym tagiem frontendu. Bez wejścia deploy.yml działa jak dotąd. Bloki
# preflightu, wersji i skanu Snyka są wycinane między znacznikami i uruchamiane; docker w skanie to atrapa.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/deploy.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" 2>/dev/null >&2 || true; exit 1; }
block() {
  awk -v from="# >>> $1" -v to="# <<< $1" \
    'index($0, from) { inside = 1; next } index($0, to) { inside = 0 } inside { sub(/^          /, ""); print }' "$workflow"
}
job() { awk -v start="  $1:" '$0 == start { p = 1; next } /^  [a-z-]+:$/ { p = 0 } p' "$workflow"; }
# step JOB NAME: krok joba od wiersza `- name: NAME…` do następnego kroku.
step() { awk -v name="      - name: $2" 'index($0, name) == 1 { p = 1; print; next } p && /^      - / { p = 0 } p' <<< "$(job "$1")"; }
line_of() { grep -nF -- "$2" <<< "$(job "$1")" | head -1 | cut -d: -f1; }

# --- wejście ---
input=$(sed -n '/^      single-image:$/,/^      [a-z-]*:$/p' "$workflow")
[[ -n "$input" ]] || fail 'deploy.yml must declare the single-image input'
grep -qFx '        type: boolean' <<< "$input" || fail 'single-image must be a boolean'
grep -qFx '        default: false' <<< "$input" || fail 'single-image must default to false, so a consumer of two images behaves as before'

# --- preflight: jeden obraz nie idzie przez SSH, które wdraża dwa ---
block preflight > "$tmp/preflight.sh"
[[ -s "$tmp/preflight.sh" ]] || fail 'deploy.yml has no preflight block between its markers'
grep -qFx '          SINGLE_IMAGE: ${{ inputs.single-image }}' <<< "$(job preflight)" \
  || fail 'the preflight step must pass inputs.single-image as SINGLE_IMAGE in its env:'
preflight() { (env -u DEPLOY_PATH GPR_USER=u GPR_KEY=k NPM_GH_TOKEN=n GHCR_OWNER=o "$@" bash "$tmp/preflight.sh") > "$tmp/out" 2>&1; }
preflight SINGLE_IMAGE=true SSH_DEPLOY=false || fail 'a single image without SSH must pass the preflight'
preflight SINGLE_IMAGE=true SSH_DEPLOY=true DEPLOY_PATH=/srv/app \
  && fail 'the preflight must refuse a single image with the SSH deploy, which deploys a backend and a frontend'
if ! grep -qF 'single-image' "$tmp/out" || ! grep -qF 'ssh-deploy' "$tmp/out"; then
  fail 'the refusal must name single-image and ssh-deploy'
fi
preflight SINGLE_IMAGE=false SSH_DEPLOY=true DEPLOY_PATH=/srv/app || fail 'two images with SSH must still pass the preflight'
preflight SSH_DEPLOY=true DEPLOY_PATH=/srv/app || fail 'a preflight without SINGLE_IMAGE must behave as for two images'
(env -u NPM_GH_TOKEN GPR_USER=u GPR_KEY=k GHCR_OWNER=o SINGLE_IMAGE=true SSH_DEPLOY=false bash "$tmp/preflight.sh") > "$tmp/out" 2>&1 \
  && fail 'a single image must still require NPM_GH_TOKEN: npm ci of the export reads it'

# --- wersje: bez wersji frontendu, więc frontend/package.json nie jest potrzebny ---
block versions > "$tmp/versions.sh"
[[ -s "$tmp/versions.sh" ]] || fail 'deploy.yml has no versions block between its markers'
grep -qFx '          SINGLE_IMAGE: ${{ inputs.single-image }}' <<< "$(job versions)" \
  || fail 'the versions step must pass inputs.single-image as SINGLE_IMAGE in its env:'
mkdir -p "$tmp/checkout/backend"
printf 'version=2.0.0\n' > "$tmp/checkout/backend/gradle.properties"
versions() {
  : > "$tmp/github-output"
  (cd "$tmp/checkout" && env GITHUB_OUTPUT="$tmp/github-output" GHCR_OWNER=Owner MIGRATE_TAG_SOURCE=backend \
    ROLLBACK_BACKEND='' ROLLBACK_FRONTEND='' "$@" bash "$tmp/versions.sh") > "$tmp/out" 2>&1 || return 1
  paste -sd' ' - < "$tmp/github-output"
}
outputs=$(versions SINGLE_IMAGE=true) || fail 'with a single image the versions block must run without frontend/package.json'
[[ "$outputs" == 'owner=owner backend=2.0.0 frontend= migrate=2.0.0 rollback=false' ]] \
  || fail "a single image takes the backend version and leaves the frontend tag empty, got: $outputs"

# --- build-push: eksport przed bootJar, bez obrazu frontendu ---
single_backend_if="        if: \${{ inputs.single-image && steps.exists.outputs.backend == 'false' }}"
for name in 'Set up Node for the frontend export' 'Install the frontend for the export' 'Build the frontend export'; do
  body=$(step build-push "$name")
  [[ -n "$body" ]] || fail "build-push must have the step '$name'"
  grep -qFx -- "$single_backend_if" <<< "$body" \
    || fail "'$name' must run exactly when single-image is set and the backend image is not in GHCR yet"
done
node_step=$(step build-push 'Set up Node for the frontend export')
grep -qFx '        uses: actions/setup-node@a0853c24544627f65ddf259abe73b1d18a591444 # v5.0.0' <<< "$node_step" \
  || fail 'the Node setup must use the setup-node pin of the other workflows'
grep -qFx '          node-version: "24"' <<< "$node_step" || fail 'the export must build on Node 24, as the other workflows do'
install_step=$(step build-push 'Install the frontend for the export')
grep -qFx '        working-directory: frontend' <<< "$install_step" || fail 'npm ci must run in frontend/'
grep -qFx '        run: npm ci --ignore-scripts' <<< "$install_step" || fail 'npm ci must skip lifecycle scripts, as in frontend-ci'
grep -qFx '          GITHUB_TOKEN: ${{ secrets.NPM_GH_TOKEN }}' <<< "$install_step" \
  || fail 'npm ci must get NPM_GH_TOKEN as GITHUB_TOKEN, which the .npmrc template reads'
build_step=$(step build-push 'Build the frontend export')
grep -qFx '        working-directory: frontend' <<< "$build_step" || fail 'the export must build in frontend/'
grep -qFx '        run: npm run build' <<< "$build_step" || fail 'the export must be npm run build'
grep -qF 'secrets.' <<< "$build_step" && fail 'npm run build runs dependency code and must get no credential'
node_line=$(line_of build-push '- name: Set up Node for the frontend export')
install_line=$(line_of build-push '- name: Install the frontend for the export')
export_line=$(line_of build-push '- name: Build the frontend export')
bootjar_line=$(line_of build-push '- name: Build bootJar')
[[ "$node_line" -lt "$install_line" && "$install_line" -lt "$export_line" && "$export_line" -lt "$bootjar_line" ]] \
  || fail 'Node, npm ci and npm run build must run in that order before bootJar, which packs the export'
grep -qFx "        if: \${{ !inputs.single-image && steps.exists.outputs.frontend == 'false' }}" \
  <<< "$(step build-push 'Build & push — frontend')" || fail 'a single image must not build the frontend image'
grep -qFx '        if: ${{ inputs.scan-images && !inputs.single-image }}' <<< "$(step build-push 'Grype scan — frontend')" \
  || fail 'a single image must not scan a frontend image'

# --- Snyk: skanuje tylko obrazy, które powstały ---
grep -qFx '      SINGLE_IMAGE: ${{ inputs.single-image }}' <<< "$(job snyk-advisory)" \
  || fail 'the Snyk job must pass inputs.single-image as SINGLE_IMAGE in its env:'
block snyk-scan > "$tmp/snyk.sh"
[[ -s "$tmp/snyk.sh" ]] || fail 'deploy.yml has no snyk-scan block between its markers'
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\n[[ "$1" == pull ]] && echo "$2" >> "$PULLS"\nexit 0\n' > "$tmp/bin/docker"
chmod +x "$tmp/bin/docker"
snyk_pulls() {
  : > "$tmp/pulls"
  (env PATH="$tmp/bin:$PATH" PULLS="$tmp/pulls" IMAGE_PREFIX=ghcr.io/o/app BACKEND_VER=2.0.0 SNYK_IMAGE=snyk "$@" \
    bash "$tmp/snyk.sh") > "$tmp/out" 2>&1 || fail 'the snyk-scan block must run'
  paste -sd' ' - < "$tmp/pulls"
}
[[ "$(snyk_pulls SINGLE_IMAGE=true FRONTEND_VER='')" == 'ghcr.io/o/app-backend:2.0.0' ]] \
  || fail 'with a single image Snyk must scan only the backend image'
[[ "$(snyk_pulls SINGLE_IMAGE=false FRONTEND_VER=3.0.0)" == 'ghcr.io/o/app-backend:2.0.0 ghcr.io/o/app-frontend:3.0.0' ]] \
  || fail 'with two images Snyk must still scan the backend and the frontend'

echo 'OK: single-image builds the export into the jar and only the backend image; two images and SSH are unchanged'
