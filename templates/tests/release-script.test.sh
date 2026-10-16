#!/usr/bin/env bash
# Hermetic tests for release.sh: every case runs a copy of the script in its own temporary
# repository whose origin is a local bare repository, so nothing reaches the network.
#
# release.sh must refuse a dirty tree, a branch other than main and a main that is not
# origin/main before it bumps, commits, tags or pushes anything; a clean release commits only
# the version files and leaves the moving `v1` tag to Release's move-v1 job.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

readonly CURRENT=1.2.3
readonly NEXT=1.2.4
readonly VERSION_FILES="gradle/build-logic/gradle.properties
gradle/catalog/build.gradle.kts
gradle/catalog/gradle.properties
gradle/test-fixtures/gradle.properties"

fail() {
  local message="$1"
  echo "FAIL: $message" >&2
  exit 1
}

seed_repo() {
  local name="$1"
  local origin="$tmp/$name.git"
  local work="$tmp/$name"
  git init -q --bare -b main "$origin"
  git init -q -b main "$work"
  git -C "$work" config user.name 'Release Test'
  git -C "$work" config user.email 'release-test@example.invalid'
  for module in build-logic catalog test-fixtures; do
    mkdir -p "$work/gradle/$module"
    printf 'platformVersion=%s\n' "$CURRENT" > "$work/gradle/$module/gradle.properties"
  done
  printf 'version = providers.gradleProperty("platformVersion").getOrElse("%s")\n' "$CURRENT" \
    > "$work/gradle/catalog/build.gradle.kts"
  cp "$root/release.sh" "$work/release.sh"
  echo '# fixture' > "$work/README.md"
  git -C "$work" add -A
  git -C "$work" commit -q -m initial
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q -u origin main >/dev/null
  printf '%s\n' "$work"
}

run_release() {
  local work="$1"
  (cd "$work" && bash ./release.sh "fix: test release" "$NEXT" -y) > "$work.log" 2>&1
}

remote_ref() {
  local work="$1"
  local ref="$2"
  git -C "$work" ls-remote origin "$ref" | cut -f1
}

assert_refused() {
  local work="$1"
  local reason="$2"
  local head_before origin_before
  head_before=$(git -C "$work" rev-parse HEAD)
  origin_before=$(remote_ref "$work" refs/heads/main)
  if run_release "$work"; then
    cat "$work.log" >&2
    fail "release.sh must refuse $reason"
  fi
  [[ "$(git -C "$work" rev-parse HEAD)" == "$head_before" ]] || fail "refusing $reason must not commit"
  [[ "$(remote_ref "$work" refs/heads/main)" == "$origin_before" ]] || fail "refusing $reason must not push main"
  [[ -z "$(remote_ref "$work" "refs/tags/v$NEXT")" ]] || fail "refusing $reason must not push the version tag"
  [[ -z "$(remote_ref "$work" refs/tags/v1)" ]] || fail "refusing $reason must not push v1"
  grep -qx "platformVersion=$CURRENT" "$work/gradle/build-logic/gradle.properties" \
    || fail "refusing $reason must not bump the version"
  return 0
}

work=$(seed_repo untracked)
echo stray > "$work/stray.txt"
assert_refused "$work" 'an untracked file'

work=$(seed_repo modified)
echo 'local edit' >> "$work/README.md"
assert_refused "$work" 'a modified tracked file'

work=$(seed_repo branch)
git -C "$work" switch -q -c feature
git -C "$work" push -q -u origin feature
assert_refused "$work" 'a branch other than main'

work=$(seed_repo ahead)
git -C "$work" commit -q --allow-empty -m 'not pushed yet'
assert_refused "$work" 'a main that is not origin/main'

work=$(seed_repo clean)
if ! run_release "$work"; then
  cat "$work.log" >&2
  fail 'release.sh must release a clean main that matches origin/main'
fi
released=$(git -C "$work" rev-parse HEAD)
[[ "$(remote_ref "$work" refs/heads/main)" == "$released" ]] || fail 'release.sh must push the release commit to main'
[[ "$(remote_ref "$work" "refs/tags/v$NEXT")" == "$released" ]] || fail "release.sh must push v$NEXT at the release commit"
[[ -z "$(remote_ref "$work" refs/tags/v1)" ]] || fail "release.sh must leave v1 to Release's move-v1 job"
[[ "$(git -C "$work" diff --name-only HEAD~1 HEAD)" == "$VERSION_FILES" ]] \
  || fail 'release.sh must commit exactly the version files'

echo 'OK: release.sh refuses unsafe trees and commits only the version bump'
