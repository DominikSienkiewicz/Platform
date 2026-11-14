#!/usr/bin/env bash
# Job frontend-image w ci.yml (N-CAP-6). Kontrakt statyczny: token tylko jako sekret BuildKit github_token i tylko
# w mapowaniach env: (nigdy --build-arg, echo ani rozwinięcie w run:), packages: read, npm z --ignore-scripts,
# sprzątanie kontenera w kroku always(). Bloki między markerami frontend-image-* biegną naprawdę: filtr wejść obrazu,
# wersja z ostatniego tagu wydania przed HEAD, komplet paczek tego wydania i ograniczone w czasie czekanie na
# odpowiedź kontenera (docker, curl i sleep to atrapy, bez sieci i bez budowania obrazu).
# shellcheck disable=SC2016 # literal GitHub expressions and shell variables in patterns
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/ci.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" >&2 2>/dev/null || true; exit 1; }

job=$(awk '/^  frontend-image:$/ { inside = 1; print; next } inside && /^  [^ ]/ { exit } inside && NF' "$workflow")
[[ -n "$job" ]] || fail 'ci.yml has no frontend-image job'
step() { awk -v name="      - name: $1" '$0 == name { inside = 1; print; next } inside && /^      - / { exit } inside' <<<"$job"; }
block() {
  awk -v start="# >>> frontend-image-$1" -v end="# <<< frontend-image-$1" '
    index($0, start) { inside = 1; next }
    index($0, end) { inside = 0 }
    inside { sub(/^          /, ""); print }
  ' "$workflow" > "$tmp/$1.sh"
  [[ -s "$tmp/$1.sh" ]] || fail "ci.yml has no frontend-image-$1 block between its markers"
}

# --- Kontrakt statyczny ----------------------------------------------------------------------------------------
permissions=$(awk '/^    permissions:$/ { inside = 1; next } inside && /^      / { print; next } inside { exit }' <<<"$job")
[[ "$permissions" == $'      contents: read\n      packages: read' ]] \
  || fail "frontend-image must grant exactly contents: read and packages: read, got: $permissions"
grep -qx '          persist-credentials: false' <<<"$job" || fail 'the checkout must not persist credentials'

grep -qE '^        run: docker build --secret id=github_token,env=GITHUB_TOKEN ' <<<"$job" \
  || fail 'docker build must mount the token as the BuildKit secret github_token'
if grep -qF -- '--build-arg' <<<"$job"; then fail 'frontend-image must pass no --build-arg: build arguments stay in the image history'; fi
tokens=$(grep -E 'secrets\.GITHUB_TOKEN|github\.token' <<<"$job") || fail 'frontend-image must hand GITHUB_TOKEN to npm and docker build'
while IFS= read -r line; do
  [[ "$line" == '          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}' ]] || fail "the token may only be a step env: mapping, got: $line"
done <<<"$tokens"
if grep -qE '\$\{?GITHUB_TOKEN' <<<"$job"; then
  fail 'no run: script may expand $GITHUB_TOKEN: npm reads it through .npmrc, docker through env=GITHUB_TOKEN'
fi
if grep -qE 'set -[a-z]*x|xtrace' <<<"$job"; then fail 'frontend-image must not trace commands'; fi
if grep -E 'docker run ' <<<"$job" | grep -qE -- ' (-e|--env|--env-file)[ =]'; then fail 'the container gets no environment from the job'; fi

grep -qF 'npm install --package-lock-only --ignore-scripts' <<<"$job" || fail 'the lockfile must be written by npm install --package-lock-only --ignore-scripts'
if grep -E '(npm|pnpm) (install|ci|i) ' <<<"$job" | grep -qvF -- '--ignore-scripts'; then fail 'every npm install runs with --ignore-scripts'; fi
grep -qF 'VERSION: ${{ steps.release.outputs.version }}' <<<"$job" || fail 'the frontend must be rendered at the version of the release step'
grep -qF -- '--frontend next --platform-version "$VERSION"' <<<"$job" || fail 'new-consumer.sh must pin the frontend at that release'

