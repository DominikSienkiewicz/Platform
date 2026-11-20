#!/usr/bin/env bash
# release.sh, case by case: every case runs a copy of the script in its own temporary repository whose origin is a local
# bare repository, so nothing reaches the network. The cases: refusals of an unsafe tree and the version bump, the
# release and versioning contract, the remaining refusals, and consumer action recorded in the history.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

# --- refuse-and-bump ---
# Hermetic tests for release.sh: every case runs a copy of the script in its own temporary
# repository whose origin is a local bare repository, so nothing reaches the network.
#
# release.sh must refuse a dirty tree, a branch other than main and a main that is not
# origin/main before it bumps, commits, tags or pushes anything; a clean release commits only
# the version files and never creates a moving `v1` tag.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

readonly CURRENT=1.2.3
readonly NEXT=1.2.4
readonly VERSION_FILES="frontend/packages/alpha/package.json
frontend/packages/beta/package.json
gradle/build-logic/gradle.properties
gradle/catalog/gradle.properties
gradle/observability-starter/gradle.properties
gradle/test-fixtures/gradle.properties
templates/jvm/java-library/gradle.properties
templates/jvm/spring-app/gradle.properties"


seed_repo() {
  local name="$1"
  local origin="$tmp/$name.git"
  local work="$tmp/$name"
  git init -q --bare -b main "$origin"
  git init -q -b main "$work"
  git -C "$work" config user.name 'Release Test'
  git -C "$work" config user.email 'release-test@example.invalid'
  for module in gradle/build-logic gradle/catalog gradle/observability-starter gradle/test-fixtures \
    templates/jvm/java-library templates/jvm/spring-app; do
    mkdir -p "$work/$module"
    printf 'platformVersion=%s\n' "$CURRENT" > "$work/$module/gradle.properties"
  done
  for package in alpha beta; do
    mkdir -p "$work/frontend/packages/$package"
    printf '{\n  "name": "@example/%s",\n  "version": "%s"\n}\n' "$package" "$CURRENT" \
      > "$work/frontend/packages/$package/package.json"
  done
  mkdir -p "$work/scripts"
  printf '# Changelog\n\n## [%s] - 2026-10-18\n\n### Consumer action required\n\nNone.\n' "$NEXT" > "$work/CHANGELOG.md"
  cp "$root/release.sh" "$work/release.sh"
  cp "$root/scripts/changelog-section.sh" "$work/scripts/changelog-section.sh"
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
[[ "$(remote_ref "$work" "refs/tags/v$NEXT^{}")" == "$released" ]] || fail "release.sh must push v$NEXT at the release commit"
[[ -z "$(remote_ref "$work" refs/tags/v1)" ]] || fail 'release.sh must not push a moving v1 tag'
[[ "$(git -C "$work" diff --name-only HEAD~1 HEAD)" == "$VERSION_FILES" ]] \
  || fail 'release.sh must commit exactly the version files'
while IFS= read -r file; do
  grep -Eq "^platformVersion=$NEXT\$|^  \"version\": \"$NEXT\"" "$work/$file" \
    || fail "release.sh must bump $file to $NEXT"
done <<<"$VERSION_FILES"
[[ "$(git -C "$work" log -1 --format=%s)" == "chore(release): platform $NEXT" ]] \
  || fail 'the release commit subject must name the version'
[[ "$(git -C "$work" cat-file -t "v$NEXT")" == tag ]] || fail 'the version tag must be annotated'

echo 'OK: release.sh refuses unsafe trees and commits only the version bump'
)

# --- contract ---
# release.sh enforces the release and versioning contract (docs/adr/0002-release-and-versioning-contract.md):
#
# - the message is an English Conventional Commit and becomes the body of
#   "chore(release): platform X.Y.Z";
# - the version has a CHANGELOG.md section with a "Consumer action required" subsection;
# - a release with consumer action, or a feat/breaking message without an explicit version,
#   cannot be a patch;
# - the version tag is annotated with the CHANGELOG section.
#
# Every case runs a copy of release.sh in its own repository whose origin is a local bare
# repository, so nothing reaches the network. Refusals must leave the repository untouched.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

readonly CURRENT=1.2.3


