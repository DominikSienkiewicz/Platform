#!/usr/bin/env bash
# release.sh wydaje tylko commit, dla którego scripts/canary.sh zapisał PASS na każdym konsumencie
# z scripts/consumers.txt (N-REL-1); --skip-canary "<powód>" pomija bramkę, a powód zostaje w historii jako
# trailer Canary-Skipped. Każdy przypadek ma własne repozytorium z lokalnym bare origin, bez sieci.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; exit 1; }

seed_repo() {
  local origin="$tmp/$1.git" work="$tmp/$1"
  git init -q --bare -b main "$origin"
  git init -q -b main "$work"
  git -C "$work" config user.name 'Release Test'
  git -C "$work" config user.email 'release-test@example.invalid'
  for module in gradle/build-logic gradle/catalog; do
    mkdir -p "$work/$module"
    printf 'platformVersion=1.2.3\n' > "$work/$module/gradle.properties"
  done
  mkdir -p "$work/frontend/packages/alpha" "$work/scripts"
  printf '{\n  "name": "@example/alpha",\n  "version": "1.2.3"\n}\n' > "$work/frontend/packages/alpha/package.json"
  printf '# Changelog\n\n## [1.2.4] - 2026-10-19\n\n### Consumer action required\n\nNone.\n\n### Fixed\n\n- Something.\n' > "$work/CHANGELOG.md"
  printf '# consumers\nacme/one\nacme/two\n' > "$work/scripts/consumers.txt"
  cp "$root/release.sh" "$work/release.sh"
  cp "$root/scripts/changelog-section.sh" "$work/scripts/changelog-section.sh"
  git -C "$work" add -A
  git -C "$work" commit -q -m initial
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q -u origin main >/dev/null
  printf '%s\n' "$work"
}

record() {
  local work="$1"
  shift
  mkdir -p "$work/.git/platform-canary"
  printf '%s\n' "$@" > "$work/.git/platform-canary/$(git -C "$work" rev-parse HEAD)"
}

run_release() {
  local work="$1"
  shift
  (cd "$work" && ASSUME_YES=1 bash ./release.sh "$@") > "$work.log" 2>&1
}

refused() {
  local work="$1" expected="$2"
  shift 2
  local head
  head=$(git -C "$work" rev-parse HEAD)
  if run_release "$work" "$@"; then cat "$work.log" >&2; fail "release.sh must refuse: $expected"; fi
  grep -qF -- "$expected" "$work.log" || { cat "$work.log" >&2; fail "the refusal must say: $expected"; }
  [[ "$(git -C "$work" rev-parse HEAD)" == "$head" ]] || fail "a refusal must not commit ($expected)"
  [[ -z "$(git -C "$work" tag --list)" ]] || fail "a refusal must not tag ($expected)"
}

work=$(seed_repo none)
refused "$work" 'No consumer canary for' 'fix: something'

work=$(seed_repo failing)
record "$work" 'PASS acme/one' 'FAIL acme/two'
refused "$work" '  FAIL acme/two' 'fix: something'

work=$(seed_repo partial)
record "$work" 'PASS acme/one'
refused "$work" '  NOT RUN acme/two' 'fix: something'

work=$(seed_repo noreason)
refused "$work" '--skip-canary needs a reason' 'fix: something' --skip-canary

work=$(seed_repo green)
record "$work" 'PASS acme/one' 'PASS acme/two'
run_release "$work" 'fix: something' || { cat "$work.log" >&2; fail 'a green canary for HEAD must release'; }
git -C "$work" rev-parse -q --verify refs/tags/v1.2.4 >/dev/null || fail 'the green release must be tagged'
if git -C "$work" log -1 --format=%B | grep -q 'Canary-Skipped'; then fail 'a green release records no skip'; fi

work=$(seed_repo skipped)
run_release "$work" 'fix: something' --skip-canary 'consumers offline' || { cat "$work.log" >&2; fail '--skip-canary must release'; }
grep -qF 'Consumer canary skipped: consumers offline' "$work.log" || fail 'the skip must be announced'
git -C "$work" log -1 --format=%B | grep -qx 'Canary-Skipped: consumers offline' || fail 'the reason must stay in the release commit'

echo 'OK: release.sh needs a green consumer canary for HEAD, or --skip-canary with a reason that stays in history'
