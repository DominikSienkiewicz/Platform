#!/usr/bin/env bash
# scripts/gate-failures.py liczy porażki konsumentów na kod bramki, tydzień ISO i pin, bez treści komunikatów.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "$out" >&2; exit 1; }
cat > "$tmp/annotations.json" <<'JSON'
[
  {"repo": "acme/one", "pin": "1.6.0", "completed_at": "2026-10-19T10:00:00Z", "title": "PLAT-DEP-001", "message": "secret detail"},
  {"repo": "acme/two", "pin": "1.6.0", "completed_at": "2026-10-20T10:00:00Z", "title": "Platform canon", "message": "[PLAT-DEP-001] x"},
  {"repo": "acme/one", "pin": "1.5.31", "completed_at": "2026-10-12T10:00:00Z", "title": "PLAT-VER-001", "message": "y"},
  {"repo": "acme/one", "pin": "1.6.0", "completed_at": "2026-10-19T11:00:00Z", "title": "Test failed: A", "message": "no code"}
]
JSON
out=$(python3 -I "$here/gate-failures.py" "$tmp/annotations.json")
grep -qxF '| PLAT-DEP-001 | 2026-W43 | 1.6.0 | 2 |' <<<"$out" || fail 'two PLAT-DEP-001 failures in week 43 on 1.6.0'
grep -qxF '| PLAT-VER-001 | 2026-W42 | 1.5.31 | 1 |' <<<"$out" || fail 'one PLAT-VER-001 failure in week 42 on 1.5.31'
if grep -q 'secret detail\|acme/' <<<"$out"; then fail 'the report must stay aggregate'; fi
[[ $(grep -c '^| PLAT-' <<<"$out") -eq 2 ]] || fail 'annotations without a code are not counted'
echo 'OK: gate-failures counts consumer failures per gate code, week and pin'
