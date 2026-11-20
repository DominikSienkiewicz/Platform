#!/usr/bin/env bash
# backend-ci.yml, przypadek po przypadku: krok Gradle przekazuje osobne zadania bez rozwijania wildcardów i zachowuje kod
# wyjścia Gradle'a za tee, a dokumentacja Spring Modulith każdego modułu jest wysyłana jako artefakt.
# Wspólne helpery (extract_step) są w lib/workflow.sh.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/workflow.sh
source "$(dirname "$0")/lib/workflow.sh"

# --- gradle-arguments ---
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

awk '
  $0 == "      - name: ./gradlew ${{ inputs.gradle-task }}" { selected = 1; next }
  selected && /^        run: \|$/ { body = 1; next }
  selected && /^        run: / { sub(/^        run: /, ""); print; exit }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$root/.github/workflows/backend-ci.yml" > "$tmp/step.sh"
[[ -s "$tmp/step.sh" ]] || { echo 'Missing backend Gradle step' >&2; exit 1; }

cat > "$tmp/gradlew" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@"
STUB
chmod +x "$tmp/gradlew"
touch "$tmp/:app:bootJar"
cd "$tmp"
actual=$(GRADLE_TASK='lint test :app:integrationTest :app:*' bash -e step.sh)
expected=$'lint\ntest\n:app:integrationTest\n:app:*\n--no-daemon\n--stacktrace'
[[ "$actual" == "$expected" ]] || {
  echo 'Backend CI must forward separate Gradle tasks without expanding wildcard arguments.' >&2
  exit 1
}
)

# --- gradle-failure ---
# Krok Gradle w backend-ci.yml przepuszcza wyjście przez tee do pliku dla digestu; porażka Gradle musi nadal
# failować krok. Domyślna powłoka kroku to `bash -e` bez pipefail, więc test uruchamia go dokładnie tak.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

extract_step "$root/.github/workflows/backend-ci.yml" './gradlew ${{ inputs.gradle-task }}' > "$tmp/step.sh"
[[ -s "$tmp/step.sh" ]] || { echo 'Missing backend Gradle step' >&2; exit 1; }
printf '#!/usr/bin/env bash\necho "* What went wrong:"\nexit 1\n' > "$tmp/gradlew"
chmod +x "$tmp/gradlew"
cd "$tmp"
if GRADLE_TASK=build RUNNER_TEMP="$tmp" bash -e step.sh > /dev/null 2>&1; then
  echo 'FAIL: a failing Gradle run must fail the step even though its output goes through tee' >&2
  exit 1
fi
grep -qF '* What went wrong:' "$tmp/gradle-output.log" || { echo 'FAIL: the Gradle output must reach the digest file' >&2; exit 1; }
echo 'OK: the backend-ci Gradle step keeps the Gradle exit code and the output for the digest'
)

# --- module-docs ---
# backend-ci.yml dołącza dokumentację Spring Modulith każdego modułu jako artefakt module-docs-<run id>.
(
step=$(sed -n '/- name: Upload Spring Modulith documentation/,/retention-days/p' "$root/.github/workflows/backend-ci.yml")
[[ -n "$step" ]] || { echo 'FAIL: backend-ci.yml has no "Upload Spring Modulith documentation" step' >&2; exit 1; }
# shellcheck disable=SC2016 # dosłowne wyrażenia GitHuba
for expected in 'name: module-docs-${{ github.run_id }}' 'path: ${{ inputs.working-directory }}/**/build/spring-modulith-docs/' 'if-no-files-found: ignore'; do
  grep -qF "$expected" <<<"$step" || { echo "FAIL: the module docs upload needs: $expected" >&2; exit 1; }
done
echo 'OK: backend-ci uploads the Spring Modulith documentation of every module'
)