health=$(step 'Start the container and wait for an answer on port 3000')
[[ -n "$health" ]] || fail 'frontend-image has no health step'
grep -qE '^        timeout-minutes: [0-9]+$' <<<"$health" || fail 'the health step needs its own timeout-minutes'
cleanup=$(step 'Remove the container')
grep -qxF '        if: ${{ always() }}' <<<"$cleanup" || fail 'the container must be removed in an always() step'
grep -qF 'docker rm -f platform-frontend-image' <<<"$cleanup" || fail 'the cleanup step must remove platform-frontend-image'
[[ "$(grep -E '^      - ' <<<"$job" | tail -1)" == '      - name: Remove the container' ]] || fail 'the cleanup step must be the last step of the job'

# --- Filtr wejść obrazu ----------------------------------------------------------------------------------------
block changes
inputs=$(sed -n "s/^inputs='\(.*\)'$/\1/p" "$tmp/changes.sh")
[[ -n "$inputs" ]] || fail 'the changes block defines no inputs pattern'
for path in templates/Dockerfile.frontend templates/frontend/next.config.ts templates/npmrc scripts/new-consumer.sh .github/workflows/ci.yml; do
  grep -qE -- "$inputs" <<<"$path" || fail "a change of $path must build the image"
done
for path in templates/Dockerfile.backend docs/consuming.md frontend/packages/versions/versions.json scripts/new-consumer.sh.bak; do
  if grep -qE -- "$inputs" <<<"$path"; then fail "a change of $path alone must not build the image"; fi
done

repo="$tmp/repo"
git init -q -b main "$repo"
commit() { git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q -m "$1"; git -C "$repo" rev-parse HEAD; }
mkdir -p "$repo/templates" "$repo/docs"
echo base > "$repo/README.md"; echo 'FROM node:24-slim' > "$repo/templates/Dockerfile.frontend"
base=$(commit base)
echo docs > "$repo/docs/consuming.md"
docs=$(commit docs)
echo 'FROM node:24-slim AS deps' > "$repo/templates/Dockerfile.frontend"
image=$(commit image)
git -C "$repo" update-ref refs/remotes/origin/main "$base"

# changes <head> <event> [before] [ref type]: wypisuje wyjście build dla biegu na <head>
changes() {
  git -C "$repo" checkout -q "$1"
  : > "$tmp/output"
  (cd "$repo" && GITHUB_OUTPUT="$tmp/output" EVENT="$2" BEFORE="${3:-}" REF_TYPE="${4:-branch}" BASE_REF=main \
    bash "$tmp/changes.sh" > /dev/null)
  sed -n 's/^build=//p' "$tmp/output"
}
[[ "$(changes "$docs" pull_request)" == false ]] || fail 'a pull request that changes only docs must not build the image'
[[ "$(changes "$image" pull_request)" == true ]] || fail 'a pull request that changes Dockerfile.frontend must build the image'
[[ "$(changes "$docs" push "$base")" == false ]] || fail 'a push that changes only docs must not build the image'
[[ "$(changes "$image" push "$docs")" == true ]] || fail 'a push that changes Dockerfile.frontend must build the image'
[[ "$(changes "$docs" push 0000000000000000000000000000000000000000)" == false ]] || fail 'a new branch push compares HEAD^...HEAD'
[[ "$(changes "$docs" schedule)" == true ]] || fail 'the weekly cron always builds the image'
[[ "$(changes "$docs" push "$base" tag)" == true ]] || fail 'the release gate (ci.yml called on a tag) always builds the image'

# --- Wersja z tagu wydania -------------------------------------------------------------------------------------
block release
tag() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid tag "$@"; }
tag v1.9.0 "$base"
tag -a -m 'Platform 1.10.0' v1.10.0 "$docs"
tag v1 "$image"
tag v1.11.0-rc.1 "$image"
git -C "$repo" checkout -q main
echo 'FROM node:24-slim AS runner' > "$repo/templates/Dockerfile.frontend"
head=$(commit head)
tag v1.12.0 "$head"

