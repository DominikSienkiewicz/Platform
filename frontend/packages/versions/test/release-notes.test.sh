#!/usr/bin/env bash
# Test bloków python z bin/platform-bump.sh, które wybierają wersję docelową i pokazują notatki
# wydań, przez które bump przechodzi (docs/adr/0002-release-and-versioning-contract.md).
#
# Bloki są WYCINANE ze skryptu po markerach (`# platform-bump:target` / `# platform-bump:notes`)
# i uruchamiane na fiksturach JSON — bez sieci i bez GitHub API, ale na kodzie z produkcji.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/bin/platform-bump.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { local message="$1"; echo "FAIL: $message"; exit 1; }

# Wycina ciało heredoca od linii z markerem do terminatora `PY` (bez niego).
extract() { local marker="$1"; awk -v m="$marker" 'index($0, m) { f = 1 } f && $0 == "PY" { exit } f' "$SRC"; }

extract '# platform-bump:target' > "$WORK/target.py"
extract '# platform-bump:notes' > "$WORK/notes.py"
[[ -s "$WORK/target.py" ]] || fail "no '# platform-bump:target' block in $SRC"
[[ -s "$WORK/notes.py" ]] || fail "no '# platform-bump:notes' block in $SRC"

# --- Target: newest release of the current MAJOR, never a new MAJOR by default ---------------
cat > "$WORK/versions.json" <<'JSON'
[{"name": "1.5.30"}, {"name": "2.0.0"}, {"name": "1.6.0"}, {"name": "1.5.31"}, {"name": "2.0.0-rc1"}]
JSON
[[ "$(python3 "$WORK/target.py" "$WORK/versions.json" 1.5.31)" == "1.6.0 2.0.0" ]] \
  || fail 'without an argument the bump must stay in the current MAJOR and report the newest release'
[[ "$(python3 "$WORK/target.py" "$WORK/versions.json" 2.0.0)" == "2.0.0 2.0.0" ]] \
  || fail 'a consumer already on the newest MAJOR must get its newest release'
[[ "$(python3 "$WORK/target.py" "$WORK/versions.json" "")" == "2.0.0 2.0.0" ]] \
  || fail 'without a known current pin the bump must take the newest release'

# --- Notes: every release in (current, target], oldest first, and their consumer actions ------
cat > "$WORK/releases.json" <<'JSON'
[
  {"tag_name": "v1.7.0", "body": "### Consumer action required\r\n\r\n- Beyond the target.\r\n"},
  {"tag_name": "v1.6.1", "body": "### Consumer action required\r\n\r\nNone.\r\n\r\n### Fixed\r\n\r\n- A fix.\r\n"},
  {"tag_name": "v1.6.0", "body": "### Consumer action required\r\n\r\n- Grant packages: read.\r\n\r\n### Changed\r\n\r\n- A gate.\r\n\r\n**Full diff:** https://example.invalid/compare\r\n"},
  {"tag_name": "v1.5.31", "body": "### Consumer action required\r\n\r\nNone.\r\n"},
  {"tag_name": "latest", "body": "not a version"}
]
JSON
notes=$(python3 "$WORK/notes.py" "$WORK/releases.json" 1.5.31 1.6.1 "$WORK/actions.txt")
grep -q '^===== Platform 1.6.0 =====$' <<<"$notes" || fail 'the notes of 1.6.0 must be printed'
grep -q '^===== Platform 1.6.1 =====$' <<<"$notes" || fail 'the notes of the target must be printed'
if grep -Eq 'Platform 1\.5\.31|Platform 1\.7\.0|Beyond the target' <<<"$notes"; then
  fail 'only releases after the current pin and up to the target may be printed'
fi
[[ "$(grep -n '===== Platform' <<<"$notes" | head -1)" == *'1.6.0'* ]] || fail 'the notes must be printed oldest first'
[[ "$(cat "$WORK/actions.txt")" == "$(printf 'Platform 1.6.0:\n- Grant packages: read.')" ]] \
  || { cat "$WORK/actions.txt"; fail 'the consumer actions must list exactly the releases whose action is not None'; }

python3 "$WORK/notes.py" "$WORK/releases.json" 1.6.1 1.6.1 "$WORK/none.txt" | grep -q 'No release notes' \
  || fail 'a bump to the current version must say there are no notes'
[[ ! -s "$WORK/none.txt" ]] || fail 'a bump without releases must not report consumer actions'

echo 'OK: platform-bump stays in the current MAJOR and prints the notes and consumer actions it crosses'