# seed_repo <name> <changelog body appended after the header>
seed_repo() {
  local name="$1"
  local changelog="$2"
  local origin="$tmp/$name.git"
  local work="$tmp/$name"
  git init -q --bare -b main "$origin"
  git init -q -b main "$work"
  git -C "$work" config user.name 'Release Test'
  git -C "$work" config user.email 'release-test@example.invalid'
  for module in gradle/build-logic gradle/catalog; do
    mkdir -p "$work/$module"
    printf 'platformVersion=%s\n' "$CURRENT" > "$work/$module/gradle.properties"
  done
  mkdir -p "$work/frontend/packages/alpha" "$work/scripts"
  printf '{\n  "name": "@example/alpha",\n  "version": "%s"\n}\n' "$CURRENT" > "$work/frontend/packages/alpha/package.json"
  printf '# Changelog\n\n## [Unreleased]\n\n%s\n' "$changelog" > "$work/CHANGELOG.md"
  cp "$root/release.sh" "$work/release.sh"
  cp "$root/scripts/changelog-section.sh" "$work/scripts/changelog-section.sh"
  git -C "$work" add -A
  git -C "$work" commit -q -m initial
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q -u origin main >/dev/null
  printf '%s\n' "$work"
}

section() {
  local version="$1"
  local action="$2"
  printf '## [%s] - 2026-10-18\n\n### Consumer action required\n\n%s\n\n### Fixed\n\n- Something.\n\n' "$version" "$action"
}

run_release() {
  local work="$1"
  shift
  (cd "$work" && ASSUME_YES=1 bash ./release.sh "$@") > "$work.log" 2>&1
}

assert_refused() {
  local work="$1"
  local reason="$2"
  local expected_output="$3"
  shift 3
  local head_before
  head_before=$(git -C "$work" rev-parse HEAD)
  if run_release "$work" "$@"; then
    cat "$work.log" >&2
    fail "release.sh must refuse $reason"
  fi
  grep -qF -- "$expected_output" "$work.log" || { cat "$work.log" >&2; fail "refusing $reason must explain: $expected_output"; }
  [[ "$(git -C "$work" rev-parse HEAD)" == "$head_before" ]] || fail "refusing $reason must not commit"
  [[ -z "$(git -C "$work" tag --list)" ]] || fail "refusing $reason must not tag"
  [[ -z "$(git -C "$work" status --porcelain)" ]] || fail "refusing $reason must not touch the tree"
  return 0
}

# --- changelog-section.sh ------------------------------------------------------------------
fixture="$tmp/CHANGELOG.md"
printf '# Changelog\n\n%s\n\n%s\n' "$(section 2.0.0 '- Move to X.')" "$(section 1.9.9 'None.')" > "$fixture"
[[ "$(bash "$root/scripts/changelog-section.sh" --consumer-action 2.0.0 "$fixture")" == '- Move to X.' ]] \
  || fail 'changelog-section.sh must print the consumer action subsection of the version'
[[ "$(bash "$root/scripts/changelog-section.sh" 1.9.9 "$fixture" | head -1)" == '### Consumer action required' ]] \
  || fail 'changelog-section.sh must print the section body without its heading or leading blank lines'
if bash "$root/scripts/changelog-section.sh" 3.0.0 "$fixture" >/dev/null; then
  fail 'changelog-section.sh must exit non-zero for a version without a section'
fi

# --- Refusals ------------------------------------------------------------------------------
work=$(seed_repo message "$(section 1.2.4 'None.')")
assert_refused "$work" 'a message that is not a Conventional Commit' 'Conventional Commit' 'update libs'

work=$(seed_repo polish "$(section 1.2.4 'None.')")
assert_refused "$work" 'a message in Polish' 'in English' 'fix: popraw błąd wydania'

work=$(seed_repo feat-patch "$(section 1.2.4 'None.')")
assert_refused "$work" 'an automatic patch for a feat message' 'needs an explicit version' 'feat: add a gate'

work=$(seed_repo breaking-patch "$(section 1.2.4 'None.')")
assert_refused "$work" 'an automatic patch for a breaking message' 'needs an explicit version' 'fix!: drop a knob'

work=$(seed_repo no-section "$(section 1.2.9 'None.')")
assert_refused "$work" 'a version without a CHANGELOG section' 'has no "## [1.2.4]' 'fix: patch it'

