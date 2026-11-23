#!/usr/bin/env bash
# release.yml, przypadek po przypadku: każdy job i każdy blok wycięty z workflowu biegnie na atrapach, więc testy
# uruchamiają dostarczany kod. Przypadki: atestacja i publikacja tarballi npm, notatki GitHub Release, jednoznaczna
# ścieżka npm publish, starter spring-app w verify-bundle, verify-published i version_exists.
# Wspólne helpery (fail, block, job) są w lib/workflow.sh.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/workflow.sh
source "$(dirname "$0")/lib/workflow.sh"
# shellcheck disable=SC2034 # workflow czyta lib/workflow.sh
workflow="$root/.github/workflows/release.yml"

# --- attest ---
# release.yml atestuje dokładnie to, co publikuje: job npm pakuje (bez paczek private i już wydanych),
# atestuje tarballe i publikuje te same pliki; job gradle atestuje pliki po publikacji. Oba mają
# uprawnienia id-token i attestations.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

block npm-pack > "$tmp/pack.sh"
block npm-publish > "$tmp/publish.sh"
[[ -s "$tmp/pack.sh" && -s "$tmp/publish.sh" ]] || fail 'the npm-pack and npm-publish blocks are missing'

mkdir -p "$tmp/bin" "$tmp/frontend/packages"/{alpha,secret,released}
printf '{ "name": "@x/alpha" }\n' > "$tmp/frontend/packages/alpha/package.json"
printf '{ "name": "@x/secret", "private": true }\n' > "$tmp/frontend/packages/secret/package.json"
printf '{ "name": "@x/released" }\n' > "$tmp/frontend/packages/released/package.json"
cat > "$tmp/bin/npm" <<'STUB'
#!/usr/bin/env bash
echo "npm $*" >> "$STUB_LOG"
case "$1" in
  view) [[ "$2" == "@x/released@"* ]] ;;
  publish)
    case "$2" in
      *conflict*) echo "npm error code E409"; exit 1 ;;
      *broken*) echo "npm error code E500"; exit 1 ;;
    esac ;;
esac
STUB
cat > "$tmp/bin/pnpm" <<'STUB'
#!/usr/bin/env bash
echo "pnpm $* in $(basename "$PWD")" >> "$STUB_LOG"
[[ "$1" == pack && "$2" == --pack-destination ]] && : > "$3/x-$(basename "$PWD")-$V.tgz"
STUB
chmod +x "$tmp/bin/npm" "$tmp/bin/pnpm"
export STUB_LOG="$tmp/stub.log" V=9.9.9 PATH="$tmp/bin:$PATH"

(cd "$tmp/frontend" && bash "$tmp/pack.sh") > "$tmp/out.txt" 2>&1 || fail "packing must succeed: $(cat "$tmp/out.txt")"
[[ "$(ls "$tmp/frontend/dist")" == "x-alpha-9.9.9.tgz" ]] || fail "only the public unreleased package is packed: $(ls "$tmp/frontend/dist")"
grep -q 'private — pomijam' "$tmp/out.txt" || fail 'a private package must be reported as skipped'
grep -q 'released@9.9.9 już w registry' "$tmp/out.txt" || fail 'an already published package must be skipped'

(cd "$tmp/frontend" && bash "$tmp/publish.sh") > "$tmp/out.txt" 2>&1 || fail "publishing the packed tarball must succeed"
grep -qx 'npm publish ./dist/x-alpha-9.9.9.tgz' "$STUB_LOG" || fail 'the job must publish the attested tarball itself'

: > "$tmp/frontend/dist/x-conflict-9.9.9.tgz"
(cd "$tmp/frontend" && bash "$tmp/publish.sh") > "$tmp/out.txt" 2>&1 || fail 'a version conflict is idempotent, not a failure'
: > "$tmp/frontend/dist/x-broken-9.9.9.tgz"
if (cd "$tmp/frontend" && bash "$tmp/publish.sh") > "$tmp/out.txt" 2>&1; then fail 'another publish error must fail the job'; fi

