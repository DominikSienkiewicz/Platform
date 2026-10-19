#!/usr/bin/env bash
# adr-index.sh [--check] [<adr-dir>] — tabela w docs/adr/README.md generowana z nagłówków ADR (numer z nazwy pliku,
# tytuł z "# ADR-NNNN: …", status z pierwszego słowa pod "## Status"). Bez --check przepisuje tabelę, z --check
# kończy się kodem 1, gdy README nie odpowiada plikom — ADR dodany bez regeneracji indeksu. Tekst nad tabelą
# zostaje. Test: templates/tests/adr-index.test.sh (biegnie w jobie Templates).
set -euo pipefail
check=0
if [[ "${1:-}" == --check ]]; then check=1; shift; fi
dir=${1:-$(cd "$(dirname "$0")/.." && pwd)/docs/adr}
readme="$dir/README.md"

rows="| # | Decision | Status |"$'\n'"| --- | --- | --- |"
for adr in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
  [[ -f "$adr" ]] || continue
  file=${adr##*/}
  number=${file%%-*}
  title=$(sed -n -E "1s/^# ADR-$number: (.*)$/\1/p" "$adr")
  status=$(awk '/^## Status/ { inside = 1; next } inside && NF { print $1; exit }' "$adr")
  if [[ -z "$title" || -z "$status" ]]; then
    echo "$file needs a first line '# ADR-$number: <title>' and a '## Status' section." >&2
    exit 1
  fi
  rows+=$'\n'"| [$number]($file) | $title | $status |"
done

preamble=$(awk '/^\| # \| Decision \| Status \|$/ { exit } { print }' "$readme")
# $(…) gubi końcowe puste linie, więc jedną przed tabelą dodajemy jawnie.
expected="$preamble"$'\n\n'"$rows"
if [[ "$check" -eq 1 ]]; then
  if [[ "$(cat "$readme")" != "$expected" ]]; then
    echo "docs/adr/README.md does not match the ADRs; run scripts/adr-index.sh and commit the result." >&2
    diff <(printf '%s\n' "$expected") "$readme" >&2 || true
    exit 1
  fi
  echo "docs/adr/README.md lists every ADR."
else
  printf '%s\n' "$expected" > "$readme"
  echo "Regenerated $readme."
fi
