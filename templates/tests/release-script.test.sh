#!/usr/bin/env bash
# release.sh, przypadek po przypadku: każdy przypadek uruchamia kopię skryptu we własnym repozytorium tymczasowym,
# którego origin to lokalne bare repo, więc nic nie wychodzi do sieci. Przypadki: odmowy dla niebezpiecznego drzewa
# i podbicie wersji, kontrakt wydań i wersjonowania, pozostałe odmowy oraz akcja konsumenta zapisana w historii.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- refuse-and-bump ---
# Hermetyczne testy release.sh: każdy przypadek uruchamia kopię skryptu we własnym repozytorium tymczasowym,
# którego origin to lokalne bare repo, więc nic nie wychodzi do sieci.
#
# release.sh musi odmówić przy brudnym drzewie, gałęzi innej niż main i mainie, który nie jest origin/main,
# zanim cokolwiek podbije, scommituje, otaguje albo wypchnie; czyste wydanie commituje tylko
# pliki wersji i nigdy nie tworzy ruchomego tagu `v1`.
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
  cp "$root/scripts/release-notes.sh" "$work/scripts/release-notes.sh"
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

# Wydanie nie czeka na canary konsumentów: lista konsumentów bez zapisanego wyniku nie blokuje wydania.
work=$(seed_repo consumers)
printf '# consumers\nacme/one\n' > "$work/scripts/consumers.txt"
git -C "$work" add -A
git -C "$work" commit -q -m 'chore: list the consumers'
git -C "$work" push -q origin main
if ! run_release "$work"; then
  cat "$work.log" >&2
  fail 'release.sh must release without a consumer canary record'
fi

echo 'OK: release.sh refuses unsafe trees and commits only the version bump'
)

# --- contract ---
# release.sh egzekwuje kontrakt wydań i wersjonowania (docs/adr/0002-release-and-versioning-contract.md):
#
# - komunikat to angielski Conventional Commit i staje się treścią
#   "chore(release): platform X.Y.Z";
# - wersja ma sekcję CHANGELOG.md z podsekcją "Consumer action required";
# - wydanie z akcją konsumenta albo komunikat feat/breaking bez jawnej wersji
#   nie może być patchem;
# - tag wersji jest adnotowany sekcją CHANGELOG.
#
# Każdy przypadek uruchamia kopię release.sh we własnym repozytorium, którego origin to lokalne bare
# repo, więc nic nie wychodzi do sieci. Odmowy muszą zostawić repozytorium nietknięte.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

readonly CURRENT=1.2.3


# seed_repo <nazwa> <treść changelogu dopisana po nagłówku>
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
  cp "$root/scripts/release-notes.sh" "$work/scripts/release-notes.sh"
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

# --- Odmowy --------------------------------------------------------------------------------
work=$(seed_repo message "$(section 1.2.4 'None.')")
assert_refused "$work" 'a message that is not a Conventional Commit' 'Conventional Commit' 'update libs'

work=$(seed_repo polish "$(section 1.2.4 'None.')")
assert_refused "$work" 'a message in Polish' 'in English' 'fix: popraw błąd wydania'

work=$(seed_repo feat-patch "$(section 1.2.4 'None.')")
assert_refused "$work" 'an automatic patch for a feat message' 'needs an explicit version' 'feat: add a gate'

work=$(seed_repo breaking-patch "$(section 1.2.4 'None.')")
assert_refused "$work" 'an automatic patch for a breaking message' 'needs an explicit version' 'fix!: drop a knob'

work=$(seed_repo no-action "$(printf '## [1.2.4] - 2026-10-18\n\n### Fixed\n\n- Something.\n')")
assert_refused "$work" 'a section without Consumer action required' 'Consumer action required' 'fix: patch it'

work=$(seed_repo action-patch "$(section 1.2.4 '- Grant packages: read.')")
assert_refused "$work" 'a patch that requires consumer action' './release.sh "fix: patch it" 1.3.0' 'fix: patch it'

# --- Minor z akcją konsumenta --------------------------------------------------------------
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
# Odmowy release.sh, których nie pokrywa release-script.test.sh: pusty komunikat wypisuje użycie,
# a wersja, której tag istnieje, jest odrzucana. Żadna nie może commitować, tagować ani pushować.
# Hermetycznie jak release-script.test.sh: kopia skryptu w repozytorium tymczasowym, którego origin
# to lokalne bare repo.
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
  cp "$root/scripts/release-notes.sh" "$work/scripts/release-notes.sh"
  git -C "$work" add -A
  git -C "$work" commit -q -m initial
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q -u origin main > /dev/null
  printf '%s\n' "$work"
}

