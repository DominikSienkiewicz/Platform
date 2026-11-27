#!/usr/bin/env bash
# ADR-0022: everything Platform prints, names or ships for a reader is English; Polish stays only in
# CLAUDE.md and in comments. The guard scans the scripts, workflows, convention plugins, Java libraries and
# starters for Polish letters outside comments. A line that holds Polish letters as data (a detector
# pattern) ends with the comment `language-guard: allow`.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"

polish='ą|ć|ę|ł|ń|ó|ś|ź|ż|Ą|Ć|Ę|Ł|Ń|Ó|Ś|Ź|Ż'

scan() { # $1 = comment style (hash|slash), files on stdin
  local style=$1 file
  while IFS= read -r file; do
    LC_ALL=C awk -v style="$style" -v file="$file" -v polish="$polish" '
      /language-guard: allow[[:space:]]*$/ { next }
      {
        text = $0
        if (style == "hash") {
          if (text ~ /^[[:space:]]*(#|\/\/)/) next
          sub(/[[:space:]]#([[:space:]].*)?$/, "", text)
        } else {
          if (text ~ /^[[:space:]]*(\/\/|\*|\/\*)/) next
          sub(/[[:space:]]\/\/.*$/, "", text)
        }
        if (text ~ polish) printf "  %s:%d: %s\n", file, NR, $0
      }
    ' "$file"
  done
}

hash_files=$(git ls-files '*.sh' '.github/workflows/*.yml' 'templates/github/**.yml' \
  ':!:templates/tests/**' ':!:**/test/**' ':!:*.test.sh')
slash_files=$(git ls-files 'gradle/*/src/main/**.kt' 'gradle/*/src/main/**.kts' 'gradle/*/src/main/**.java' \
  'templates/jvm/**.java' 'templates/jvm/**.kts' 'frontend/packages/*/bin/*.mjs' \
  ':!:**/src/test/**' ':!:**/test/**')

count=$(printf '%s\n%s\n' "$hash_files" "$slash_files" | grep -c . || true)
[[ "$count" -gt 50 ]] || { echo "the language guard found only $count files to scan" >&2; exit 1; }

found=$( { scan hash <<< "$hash_files"; scan slash <<< "$slash_files"; } )
if [[ -n "$found" ]]; then
  printf 'Polish outside comments (ADR-0022: output, names and descriptions are English):\n%s\n' "$found" >&2
  exit 1
fi
echo "OK: $count scripts, workflows and sources print, name and describe in English"
