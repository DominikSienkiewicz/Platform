#!/usr/bin/env bash
# compare-rebuild.sh: każdy przebudowany jar porównany z kopią rejestru (tu file://) — zgodne sumy to "match" i kod 0,
# inna suma albo brak kopii to "differ"/"missing" i kod 1, pusty bundle to kod 2.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "$OUT" >&2; exit 1; }
artifact() { mkdir -p "$1/pl/seniordeveloper/$2/1.6.0"; printf '%s' "$3" > "$1/pl/seniordeveloper/$2/1.6.0/$2-1.6.0.jar"; }
artifact "$tmp/bundle" platform-web-starter same
artifact "$tmp/registry" platform-web-starter same
artifact "$tmp/bundle" platform-test-fixtures same
artifact "$tmp/registry" platform-test-fixtures same
run() { RC=0; OUT=$(PLATFORM_MAVEN_URL="file://$tmp/registry" bash "$here/compare-rebuild.sh" "$tmp/bundle" 2>&1) || RC=$?; }

run
[[ $RC -eq 0 ]] || fail 'identical rebuilds must pass'
[[ $(grep -c '^match ' <<<"$OUT") -eq 2 ]] || fail 'every jar must be logged with its digest'
artifact "$tmp/registry" platform-test-fixtures other
artifact "$tmp/bundle" platform-bom-only absent
run
[[ $RC -eq 1 ]] || fail 'a differing or missing jar must fail'
grep -qE '^differ pl/seniordeveloper/platform-test-fixtures/1.6.0/platform-test-fixtures-1.6.0.jar [0-9a-f]{64} [0-9a-f]{64}$' <<<"$OUT" || fail 'a difference must print both digests'
grep -qE '^missing pl/seniordeveloper/platform-bom-only/' <<<"$OUT" || fail 'a jar without a registry copy must be named'
mkdir -p "$tmp/empty"
RC=0; OUT=$(bash "$here/compare-rebuild.sh" "$tmp/empty" 2>&1) || RC=$?
[[ $RC -eq 2 ]] || fail 'an empty bundle must be an error'
echo 'OK: compare-rebuild logs the digest of every rebuilt jar against the registry copy'
