#!/usr/bin/env bash
# backend-ci-smoke w ci.yml buduje starter java-library z GitHub Packages. Commit wydania z release.sh podbija pin
# do wersji, którą release.yml publikuje dopiero po zielonym ci.yml (push main i tag niosą ten sam commit), więc
# smoke bierze wtedy pin rodzica, czyli ostatnie wydanie. Blok wycięty spomiędzy markerów biegnie pod `bash -e`
# runnera na zasianym repo git.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
workflow="$root/.github/workflows/ci.yml"
OUT=""

fail() { local message="$1"; echo "FAIL: $message" >&2; echo "--- output ---" >&2; echo "$OUT" >&2; exit 1; }

awk '
  index($0, "# >>> smoke-platform-version") { inside = 1; next }
  index($0, "# <<< smoke-platform-version") { inside = 0 }
  inside
' "$workflow" > "$tmp/resolve.sh"
[[ -s "$tmp/resolve.sh" ]] || fail 'ci.yml has no smoke-platform-version block between its markers'
# shellcheck disable=SC2016 # wyrażenie GitHub Actions szukane dosłownie
grep -qF -- '-PplatformVersion=${{ needs.smoke-platform-version.outputs.version }}' "$workflow" \
  || fail 'backend-ci-smoke must build on the version the smoke-platform-version job resolves'

repo="$tmp/repo"
pin_file=templates/jvm/java-library/gradle.properties
git init -q -b main "$repo"
git -C "$repo" config user.name 'Smoke Test'
git -C "$repo" config user.email 'smoke-test@example.invalid'
mkdir -p "$repo/$(dirname "$pin_file")"

commit() {
  local pin="$1" message="$2"
  printf 'platformVersion=%s\n' "$pin" > "$repo/$pin_file"
  git -C "$repo" add -A
  git -C "$repo" commit -q --allow-empty -m "$message"
}

resolve() {
  : > "$tmp/output"
  RC=0
  OUT=$(cd "$repo" && GITHUB_OUTPUT="$tmp/output" bash -e "$tmp/resolve.sh" 2>&1) || RC=$?
  RESOLVED=$(sed -n 's/^version=//p' "$tmp/output")
}

commit 1.5.31 'feat: the first commit'
resolve
[[ $RC -eq 0 && "$RESOLVED" == 1.5.31 ]] || fail "a commit without a parent must build on its pin, got '$RESOLVED' (exit $RC)"

commit 1.6.0 'chore(release): platform 1.6.0'
resolve
[[ $RC -eq 0 && "$RESOLVED" == 1.5.31 ]] \
  || fail "the release commit (push to main and the tag) must build on the published parent pin, got '$RESOLVED' (exit $RC)"
grep -qF 'builds on 1.5.31' <<<"$OUT" || fail 'the release commit must say why the smoke does not build on its own pin'

echo 'after the release' > "$repo/README.md"
commit 1.6.0 'docs: a commit after the release'
resolve
[[ $RC -eq 0 && "$RESOLVED" == 1.6.0 ]] || fail "a commit after the release must build on its own pin, got '$RESOLVED' (exit $RC)"

echo 'OK: backend-ci-smoke builds a release commit on the previous release and every other commit on its pin'
