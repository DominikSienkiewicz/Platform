#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
command=$(awk '/name: Build registry \(shadcn\)/ { getline; sub(/^ *run: /, ""); print; exit }' "$root/.github/workflows/release.yml")
[[ -n "$command" ]] || { echo 'Missing registry build step' >&2; exit 1; }
mkdir "$tmp/bin"
cat > "$tmp/bin/pnpm" <<'STUB'
#!/usr/bin/env bash
exit 42
STUB
chmod +x "$tmp/bin/pnpm"
if PATH="$tmp/bin:$PATH" bash -e -c "$command"; then
  echo 'A failed registry build must block publication' >&2
  exit 1
fi
