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