for name in gradle npm; do
  body=$(job "$name")
  grep -qx '      id-token: write' <<<"$body" || fail "$name needs id-token: write"
  grep -qx '      attestations: write' <<<"$body" || fail "$name needs attestations: write"
  grep -q 'uses: actions/attest@[0-9a-f]\{40\} # v' <<<"$body" || fail "$name must attest with a SHA-pinned actions/attest"
done
gradle=$(job gradle)
publish=$(grep -n 'name: Publish Maven' <<<"$gradle" | cut -d: -f1)
attest=$(grep -n 'uses: actions/attest@' <<<"$gradle" | cut -d: -f1)
[[ "$attest" -gt "$publish" ]] || fail 'the gradle job attests after it publishes'
npm=$(job npm)
pack=$(grep -n 'name: Pack the packages to publish' <<<"$npm" | cut -d: -f1)
attest=$(grep -n 'uses: actions/attest@' <<<"$npm" | cut -d: -f1)
publish=$(grep -n 'name: Publish (idempotentny)' <<<"$npm" | cut -d: -f1)
[[ "$pack" -lt "$attest" && "$attest" -lt "$publish" ]] || fail 'the npm job packs, attests, then publishes'

echo 'OK: release.yml attests the files it publishes and publishes the attested npm tarballs'
)

# --- github-release ---
# release.yml tworzy GitHub Release wersji z jej sekcji CHANGELOG.md, po obu publikacjach i tylko raz.
#
# Struktura: job github-release wymaga version, gradle i npm, ma contents: write i nic zapisywalnego dla packages.
# Zachowanie: krok z notatkami jest wycinany z release.yml między znacznikami i uruchamiany na jednorazowym repozytorium
# z atrapą gh, więc test uruchamia dostarczany kod.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1


# --- Struktura -------------------------------------------------------------------------------
block=$(job github-release)
[[ -n "$block" ]] || fail "release.yml must have a github-release job"
grep -Eq '^    needs: \[version, gradle, npm\][[:space:]]*$' <<<"$block" \
  || fail "github-release must need version, gradle and npm, so a Release describes a published version"
grep -Eq '^      contents: write[[:space:]]*$' <<<"$block" || fail "github-release must hold contents: write"
if grep -Eq 'packages:[[:space:]]*write' <<<"$block"; then
  fail "github-release must not hold packages: write"
fi

# --- Zachowanie ------------------------------------------------------------------------------
step="$tmp/notes-step.sh"
block github-release-notes > "$step"
[[ -s "$step" ]] || fail "release.yml has no github-release-notes block between its markers"

work="$tmp/repo"
git init -q -b main "$work"
git -C "$work" config user.name 'Release Test'
git -C "$work" config user.email 'release-test@example.invalid'
mkdir -p "$work/scripts"
cp "$root/scripts/changelog-section.sh" "$work/scripts/changelog-section.sh"
printf '# Changelog\n\n## [1.1.0] - 2026-10-18\n\n### Consumer action required\n\n- Grant packages: read.\n\n## [1.0.0] - 2026-10-01\n\n### Consumer action required\n\nNone.\n' \
  > "$work/CHANGELOG.md"
git -C "$work" add -A
git -C "$work" commit -q -m 'chore(release): platform 1.0.0'
git -C "$work" tag -a -m 'Platform 1.0.0' v1.0.0
git -C "$work" commit -q --allow-empty -m 'chore(release): platform 1.1.0'
git -C "$work" tag -a -m 'Platform 1.1.0' v1.1.0

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
if [ "$1 $2" = "release view" ]; then exit "${GH_RELEASE_EXISTS:-1}"; fi
if [ "$1 $2" = "release create" ]; then cp notes.md "$GH_NOTES_COPY"; fi
exit 0
STUB
chmod +x "$tmp/bin/gh"

run_step() {
  (cd "$work" && PATH="$tmp/bin:$PATH" VERSION=1.1.0 GITHUB_REPOSITORY=owner/platform bash -e "$step")
}

