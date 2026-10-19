#!/usr/bin/env bash
# The open-pr block of platform-bump.yml puts the impact report of `platform-bump --report` (N-REL-8) into the pull
# request body when the bump job produced one, above the log; without a report the body is as before.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
OUT=""
fail() { echo "FAIL: $*" >&2; echo "$OUT" >&2; exit 1; }
awk 'index($0, "# >>> open-pr") { inside = 1; next } index($0, "# <<< open-pr") { inside = 0 } inside' \
  "$root/.github/workflows/platform-bump.yml" > "$tmp/open-pr.sh"
grep -q 'BUMP_REPORT' "$tmp/open-pr.sh" || fail 'the open-pr block must read the report'
grep -q -- '--report=' "$root/.github/workflows/platform-bump.yml" || fail 'the bump job must ask platform-bump for the report'
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\nprevious=""\nfor arg in "$@"; do [[ "$previous" == --body-file ]] && cp "$arg" "$GH_BODY"; previous="$arg"; done\n' > "$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
printf 'bump log\n' > "$tmp/bump.log"
printf '## Platform 1.5.31 → 1.6.0: impact on this repository\n\n### Affects this repo\n\n- catalog `libs.jsoup`\n' > "$tmp/report.md"

# shellcheck disable=SC2329 # wołana niżej, w pętli przez nazwę
attempt() {
  local name=$1 report=$2 work="$tmp/$1"
  git init -q --bare -b main "$work.git"
  git init -q -b main "$work"
  mkdir -p "$work/backend"
  printf 'platformVersion=1.5.31\n' > "$work/backend/gradle.properties"
  git -C "$work" add -A
  git -C "$work" -c user.name=t -c user.email=t@example.invalid commit -q -m initial
  git -C "$work" remote add origin "$work.git"
  git -C "$work" push -q origin main
  printf 'platformVersion=1.6.0\n' > "$work/backend/gradle.properties"
  rm -f "$tmp/gh-body"
  OUT=$(cd "$work" && PATH="$tmp/bin:$PATH" GH_BODY="$tmp/gh-body" RUNNER_TEMP="$tmp" TARGET=1.6.0 BASE=main \
    BUMP_LOG="$tmp/bump.log" BUMP_REPORT="$report" BUMP_TOKEN=pat PUSH_TOKEN=pat bash "$tmp/open-pr.sh" 2>&1) || fail "$name: the block must succeed"
}

attempt with-report "$tmp/report.md"
grep -qF '### Affects this repo' "$tmp/gh-body" || fail 'the body must carry the impact report'
[[ $(grep -n 'Affects this repo' "$tmp/gh-body" | cut -d: -f1) -lt $(grep -n 'bump log' "$tmp/gh-body" | cut -d: -f1) ]] \
  || fail 'the report comes before the log'
attempt without-report "$tmp/absent.md"
grep -qF 'Affects this repo' "$tmp/gh-body" && fail 'without a report the body has none'
echo 'OK: the bump pull request carries the impact report above the bump log'
