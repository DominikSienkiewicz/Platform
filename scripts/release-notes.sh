#!/usr/bin/env bash
# release-notes.sh <from>..<to> — treść sekcji CHANGELOG.md z historii wydania; ./release.sh składa nią sekcję
# wersji, gdy CHANGELOG.md jej nie ma. Tematy idą z historii first-parent (merge.sh scala z --no-ff, więc commity
# gałęzi się nie dublują), pogrupowane według typu Conventional Commit. "Consumer action required" zbiera ze
# wszystkich commitów zakresu, także z merge commitów merge.sh, trailery Consumer-Action, a commit bez trailera ze
# stopką BREAKING CHANGE albo "!" w temacie jako "Breaking change: …" (pominięte, gdy trailer ma druga strona tego
# samego merge'a); ten sam tekst z kilku commitów (trailer powtórzony w merge commicie) idzie raz, a gdy nic nie ma —
# "None.". Temat spoza Conventional Commits trafia do "Unclassified" do przeredagowania (release.sh takiej sekcji
# nie składa).
#   ./scripts/release-notes.sh v1.6.0..HEAD
#
# release-notes.sh --markers <from>..<to> — jedno źródło znaczników akcji konsumenta dla tej sekcji i dla bramki
# historii w release.sh: rekord na linię, pola rozdzielone \037: <sha> <temat> <trailer|footer|bang> <tekst>.
set -euo pipefail
usage='Usage: release-notes.sh [--markers] <from>..<to>'

# Domyślny merge GitHuba ma tytuł PR-a w pierwszej linii body. Temat zastępujemy tylko
# w rzeczywistym merge'u dwóch commitów i tylko wtedy, gdy tytuł jest Conventional Commit.
release_history() {
  git log --format='%h%x1f%s%x1f%b%x1f%P%x1e' "$@" | awk -v RS=$'\036' -v FS=$'\037' '
    {
      sub(/^\n+/, "", $1)
      if ($1 == "") next
      if ($4 ~ /^[0-9a-f]+ [0-9a-f]+$/ && $2 ~ /^Merge pull request #[0-9]+ from /) {
        split($3, body, "\n")
        if (body[1] ~ /^(feat|fix|docs|chore|refactor|test|build|ci|perf|revert)(\([a-z0-9-]+\))?!?: .+/)
          $2 = body[1]
      }
      printf "%s\037%s\037%s\036", $1, $2, $3
    }'
}

# markers <zakres>: każdy trailer Consumer-Action, pierwsza stopka BREAKING CHANGE i "!" w temacie każdego commita
# zakresu, merge commity włącznie.
markers() {
  release_history "$1" | awk -v RS=$'\036' -v FS=$'\037' '
    {
      sub(/^\n+/, "", $1)
      if ($1 == "") next
      rest = $3
      while (match(rest, /(^|\n)Consumer-Action: [^\n]+/)) {
        trailer = substr(rest, RSTART, RLENGTH)
        sub(/^\n?Consumer-Action: /, "", trailer)
        print $1 "\037" $2 "\037trailer\037" trailer
        rest = substr(rest, RSTART + RLENGTH)
      }
      if (match($3, /(^|\n)BREAKING[ -]CHANGE: [^\n]+/)) {
        footer = substr($3, RSTART, RLENGTH)
        sub(/^\n?BREAKING[ -]CHANGE: /, "", footer)
        print $1 "\037" $2 "\037footer\037" footer
      }
      if ($2 ~ /^[a-z]+(\([a-z0-9-]+\))?!:/) {
        description = $2
        sub(/^[a-z]+(\([a-z0-9-]+\))?!: */, "", description)
        print $1 "\037" $2 "\037bang\037" description
      }
    }'
}

if [[ "${1:-}" == --markers ]]; then
  markers "${2:?$usage}"
  exit 0
fi
range=${1:?$usage}

# Grupy merge.sh: "<merge> <wniesiony commit>…" na linię. Merge commit i to, co wnosi, opisują jedną zmianę, więc
# trailer po jednej stronie zastępuje linię "Breaking change:" po drugiej (np. "!" powtórzony w komunikacie merge.sh).
groups=$(git log --merges --format='%h' "$range" | while read -r merge; do
  printf '%s %s\n' "$merge" "$(git log --format='%h' "$merge^1..$merge^2" | tr '\n' ' ')"
done)
actions=$(awk -v FS=$'\037' '
  NR == FNR { group[++groups] = $0; next }
  { record[++records] = $0; if ($3 == "trailer") with_trailer[$1] = 1 }
  END {
    for (g = 1; g <= groups; g++) {
      n = split(group[g], member, " ")
      for (i = 2; i <= n; i++) {
        if (member[i] in with_trailer) covered[member[1]] = 1
        if (member[1] in with_trailer) covered[member[i]] = 1
      }
    }
    for (r = 1; r <= records; r++) {
      split(record[r], field, "\037")
      if (field[3] == "trailer") { listed[field[1]] = 1; text = field[4] }
      else {
        if ((field[1] in listed) || (field[1] in covered)) continue
        listed[field[1]] = 1
        text = "Breaking change: " field[4]
      }
      if (!(text in seen)) { seen[text] = 1; print "- " text " (" field[1] ")" }
    }
  }' <(printf '%s\n' "$groups") <(markers "$range"))

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
done < <(release_history --first-parent "$range" | awk -v RS=$'\036' -v FS=$'\037' '{ print $1 FS $2 }')

printf '### Consumer action required\n\n%s\n' "${actions:-None.}"
for heading in Added Changed Fixed; do
  case "$heading" in Added) body=$added ;; Changed) body=$changed ;; Fixed) body=$fixed ;; esac
  [[ -n "$body" ]] && printf '\n### %s\n\n%s' "$heading" "$body"
done
if [[ -n "$unclassified" ]]; then
  printf '\n### Unclassified (not Conventional Commits; reword or drop)\n\n%s' "$unclassified"
fi
