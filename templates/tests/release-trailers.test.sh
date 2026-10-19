#!/usr/bin/env bash
# Akcja konsumenta zapisana w historii: release.sh odmawia patcha i sekcji "None.", gdy commit od poprzedniego
# wydania niesie trailer Consumer-Action, "!" albo stopkę BREAKING CHANGE; bez taga poprzedniego wydania nie
# sprawdza historii. scripts/release-notes.sh szkicuje sekcję z historii first-parent i trailerów.
# Każdy przypadek to kopia release.sh we własnym repo z lokalnym bare origin, bez sieci.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; exit 1; }

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