# assert_untouched <work> <head przed> <tagi przed>: bez commita, bez nowego taga, origin bez zmian.
assert_untouched() {
  local work="$1" head="$2" tags="$3"
  [[ "$(git -C "$work" rev-parse HEAD)" == "$head" ]] || fail "release.sh committed although it refused"
  [[ "$(git -C "$work" tag)" == "$tags" ]] || fail "release.sh tagged although it refused"
  [[ "$(git -C "$work" ls-remote origin refs/heads/main | cut -f1)" == "$head" ]] || fail "release.sh pushed although it refused"
}

# (a) pusty komunikat wypisuje użycie
work=$(seed_repo empty-message)
head=$(git -C "$work" rev-parse HEAD)
if (cd "$work" && bash ./release.sh "" 1.2.4 -y) > "$work.log" 2>&1; then
  fail "an empty message must be refused"
fi
grep -q 'release.sh "commit message" \[X.Y.Z\] \[-y\]' "$work.log" || fail "an empty message must print the usage"
assert_untouched "$work" "$head" ""

# (b) wersja, której tag już istnieje, jest odrzucana
work=$(seed_repo existing-tag)
git -C "$work" tag v1.2.4
head=$(git -C "$work" rev-parse HEAD)
if (cd "$work" && bash ./release.sh "fix: test release" 1.2.4 -y) > "$work.log" 2>&1; then
  fail "a version whose tag exists must be refused"
fi
grep -q 'Tag v1.2.4' "$work.log" || fail "the refusal must name the existing tag"
assert_untouched "$work" "$head" "v1.2.4"

# (c) argument spoza formy "<message>" [X.Y.Z] [-y] (np. dawne --skip-canary) jest odrzucany, nie pomijany
work=$(seed_repo stray-argument)
head=$(git -C "$work" rev-parse HEAD)
for args in '1.2.4|--skip-canary|consumers offline' '1.2.4|-y|extra' '--skip-canary'; do
  IFS='|' read -r -a extra <<<"$args"
  if (cd "$work" && ASSUME_YES=1 bash ./release.sh "fix: test release" "${extra[@]}") > "$work.log" 2>&1; then
    fail "release.sh must refuse the arguments: ${extra[*]}"
  fi
  grep -qF 'Unexpected argument' "$work.log" || { cat "$work.log"; fail "the refusal must name the unexpected argument (${extra[*]})"; }
  assert_untouched "$work" "$head" ""
done
grep -qF 'Unexpected argument "--skip-canary"' "$work.log" || fail 'the refusal must quote the argument'
# "-y" w miejscu wersji: odmowa podpowiada obie poprawne formy.
if (cd "$work" && bash ./release.sh "fix: test release" -y) > "$work.log" 2>&1; then fail 'a -y in place of the version must be refused'; fi
grep -qF 'ASSUME_YES=1' "$work.log" && grep -qF '"fix: test release" X.Y.Z -y' "$work.log" \
  || { cat "$work.log"; fail 'the refusal of -y in place of the version must point to ASSUME_YES=1 and to X.Y.Z -y'; }
assert_untouched "$work" "$head" ""

echo 'OK: release.sh refuses an empty message, an existing tag and stray arguments without committing, tagging or pushing'
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

# seed <nazwa> <tag startu: yes|no> <komunikat commita zmiany> <sekcja changelogu>
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
  cp "$root/scripts/release-notes.sh" "$work/scripts/release-notes.sh"
  git -C "$work" add -A
  git -C "$work" commit -q -m 'chore: start the history'
  [[ "$2" == no ]] || git -C "$work" tag v1.2.3
  echo change > "$work/change.txt"
  printf '%s\n\n%s' "# Changelog" "$4" > "$work/CHANGELOG.md"
  git -C "$work" add -A
  git -C "$work" commit -q -m "$3"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q -u origin main >/dev/null
  printf '%s\n' "$work"
}

