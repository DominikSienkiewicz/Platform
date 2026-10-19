#!/usr/bin/env bash
# Semafor slotów agent-gradle.sh między osobnymi wywołaniami Gradle: przy AI_AGENT_TEST_SLOTS=1 dwa runy testów
# idą po kolei, slot martwego PID-u jest odzyskiwany, zadania bez testów go omijają, kod wyjścia przechodzi dalej,
# a przekroczenie AI_AGENT_SLOT_TIMEOUT kończy się kodem 75.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/repo/scripts" "$tmp/slots-tmp"
cp "$root/templates/agent-gradle.sh" "$tmp/repo/scripts/agent-gradle.sh"
cat > "$tmp/repo/gradlew" <<'STUB'
#!/usr/bin/env bash
echo "start $1 $(date +%s%N)" >> "$FAKE_LOG"
sleep "${FAKE_SLEEP:-0}"
echo "end $1 $(date +%s%N)" >> "$FAKE_LOG"
exit "${FAKE_RC:-0}"
STUB
chmod +x "$tmp/repo/gradlew"
export TMPDIR="$tmp/slots-tmp" AI_AGENT=1 FAKE_LOG="$tmp/gradle.log"
run() { bash "$tmp/repo/scripts/agent-gradle.sh" "$@"; }
slots="$TMPDIR/platform-agent-slots"

# (a) dwa równoległe runy testów przy jednym slocie się nie nakładają
: > "$FAKE_LOG"
AI_AGENT_TEST_SLOTS=1 FAKE_SLEEP=1 run first:test 2>/dev/null &
first=$!
sleep 0.3
AI_AGENT_TEST_SLOTS=1 FAKE_SLEEP=1 run second:test 2>"$tmp/wait.err" &
second=$!
wait "$first" "$second"
order=$(awk '{print $1, $2}' "$FAKE_LOG" | tr '\n' ' ')
[[ "$order" == 'start first:test end first:test start second:test end second:test ' ]] || fail "test runs must serialize, got: $order"
grep -qF 'waiting for an agent test slot (1 in use, held by pids' "$tmp/wait.err" || fail 'the waiting run must say so'
[[ -z "$(ls -A "$slots")" ]] || fail 'every slot must be released'

# (b) slot martwego procesu jest odzyskiwany
mkdir -p "$slots/slot-1" && echo 999999 > "$slots/slot-1/pid"
AI_AGENT_TEST_SLOTS=1 AI_AGENT_SLOT_TIMEOUT=2 run reclaimed:test 2>/dev/null || fail 'a slot held by a dead pid must be reclaimed'

# (c) zadania bez testów omijają semafor, nawet gdy jedyny slot zajmuje żywy proces
mkdir -p "$slots/slot-1" && echo $$ > "$slots/slot-1/pid"
AI_AGENT_TEST_SLOTS=1 AI_AGENT_SLOT_TIMEOUT=1 run spotlessApply 2>/dev/null || fail 'spotlessApply must not wait for a test slot'

# (d) brak wolnego slotu przez AI_AGENT_SLOT_TIMEOUT = kod 75
set +e
AI_AGENT_TEST_SLOTS=1 AI_AGENT_SLOT_TIMEOUT=1 run blocked:check 2>"$tmp/timeout.err"
rc=$?
set -e
[[ $rc -eq 75 ]] || fail "a timed-out wait must exit 75, got $rc"
grep -qF 'No agent test slot became free in 1s' "$tmp/timeout.err" || fail 'the timeout must be explained'
rm -rf "$slots/slot-1"

# (e) kod wyjścia Gradle przechodzi dalej, a slot zostaje zwolniony
set +e
FAKE_RC=3 run failing:test 2>/dev/null
rc=$?
set -e
[[ $rc -eq 3 ]] || fail "the Gradle exit code must propagate, got $rc"
[[ -z "$(ls -A "$slots")" ]] || fail 'a failing run must release its slot'

echo 'OK: agent-gradle.sh serializes test runs across invocations through machine-wide slots'