export GH_CALLS="$tmp/gh-calls" GH_NOTES_COPY="$tmp/notes.md"
GH_RELEASE_EXISTS=1 run_step >/dev/null || fail 'the notes step must succeed when the Release does not exist yet'
grep -q '^release create v1.1.0 --title Platform 1.1.0 --notes-file notes.md --verify-tag$' "$GH_CALLS" \
  || { cat "$GH_CALLS" >&2; fail 'the notes step must create the Release of the tag with its title and notes'; }
grep -qx -- '- Grant packages: read.' "$GH_NOTES_COPY" || fail 'the Release notes must carry the CHANGELOG section'
grep -qx '### Consumer action required' "$GH_NOTES_COPY" || fail 'the Release notes must keep the section headings'
grep -q 'compare/v1.0.0...v1.1.0' "$GH_NOTES_COPY" || fail 'the Release notes must link the diff from the previous version'
if grep -q '1.0.0 - 2026-10-01' "$GH_NOTES_COPY"; then
  fail 'the Release notes must stop at the next version section'
fi

: > "$GH_CALLS"
GH_RELEASE_EXISTS=0 run_step >/dev/null || fail 'the notes step must succeed when the Release already exists'
if grep -q '^release create' "$GH_CALLS"; then
  fail 'a re-run must not create the Release twice'
fi

echo 'OK: release.yml creates one GitHub Release per version from its CHANGELOG section'
)

# --- npm-publish-path ---
# Blok npm-publish z release.yml musi podawać `npm publish` jednoznaczną ścieżkę do tarballa.
# npm czyta `dist/x.tgz` jako skrót GitHub `owner/repo` i robi `git ls-remote`, a wydanie 1.6.0
# padło przez to na `Permission denied (publickey)`. Stub odrzuca każdy spec, który nie zaczyna
# się od `./` ani `/`, tak jak prawdziwy npm.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

block npm-publish > "$tmp/publish.sh"
[[ -s "$tmp/publish.sh" ]] || fail 'the npm-publish block is missing'

