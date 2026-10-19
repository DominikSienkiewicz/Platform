#!/usr/bin/env bash
# scripts/release-assets.sh na atrapach: gradlew publikuje udawane moduły do katalogu z -PplatformBundleRepository,
# npm pack tworzy tarball każdej publicznej paczki. Sprawdza zip repozytorium Maven, tarballe i SHA256SUMS.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/bin"
cat > "$tmp/gradlew" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do case "$arg" in -PplatformBundleRepository=*) bundle="${arg#*=}" ;; -PplatformVersion=*) version="${arg#*=}" ;; esac; done
module=${PWD##*/}
mkdir -p "$bundle/pl/seniordeveloper/$module/$version"
echo jar > "$bundle/pl/seniordeveloper/$module/$version/$module-$version.jar"
echo "$module" >> "$FAKE_LOG"
STUB
cat > "$tmp/bin/npm" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == pack ]] || exit 1
spec=$2 destination=$4
name=${spec%@*}; name=${name#@}; name=${name//\//-}
echo tarball > "$destination/$name-${spec##*@}.tgz"
STUB
chmod +x "$tmp/gradlew" "$tmp/bin/npm"
export PATH="$tmp/bin:$PATH" RELEASE_ASSETS_GRADLEW="$tmp/gradlew" FAKE_LOG="$tmp/gradle.log"

bash "$root/scripts/release-assets.sh" 9.9.9 "$tmp/out" > "$tmp/output" 2>&1 || { cat "$tmp/output"; fail 'the assets must build'; }
[[ "$(tr '\n' ' ' < "$FAKE_LOG")" == 'build-logic catalog test-fixtures security-starter ' ]] || fail 'all four Maven modules must be bundled'
listing=$(unzip -l "$tmp/out/platform-maven-repo-9.9.9.zip")
grep -qF 'platform-maven-repo/pl/seniordeveloper/catalog/9.9.9/catalog-9.9.9.jar' <<<"$listing" \
  || fail 'the zip must hold the Maven repository layout under platform-maven-repo/'
[[ -f "$tmp/out/dominiksienkiewicz-versions-9.9.9.tgz" ]] || fail 'every public npm package must be packed'
if compgen -G "$tmp/out/dominiksienkiewicz-query-*" >/dev/null; then fail 'private packages are not attached'; fi
(cd "$tmp/out" && { sha256sum --check SHA256SUMS 2>/dev/null || shasum -a 256 --check SHA256SUMS; }) > /dev/null || fail 'SHA256SUMS must verify'
[[ $(grep -c . "$tmp/out/SHA256SUMS") -eq $(find "$tmp/out" -type f ! -name SHA256SUMS | wc -l) ]] || fail 'SHA256SUMS must list every asset'
if grep -qF SHA256SUMS "$tmp/out/SHA256SUMS"; then fail 'SHA256SUMS must not list itself'; fi

echo 'OK: release-assets bundles the Maven repository and the npm tarballs with their checksums'
