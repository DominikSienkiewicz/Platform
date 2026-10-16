#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
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
