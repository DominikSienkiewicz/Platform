#!/usr/bin/env bash
# release-notes.sh <from>..<to> — treść sekcji CHANGELOG.md z historii wydania; ./release.sh składa nią sekcję
# wersji, gdy CHANGELOG.md jej nie ma. Tematy idą z historii first-parent (merge.sh scala z --no-ff, więc commity
# gałęzi się nie dublują), pogrupowane według typu Conventional Commit. "Consumer action required" zbiera ze
# wszystkich commitów zakresu trailery Consumer-Action, a commit bez trailera ze stopką BREAKING CHANGE albo "!"
# w temacie jako "Breaking change: …" ("None.", gdy żadnego). Temat spoza Conventional Commits trafia do
# "Unclassified" do przeredagowania (release.sh takiej sekcji nie składa).
#   ./scripts/release-notes.sh v1.6.0..HEAD
set -euo pipefail
range=${1:?Usage: release-notes.sh <from>..<to>}

actions=$(git log --no-merges --format='%h%x1f%s%x1f%b%x1e' "$range" | awk -v RS=$'\036' -v FS=$'\037' '
  {
    sub(/^\n+/, "", $1)
    if ($1 == "") next
    rest = $3
    listed = 0
    while (match(rest, /(^|\n)Consumer-Action: [^\n]+/)) {
      trailer = substr(rest, RSTART, RLENGTH)
      sub(/^\n?Consumer-Action: /, "", trailer)
      print "- " trailer " (" $1 ")"
      listed = 1
      rest = substr(rest, RSTART + RLENGTH)
    }
    if (listed) next
    if (match($3, /(^|\n)BREAKING[ -]CHANGE: [^\n]+/)) {
      footer = substr($3, RSTART, RLENGTH)
      sub(/^\n?BREAKING[ -]CHANGE: /, "", footer)
      print "- Breaking change: " footer " (" $1 ")"
    } else if ($2 ~ /^[a-z]+(\([a-z0-9-]+\))?!: /) {
      description = $2
      sub(/^[a-z]+(\([a-z0-9-]+\))?!: /, "", description)
      print "- Breaking change: " description " (" $1 ")"
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
