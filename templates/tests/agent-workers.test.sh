#!/usr/bin/env bash
# agent-gradle.sh i AI_AGENT_MAX_WORKERS (N-SHOW-2): jedno pokrętło liczby workerów dla Gradle'a i Vitesta,
# domyślnie 2; poza trybem agenta nie działa, a wartość, która nie jest dodatnią liczbą, kończy się kodem 2.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/scripts"
cp "$root/templates/agent-gradle.sh" "$tmp/scripts/agent-gradle.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' > "$tmp/gradlew"
chmod +x "$tmp/gradlew"
fail() { echo "FAIL: $*" >&2; exit 1; }

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
