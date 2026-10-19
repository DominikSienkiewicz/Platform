#!/usr/bin/env bash
# check-action-pins.sh [katalog-repo] — każda akcja przypięta po SHA w śledzonych plikach YAML wskazuje commit,
# na który rozwija się tag z jej komentarza `# vX.Y.Z`. SHA obiektu annotated taga runner Actions rozwija sam,
# ale weryfikacja OpenSSF Scorecard (publish_results) odrzuca go jako „imposter commit”, a inny SHA niż tag
# kłamie w komentarzu. Pyta GitHub przez `gh api` (w CI z GH_TOKEN); test: scripts/check-action-pins.test.sh.
set -euo pipefail
root=$(cd "${1:-$(dirname "$0")/..}" && pwd)
cd "$root"

pin_re='uses:[[:space:]]*[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}'
cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT

# resolve <owner/repo> <tag>: SHA commita, na który rozwija się tag; pusty, gdy GitHub go nie zna.
resolve() {
  local entry="$cache/${1//\//_}@$2"
  [[ -f "$entry" ]] || gh api "repos/$1/commits/$2" --jq .sha > "$entry" 2>/dev/null || : > "$entry"
  cat "$entry"
}

pins=0
failures=0
problem() { echo "$1" >&2; failures=$((failures + 1)); }

while IFS= read -r -d '' file; do
  while IFS= read -r hit; do
    line=${hit%%:*}
    text=${hit#*:}
    ref=$(grep -oE "$pin_re" <<<"$text" | sed -E 's/^uses:[[:space:]]*//')
    action=${ref%@*}
    sha=${ref##*@}
    repo=$(cut -d/ -f1-2 <<<"$action")
    tag=$(sed -nE 's/.*#[[:space:]]*([^[:space:]]+).*/\1/p' <<<"$text")
    pins=$((pins + 1))
    if [[ -z "$tag" ]]; then
      problem "$file:$line: $action@$sha has no '# vX.Y.Z' comment naming the tag it pins"
      continue
    fi
    want=$(resolve "$repo" "$tag")
    if [[ -z "$want" ]]; then
      problem "$file:$line: tag $tag not found in $repo"
    elif [[ "$sha" != "$want" ]]; then
      problem "$file:$line: $action@$sha is not the commit $tag points at; an annotated tag's own SHA fails OpenSSF Scorecard's imposter-commit check. Pin $action@$want # $tag"
    fi
  done < <(grep -nE "$pin_re" "$file" || true)
done < <(git ls-files -z -- '*.yml' '*.yaml')

if [[ "$failures" -gt 0 ]]; then
  echo "FAIL: $failures of $pins action pins do not point at the commit of their tag" >&2
  exit 1
fi
echo "OK: $pins action pins point at the commits of their tags"
