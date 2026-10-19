#!/usr/bin/env bash
# Stub platform-bump.sh w repo bez frontendu (N-DX-4): bin przychodzi z assetów GitHub Release (tu file://), po
# sprawdzeniu sumy z SHA256SUMS, i dostaje argumenty bez zmian; bez wersji stub bierze najnowsze wydanie, a zła
# suma zatrzymuje go, zanim cokolwiek uruchomi. Repo z zainstalowanym binem pilnuje platform-bump.test.sh.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "$OUT" >&2; exit 1; }
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{ print $1 }'; }

# release <version>: asset paczki versions, której bin zapisuje swoje argumenty i własną ścieżkę.
release() {
  local version=$1 staging="$tmp/staging-$1"
  mkdir -p "$staging/package/bin" "$tmp/releases/v$version"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0" "$@" > "$BUMP_CALL"\n' > "$staging/package/bin/platform-bump.sh"
  printf '{ "name": "@dominiksienkiewicz/versions", "version": "%s" }\n' "$version" > "$staging/package/package.json"
  tar -czf "$tmp/releases/v$version/dominiksienkiewicz-versions-$version.tgz" -C "$staging" package
  (cd "$tmp/releases/v$version" && printf '%s  %s\n' "$(sha "dominiksienkiewicz-versions-$version.tgz")" "dominiksienkiewicz-versions-$version.tgz" > SHA256SUMS)
}
release 1.6.0
release 1.7.0
printf '{ "tag_name": "v1.7.0" }\n' > "$tmp/latest.json"

repo="$tmp/jvm-only"
mkdir -p "$repo/scripts" "$repo/backend"
cp "$root/templates/platform-bump.sh" "$repo/scripts/platform-bump.sh"
printf 'platformVersion=1.5.31\n' > "$repo/backend/gradle.properties"
run() {
  OUT=$(cd "$tmp" && BUMP_CALL="$tmp/call" PLATFORM_RELEASES_URL="file://$tmp/releases" PLATFORM_RELEASES_API="file://$tmp/latest.json" \
    PLATFORM_CLI_CACHE="$tmp/cache" bash "$repo/scripts/platform-bump.sh" "$@" 2>&1)
}

run 1.6.0 --dry-run || fail 'a JVM-only repo must bump through the release assets'
[[ "$(sed -n 1p "$tmp/call")" == "$tmp/cache/1.6.0/package/bin/platform-bump.sh" ]] || fail 'the bin of the requested release must run'
[[ "$(sed -n '2,$p' "$tmp/call" | paste -sd' ' -)" == "1.6.0 --dry-run" ]] || fail 'the arguments must reach the bin unchanged'
grep -qF 'Running the platform-bump of Platform 1.6.0 from its release assets' <<<"$OUT" || fail 'the stub must say where the bin comes from'

rm -f "$tmp/call"
run --dry-run || fail 'without a version the stub takes the latest release'
[[ "$(sed -n 1p "$tmp/call")" == "$tmp/cache/1.7.0/package/bin/platform-bump.sh" ]] || fail 'the latest release must run without a version'

release 1.8.0
printf '0000  dominiksienkiewicz-versions-1.8.0.tgz\n' > "$tmp/releases/v1.8.0/SHA256SUMS"
rm -f "$tmp/call"
if run 1.8.0; then fail 'a checksum mismatch must stop the stub'; fi
grep -qF 'does not match its SHA256SUMS' <<<"$OUT" || fail 'the mismatch must be named'
[[ ! -e "$tmp/call" ]] || fail 'nothing may run after a mismatch'
echo 'OK: a JVM-only repo bumps with the bin of the release assets, checked against SHA256SUMS'