mkdir -p "$tmp/bin" "$tmp/frontend/dist"
: > "$tmp/frontend/dist/seniordeveloper-pl-dominik-sienkiewicz-versions-9.9.9.tgz"
cat > "$tmp/bin/npm" <<'STUB'
#!/usr/bin/env bash
echo "npm $*" >> "$STUB_LOG"
[[ "$1" == publish ]] || exit 0
case "$2" in
  ./* | /*) [[ -f "$2" ]] || { echo "npm error code ENOENT"; exit 1; } ;;
  *) echo "npm error command git --no-replace-objects ls-remote ssh://git@github.com/$2.git"
     echo "npm error git@github.com: Permission denied (publickey)."
     exit 128 ;;
esac
STUB
chmod +x "$tmp/bin/npm"
export STUB_LOG="$tmp/stub.log" PATH="$tmp/bin:$PATH"

(cd "$tmp/frontend" && bash "$tmp/publish.sh") > "$tmp/out.txt" 2>&1 \
  || fail "npm publish must get a path, not a git spec, for every tarball: $(cat "$tmp/out.txt")"
grep -q '^npm publish .*seniordeveloper-pl-dominik-sienkiewicz-versions-9.9.9.tgz$' "$STUB_LOG" || fail 'the packed tarball was not published'

echo 'OK: release.yml publishes each npm tarball by an unambiguous path'
)

# --- verify-bundle-wrapper ---
# Job verify-bundle w release.yml składa starter spring-app z wrapperem java-library. spring-app ma własne gradle/
# (kryteria JVM demona), więc `cp -R …/gradle "$app/gradle"` zagnieżdżało wrapper w gradle/gradle/wrapper i build
# wydania 1.8.0 padł na "Unable to access jarfile". Kroki przygotowania (do `cd "$app"`) biegną na zasianym drzewie.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

awk '
  /- name: Build the spring-app starter from the bundle alone$/ { step = 1; next }
  step && /^          cd "\$app"$/ { exit }
  step && /^        run: \|$/ { body = 1; next }
  body { sub(/^          /, ""); print }
' "$root/.github/workflows/release.yml" > "$tmp/prepare.sh"
[[ -s "$tmp/prepare.sh" ]] || fail 'release.yml has no "Build the spring-app starter from the bundle alone" step'

tree="$tmp/tree"
mkdir -p "$tree/templates/jvm/spring-app/gradle" "$tree/templates/jvm/java-library/gradle/wrapper" "$tmp/runner"
echo 'toolchainVersion=27' > "$tree/templates/jvm/spring-app/gradle/gradle-daemon-jvm.properties"
echo 'platformVersion=1.0.0' > "$tree/templates/jvm/spring-app/gradle.properties"
echo '#!/bin/sh' > "$tree/templates/jvm/java-library/gradlew"
: > "$tree/templates/jvm/java-library/gradle/wrapper/gradle-wrapper.jar"
: > "$tree/templates/jvm/java-library/gradle/wrapper/gradle-wrapper.properties"

# sed -i bez sufiksu działa tylko w GNU sed (runner); na macOS zastępuje go atrapa.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/sed" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == -i ]]; then shift; file="${*: -1}"; "$REAL_SED" "${@:1:$#-1}" "$file" > "$file.new" && mv "$file.new" "$file"; else "$REAL_SED" "$@"; fi
STUB
chmod +x "$tmp/bin/sed"
(cd "$tree" && REAL_SED="$(command -v sed)" PATH="$tmp/bin:$PATH" RUNNER_TEMP="$tmp/runner" V=9.9.9 bash -e "$tmp/prepare.sh") || fail 'the preparation steps failed'

app="$tmp/runner/spring-app"
[[ -f "$app/gradle/wrapper/gradle-wrapper.jar" ]] \
  || fail "the wrapper jar must land in spring-app/gradle/wrapper, found: $(cd "$app" && find gradle -type f | sort | tr '\n' ' ')"
[[ -f "$app/gradle/gradle-daemon-jvm.properties" ]] || fail 'the daemon JVM criteria of spring-app must stay'
[[ -f "$app/gradlew" ]] || fail 'spring-app must get gradlew'
grep -qx 'platformVersion=9.9.9' "$app/gradle.properties" || fail 'the starter must be pinned at the release'

echo 'OK: verify-bundle gives spring-app the wrapper of java-library next to its own gradle/ files'
)

# --- verify-published ---
# verify-published w release.yml czerwieni wydanie, jeśli któryś opublikowany artefakt nie niesie wersji.
# Blok jest wycinany między znacznikami i uruchamiany w atrapie checkoutu na atrapach gh i npm.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { local message="$1"; echo "FAIL: $message" >&2; echo "--- output ---" >&2; echo "$OUT" >&2; exit 1; }

block verify-published > "$tmp/verify.sh"
OUT=""
[[ -s "$tmp/verify.sh" ]] || fail 'release.yml has no verify-published block between its markers'

checkout="$tmp/checkout"
mkdir -p "$checkout/gradle/build-logic/src/main/kotlin" "$checkout/frontend/packages/eslint-config" "$checkout/frontend/packages/query"
touch "$checkout/gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts" \
      "$checkout/gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts"
printf '{ "name": "@seniordeveloper-pl-dominik-sienkiewicz/eslint-config" }\n' > "$checkout/frontend/packages/eslint-config/package.json"
printf '{ "name": "@seniordeveloper-pl-dominik-sienkiewicz/query", "private": true }\n' > "$checkout/frontend/packages/query/package.json"

# Atrapy: gh wypisuje 1.6.0 dla każdej paczki Maven poza $MISSING_MAVEN; npm zna 1.6.0, chyba że ustawiono $MISSING_NPM.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
for arg in "$@"; do case "$arg" in */packages/maven/*) package="${arg#*/packages/maven/}"; package="${package%/versions}" ;; esac; done
echo "$package" >> "$CALLS"
[[ "$package" == "${MISSING_MAVEN:-}" ]] && { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
printf '1.5.31\n1.6.0\n'
GH
cat > "$tmp/bin/npm" <<'NPM'
#!/usr/bin/env bash
[[ "$2" == "${MISSING_NPM:-}@1.6.0" ]] && exit 1
echo 1.6.0
NPM
chmod +x "$tmp/bin/gh" "$tmp/bin/npm"

run() {
  : > "$tmp/calls"
  RC=0
  OUT=$(cd "$checkout" && PATH="$tmp/bin:$PATH" CALLS="$tmp/calls" V=1.6.0 GITHUB_TOKEN=dummy GPR_OWNER=owner bash "$tmp/verify.sh" 2>&1) || RC=$?
}

run
[[ $RC -eq 0 ]] || fail "a release where every artifact carries the version must pass (exit $RC)"
for package in pl.seniordeveloper.gradle.build-logic pl.seniordeveloper.platform-catalog \
  seniordev.java-conventions.seniordev.java-conventions.gradle.plugin \
  seniordev.settings-conventions.seniordev.settings-conventions.gradle.plugin; do
  grep -qx "$package" "$tmp/calls" || fail "verify-published must check $package"
done

MISSING_MAVEN=seniordev.settings-conventions.seniordev.settings-conventions.gradle.plugin run
[[ $RC -ne 0 ]] || fail 'a missing plugin marker must fail the release'
grep -q 'settings-conventions.gradle.plugin has no version 1.6.0' <<<"$OUT" || fail 'the error must name the missing package'

MISSING_NPM=@seniordeveloper-pl-dominik-sienkiewicz/eslint-config run
[[ $RC -ne 0 ]] || fail 'a missing npm package must fail the release'
grep -q 'npm @seniordeveloper-pl-dominik-sienkiewicz/eslint-config has no version 1.6.0' <<<"$OUT" || fail 'the error must name the missing npm package'

MISSING_NPM=@seniordeveloper-pl-dominik-sienkiewicz/query run
[[ $RC -eq 0 ]] || fail 'a private package is not published and must not be required'

echo 'OK: verify-published requires the version on every Maven package and every public npm package'
)

