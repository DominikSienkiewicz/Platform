#!/usr/bin/env bash
# ADR-0038: modules follow the package canon domain, application, adapter.in and adapter.out. A shared
# Checkstyle suppression that names another layer (infrastructure, web outside adapter.in, ...) matches no
# module laid out on the canon, so it silently stops applying; the suppressions name canon layers only.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
xml="$root/gradle/build-logic/src/main/resources/platform-checkstyle/checkstyle-suppressions.xml"

patterns=$(grep -o 'files="[^"]*"' "$xml" | sed 's/^files="//; s/"$//')
[[ -n "$patterns" ]] || { echo "no files= patterns found in $xml" >&2; exit 1; }

stale=$(grep -E '(^|[/.])(infrastructure|web|rest|controller|persistence)([/.]|$)' <<< "$patterns" \
  | grep -v -E 'adapter[/.](in|out)[/.]' || true)
if [[ -n "$stale" ]]; then
  printf 'Checkstyle suppressions name a layer outside the package canon (ADR-0038):\n%s\n' "$stale" >&2
  exit 1
fi
echo "OK: every Checkstyle suppression names a layer of the package canon or no layer at all"
