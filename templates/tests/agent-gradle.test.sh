#!/usr/bin/env bash
# templates/agent-gradle.sh, przypadek po przypadku: limity agenta i układ backend/, brak wrappera, ogólnomaszynowe
# sloty testów i AI_AGENT_MAX_WORKERS.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- flags-and-layout ---
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/scripts"
cp "$root/templates/agent-gradle.sh" "$tmp/scripts/agent-gradle.sh"
cat > "$tmp/gradlew" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@"
STUB
chmod +x "$tmp/gradlew"
for mode in '' 0 false TRUE; do
 actual=$(AI_AGENT="$mode" bash "$tmp/scripts/agent-gradle.sh" 'task with spaces')
 [[ "$actual" == 'task with spaces' ]] || { echo "Unexpected flags for $mode" >&2; exit 1; }
done
for mode in 1 true; do
 actual=$(AI_AGENT="$mode" bash "$tmp/scripts/agent-gradle.sh" '--max-workers=9' ':module:test')
 expected=$'--max-workers=9\n:module:test\n--max-workers=2\n--no-parallel'
 [[ "$actual" == "$expected" ]] || { echo "Missing agent limits for $mode" >&2; exit 1; }
done
layout="$tmp/backend-layout"
mkdir -p "$layout/scripts" "$layout/backend"
cp "$root/templates/agent-gradle.sh" "$layout/scripts/agent-gradle.sh"
cat > "$layout/backend/gradlew" <<'STUB'
#!/usr/bin/env bash
pwd -P
printf '%s\n' "$@"
STUB
chmod +x "$layout/backend/gradlew"
backend_dir=$(cd "$layout/backend" && pwd -P)
actual=$(AI_AGENT='' bash "$layout/scripts/agent-gradle.sh" ':module:test')
[[ "$actual" == "$backend_dir"$'\n:module:test' ]] || { echo "backend/gradlew not run from backend/" >&2; exit 1; }
actual=$(AI_AGENT=1 bash "$layout/scripts/agent-gradle.sh" ':module:test')
expected="$backend_dir"$'\n:module:test\n--max-workers=2\n--no-parallel'
[[ "$actual" == "$expected" ]] || { echo "Missing agent limits for backend/gradlew" >&2; exit 1; }
)

# --- no-wrapper ---
# agent-gradle.sh w repozytorium bez ./gradlew i bez backend/gradlew mówi o tym i kończy się kodem 1,
# zamiast paść na exec z "No such file or directory" (kod 127).
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/scripts"
cp "$root/templates/agent-gradle.sh" "$tmp/scripts/agent-gradle.sh"
rc=0
out=$(bash "$tmp/scripts/agent-gradle.sh" build 2>&1) || rc=$?
[[ $rc -eq 1 ]] || { echo "FAIL: expected exit 1 without a wrapper, got $rc: $out" >&2; exit 1; }
grep -qF 'No gradlew in . or backend/' <<<"$out" || { echo "FAIL: the message must name both places: $out" >&2; exit 1; }
echo 'OK: agent-gradle.sh names the missing wrapper and exits 1'
)

# --- test-slots ---
# Semafor slotów agent-gradle.sh między osobnymi wywołaniami Gradle: przy AI_AGENT_TEST_SLOTS=1 dwa runy testów
# idą po kolei, slot martwego PID-u jest odzyskiwany, zadania bez testów go omijają, kod wyjścia przechodzi dalej,
# a przekroczenie AI_AGENT_SLOT_TIMEOUT kończy się kodem 75.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

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
)

# --- max-workers ---
# agent-gradle.sh i AI_AGENT_MAX_WORKERS (N-SHOW-2): jedno pokrętło liczby workerów dla Gradle'a i Vitesta,
# domyślnie 2; poza trybem agenta nie działa, a wartość, która nie jest dodatnią liczbą, kończy się kodem 2.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/scripts"
cp "$root/templates/agent-gradle.sh" "$tmp/scripts/agent-gradle.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' > "$tmp/gradlew"
chmod +x "$tmp/gradlew"

actual=$(AI_AGENT=1 AI_AGENT_MAX_WORKERS=3 bash "$tmp/scripts/agent-gradle.sh" 'help')
[[ "$actual" == $'help\n--max-workers=3\n--no-parallel' ]] || fail "AI_AGENT_MAX_WORKERS=3 must yield --max-workers=3, got: $actual"
actual=$(AI_AGENT=1 bash "$tmp/scripts/agent-gradle.sh" 'help')
[[ "$actual" == $'help\n--max-workers=2\n--no-parallel' ]] || fail "the default must stay --max-workers=2, got: $actual"
actual=$(AI_AGENT='' AI_AGENT_MAX_WORKERS=3 bash "$tmp/scripts/agent-gradle.sh" 'help')
[[ "$actual" == 'help' ]] || fail "without AI_AGENT the variable must change nothing, got: $actual"
status=0
message=$(AI_AGENT=1 AI_AGENT_MAX_WORKERS=many bash "$tmp/scripts/agent-gradle.sh" 'help' 2>&1) || status=$?
[[ "$status" -eq 2 ]] || fail "an invalid AI_AGENT_MAX_WORKERS must exit 2, got $status"
grep -qF "AI_AGENT_MAX_WORKERS must be a positive integer, got 'many'." <<<"$message" || fail "the error must name the value"
echo 'OK: agent-gradle.sh reads AI_AGENT_MAX_WORKERS in agent mode only'
)
