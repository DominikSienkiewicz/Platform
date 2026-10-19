#!/usr/bin/env bash
# release-notes.sh <from>..<to> — szkic sekcji CHANGELOG.md z historii wydania, do redakcji przed ./release.sh.
# Tematy idą z historii first-parent (merge.sh scala z --no-ff, więc commity gałęzi się nie dublują), pogrupowane
# według typu Conventional Commit; "Consumer action required" zbiera trailery Consumer-Action wszystkich commitów
# zakresu ("None.", gdy żadnego). Temat spoza Conventional Commits trafia do "Unclassified" do przeredagowania.
#   ./scripts/release-notes.sh v1.6.0..HEAD
set -euo pipefail
range=${1:?Usage: release-notes.sh <from>..<to>}

actions=$(git log --no-merges --format='%h%x1f%b%x1e' "$range" | awk -v RS=$'\036' -v FS=$'\037' '
  {
    sub(/^\n+/, "", $1)
    rest = $2
    while (match(rest, /(^|\n)Consumer-Action: [^\n]+/)) {
      trailer = substr(rest, RSTART, RLENGTH)
      sub(/^\n?Consumer-Action: /, "", trailer)
      print "- " trailer " (" $1 ")"
      rest = substr(rest, RSTART + RLENGTH)
    }
  }')

added="" changed="" fixed="" unclassified=""
while IFS=$'\037' read -r sha subject; do
  [[ -n "$sha" ]] || continue
  [[ "$subject" =~ ^chore\(release\): ]] && continue
  if [[ "$subject" =~ ^([a-z]+)(\([a-z0-9-]+\))?!?:\ (.+)$ ]]; then
    entry="- ${BASH_REMATCH[3]} ($sha)"$'\n'
    case "${BASH_REMATCH[1]}" in
      feat) added+="$entry" ;;
      fix) fixed+="$entry" ;;
      *) changed+="$entry" ;;
    esac
  else
    unclassified+="- $subject ($sha)"$'\n'
  fi
done < <(git log --first-parent --format='%h%x1f%s' "$range")

printf '### Consumer action required\n\n%s\n' "${actions:-None.}"
for heading in Added Changed Fixed; do
  case "$heading" in Added) body=$added ;; Changed) body=$changed ;; Fixed) body=$fixed ;; esac
  [[ -n "$body" ]] && printf '\n### %s\n\n%s' "$heading" "$body"
done
if [[ -n "$unclassified" ]]; then
  printf '\n### Unclassified (not Conventional Commits; reword or drop)\n\n%s' "$unclassified"
fi
