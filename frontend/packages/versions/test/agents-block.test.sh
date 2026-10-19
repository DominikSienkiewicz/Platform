#!/usr/bin/env bash
# sync-agents-block.py (N-SHOW-1): blok platform-agents wstawiony, gdy go nie ma, zastąpiony w miejscu, gdy jest,
# tekst poza markerami bajt w bajt ten sam, drugi przebieg bez zmian, a brak AGENTS.md tworzy plik. Kopia bloku
# w paczce versions równa się kanonowi z templates/agents.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/AGENTS.md" >&2 2>/dev/null; exit 1; }
sync() { python3 "$here/../bin/sync-agents-block.py" "$here/../agents/platform-block.md" "$1" "$tmp/AGENTS.md"; }
canon="$here/../../../../templates/agents/platform-block.md"
if [[ -f "$canon" ]]; then cmp -s "$canon" "$here/../agents/platform-block.md" || fail 'the packaged block must equal templates/agents/platform-block.md'; fi

printf '# Consumer\n\nOur own rules.\n' > "$tmp/AGENTS.md"
[[ "$(sync 1.6.0)" == added ]] || fail 'a file without the block gets it appended'
grep -qF '<!-- BEGIN platform-agents v1.6.0 ' "$tmp/AGENTS.md" || fail 'the block carries the target version'
[[ "$(head -3 "$tmp/AGENTS.md")" == $'# Consumer\n\nOur own rules.' ]] || fail 'the text before the block is unchanged'

printf '\n## After the block\n\nMore rules.\n' >> "$tmp/AGENTS.md"
before=$(sed '/<!-- BEGIN platform-agents/,/<!-- END platform-agents -->/d' "$tmp/AGENTS.md")
[[ "$(sync 1.7.0)" == replaced ]] || fail 'an existing block is replaced'
grep -qF '<!-- BEGIN platform-agents v1.7.0 ' "$tmp/AGENTS.md" || fail 'the replacement carries the new version'
[[ $(grep -c '<!-- BEGIN platform-agents' "$tmp/AGENTS.md") -eq 1 ]] || fail 'there is one block only'
after=$(sed '/<!-- BEGIN platform-agents/,/<!-- END platform-agents -->/d' "$tmp/AGENTS.md")
[[ "$before" == "$after" ]] || fail 'text outside the markers must stay byte-identical'
snapshot=$(cat "$tmp/AGENTS.md")
[[ "$(sync 1.7.0)" == unchanged && "$(cat "$tmp/AGENTS.md")" == "$snapshot" ]] || fail 'a second run must be a no-op'

rm "$tmp/AGENTS.md"
[[ "$(sync 1.7.0)" == added ]] || fail 'a missing AGENTS.md is created'
[[ "$(head -1 "$tmp/AGENTS.md")" == '<!-- BEGIN platform-agents v1.7.0 (managed by platform-bump; edits inside these markers are replaced) -->' ]] \
  || fail 'a new AGENTS.md starts with the block'
echo 'OK: sync-agents-block inserts, replaces in place and leaves the rest of AGENTS.md alone'