work=$(seed_repo no-action "$(printf '## [1.2.4] - 2026-10-18\n\n### Fixed\n\n- Something.\n')")
assert_refused "$work" 'a section without Consumer action required' 'Consumer action required' 'fix: patch it'

work=$(seed_repo action-patch "$(section 1.2.4 '- Grant packages: read.')")
assert_refused "$work" 'a patch that requires consumer action' './release.sh "fix: patch it" 1.3.0' 'fix: patch it'

# --- A minor with consumer action ----------------------------------------------------------
work=$(seed_repo minor "$(section 1.3.0 '- Grant packages: read.')")
if ! run_release "$work" 'feat: require packages read' 1.3.0; then
  cat "$work.log" >&2
  fail 'release.sh must release a minor whose CHANGELOG section lists consumer action'
fi
[[ "$(git -C "$work" log -1 --format=%s)" == 'chore(release): platform 1.3.0' ]] \
  || fail 'the release commit subject must name the version'
[[ "$(git -C "$work" log -1 --format=%b)" == 'feat: require packages read'* ]] \
  || fail 'the release message must become the body of the release commit'
[[ "$(git -C "$work" cat-file -t v1.3.0)" == tag ]] || fail 'the version tag must be annotated'
tag_message=$(git -C "$work" tag -l --format='%(contents)' v1.3.0)
grep -qx 'Platform 1.3.0' <<<"$tag_message" || fail 'the tag message must start with the release title'
grep -qx '### Consumer action required' <<<"$tag_message" \
  || fail 'the tag message must keep the Markdown headings of the CHANGELOG section'
grep -qx -- '- Grant packages: read.' <<<"$tag_message" || fail 'the tag message must carry the consumer action'
[[ "$(git -C "$work" ls-remote origin refs/tags/v1.3.0 | cut -f1)" == "$(git -C "$work" rev-parse v1.3.0)" ]] \
  || fail 'release.sh must push the annotated tag'

echo 'OK: release.sh enforces the message, CHANGELOG and MINOR rules and annotates the tag'
)

# --- refusals ---
# release.sh refusals that release-script.test.sh does not cover: an empty message prints the usage,
# and a version whose tag exists is refused. Neither may commit, tag or push anything.
# Hermetic like release-script.test.sh: a copy of the script in a temporary repository whose origin
# is a local bare repository.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1


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
)

# --- trailers ---
# Akcja konsumenta zapisana w historii: release.sh odmawia patcha i sekcji "None.", gdy commit od poprzedniego
# wydania niesie trailer Consumer-Action, "!" albo stopkę BREAKING CHANGE; bez taga poprzedniego wydania nie
# sprawdza historii. scripts/release-notes.sh szkicuje sekcję z historii first-parent i trailerów.
# Każdy przypadek to kopia release.sh we własnym repo z lokalnym bare origin, bez sieci.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

section() {
  printf '## [%s] - 2026-10-19\n\n### Consumer action required\n\n%s\n\n### Fixed\n\n- Something.\n\n' "$1" "$2"
}

# seed <name> <tag the start: yes|no> <commit message of the change> <changelog section>
seed() {
  local work="$tmp/$1" origin="$tmp/$1.git"
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
  printf '# Changelog\n\n' > "$work/CHANGELOG.md"
  cp "$root/release.sh" "$work/release.sh"
  cp "$root/scripts/changelog-section.sh" "$work/scripts/changelog-section.sh"
  git -C "$work" add -A
  git -C "$work" commit -q -m initial
  [[ "$2" == no ]] || git -C "$work" tag v1.2.3
  echo change > "$work/change.txt"
  printf '%s\n\n%s' "# Changelog" "$4" > "$work/CHANGELOG.md"
  git -C "$work" add -A
  git -C "$work" commit -q -m "$3"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q -u origin main >/dev/null
  printf '%s\n' "$work"
}

release() {
  local work="$1"
  shift
  set +e
  (cd "$work" && ASSUME_YES=1 bash ./release.sh "$@") > "$work.log" 2>&1
  rc=$?
  set -e
}

refused() {
  local work="$1" expected="$2"
  [[ $rc -ne 0 ]] || { cat "$work.log"; fail "release.sh must refuse: $expected"; }
  grep -qF -- "$expected" "$work.log" || { cat "$work.log"; fail "the refusal must say: $expected"; }
  [[ "$(git -C "$work" tag --list)" == v1.2.3 ]] || fail 'a refusal must not tag'
  [[ -z "$(git -C "$work" status --porcelain)" ]] || fail 'a refusal must not touch the tree'
}

