#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
extract_step() {
  awk -v step="$1" '
    $0 == "      - name: " step { selected = 1; next }
    selected && /^        run: \|$/ { body = 1; next }
    body && /^          / { sub(/^          /, ""); print; next }
    body { exit }
  ' "$root/.github/workflows/frontend-ci.yml"
}
extract_step 'Require standard scripts' > "$tmp/scripts.sh"
extract_step 'Platform versions guard' > "$tmp/guard.sh"
[[ -s "$tmp/scripts.sh" && -s "$tmp/guard.sh" ]] || exit 1
cd "$tmp"
cat > package.json <<'JSON'
{"scripts":{"lint":"eslint .","typecheck":"tsc","test":"vitest run","build":"next build"}}
JSON
REQUIRE_E2E=false bash -e scripts.sh
if REQUIRE_E2E=true bash -e scripts.sh; then
  echo 'Strict E2E must require test:e2e' >&2; exit 1
fi
node -e 'const fs=require("node:fs");const p=require("./package.json");p.scripts["test:e2e"]="playwright test";fs.writeFileSync("package.json",JSON.stringify(p))'
REQUIRE_E2E=true bash -e scripts.sh
node -e 'const fs=require("node:fs");const p=require("./package.json");p.scripts.lint=" ";fs.writeFileSync("package.json",JSON.stringify(p))'
if REQUIRE_E2E=false bash -e scripts.sh; then
  echo 'Whitespace-only scripts must be rejected' >&2; exit 1
fi
STRICT=false bash -e guard.sh
if STRICT=true bash -e guard.sh; then
  echo 'Strict mode must require the version guard' >&2; exit 1
fi
mkdir -p node_modules/.bin node_modules/@dominiksienkiewicz/versions/bin
touch node_modules/.bin/platform-versions-check
printf 'process.exit(0);\n' > node_modules/@dominiksienkiewicz/versions/bin/check.mjs
STRICT=true bash -e guard.sh
printf 'process.exit(7);\n' > node_modules/@dominiksienkiewicz/versions/bin/check.mjs
if STRICT=false bash -e guard.sh; then
  echo 'An installed failing guard must block both profiles' >&2; exit 1
fi
