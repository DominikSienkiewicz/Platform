#!/usr/bin/env bash
# release.sh refusals that release-script.test.sh does not cover: an empty message prints the usage,
# and a version whose tag exists is refused. Neither may commit, tag or push anything.
# Hermetic like release-script.test.sh: a copy of the script in a temporary repository whose origin
# is a local bare repository.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fail() { local message="$1"; echo "FAIL: $message" >&2; exit 1; }

seed_repo() {
  local name="$1"
  local origin="$tmp/$name.git" work="$tmp/$name"
  git init -q --bare -b main "$origin"
  git init -q -b main "$work"
  git -C "$work" config user.name 'Release Test'
  git -C "$work" config user.email 'release-test@example.invalid'
  mkdir -p "$work/gradle/build-logic" "$work/frontend/packages/alpha" "$work/scripts"
  printf 'platformVersion=1.2.3\n' > "$work/gradle/build-logic/gradle.properties"
  printf '{\n  "name": "@example/alpha",\n  "version": "1.2.3"\n}\n' > "$work/frontend/packages/alpha/package.json"
  printf '# Changelog\n\n## [1.2.4] - 2026-10-18\n\n### Consumer action required\n\nNone.\n' > "$work/CHANGELOG.md"
  cp "$root/release.sh" "$work/release.sh"
  cp "$root/scripts/changelog-section.sh" "$work/scripts/changelog-section.sh"
  git -C "$work" add -A
  git -C "$work" commit -q -m initial
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q -u origin main > /dev/null
  printf '%s\n' "$work"
}

# assert_untouched <work> <head before> <tags before>: no commit, no new tag, origin unchanged.
assert_untouched() {
  local work="$1" head="$2" tags="$3"
  [[ "$(git -C "$work" rev-parse HEAD)" == "$head" ]] || fail "release.sh committed although it refused"
  [[ "$(git -C "$work" tag)" == "$tags" ]] || fail "release.sh tagged although it refused"
  [[ "$(git -C "$work" ls-remote origin refs/heads/main | cut -f1)" == "$head" ]] || fail "release.sh pushed although it refused"
}

# (a) an empty message prints the usage
work=$(seed_repo empty-message)
head=$(git -C "$work" rev-parse HEAD)
if (cd "$work" && bash ./release.sh "" 1.2.4 -y) > "$work.log" 2>&1; then
  fail "an empty message must be refused"
fi
grep -q 'release.sh "commit message" \[X.Y.Z\] \[-y\]' "$work.log" || fail "an empty message must print the usage"
assert_untouched "$work" "$head" ""

# (b) a version whose tag already exists is refused
work=$(seed_repo existing-tag)
git -C "$work" tag v1.2.4
head=$(git -C "$work" rev-parse HEAD)
if (cd "$work" && bash ./release.sh "fix: test release" 1.2.4 -y) > "$work.log" 2>&1; then
  fail "a version whose tag exists must be refused"
fi
grep -q 'Tag v1.2.4' "$work.log" || fail "the refusal must name the existing tag"
assert_untouched "$work" "$head" "v1.2.4"

echo 'OK: release.sh refuses an empty message and an existing tag without committing, tagging or pushing'
