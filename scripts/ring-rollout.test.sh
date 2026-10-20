#!/usr/bin/env bash
# ring-rollout.sh: Touchstone dostaje bump pierwszy, reszta konsumentów dopiero po zielonych checkach jego PR-a;
# czerwone checki zatrzymują rollout przed pierścieniem 2. gh jest podmieniony i zapisuje wywołania.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "$OUT" >&2; cat "$tmp/calls" >&2 2>/dev/null; exit 1; }
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
case "$1 $2" in
  "pr list") echo 7 ;;
  "pr checks") [[ "${FAKE_CHECKS:-pass}" == pass ]] ;;
esac
GH
chmod +x "$tmp/bin/gh"
run() { : > "$tmp/calls"; RC=0; OUT=$(PATH="$tmp/bin:$PATH" GH_CALLS="$tmp/calls" RING_ROLLOUT_POLL=0 bash "$here/ring-rollout.sh" "$@" 2>&1) || RC=$?; }

run 1.6.0
[[ $RC -eq 0 ]] || fail 'a green ring 1 must reach ring 2'
[[ "$(sed -n 1p "$tmp/calls")" == "workflow run platform-bump.yml -R DominikSienkiewicz/Touchstone -f version=1.6.0" ]] || fail 'Touchstone goes first'
checks=$(grep -n '^pr checks' "$tmp/calls" | head -1 | cut -d: -f1)
second=$(grep -n '^workflow run' "$tmp/calls" | sed -n 2p | cut -d: -f1)
[[ -n "$checks" && -n "$second" && $checks -lt $second ]] || fail 'ring 2 waits for the checks of ring 1'
consumers=$(grep -cEv '^[[:space:]]*(#|$)' "$here/consumers.txt")
[[ $(grep -c '^workflow run' "$tmp/calls") -eq $consumers ]] || fail 'every consumer is bumped once'
grep -q 'Touchstone' <(grep '^workflow run' "$tmp/calls" | sed 1d) && fail 'Touchstone is bumped only in ring 1'

FAKE_CHECKS=fail run 1.6.0
[[ $RC -eq 1 ]] || fail 'red checks in ring 1 must stop the rollout'
[[ $(grep -c '^workflow run' "$tmp/calls") -eq 1 ]] || fail 'no consumer of ring 2 may be bumped after red checks'
grep -qF 'stops there; the other consumers were not bumped' <<<"$OUT" || fail 'the stop must be explained'

run 1.6.0 --dry-run
[[ ! -s "$tmp/calls" ]] || fail 'a dry run calls nothing'
grep -qF 'would run platform-bump.yml in DominikSienkiewicz/Touchstone for 1.6.0' <<<"$OUT" || fail 'a dry run prints the plan'
echo 'OK: ring-rollout bumps Touchstone first and the other consumers only after its pull request is green'
