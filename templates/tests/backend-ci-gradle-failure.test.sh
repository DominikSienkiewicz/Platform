#!/usr/bin/env bash
# Krok Gradle w backend-ci.yml przepuszcza wyjście przez tee do pliku dla digestu; porażka Gradle musi nadal
# failować krok. Domyślna powłoka kroku to `bash -e` bez pipefail, więc test uruchamia go dokładnie tak.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

awk '
  $0 == "      - name: ./gradlew ${{ inputs.gradle-task }}" { selected = 1; next }
  selected && /^        run: \|$/ { body = 1; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$root/.github/workflows/backend-ci.yml" > "$tmp/step.sh"
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
