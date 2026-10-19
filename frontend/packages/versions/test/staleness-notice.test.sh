#!/usr/bin/env bash
# platform-versions-check i okno wsparcia (N-REL-6): kanon z releasedAt starszym niż 60 dni daje dokładnie jedną
# linię, a wynik zostaje zielony; świeży kanon, kanon bez daty i PLATFORM_STALENESS_NOTICE=false milczą.
set -euo pipefail
# Runner GitHub Actions ustawia GITHUB_ACTIONS=true, a wtedy check.mjs dokłada adnotację ::notice z tym samym
# tekstem; przypadki poza Actions muszą jej nie widzieć, przypadek Actions ustawia zmienną jawnie.
unset GITHUB_ACTIONS
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "$OUT" >&2; exit 1; }

mkdir -p "$tmp/pkg/bin" "$tmp/app"
cp "$here/../bin/check.mjs" "$tmp/pkg/bin/check.mjs"
printf '{ "name": "@dominiksienkiewicz/versions", "version": "1.5.26" }\n' > "$tmp/pkg/package.json"
printf '{ "versions": { "next": "16.4.0" }, "releasedAt": "2026-08-10" }\n' > "$tmp/pkg/versions.json"
printf '{ "dependencies": { "next": "16.4.0" } }\n' > "$tmp/app/package.json"
notices() { grep -c ' days ago (2026-08-10); the support window is 60 days or 3 releases' <<<"$OUT" || true; }

OUT=$(cd "$tmp/app" && PLATFORM_STALENESS_TODAY=2026-10-14 node "$tmp/pkg/bin/check.mjs" 2>&1) || fail 'an old canon must not fail the guard'
[[ $(notices) == 1 ]] || fail 'an old canon must print exactly one notice'
grep -qF 'Platform 1.5.26 was released 65 days ago (2026-08-10)' <<<"$OUT" || fail 'the notice must name the release and its age'

OUT=$(cd "$tmp/app" && GITHUB_ACTIONS=true PLATFORM_STALENESS_TODAY=2026-10-14 node "$tmp/pkg/bin/check.mjs" 2>&1)
grep -qF '::notice title=Platform support window::Platform 1.5.26 was released 65 days ago' <<<"$OUT" \
  || fail 'GitHub Actions must get a notice annotation'

OUT=$(cd "$tmp/app" && PLATFORM_STALENESS_TODAY=2026-08-20 node "$tmp/pkg/bin/check.mjs" 2>&1)
[[ $(notices) == 0 ]] || fail 'a fresh canon must stay silent'

OUT=$(cd "$tmp/app" && PLATFORM_STALENESS_NOTICE=false PLATFORM_STALENESS_TODAY=2026-10-14 node "$tmp/pkg/bin/check.mjs" 2>&1)
[[ $(notices) == 0 ]] || fail 'PLATFORM_STALENESS_NOTICE=false must silence the notice'

printf '{ "versions": { "next": "16.4.0" } }\n' > "$tmp/pkg/versions.json"
OUT=$(cd "$tmp/app" && PLATFORM_STALENESS_TODAY=2026-10-14 node "$tmp/pkg/bin/check.mjs" 2>&1)
grep -qF 'days ago' <<<"$OUT" && fail 'a canon without releasedAt must stay silent'
echo 'OK: platform-versions-check names a canon older than the support window once and never fails on it'
