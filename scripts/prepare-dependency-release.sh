#!/usr/bin/env bash
# Przygotowuje pliki wydania w checkoutcie PR-a po aktualizacji zależności. Nie zapisuje
# obiektów ani referencji Git. Wywołujący klasyfikuje major zależności przez --review-major.
set -euo pipefail
die() { echo "Cannot prepare dependency release: $*" >&2; exit 1; }
[[ $# -eq 1 || ( $# -eq 2 && $2 == --review-major ) ]] ||
  die 'usage: prepare-dependency-release.sh <main commit SHA> [--review-major]'
cd "$(git rev-parse --show-toplevel)"
base=$1
[[ "$base" =~ ^[0-9a-f]{40}$ && "$base" == "$(git rev-parse --verify refs/remotes/origin/main)" ]] ||
  die 'the update base is stale; refresh it against origin/main'
[[ $(git rev-parse --is-shallow-repository) == false ]] || die 'fetch the complete history and release tags'
git merge-base --is-ancestor "$base" HEAD || die 'rebase the update onto current main'
notes_head=$(git rev-parse HEAD)
while [[ "$notes_head" != "$base" && $(git show -s --format=%s "$notes_head") == 'chore(deps): refresh generated dependency files' ]]; do
  notes_head=$(git rev-parse "$notes_head^")
done
[[ "$notes_head" != "$base" ]] || die 'the update has no dependency commit beyond main'

current=$(git show "$base:gradle/build-logic/gradle.properties" | sed -n 's/^platformVersion=//p')
[[ "$current" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die 'main has an invalid platformVersion'
IFS=. read -r major minor patch <<< "$current"
tag="v$current"
[[ $(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$base") == "$tag" ]] ||
  die "fetch the tags and confirm main's previous release is $tag"
git merge-base --is-ancestor "$tag" "$base" || die "$tag is outside the release history"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bash scripts/release-notes.sh "$tag..$notes_head" > "$tmp/notes"
if grep -q '^### Unclassified' "$tmp/notes"; then die 'release history contains unclassified commits; prepare the release manually'; fi
if [[ -n $(bash scripts/release-notes.sh --markers "$notes_head..HEAD") ]]; then
  die 'a generated commit declares consumer actions; review the release notes manually'
fi
bash scripts/release-notes.sh --markers "$tag..$notes_head" > "$tmp/markers"
target="$major.$minor.$((patch + 1))"
if [[ -s "$tmp/markers" || ${2:-} == --review-major ]]; then
  target="$major.$((minor + 1)).0"
fi
if git show-ref --verify --quiet "refs/tags/v$target"; then die "the immutable tag v$target already exists"; fi

git show "$base:CHANGELOG.md" > "$tmp/base-changelog"
date_of_update=$(TZ=UTC git show -s --format=%cd --date=format-local:%F "$notes_head")
subject=$(git show -s --format=%s "$notes_head")
python3 - "$tmp" "$current" "$target" "$date_of_update" "${2:-}" "$subject" <<'PY'
from pathlib import Path
import re
import sys

tmp, current, target, date, review, subject = sys.argv[1:]
work = Path(tmp)
base = (work / "base-changelog").read_text()
notes = (work / "notes").read_text().rstrip()
if review:
    update = subject.partition(": ")[2] or subject
    action = f"- Review the upstream migration for “{update}” before adopting this Platform release."
    actions, *sections = notes.split("\n### ", 1)
    if actions.rstrip().endswith("\nNone."):
        actions = actions.rstrip().removesuffix("None.").rstrip() + "\n\n" + action
    else:
        actions = actions.rstrip() + "\n" + action
    notes = "\n### ".join([actions, *sections])
heading = "## [Unreleased]"
start = re.search(r"^## \[Unreleased\]$\n\s*(?=^## )", base, re.M)
if not start or not base[start.end():].startswith(f"## [{current}] - "):
    sys.exit("Cannot prepare dependency release: review the pending changelog section and release it manually.")
release = f"{heading}\n\n## [{target}] - {date}\n\n{notes}\n\n"
changelog = Path("CHANGELOG.md")
prepared = base[:start.start()] + release + base[start.end():]
if changelog.read_text() not in (base, prepared):
    sys.exit("Cannot prepare dependency release: the candidate contains independently edited release notes.")

changes = {changelog: prepared}
properties = sorted(Path("gradle").glob("*/gradle.properties")) + sorted(Path("templates/jvm").glob("*/gradle.properties"))
packages = sorted(Path("frontend/packages").glob("*/package.json"))
if not properties or not packages:
    sys.exit("Cannot prepare dependency release: missing Platform version files.")
for file, pattern in [(f, r"^(platformVersion=)([^\n]+)$") for f in properties] + [
    (f, r'^(  "version": ")([^"]+)(?=",?$)') for f in packages
]:
    source = file.read_text()
    matches = list(re.finditer(pattern, source, re.M))
    if len(matches) != 1 or matches[0][2] not in (current, target):
        sys.exit(f"Cannot prepare dependency release: inconsistent version in {file}.")
    version = matches[0]
    changes[file] = source[:version.start(2)] + target + source[version.end(2):]
for file, content in changes.items():
    if file.read_text() != content:
        file.write_text(content)
PY
printf '%s\n' "$target"
