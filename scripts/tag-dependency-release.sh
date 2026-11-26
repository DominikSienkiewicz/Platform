#!/usr/bin/env bash
# tag-dependency-release.sh <merge-sha> <reviewed-head-sha>: po scaleniu PR-a oznacza sprawdzony commit
# tagiem. Utworzenie referencji przez aplikację GitHub lub opiekuna uruchamia release.yml.
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
[[ $# == 2 ]] || fail 'Usage: tag-dependency-release.sh <merge-sha> <reviewed-head-sha>'
merged=$1
reviewed=$2
scripts=$(cd "$(dirname "$0")" && pwd)
[[ $merged =~ ^[a-f0-9]{40}$ && $reviewed =~ ^[a-f0-9]{40}$ ]] || fail 'Both event revisions must be full commit SHAs.'
[[ $(git rev-parse HEAD) == "$merged" ]] || fail 'The checkout does not match the merge commit.'
reviewed_tree=$(git rev-parse --verify "$reviewed^{tree}")
[[ $(git rev-parse "$merged^{tree}") == "$reviewed_tree" ]] || fail 'The merged tree differs from the reviewed PR head. Refresh and review the candidate.'
parent=$(git rev-parse "$merged^1")
property=gradle/build-logic/gradle.properties
platform_version() {
  git show "$1:$property" | sed -n 's/^platformVersion=//p'
}
previous=$(platform_version "$parent")
version=$(platform_version "$merged")
number='(0|[1-9][0-9]*)'
semver="^$number\\.$number\\.$number$"
[[ $version =~ $semver && $previous =~ $semver ]] || fail 'Expected one canonical platformVersion X.Y.Z in both commits.'
IFS=. read -r major minor patch <<< "$previous"
next_patch="$major.$minor.$((patch + 1))"
next_minor="$major.$((minor + 1)).0"
[[ $version == "$next_patch" || $version == "$next_minor" ]] || fail "Expected the next patch ($next_patch) or minor ($next_minor), found $version."
git merge-base --is-ancestor "refs/tags/v$previous^{commit}" "$parent" || fail "The previous tag v$previous must precede the update on main."

changelog=$(mktemp)
trap 'rm -f "$changelog"' EXIT
git show "$merged:CHANGELOG.md" > "$changelog"
prefix="## [$version] - "
heading=$(awk -v prefix="$prefix" 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1) }' "$changelog")
[[ $heading =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "Expected one dated CHANGELOG section for $version."
section=$(bash "$scripts/changelog-section.sh" "$version" "$changelog") || fail "Missing reviewed CHANGELOG section for $version."
action=$(bash "$scripts/changelog-section.sh" --consumer-action "$version" "$changelog") || fail 'Missing Consumer action required subsection.'
[[ -n $action ]] || fail 'The Consumer action required subsection is empty.'
markers=$(bash "$scripts/release-notes.sh" --markers "refs/tags/v$previous..$merged")
if [[ $action == None || $action == None. ]]; then
  [[ $version == "$next_patch" && -z $markers ]] || fail 'A release without consumer action must be a patch and have no breaking-change markers.'
else
  [[ $version == "$next_minor" ]] || fail 'A release with consumer action must be a minor.'
fi

tag="v$version"
message=$(printf 'Platform %s\n\n%s' "$version" "$section")
api='repos/{owner}/{repo}/git'
ref="refs/tags/$tag"
# matching-refs zwraca także dłuższe nazwy zaczynające się od taga. Błąd API przerywa pracę.
find_tag_ref() {
  gh api "$api/matching-refs/tags/$tag" | jq -r --arg ref "$ref" '.[] | select(.ref == $ref) | [.object.type, .object.sha] | @tsv'
}
existing=$(find_tag_ref)
if [[ -z $existing ]]; then
  object=$(gh api "$api/tags" --method POST -f "tag=$tag" -f "message=$message" -f "object=$merged" -f type=commit | jq -er '.sha')
  [[ $object =~ ^[a-f0-9]{40}$ ]] || fail 'GitHub did not return the annotated tag object.'
  if gh api "$api/refs" --method POST -f "ref=$ref" -f "sha=$object" >/dev/null; then
    echo "Created $tag on the reviewed merge."
    exit 0
  fi
  # Odpowiedź mogła zaginąć lub drugi job mógł właśnie utworzyć ten sam tag.
  existing=$(find_tag_ref)
  [[ -n $existing ]] || fail "Could not create $ref."
fi

IFS=$'\t' read -r kind sha <<< "$existing"
[[ $kind == tag && $sha =~ ^[a-f0-9]{40}$ ]] || fail "Existing $tag is not an annotated tag."
gh api "$api/tags/$sha" | jq -e --arg tag "$tag" --arg merge "$merged" --arg notes "$message" '
  .tag == $tag and .object.type == "commit" and .object.sha == $merge and
  (.message | rtrimstr("\n")) == $notes
' >/dev/null || fail "Existing $tag differs from the reviewed commit or release notes."
echo "Verified existing $tag on the reviewed merge."
