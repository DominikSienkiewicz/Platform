#!/usr/bin/env bash
# Copy to scripts/agent-gradle.sh in a consumer. Explicitly opt in with AI_AGENT=1 or true.
# Runs ./gradlew from the repository root, or backend/gradlew from backend/ when the root has none.
#
# With AI_AGENT on, Gradle runs with --max-workers=${AI_AGENT_MAX_WORKERS:-2} --no-parallel (the Vitest preset reads
# the same variable), and a run of test, integrationTest,
# check or build first takes one of AI_AGENT_TEST_SLOTS (default 3) machine-wide slots, so parallel agents
# cannot start more JVM test suites at once than the machine holds. A slot is a directory under
# ${TMPDIR:-/tmp}/platform-agent-slots/ holding its owner's PID; a slot whose owner died is reclaimed.
# Waiting longer than AI_AGENT_SLOT_TIMEOUT seconds (default 3600) exits with 75. Slots are per OS
# instance: agents in separate containers are not coordinated.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f gradlew && -f backend/gradlew ]]; then cd backend; fi
[[ -f gradlew ]] || { echo "No gradlew in . or backend/; copy the wrapper from Platform: gradle/catalog/{gradlew,gradlew.bat,gradle}." >&2; exit 1; }
case "${AI_AGENT:-}" in
  1|true) ;;
  *) exec ./gradlew "$@" ;;
esac
workers=${AI_AGENT_MAX_WORKERS:-2}
[[ "$workers" =~ ^[1-9][0-9]*$ ]] || { echo "AI_AGENT_MAX_WORKERS must be a positive integer, got '$workers'." >&2; exit 2; }

needs_slot=0
for task in "$@"; do
  case "$task" in
    test | *:test | integrationTest | *:integrationTest | check | *:check | build | *:build) needs_slot=1 ;;
  esac
done
[[ "$needs_slot" -eq 1 ]] || exec ./gradlew "$@" --max-workers="$workers" --no-parallel

slots=${AI_AGENT_TEST_SLOTS:-3}
timeout=${AI_AGENT_SLOT_TIMEOUT:-3600}
dir="${TMPDIR:-/tmp}/platform-agent-slots"
mkdir -p "$dir"
slot=""
acquire() {
  local number owner
  for ((number = 1; number <= slots; number++)); do
    if mkdir "$dir/slot-$number" 2>/dev/null; then
      echo $$ > "$dir/slot-$number/pid"
      slot="$dir/slot-$number"
      return 0
    fi
    owner=$(cat "$dir/slot-$number/pid" 2>/dev/null || true)
    if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$dir/slot-$number"
      number=$((number - 1))
    fi
  done
  return 1
}
holders() { cat "$dir"/slot-*/pid 2>/dev/null | tr '\n' ' '; }

waited=0
until acquire; do
  if [[ "$waited" -ge "$timeout" ]]; then
    echo "No agent test slot became free in ${timeout}s (held by pids $(holders)); raise AI_AGENT_TEST_SLOTS or AI_AGENT_SLOT_TIMEOUT." >&2
    exit 75
  fi
  if (( waited % 30 == 0 )); then
    echo "waiting for an agent test slot ($slots in use, held by pids $(holders))" >&2
  fi
  sleep 1
  waited=$((waited + 1))
done
trap 'rm -rf "$slot"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
status=0
./gradlew "$@" --max-workers="$workers" --no-parallel || status=$?
exit "$status"
