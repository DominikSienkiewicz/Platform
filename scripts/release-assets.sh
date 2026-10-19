#!/usr/bin/env bash
# release-assets.sh <version> <out-dir> — pliki GitHub Release do użycia bez poświadczeń (N-SHOW-9): GitHub Packages
# odrzuca anonimowe odczyty, więc bez PAT-a nie da się zbudować nawet startera. Do <out-dir> trafia:
#   platform-maven-repo-<version>.zip — repozytorium Maven modułów z gradle/maven-modules.txt (publikacja do katalogu,
#                                       -PplatformBundleRepository), użycie: -PplatformRepository=file://…;
#   tarballe npm każdej publicznej paczki — `npm pack` z rejestru, czyli bajty, które atestował job npm;
#   SHA256SUMS wszystkich plików.
# Woła go job release-assets w release.yml; test: templates/tests/release-assets.test.sh.
set -euo pipefail
version=${1:?Usage: release-assets.sh <version> <out-dir>}
out=${2:?Usage: release-assets.sh <version> <out-dir>}
root=$(cd "$(dirname "$0")/.." && pwd)
gradlew=${RELEASE_ASSETS_GRADLEW:-./gradlew}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"
out=$(cd "$out" && pwd)

bundle="$work/platform-maven-repo"
for module in $(awk '!/^#/ && NF { print $1 }' "$root/gradle/maven-modules.txt"); do
  echo "== bundle gradle/$module ($version) =="
  (cd "$root/gradle/$module" && "$gradlew" --no-daemon -PplatformVersion="$version" \
    -PplatformBundleRepository="$bundle" publishAllPublicationsToBundleRepository)
done
[[ -d "$bundle/pl/seniordeveloper" ]] || { echo "The bundle has no pl/seniordeveloper artifacts." >&2; exit 1; }
(cd "$work" && zip -qr "$out/platform-maven-repo-$version.zip" platform-maven-repo)

for manifest in "$root"/frontend/packages/*/package.json; do
  [[ "$(node -p 'require(process.argv[1]).private === true' "$manifest")" == true ]] && continue
  name=$(node -p 'require(process.argv[1]).name' "$manifest")
  (cd "$work" && npm pack "$name@$version" --pack-destination "$out" >/dev/null)
done

(cd "$out" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print | sed 's#^\./##' | LC_ALL=C sort \
  | while IFS= read -r file; do sha256sum "$file" 2>/dev/null || shasum -a 256 "$file"; done) > "$work/SHA256SUMS"
mv "$work/SHA256SUMS" "$out/SHA256SUMS"
echo "Release assets for $version in $out:"
cat "$out/SHA256SUMS"
