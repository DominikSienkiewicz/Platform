#!/usr/bin/env bash
# scripts/new-consumer.sh --frontend next: frontend/ z konfiguracjami paczek Platform, skryptami trybu strict
# i package.json, który przechodzi platform-versions-check kanonu tego checkoutu (każda zależność z kanonu,
# każdy @dominiksienkiewicz/* na wersji wydania), plus caller frontend-ci.yml ze strict: true.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
version=$(sed -n 's/^platformVersion=//p' "$root/gradle/build-logic/gradle.properties")

bash "$root/scripts/new-consumer.sh" --name shop --package pl.example.shop --kind spring-app --out "$tmp/shop" --frontend next > "$tmp/out"
web="$tmp/shop/frontend"
for file in package.json .npmrc .gitignore .nvmrc tsconfig.json eslint.config.mjs postcss.config.mjs vitest.config.ts next.config.ts \
  Dockerfile src/app/layout.tsx src/app/page.tsx src/app/page.test.tsx src/app/globals.css; do
  [[ -f "$web/$file" ]] || fail "frontend/$file is missing"
done
cmp -s "$root/templates/npmrc" "$web/.npmrc" || fail 'frontend/.npmrc must be the canonical copy'
cmp -s "$root/templates/Dockerfile.frontend" "$web/Dockerfile" || fail 'frontend/Dockerfile must be the canonical copy'
cmp -s "$root/templates/frontend/next.config.ts" "$web/next.config.ts" || fail 'next.config.ts must be the canonical copy'
for script in lint typecheck test build format:check; do
  node -e 'const s = require(process.argv[1]).scripts; if (!s[process.argv[2]]) process.exit(1)' "$web/package.json" "$script" \
    || fail "strict frontend-ci needs the $script script"
done
node -e 'const m = require(process.argv[1]); if (m.devDependencies["@dominiksienkiewicz/versions"] !== process.argv[2]) process.exit(1)' \
  "$web/package.json" "$version" || fail "@dominiksienkiewicz/versions must be pinned at $version"
(cd "$web" && node "$root/frontend/packages/versions/bin/check.mjs") > "$tmp/check" 2>&1 \
  || { cat "$tmp/check" >&2; fail 'the generated package.json must pass platform-versions-check of this canon'; }
grep -qF 'Frontend: (cd' "$tmp/out" || fail 'the generator must say how to create package-lock.json'

workflow="$tmp/shop/.github/workflows/ci.yml"
grep -qF "uses: DominikSienkiewicz/Platform/.github/workflows/frontend-ci.yml@v$version" "$workflow" || fail 'the frontend caller must use the exact tag'
grep -qx '      strict: true' "$workflow" || fail 'the frontend caller must run strict'
[[ $(grep -c 'gpr_token: ${{ secrets.GPR_TOKEN }}' "$workflow") -eq 2 ]] || fail 'both callers pass gpr_token explicitly'

if bash "$root/scripts/new-consumer.sh" --name other --package pl.example.other --kind spring-app --out "$tmp/other" --frontend vue 2>/dev/null; then
  fail 'an unknown frontend must be refused'
fi
echo 'OK: new-consumer --frontend next renders a strict Next.js frontend that passes the version canon'
