#!/usr/bin/env bash
# platform-versions-check i kanał deprecacji (N-REL-9): paczka z mapy "deprecated" kanonu daje ostrzeżenie z kodem
# PLAT-DEPR-001 (i ::warning w GitHub Actions), a wynik zostaje zielony; błąd kanonu niesie kod i link do docs wydania.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "$OUT" >&2; exit 1; }

mkdir -p "$tmp/pkg/bin" "$tmp/app"
cp "$here/../bin/check.mjs" "$tmp/pkg/bin/check.mjs"
printf '{ "name": "@dominiksienkiewicz/versions", "version": "1.6.0" }\n' > "$tmp/pkg/package.json"
cat > "$tmp/pkg/versions.json" <<'JSON'
{ "versions": { "next": "16.4.0", "old-lib": "1.0.0" },
  "deprecated": { "old-lib": { "since": "1.6.0", "removeIn": "1.7.0", "replacement": "new-lib" } } }
JSON
printf '{ "dependencies": { "next": "16.4.0", "old-lib": "1.0.0" } }\n' > "$tmp/app/package.json"

OUT=$(cd "$tmp/app" && node "$tmp/pkg/bin/check.mjs" 2>&1) || fail 'a deprecated package must not fail the guard'
grep -qF '[PLAT-DEPR-001] platform-versions-check: old-lib is deprecated since Platform 1.6.0 and goes in 1.7.0: use new-lib' <<<"$OUT" \
  || fail 'the deprecation must be named with its code and replacement'
grep -qF 'blob/v1.6.0/docs/gates.md#plat-depr-001' <<<"$OUT" || fail 'the warning must link the docs of the canon release'
OUT=$(cd "$tmp/app" && GITHUB_ACTIONS=true node "$tmp/pkg/bin/check.mjs" 2>&1)
grep -qxF '::warning title=Platform deprecation::old-lib is deprecated since Platform 1.6.0 and goes in 1.7.0: use new-lib' <<<"$OUT" \
  || fail 'GitHub Actions must get a warning annotation'

printf '{ "dependencies": { "next": "16.3.0", "left-pad": "1.3.0" } }\n' > "$tmp/app/package.json"
if OUT=$(cd "$tmp/app" && node "$tmp/pkg/bin/check.mjs" 2>&1); then fail 'drift must still fail'; fi
grep -qF '[PLAT-FE-001] platform-versions-check: dependencies without a Platform canon entry' <<<"$OUT" || fail 'missing entries carry PLAT-FE-001'
grep -qF '[PLAT-FE-002] platform-versions-check: versions that differ from the Platform canon' <<<"$OUT" || fail 'drift carries PLAT-FE-002'
grep -qF '  PLAT-FE-002: https://github.com/DominikSienkiewicz/Platform/blob/v1.6.0/docs/gates.md#plat-fe-002' <<<"$OUT" \
  || fail 'every code must link the docs of the canon release'
echo 'OK: platform-versions-check warns on deprecated packages and codes every violation'