# --- version-exists ---
# version_exists w release.yml rozstrzyga, czy moduł Maven jest już opublikowany i pomijany przy ponownym przebiegu.
# Blok jest wycinany z release.yml między znacznikami i uruchamiany na atrapie gh.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT


block version-exists > "$tmp/version-exists.sh"
[[ -s "$tmp/version-exists.sh" ]] || fail 'release.yml has no version-exists block between its markers'

# Atrapa gh: wypisuje nazwy z $STUB_NAMES_FILE (po jednej w wierszu) albo failuje jak 404, gdy STUB_STATUS != 0.
# Plik, nie zmienna środowiskowa: Linux odmawia exec przy jednej zmiennej powyżej 128 KiB (MAX_ARG_STRLEN),
# a długa lista poniżej jest większa.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
[[ "${STUB_STATUS:-0}" -eq 0 ]] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
cat "$STUB_NAMES_FILE"
GH
chmod +x "$tmp/bin/gh"

published() { printf '%s\n' "$@" > "$tmp/names"; }

check() {
  PATH="$tmp/bin:$PATH" GITHUB_TOKEN=dummy GPR_OWNER=owner STUB_NAMES_FILE="$tmp/names" V="$1" bash -c \
    "set -uo pipefail; source '$tmp/version-exists.sh'; version_exists pl.seniordeveloper.platform-catalog"
}

published 1.5.30 1.5.31
check 1.5.31 || fail 'a published version must be found'
if check 1.5.3; then fail 'a prefix of a published version is not that version'; fi
published 1.5.30
if check 1.5.31; then fail 'an unpublished version must not be found'; fi
if STUB_STATUS=1 check 1.5.31; then fail 'a missing package (404) means not published'; fi
# Wiele wersji, trafienie pierwsze: grep kończy wcześnie, co nie może zamienić się w "nieopublikowane".
{ printf '1.6.0\n'; seq -f '0.%g.0' 1 50000; } > "$tmp/names"
check 1.6.0 || fail 'an early match in a long version list must be found'

echo 'OK: version_exists finds published versions by exit code and treats a missing package as unpublished'
)