# seed_merge <nazwa> <komunikat commita gałęzi> <komunikat merge commita> <sekcja changelogu>: po tagu v1.2.3 zmiana
# wchodzi do main przez --no-ff, jak w merge.sh, więc akcja konsumenta może stać tylko w merge commicie.
seed_merge() {
  local work
  work=$(seed "$1" yes 'chore: prepare the branch' "$4")
  {
    git -C "$work" switch -q -c feature
    git -C "$work" commit -q --allow-empty -m "$2"
    git -C "$work" switch -q main
    git -C "$work" merge -q --no-ff -m "$3" feature
    git -C "$work" push -q origin main
  } > /dev/null 2>&1
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

# refused <work> <oczekiwany komunikat> [tagi po odmowie, domyślnie v1.2.3]
refused() {
  local work="$1" expected="$2" tags="${3-v1.2.3}"
  [[ $rc -ne 0 ]] || { cat "$work.log"; fail "release.sh must refuse: $expected"; }
  grep -qF -- "$expected" "$work.log" || { cat "$work.log"; fail "the refusal must say: $expected"; }
  [[ "$(git -C "$work" tag --list)" == "$tags" ]] || fail 'a refusal must not tag'
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

# --- Sekcja złożona z commitów, gdy CHANGELOG.md nie ma sekcji wersji ---------------------
# release.sh składa ją scripts/release-notes.sh od taga poprzedniego wydania, wstawia pod "## [Unreleased]"
# i commituje CHANGELOG.md razem z plikami wersji; reguły MINOR/PATCH działają na złożonej sekcji.
unreleased=$'## [Unreleased]\n'

work=$(seed composed-patch yes "$trailer" "$unreleased")
release "$work" "fix: release" 1.2.4
refused "$work" 'Commits since v1.2.3 record consumer action, so this must be a MINOR release (1.3.0):'

work=$(seed composed-minor yes "$trailer" "$unreleased")
release "$work" "feat: release" 1.3.0
[[ $rc -eq 0 ]] || { cat "$work.log"; fail 'a MINOR release must compose its section from the commits'; }
change=$(git -C "$work" rev-parse --short HEAD~1)
composed=$(git -C "$work" show HEAD:CHANGELOG.md)
printf '%s\n' "$composed" > "$tmp/composed.md"
grep -qE '^## \[1\.3\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' <<<"$composed" || { echo "$composed"; fail 'the composed section must have a dated version heading'; }
[[ "$(grep -m2 '^## ' <<<"$composed")" == "## [Unreleased]"$'\n'"## [1.3.0] - "* ]] \
  || { echo "$composed"; fail 'the composed section must go right under ## [Unreleased]'; }
action=$(bash "$root/scripts/changelog-section.sh" --consumer-action 1.3.0 "$tmp/composed.md")
[[ "$action" == "- rename platform.x to platform.y in application.yml ($change)" ]] \
  || { echo "$composed"; fail 'the Consumer-Action trailer must become the consumer action of the composed section'; }
grep -qx -- "- rename the knob ($change)" <<<"$composed" || { echo "$composed"; fail 'the feat commit must be listed'; }
[[ "$(git -C "$work" diff --name-only HEAD~1 HEAD)" == *CHANGELOG.md* ]] || fail 'the release commit must carry the composed CHANGELOG.md'
[[ -z "$(git -C "$work" status --porcelain)" ]] || fail 'a composed release must leave a clean tree'
git -C "$work" tag -l --format='%(contents)' v1.3.0 | grep -qxF -- "- rename platform.x to platform.y in application.yml ($change)" \
  || fail 'the tag message must carry the composed consumer action'

work=$(seed composed-bang yes 'refactor!: drop the knob' "$unreleased")
release "$work" "feat: release" 1.3.0
[[ $rc -eq 0 ]] || { cat "$work.log"; fail 'a MINOR release after a "!" commit must compose its section'; }
git -C "$work" show HEAD:CHANGELOG.md > "$tmp/composed.md"
bash "$root/scripts/changelog-section.sh" --consumer-action 1.3.0 "$tmp/composed.md" \
  | grep -qE '^- Breaking change: drop the knob \([0-9a-f]+\)$' || fail 'a "!" commit must become a consumer action'

work=$(seed composed-none yes 'fix: keep the lockfile' "$unreleased")
release "$work" "fix: release" 1.2.4
[[ $rc -eq 0 ]] || { cat "$work.log"; fail 'a PATCH without consumer action must compose its section'; }
git -C "$work" show HEAD:CHANGELOG.md > "$tmp/composed.md"
[[ "$(bash "$root/scripts/changelog-section.sh" --consumer-action 1.2.4 "$tmp/composed.md")" == None. ]] \
  || fail 'a composed section without trailers or "!" says None.'

# Akcja konsumenta zapisana tylko w merge commicie (merge.sh pisze go z --no-ff) liczy się jak na commicie gałęzi:
# "!" w temacie i trailer Consumer-Action wymuszają MINOR i trafiają do złożonej sekcji.
bang_merge='refactor(ci)!: rename the deploy input'
trailer_merge=$'feat: add the knob\n\nConsumer-Action: set platform.knob in gradle.properties'

work=$(seed_merge merge-bang-patch 'refactor(ci): rename input' "$bang_merge" "$unreleased")
release "$work" "fix: release" 1.2.4
refused "$work" 'Commits since v1.2.3 record consumer action, so this must be a MINOR release (1.3.0):'
grep -qF '"!" marks a breaking change' "$work.log" || { cat "$work.log"; fail 'the refusal must name the "!" merge commit'; }

work=$(seed_merge merge-bang-minor 'refactor(ci): rename input' "$bang_merge" "$unreleased")
release "$work" "feat: release" 1.3.0
[[ $rc -eq 0 ]] || { cat "$work.log"; fail 'a MINOR release after a "!" merge commit must compose its section'; }
merge=$(git -C "$work" rev-parse --short HEAD~1)
git -C "$work" show HEAD:CHANGELOG.md > "$tmp/composed.md"
[[ "$(bash "$root/scripts/changelog-section.sh" --consumer-action 1.3.0 "$tmp/composed.md")" == "- Breaking change: rename the deploy input ($merge)" ]] \
  || { cat "$tmp/composed.md"; fail 'a "!" merge commit must become the consumer action'; }

work=$(seed_merge merge-trailer-patch 'feat: add a knob' "$trailer_merge" "$unreleased")
release "$work" "fix: release" 1.2.4
refused "$work" 'Commits since v1.2.3 record consumer action, so this must be a MINOR release (1.3.0):'
grep -qF 'Consumer-Action: set platform.knob in gradle.properties' "$work.log" || { cat "$work.log"; fail 'the refusal must quote the merge trailer'; }

work=$(seed_merge merge-trailer-minor 'feat: add a knob' "$trailer_merge" "$unreleased")
release "$work" "feat: release" 1.3.0
[[ $rc -eq 0 ]] || { cat "$work.log"; fail 'a MINOR release after a merge trailer must compose its section'; }
merge=$(git -C "$work" rev-parse --short HEAD~1)
git -C "$work" show HEAD:CHANGELOG.md > "$tmp/composed.md"
[[ "$(bash "$root/scripts/changelog-section.sh" --consumer-action 1.3.0 "$tmp/composed.md")" == "- set platform.knob in gradle.properties ($merge)" ]] \
  || { cat "$tmp/composed.md"; fail 'a trailer only in the merge commit must become the consumer action'; }

# Ręcznie napisana sekcja wersji wygrywa ze składaniem: release.sh bierze ją bez zmian i nie dotyka CHANGELOG.md.
work=$(seed hand-written-patch yes 'fix: keep the lockfile' "$unreleased"$'\n'"$(section 1.2.4 'None.')")
before=$(git -C "$work" show HEAD:CHANGELOG.md)
release "$work" "fix: release" 1.2.4
[[ $rc -eq 0 ]] || { cat "$work.log"; fail 'a hand-written section must release'; }
[[ "$(git -C "$work" show HEAD:CHANGELOG.md)" == "$before" ]] || fail 'a hand-written section must leave CHANGELOG.md as it is'
[[ "$(git -C "$work" diff --name-only HEAD~1 HEAD)" != *CHANGELOG.md* ]] || fail 'a hand-written release commits only the version files'
notes=$(git -C "$work" tag -l --format='%(contents)' v1.2.4)
grep -qx -- '- Something.' <<<"$notes" || fail 'the tag must carry the hand-written section'
if grep -q 'keep the lockfile' <<<"$notes"; then fail 'a hand-written section must not be composed from the commits'; fi

# Bez taga poprzedniego wydania release.sh składa sekcję z całej historii, a PATCH z akcją konsumenta odsyła wprost
# do komendy MINOR (nie ma sekcji do przemianowania).
work=$(seed composed-untagged-patch no "$trailer" "$unreleased")
release "$work" "fix: release" 1.2.4
refused "$work" './release.sh "fix: release" 1.3.0' ''
grep -qF 'CHANGELOG.md lists consumer action for 1.2.4, so it must be a MINOR release:' "$work.log" || { cat "$work.log"; fail 'the refusal must say why'; }
if grep -q 'rename the section' "$work.log"; then cat "$work.log"; fail 'a composed section has no heading to rename'; fi
work=$(seed composed-untagged-minor no "$trailer" "$unreleased")
release "$work" "feat: release" 1.3.0
[[ $rc -eq 0 ]] || { cat "$work.log"; fail 'without a previous tag the section must be composed from the whole history'; }
grep -qF 'composed from the commits since the first commit' "$work.log" || { cat "$work.log"; fail 'the plan must say where the composed notes start'; }

# Najnowsza sekcja wersji w CHANGELOG.md bez taga to niewydana ręczna sekcja: najpierw wydaj ją, potem składaj kolejną.
work=$(seed untagged-section yes 'fix: keep the lockfile' "$unreleased"$'\n'"$(section 1.2.4 'None.')")
release "$work" "fix: release" 1.2.5
refused "$work" 'has no v1.2.4 tag: release 1.2.4 first'
work=$(seed tagged-section yes 'fix: keep the lockfile' "$unreleased"$'\n'"$(section 1.2.3 'None.')")
release "$work" "fix: release" 1.2.4
[[ $rc -eq 0 ]] || { cat "$work.log"; fail 'a released newest section must not block composing the next one'; }
[[ "$(git -C "$work" show HEAD:CHANGELOG.md | grep '^## ' | cut -c1-12)" == $'## [Unreleas\n## [1.2.4] -\n## [1.2.3] -' ]] \
  || { git -C "$work" show HEAD:CHANGELOG.md; fail 'the composed section must go between [Unreleased] and the released section'; }

# Tag poprzedniego wydania tylko w origin (klon pobrał commit przed tagiem): release.sh pobiera tagi i składa sekcję
# od niego, a nie od starszego taga lokalnego, więc wydane już commity nie wracają do notatek.
work=$(seed remote-tag yes 'fix: keep the lockfile' "$unreleased")
{
  git -C "$work" commit -q --allow-empty -m 'fix: drop the cache'
  git -C "$work" tag v1.2.4
  git -C "$work" push -q origin main v1.2.4
  git -C "$work" tag -d v1.2.4
  git -C "$work" commit -q --allow-empty -m 'fix: name the starter'
  git -C "$work" push -q origin main
} > /dev/null 2>&1
release "$work" "fix: release" 1.2.5
[[ $rc -eq 0 ]] || { cat "$work.log"; fail 'a release after a tag that exists only on origin must compose its section'; }
grep -qF 'composed from the commits since v1.2.4' "$work.log" || { cat "$work.log"; fail 'the composed range must start at the tag on origin'; }
composed=$(git -C "$work" show HEAD:CHANGELOG.md)
grep -q 'name the starter' <<<"$composed" || { echo "$composed"; fail 'the commit after the tag must be listed'; }
if grep -q 'drop the cache\|keep the lockfile' <<<"$composed"; then echo "$composed"; fail 'commits of earlier releases must not come back'; fi

# Tag lokalny różny od tego w origin zatrzymuje pobranie tagów: release.sh odmawia, zamiast liczyć od złego taga.
work=$(seed clobbered-tag yes 'fix: keep the lockfile' "$unreleased")
{
  git -C "$work" push -q origin v1.2.3
  git -C "$work" tag -f v1.2.3 HEAD
} > /dev/null 2>&1
release "$work" "fix: release" 1.2.4
refused "$work" 'Could not fetch the release tags from origin'

# Pusty zakres od taga: nie ma czego wydać.
work=$(seed empty-range no 'chore: prepare the release' "$unreleased")
git -C "$work" tag v1.2.3
release "$work" "fix: release" 1.2.4
refused "$work" 'there are no commits since v1.2.3'

# Składanie odmawia, gdy nie wiadomo, gdzie wstawić sekcję albo co z niej opublikować.
work=$(seed no-unreleased yes 'fix: keep the lockfile' '')
release "$work" "fix: release" 1.2.4
refused "$work" 'no "## [Unreleased]" heading'
work=$(seed unreleased-entries yes 'fix: keep the lockfile' "$unreleased"$'\n### Fixed\n\n- An entry.\n')
release "$work" "fix: release" 1.2.4
refused "$work" 'has entries under "## [Unreleased]"'
work=$(seed unclassified yes 'update libs' "$unreleased")
release "$work" "fix: release" 1.2.4
refused "$work" 'not Conventional Commits'

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
git -C "$notes" commit -q --allow-empty -m 'refactor(versions)!: drop the legacy flag'
git -C "$notes" commit -q --allow-empty -m $'fix: drop the knob\n\nBREAKING CHANGE: platform.x is gone'
git -C "$notes" commit -q --allow-empty -m $'feat!: rename the flag\n\nConsumer-Action: rename flag x to y'
breaking=$(cd "$notes" && bash "$root/scripts/release-notes.sh" HEAD~3..HEAD)
grep -qE '^- Breaking change: drop the legacy flag \([0-9a-f]+\)$' <<<"$breaking" || { echo "$breaking"; fail 'a "!" commit must become a consumer action'; }
grep -qE '^- Breaking change: platform.x is gone \([0-9a-f]+\)$' <<<"$breaking" || { echo "$breaking"; fail 'a BREAKING CHANGE footer must become a consumer action'; }
grep -qE '^- rename flag x to y \([0-9a-f]+\)$' <<<"$breaking" || { echo "$breaking"; fail 'the trailer of a "!" commit must become its consumer action'; }
if grep -q 'Breaking change: rename the flag' <<<"$breaking"; then echo "$breaking"; fail 'a "!" commit with a trailer is listed once, by its trailer'; fi
git -C "$notes" switch -q -c second
git -C "$notes" commit -q --allow-empty -m $'feat: add the knob\n\nConsumer-Action: set platform.knob'
git -C "$notes" switch -q main
git -C "$notes" merge -q --no-ff -m $'feat: add the knob\n\nConsumer-Action: set platform.knob' second
twice=$(cd "$notes" && bash "$root/scripts/release-notes.sh" HEAD~1..HEAD)
[[ "$(grep -c 'set platform.knob' <<<"$twice")" == 1 ]] || { echo "$twice"; fail 'a trailer repeated in the merge commit is listed once'; }
# Merge commit i commity, które wnosi, to jedna zmiana: trailer po jednej stronie zastępuje linię "Breaking change:"
# po drugiej, w obu kierunkach.
git -C "$notes" switch -q -c third
git -C "$notes" commit -q --allow-empty -m $'feat!: drop the old input\n\nConsumer-Action: replace input x with y'
git -C "$notes" switch -q main
git -C "$notes" merge -q --no-ff -m 'feat!: drop the old input' third
git -C "$notes" switch -q -c fourth
git -C "$notes" commit -q --allow-empty -m 'refactor!: rename the input'
git -C "$notes" switch -q main
git -C "$notes" merge -q --no-ff -m $'refactor!: rename the input\n\nConsumer-Action: rename input a to b' fourth
grouped=$(cd "$notes" && bash "$root/scripts/release-notes.sh" HEAD~2..HEAD)
[[ "$(sed -n '/^### Consumer action required/,/^### Added/p' <<<"$grouped" | grep -c '^- ')" == 2 ]] \
  || { echo "$grouped"; fail 'a merge and the commits it brings in give one line per trailer'; }
grep -qE '^- replace input x with y \([0-9a-f]+\)$' <<<"$grouped" || { echo "$grouped"; fail 'the trailer of the branch commit must be listed'; }
grep -qE '^- rename input a to b \([0-9a-f]+\)$' <<<"$grouped" || { echo "$grouped"; fail 'the trailer of the merge commit must be listed'; }
if grep -q 'Breaking change:' <<<"$grouped"; then echo "$grouped"; fail 'a "!" covered by a trailer on the other side of the merge adds no Breaking change line'; fi

echo 'OK: release.sh reads consumer action from history and composes a missing section with release-notes.sh'
)