trailer=$'feat: rename the knob\n\nConsumer-Action: rename platform.x to platform.y in application.yml'

work=$(seed patch yes "$trailer" "$(section 1.2.4 'None.')")
release "$work" "fix: release" 1.2.4
refused "$work" 'Commits since v1.2.3 record consumer action, so this must be a MINOR release (1.3.0):'
grep -qF 'Consumer-Action: rename platform.x to platform.y in application.yml' "$work.log" || fail 'the refusal must quote the trailer'

work=$(seed none yes "$trailer" "$(section 1.3.0 'None.')")
release "$work" "feat: release" 1.3.0
refused "$work" 'but the 1.3.0 section of CHANGELOG.md says None.'

work=$(seed bang yes 'fix!: drop the knob' "$(section 1.2.4 'None.')")
release "$work" "fix: release" 1.2.4
refused "$work" '"!" marks a breaking change'

work=$(seed footer yes $'fix: drop the knob\n\nBREAKING CHANGE: platform.x is gone' "$(section 1.2.4 'None.')")
release "$work" "fix: release" 1.2.4
refused "$work" 'BREAKING CHANGE footer'

work=$(seed minor yes "$trailer" "$(section 1.3.0 '- Rename platform.x to platform.y.')")
release "$work" "feat: release" 1.3.0
[[ $rc -eq 0 ]] || { cat "$work.log"; fail 'a MINOR release that describes the consumer action must pass'; }
git -C "$work" rev-parse -q --verify refs/tags/v1.3.0 >/dev/null || fail 'the MINOR release must be tagged'

work=$(seed untagged no "$trailer" "$(section 1.2.4 'None.')")
release "$work" "fix: release" 1.2.4
[[ $rc -eq 0 ]] || { cat "$work.log"; fail 'without the previous tag there is no history to check'; }

# release-notes.sh: first-parent tematy po typie, trailery ze wszystkich commitów, bez dubli po --no-ff.
notes="$tmp/notes"
git init -q -b main "$notes"
git -C "$notes" config user.name t
git -C "$notes" config user.email t@example.invalid
git -C "$notes" commit -q --allow-empty -m initial
git -C "$notes" tag v1.6.0
git -C "$notes" switch -q -c feature
git -C "$notes" commit -q --allow-empty -m $'feat(versions): add migrations\n\nConsumer-Action: run platform-bump twice'
git -C "$notes" commit -q --allow-empty -m 'fix: keep the lockfile'
git -C "$notes" switch -q main
git -C "$notes" merge -q --no-ff -m 'feat: upgrade migrations' feature
git -C "$notes" commit -q --allow-empty -m 'fix(release): name the starter'
git -C "$notes" commit -q --allow-empty -m 'update libs'
git -C "$notes" commit -q --allow-empty -m 'chore(release): platform 1.6.1'
out=$(cd "$notes" && bash "$root/scripts/release-notes.sh" v1.6.0..HEAD)
grep -qE '^- run platform-bump twice \([0-9a-f]+\)$' <<<"$out" || { echo "$out"; fail 'the trailer must become a consumer action'; }
grep -qE '^- upgrade migrations \([0-9a-f]+\)$' <<<"$out" || { echo "$out"; fail 'the merge commit must be listed under Added'; }
grep -qE '^- name the starter \([0-9a-f]+\)$' <<<"$out" || fail 'a fix must be listed'
if grep -q 'add migrations\|keep the lockfile\|platform 1.6.1' <<<"$out"; then echo "$out"; fail 'only first-parent subjects, without the release commit'; fi
grep -qE '^- update libs \([0-9a-f]+\)$' <<<"$out" || fail 'a non-conventional subject must be listed as unclassified'
[[ "$(head -3 <<<"$out")" == $'### Consumer action required\n\n- run platform-bump twice'* ]] || { echo "$out"; fail 'the section starts with the consumer action'; }
none=$(cd "$notes" && bash "$root/scripts/release-notes.sh" HEAD~1..HEAD)
grep -qx 'None.' <<<"$none" || { echo "$none"; fail 'a range without trailers says None.'; }

echo 'OK: release.sh reads consumer action from history, and release-notes.sh drafts the section from it'
)