# release <head>: wypisuje wersję wybraną dla biegu na <head>
release() {
  git -C "$repo" checkout -q "$1"
  : > "$tmp/output"
  (cd "$repo" && GITHUB_OUTPUT="$tmp/output" bash "$tmp/release.sh" > "$tmp/out" 2>&1) || return 1
  sed -n 's/^version=//p' "$tmp/output"
}
[[ "$(release "$head")" == 1.10.0 ]] || fail 'the release gate on v1.12.0 must take the newest vX.Y.Z before it (semver order, no v1, no rc)'
[[ "$(release "$docs")" == 1.9.0 ]] || fail 'a tag at HEAD or after it is not published yet and must be skipped'
if release "$base" > /dev/null; then fail 'without a release tag before HEAD the step must fail'; fi
grep -qF '::error::No release tag' "$tmp/out" || fail 'the missing release tag must be named'

# --- Komplet paczek wydania ------------------------------------------------------------------------------------
block shipped
packages() {
  local version="$1" private="$2"
  mkdir -p "$repo/frontend/packages/versions" "$repo/frontend/packages/eslint-config" "$repo/frontend/packages/api-client" \
    "$repo/frontend/packages/docs-only"
  printf '{ "name": "@dominiksienkiewicz/versions", "version": "%s" }\n' "$version" > "$repo/frontend/packages/versions/package.json"
  printf '{ "name": "@dominiksienkiewicz/eslint-config", "version": "%s" }\n' "$version" > "$repo/frontend/packages/eslint-config/package.json"
  printf '{ "name": "@dominiksienkiewicz/api-client", "version": "%s", "private": %s }\n' "$version" "$private" \
    > "$repo/frontend/packages/api-client/package.json"
  echo notes > "$repo/frontend/packages/docs-only/README.md"
}
git -C "$repo" checkout -q main
packages 1.0.0 true
tag v1.5.31 "$(commit 'packages without the Platform version')"
packages 1.6.0 true
tag v1.6.0 "$(commit 'packages at the Platform version')"
packages 1.7.0 false
tag v1.7.0 "$(commit 'api-client published')"
packages 1.8.0 false
tag v1.8.0 "$(commit 'tagged, but the npm publish failed')"

# Atrapa rejestru: `npm view <name>@<version> version` zna tylko wpisy z $tmp/registry, jak verify-published
# w release.yml — wersji spoza rejestru npm nie wypisuje.
mkdir -p "$tmp/npm-bin"
cat > "$tmp/npm-bin/npm" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == view && "$3" == version ]] || { echo "unexpected npm $*" >&2; exit 2; }
case "${2%@*}" in
  */gone) echo 'npm error code E404' >&2; exit 1 ;;
  */locked) echo 'npm error code E401' >&2; exit 1 ;;
esac
grep -qxF "$2" "$REGISTRY" && echo "${2##*@}"
exit 0
STUB
chmod +x "$tmp/npm-bin/npm"
printf '%s\n' @dominiksienkiewicz/versions@1.6.0 @dominiksienkiewicz/eslint-config@1.6.0 \
  @dominiksienkiewicz/versions@1.7.0 @dominiksienkiewicz/api-client@1.7.0 > "$tmp/registry"

# shipped <version> <pinned package...>: wypisuje wyjście shipped dla manifestu, który przypina pakiety na <version>
shipped() {
  local version="$1"; shift
  node -e 'const [version, ...names] = process.argv.slice(1);
    const pins = Object.fromEntries(names.map((name) => [`@dominiksienkiewicz/${name}`, version]));
    process.stdout.write(JSON.stringify({ dependencies: { react: "19.2.0" }, devDependencies: pins }));' "$version" "$@" > "$tmp/package.json"
  : > "$tmp/output"
  (cd "$repo" && PATH="$tmp/npm-bin:$PATH" REGISTRY="$tmp/registry" GITHUB_OUTPUT="$tmp/output" MANIFEST="$tmp/package.json" \
    VERSION="$version" bash -euo pipefail "$tmp/shipped.sh" > "$tmp/out" 2>&1)
  sed -n 's/^shipped=//p' "$tmp/output"
}
[[ "$(shipped 1.6.0 versions eslint-config)" == true ]] || fail 'a release that publishes every pinned package at its version must build'
[[ "$(shipped 1.5.31 versions eslint-config)" == false ]] || fail 'packages at 1.0.0 are not published at 1.5.31'
grep -qF '::notice::Platform v1.5.31 does not publish @dominiksienkiewicz/versions @dominiksienkiewicz/eslint-config at 1.5.31' "$tmp/out" \
  || fail 'the notice must name every package the release does not publish'
