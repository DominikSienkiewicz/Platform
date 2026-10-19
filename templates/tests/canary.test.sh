#!/usr/bin/env bash
# scripts/canary.sh w kopii repozytorium z atrapą podglądu: każdy konsument z consumers.txt dostaje wynik
# PASS, FAIL albo MISSING dla pełnego SHA HEAD, wszystkie podglądy dzielą jedno repozytorium i biegną
# z --frontend, a brudne drzewo nic nie zapisuje.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" >&2 2>/dev/null || true; exit 1; }

platform="$tmp/Platform"
mkdir -p "$platform/scripts"
cp "$root/scripts/canary.sh" "$platform/scripts/canary.sh"
printf '# consumers\nacme/one\nacme/two_com\nacme/three\n' > "$platform/scripts/consumers.txt"
git -C "$platform" init -q -b main
git -C "$platform" -c user.name=t -c user.email=t@example.invalid add -A
git -C "$platform" -c user.name=t -c user.email=t@example.invalid commit -q -m initial
sha=$(git -C "$platform" rev-parse HEAD)
record="$platform/.git/platform-canary/$sha"

consumers="$tmp/consumers"
for name in one two; do mkdir -p "$consumers/$name" && git -C "$consumers/$name" init -q; done
cat > "$tmp/preview" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$PREVIEW_LOG"
[[ "${1##*/}" != "${FAIL_CONSUMER:-}" ]]
STUB
export PREVIEW_LOG="$tmp/preview.log" CANARY_PREVIEW="$tmp/preview" PLATFORM_CONSUMERS_DIR="$consumers"

status=0
FAIL_CONSUMER=two bash "$platform/scripts/canary.sh" > "$tmp/out" 2>&1 || status=$?
[[ $status -eq 1 ]] || fail "a failing consumer must fail the canary, got exit $status"
[[ "$(cat "$record")" == $'PASS acme/one\nFAIL acme/two_com\nMISSING acme/three' ]] \
  || fail "the record must hold one line per consumer, got: $(cat "$record")"
[[ $(wc -l < "$PREVIEW_LOG") -eq 2 ]] || fail 'only consumers with a checkout are previewed'
grep -q -- "/one --frontend --staging " "$PREVIEW_LOG" || fail 'the preview must check the frontend too'
[[ $(sed -E 's/.*--staging ([^ ]+).*/\1/' "$PREVIEW_LOG" | sort -u | wc -l) -eq 1 ]] \
  || fail 'every preview must share one staging repository, so the modules are published once'

printf 'acme/one\nacme/two_com\n' > "$platform/scripts/consumers.txt"
git -C "$platform" -c user.name=t -c user.email=t@example.invalid commit -q -am 'two consumers'
sha=$(git -C "$platform" rev-parse HEAD)
bash "$platform/scripts/canary.sh" --gradle 'compileJava' > "$tmp/out" 2>&1 || fail 'a canary where every consumer passes must exit 0'
[[ "$(cat "$platform/.git/platform-canary/$sha")" == $'PASS acme/one\nPASS acme/two_com' ]] || fail 'every consumer must pass'
grep -q -- "--gradle compileJava" "$PREVIEW_LOG" || fail '--gradle must reach the preview'

echo dirty > "$platform/dirty.txt"
status=0
bash "$platform/scripts/canary.sh" > "$tmp/out" 2>&1 || status=$?
[[ $status -eq 2 ]] || fail "a dirty tree must be refused with exit 2, got $status"
grep -qF 'the canary records its result for HEAD' "$tmp/out" || fail 'the refusal must say why'

echo 'OK: canary.sh records PASS, FAIL or MISSING per consumer for HEAD and previews them on one staging repository'
