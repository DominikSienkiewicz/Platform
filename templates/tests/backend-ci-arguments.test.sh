#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
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