[[ "$(shipped 1.6.0 versions api-client)" == false ]] || fail 'a private package is never published'
[[ "$(shipped 1.7.0 versions api-client)" == true ]] || fail 'a package that turned public is published'
[[ "$(shipped 1.6.0 versions vitest-config)" == false ]] || fail 'a package the release does not contain is not published'
[[ "$(shipped 1.8.0 versions eslint-config)" == false ]] \
  || fail 'a release whose packages are tagged at its version but missing from the registry (the failed npm publish of 1.6.0) must not build'
grep -qF '::notice::Platform v1.8.0 does not publish @dominiksienkiewicz/versions @dominiksienkiewicz/eslint-config at 1.8.0' "$tmp/out" \
  || fail 'the notice must name every package missing from the registry'
mkdir -p "$repo/frontend/packages/gone" "$repo/frontend/packages/locked"
printf '{ "name": "@dominiksienkiewicz/gone", "version": "2.0.0" }\n' > "$repo/frontend/packages/gone/package.json"
printf '{ "name": "@dominiksienkiewicz/locked", "version": "2.0.0" }\n' > "$repo/frontend/packages/locked/package.json"
tag v2.0.0 "$(commit 'packages the registry answers with errors')"
[[ "$(shipped 2.0.0 gone)" == false ]] || fail 'a package the registry answers with E404 is not published'
if [[ -n "$(shipped 2.0.0 locked)" ]]; then fail 'another registry error (E401) must fail the step, not skip the image'; fi

# --- Czekanie na odpowiedź kontenera ---------------------------------------------------------------------------
block health
mkdir -p "$tmp/bin"
cat > "$tmp/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_LOG"
case "$1" in
  inspect) echo "$CONTAINER_RUNNING" ;;
  logs) echo 'stub server log line' ;;
esac
STUB
cat > "$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
calls=$(( $(grep -c '^curl ' "$STUB_LOG") ))
[[ "$ANSWER_AFTER" -gt 0 && "$calls" -ge "$ANSWER_AFTER" ]]
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/sleep"
chmod +x "$tmp/bin/docker" "$tmp/bin/curl" "$tmp/bin/sleep"

# health <answer after N calls, 0 = never> <container running>: kod wyjścia bloku, log atrap w $tmp/stub.log
health() {
  : > "$tmp/stub.log"
  local status=0
  PATH="$tmp/bin:$PATH" STUB_LOG="$tmp/stub.log" ANSWER_AFTER="$1" CONTAINER_RUNNING="$2" bash "$tmp/health.sh" > "$tmp/out" 2>&1 || status=$?
  echo "$status"
}
curls() { grep -c '^curl ' "$tmp/stub.log"; }
[[ "$(health 3 true)" == 0 && "$(curls)" == 3 ]] || fail 'the poll must stop at the first answer'
grep -qF 'curl -fs -o /dev/null --max-time 5 http://localhost:3000/' "$tmp/stub.log" || fail 'each probe must ask http://localhost:3000/ with a time limit'
grep -qF 'docker run -d --name platform-frontend-image -p 3000:3000 platform-frontend-image:ci' "$tmp/stub.log" \
  || fail 'the container must publish port 3000 under the name the cleanup step removes'
[[ "$(health 0 true)" == 1 ]] || fail 'a container that never answers must fail the job'
[[ "$(curls)" -gt 1 && "$(curls)" -le 60 ]] || fail "the poll must retry a bounded number of times, it probed $(curls) times"
grep -qF 'stub server log line' "$tmp/out" || fail 'a failed poll must print the container logs'
grep -qF '::error::the image of templates/Dockerfile.frontend did not answer' "$tmp/out" || fail 'a failed poll must report an error'
[[ "$(health 0 false)" == 1 && "$(curls)" == 1 ]] || fail 'a container that exited must stop the poll at once'

echo 'OK: ci.yml builds templates/Dockerfile.frontend at the latest release with the token only as a BuildKit secret and waits a bounded time for port 3000'
