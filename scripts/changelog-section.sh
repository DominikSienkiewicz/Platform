#!/usr/bin/env bash
# changelog-section.sh — wypisuje treść sekcji jednej wersji z CHANGELOG.md (bez nagłówka,
# bez pustych linii na brzegach). Jedno źródło dla release.sh (odmowy i annotated tag)
# oraz release.yml (treść GitHub Release) — patrz docs/adr/0002-release-and-versioning-contract.md.
#
# Użycie:
#   scripts/changelog-section.sh <wersja> [changelog]                    # sekcja "## [<wersja>] - <data>"
#   scripts/changelog-section.sh --consumer-action <wersja> [changelog]  # jej "### Consumer action required"
#
# Kończy się kodem 1, gdy sekcji (albo, z --consumer-action, podsekcji) nie ma.
set -euo pipefail

mode=section
if [[ "${1:-}" == "--consumer-action" ]]; then
  mode=consumer-action
  shift
fi
version="${1:?usage: changelog-section.sh [--consumer-action] <version> [changelog]}"
changelog="${2:-CHANGELOG.md}"
[[ -f "$changelog" ]] || { echo "changelog-section: $changelog not found" >&2; exit 1; }

awk -v heading="## [$version] - " -v mode="$mode" '
  index($0, heading) == 1 { found = 1; inside = 1; next }
  inside && /^## / { inside = 0 }
  !inside { next }
  mode == "consumer-action" {
    if ($0 == "### Consumer action required") { subsection = 1; selected = 1; next }
    if (selected && /^### /) { selected = 0 }
    if (!selected) { next }
  }
  { lines[++count] = $0 }
  END {
    if (!found || (mode == "consumer-action" && !subsection)) { exit 1 }
    first = 1
    while (first <= count && lines[first] ~ /^[[:space:]]*$/) { first++ }
    last = count
    while (last >= first && lines[last] ~ /^[[:space:]]*$/) { last-- }
    for (line = first; line <= last; line++) { print lines[line] }
  }
' "$changelog"
