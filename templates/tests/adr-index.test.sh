#!/usr/bin/env bash
# scripts/adr-index.sh: docs/adr/README.md odpowiada plikom ADR, a ADR dodany bez regeneracji indeksu failuje --check.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

bash "$root/scripts/adr-index.sh" --check > /dev/null || fail 'docs/adr/README.md must list every ADR; run scripts/adr-index.sh'

cp -R "$root/docs/adr" "$tmp/adr"
printf '# ADR-0999: A decision nobody indexed\n\n## Status\n\nProposed\n' > "$tmp/adr/0999-unindexed.md"
if bash "$root/scripts/adr-index.sh" --check "$tmp/adr" > /dev/null 2>&1; then fail 'an ADR missing from the index must fail --check'; fi
bash "$root/scripts/adr-index.sh" "$tmp/adr" > /dev/null
grep -qxF '| [0999](0999-unindexed.md) | A decision nobody indexed | Proposed |' "$tmp/adr/README.md" || fail 'regenerating must add the row'
bash "$root/scripts/adr-index.sh" --check "$tmp/adr" > /dev/null || fail 'the regenerated index must pass --check'
head -3 "$tmp/adr/README.md" | grep -qF '# Architecture decision records' || fail 'the text above the table must stay'

printf 'no title\n' > "$tmp/adr/0998-broken.md"
if bash "$root/scripts/adr-index.sh" "$tmp/adr" > /dev/null 2>&1; then fail 'an ADR without a title must be refused'; fi

echo 'OK: adr-index keeps docs/adr/README.md in step with the ADR files'
