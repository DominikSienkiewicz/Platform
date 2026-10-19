#!/usr/bin/env bash
# platform-doctor --gradle na atrapie gradlew: wiersze PD08x taska przechodzą 1:1, ich FAIL-e liczą się do wyniku,
# a Gradle, który nie dochodzi do taska (starszy pin), daje PD083. Bez --gradle wrapper nie jest wołany.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" >&2; exit 1; }
: > "$tmp/out"

mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\necho "openjdk version \\"25.0.3\\" 2026-10-14" >&2\n' > "$tmp/bin/java"
chmod +x "$tmp/bin/java"

repo="$tmp/repo"
mkdir -p "$repo/backend"
git -C "$repo" init -q
printf 'plugins { id("seniordev.settings-conventions") version "1.6.0" }\nfrom("pl.seniordeveloper:platform-catalog:1.6.0")\n' > "$repo/backend/settings.gradle.kts"
cat > "$repo/backend/gradlew" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$GRADLEW_LOG"
case "${FAKE_GRADLE:-pass}" in
  pass) printf 'PASS PD080 seniordev.settings-conventions, platform-catalog are all 1.6.0\nPASS PD081 the Java 27 toolchain resolves to /jdks/27\nWARN PD082 coverageMinimum is not set\n          fix: set coverageMinimum\n' ;;
  fail) printf 'FAIL PD080 the Gradle-side Platform pins disagree: seniordev.settings-conventions 1.6.0, platform-catalog 1.5.31\n          fix: run scripts/platform-bump.sh <version>\nPASS PD081 ok\nPASS PD082 coverageMinimum is 0.80\n\nFAILURE: Build failed with an exception.\n' >&2; exit 1 ;;
  missing) printf "\nFAILURE: Build failed with an exception.\n\n* What went wrong:\nTask 'platformDoctor' not found in root project 'app'.\n" >&2; exit 1 ;;
esac
STUB
chmod +x "$repo/backend/gradlew"
export GRADLEW_LOG="$tmp/gradlew.log"
doctor() { (cd "$repo" && env PATH="$tmp/bin:$PATH" FAKE_GRADLE="$1" bash "$here/../bin/platform-doctor.sh" --offline "${@:2}" > "$tmp/out" 2>&1); }

: > "$GRADLEW_LOG"
doctor pass || true
[[ ! -s "$GRADLEW_LOG" ]] || fail 'without --gradle the wrapper must not run'

doctor pass --gradle || true
grep -qx -- '-q --console=plain platformDoctor' "$GRADLEW_LOG" || fail 'the bin must run ./gradlew -q --console=plain platformDoctor in backend/'
grep -qF 'PASS PD081 the Java 27 toolchain resolves to /jdks/27' "$tmp/out" || fail 'the task lines must pass through'
grep -qF '          fix: set coverageMinimum' "$tmp/out" || fail 'the fix lines must pass through'
if grep -q 'PD083' "$tmp/out"; then fail 'a task that ran must not report PD083'; fi

status=0; doctor fail --gradle || status=$?
[[ $status -eq 1 ]] || fail "a FAIL line of the task must fail the bin, got exit $status"
grep -qF 'FAIL PD080 the Gradle-side Platform pins disagree' "$tmp/out" || fail 'the task FAIL must be shown'
grep -qE '^1 check\(s\) failed' "$tmp/out" || fail 'the task FAIL must be counted once'
if grep -q 'FAILURE: Build failed' "$tmp/out"; then fail 'Gradle noise around the task lines must be dropped'; fi

status=0; doctor missing --gradle || status=$?
[[ $status -eq 1 ]] || fail "a Gradle run without the task must fail the bin, got exit $status"
grep -qF "FAIL PD083 backend/gradlew platformDoctor did not run: Task 'platformDoctor' not found in root project 'app'." "$tmp/out" \
  || fail 'a Gradle run that never reached the task must report PD083 with what went wrong'

status=0; (cd "$repo" && bash "$here/../bin/platform-doctor.sh" --bogus > "$tmp/out" 2>&1) || status=$?
[[ $status -eq 2 ]] || fail "an unknown option must exit 2, got $status"

echo 'OK: platform-doctor --gradle passes the platformDoctor lines through and reports PD083 when the task does not run'
