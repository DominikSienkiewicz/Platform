#!/usr/bin/env bash
# compare-rebuild.sh <bundle-dir> — porównuje jary przebudowanego wydania (Maven bundle z
# -PplatformBundleRepository, jak scripts/release-assets.sh) z kopiami w GitHub Packages po SHA-256 (N-REL-16).
# Każdy jar spod pl/seniordeveloper/ ma tę samą ścieżkę w rejestrze; brak kopii w rejestrze i różna suma kończą się
# kodem 1, a każdy wiersz trafia na stdout: "match|differ|missing <ścieżka> <suma lokalna> [<suma rejestru>]".
#   GITHUB_ACTOR / GITHUB_TOKEN — odczyt GitHub Packages; PLATFORM_MAVEN_URL podmienia rejestr (testy, file://).
# Woła go reproducibility.yml; test: scripts/compare-rebuild.test.sh.
set -euo pipefail
bundle=${1:?Usage: compare-rebuild.sh <bundle-dir>}
registry="${PLATFORM_MAVEN_URL:-https://maven.pkg.github.com/DominikSienkiewicz/Platform}"
proto="=https"
[[ "$registry" == file://* ]] && proto="=file"
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{ print $1 }'; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

status=0 count=0
while IFS= read -r jar; do
  path=${jar#"$bundle"/}
  count=$((count + 1))
  local_sum=$(sha "$jar")
  if ! curl -fsSL --proto "$proto" -u "${GITHUB_ACTOR:-reproducibility}:${GITHUB_TOKEN:-}" "$registry/$path" -o "$work/registry.jar" 2>/dev/null; then
    echo "missing $path $local_sum"
    status=1
    continue
  fi
  registry_sum=$(sha "$work/registry.jar")
  if [[ "$local_sum" == "$registry_sum" ]]; then
    echo "match $path $local_sum"
  else
    echo "differ $path $local_sum $registry_sum"
    status=1
  fi
done < <(find "$bundle/pl/seniordeveloper" -name '*.jar' -type f | LC_ALL=C sort)
[[ $count -gt 0 ]] || { echo "No jar under $bundle/pl/seniordeveloper; was the release rebuilt into the bundle?" >&2; exit 2; }
exit "$status"
