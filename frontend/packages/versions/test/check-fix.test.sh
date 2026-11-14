#!/usr/bin/env bash
# platform-versions-check --fix (offline) przepisuje dryf i piny platformy na kanon, nie dodaje i nie usuwa wpisów;
# w GitHub Actions każde naruszenie to adnotacja ::error z plikiem i linią package.json, a tabela idzie do podsumowania.
# shellcheck disable=SC2016 # expected lines carry literal Markdown backticks
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" >&2 2>/dev/null; exit 1; }
: > "$tmp/out"

mkdir -p "$tmp/tool/bin" "$tmp/repo/frontend"
cp "$here/../bin/check.mjs" "$tmp/tool/bin/check.mjs"
printf '{ "versions": { "react": "19.2.8", "next": "16.2.6", "postcss": "8.5.6" } }\n' > "$tmp/tool/versions.json"
printf '{ "name": "@dominiksienkiewicz/versions", "version": "1.6.0" }\n' > "$tmp/tool/package.json"
consumer() {
  cat > "$tmp/repo/frontend/package.json" <<'JSON'
{
  "name": "consumer",
  "dependencies": {
    "react": "19.0.0",
    "left-pad": "1.3.0"
  },
  "devDependencies": {
    "@dominiksienkiewicz/versions": "^1.5.0"
  },
  "overrides": {
    "next": {
      "postcss": "8.4.31"
    }
  }
}
JSON
}
check() { (cd "$tmp/repo/frontend" && node "$tmp/tool/bin/check.mjs" "$@") > "$tmp/out" 2>&1; }

consumer
if check --fix; then fail 'a dependency without a canon entry must still fail after --fix'; fi
for expected in '  react: 19.0.0 -> 19.2.8' '  postcss [overrides.next.postcss]: 8.4.31 -> 8.5.6' \
  '  @dominiksienkiewicz/versions: ^1.5.0 -> 1.6.0' 'Then run npm install --package-lock-only and commit both files.' \
  '  left-pad (1.3.0): add it to'; do
  grep -qF -- "$expected" "$tmp/out" || fail "missing output: $expected"
done
node -e '
  const m = require(process.argv[1]);
  const ok = m.dependencies.react === "19.2.8" && m.dependencies["left-pad"] === "1.3.0"
    && m.overrides.next.postcss === "8.5.6" && m.devDependencies["@dominiksienkiewicz/versions"] === "1.6.0";
  process.exit(ok ? 0 : 1);
' "$tmp/repo/frontend/package.json" || fail '--fix must rewrite the drift and keep the entry without a canon version'
if grep -qF 'versions that differ from the Platform canon' "$tmp/out"; then fail 'nothing that --fix fixed may be reported as drift'; fi

node -e 'const p=process.argv[1];const m=require(p);delete m.dependencies["left-pad"];require("fs").writeFileSync(p, JSON.stringify(m,null,2)+"\n")' "$tmp/repo/frontend/package.json"
check || fail 'a manifest on the canon must pass after --fix'

consumer
: > "$tmp/summary"
set +e
(cd "$tmp/repo/frontend" && GITHUB_ACTIONS=true GITHUB_WORKSPACE="$tmp/repo" GITHUB_STEP_SUMMARY="$tmp/summary" node "$tmp/tool/bin/check.mjs") > "$tmp/out" 2>&1
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "violations must still exit 1 in Actions, got $rc"
for expected in \
  '::error file=frontend/package.json,line=4,title=Platform canon::react declared 19.0.0, canon 19.2.8' \
  '::error file=frontend/package.json,line=5,title=Platform canon::left-pad 1.3.0 has no canon entry' \
  '::error file=frontend/package.json,line=8,title=Platform canon::@dominiksienkiewicz/versions declared ^1.5.0, expected 1.6.0' \
  '::error file=frontend/package.json,line=12,title=Platform canon::postcss [overrides.next.postcss] declared 8.4.31, canon 8.5.6'; do
  grep -qxF -- "$expected" "$tmp/out" || fail "missing annotation: $expected"
done
grep -qF '| `frontend/package.json:4` | react declared 19.0.0, canon 19.2.8 |' "$tmp/summary" || fail 'the summary must list the violations'

echo 'OK: platform-versions-check --fix applies the canon offline and annotates violations in GitHub Actions'
