#!/usr/bin/env bash
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
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

readonly CURRENT=1.2.3

fail() {
  local message="$1"
  echo "FAIL: $message" >&2
  exit 1
}

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
