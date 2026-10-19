#!/usr/bin/env bash
# scripts/upsert-issue.sh na stubie gh: brak otwartego issue z dokładnym tytułem = nowe issue, jest = komentarz.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/gh.log" >&2; exit 1; }

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
if [[ "$1 $2" == "issue list" ]]; then cat "$FAKE_ISSUES"; fi
exit 0
STUB
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" FAKE_LOG="$tmp/gh.log" FAKE_ISSUES="$tmp/issues.json"
echo 'Gradle 9.9-rc-1 breaks the starter' > "$tmp/body.md"

echo '[{"number": 3, "title": "Upstream canary: Gradle release candidate (old)"}]' > "$FAKE_ISSUES"
bash "$root/scripts/upsert-issue.sh" 'Upstream canary: Gradle release candidate' "$tmp/body.md" > "$tmp/out"
grep -qF "gh issue create --title Upstream canary: Gradle release candidate --body-file $tmp/body.md" "$tmp/gh.log" \
  || fail 'without an open issue of that exact title a new one must be opened'

: > "$tmp/gh.log"
echo '[{"number": 3, "title": "Other"}, {"number": 7, "title": "Upstream canary: Gradle release candidate"}]' > "$FAKE_ISSUES"
bash "$root/scripts/upsert-issue.sh" 'Upstream canary: Gradle release candidate' "$tmp/body.md" > "$tmp/out"
grep -qF "gh issue comment 7 --body-file $tmp/body.md" "$tmp/gh.log" || fail 'an open issue of that title must get a comment'
if grep -qF 'issue create' "$tmp/gh.log"; then fail 'no second issue may be opened'; fi
grep -qx 'Updated issue #7: Upstream canary: Gradle release candidate' "$tmp/out" || fail 'the update must be reported'

echo 'OK: upsert-issue keeps one open issue per title'
