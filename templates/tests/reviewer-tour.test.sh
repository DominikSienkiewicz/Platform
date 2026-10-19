#!/usr/bin/env bash
# docs/tour.md ma dziesięć przystanków, każda notatka w docs/notes/ ma objaw, przyczynę, poprawkę i guard,
# a żaden link nie wskazuje ruchomego main: czytane przy tagu, linki względne pokazują kod tego wydania.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ $(grep -cE '^## [0-9]+\. ' "$root/docs/tour.md") -eq 10 ]] || fail 'docs/tour.md must have ten numbered stops'
notes=("$root"/docs/notes/*.md)
[[ ${#notes[@]} -ge 5 ]] || fail 'docs/notes/ must hold the incident notes'
for note in "${notes[@]}"; do
  for part in '**Symptom.**' '**Root cause.**' '**Fix.**' '**Guards.**'; do
    grep -qF "$part" "$note" || fail "${note#"$root"/} lacks $part"
  done
done
if grep -nE 'blob/main/|tree/main/' "$root/docs/tour.md" "$root"/docs/notes/*.md "$root/docs/engineering-with-agents.md"; then
  fail 'the tour and the notes must not link to the moving main branch'
fi
echo 'OK: the reviewer tour has ten stops and every incident note names its guard'
