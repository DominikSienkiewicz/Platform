#!/usr/bin/env bash
# bump-version.sh: semver backendu (patch, jawna wersja, nieznana akcja bez zmiany pliku), changeset Liquibase
# do pustej listy master oraz autor changesetu = nazwa repo, także gdy skrypt biegnie z worktree <repo>/.worktrees/<x>.
set -euo pipefail
canon="$(cd "$(dirname "$0")/.." && pwd)/bump-version.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# app <dir>: repo w układzie konsumenta ze skryptem w scripts/.
app() {
  mkdir -p "$1/scripts" "$1/backend/src/main/resources/db/changelog"
  cp "$canon" "$1/scripts/bump-version.sh"
  printf 'version=1.2.3\norg.gradle.caching=true\n' > "$1/backend/gradle.properties"
  printf 'databaseChangeLog: []\n' > "$1/backend/src/main/resources/db/changelog/db.changelog-master.yaml"
}

plain="$tmp/Plain"
app "$plain"
bash "$plain/scripts/bump-version.sh" backend patch > /dev/null
grep -qx 'version=1.2.4' "$plain/backend/gradle.properties" || fail '(a) patch must turn 1.2.3 into 1.2.4'
bash "$plain/scripts/bump-version.sh" backend 2.0.0 > /dev/null
grep -qx 'version=2.0.0' "$plain/backend/gradle.properties" || fail '(b) an explicit version must be set as given'
cp "$plain/backend/gradle.properties" "$tmp/before"
if bash "$plain/scripts/bump-version.sh" backend bogus > /dev/null 2>&1; then fail '(c) an unknown action must fail'; fi
cmp -s "$tmp/before" "$plain/backend/gradle.properties" || fail '(c) an unknown action must leave gradle.properties unchanged'

bash "$plain/scripts/bump-version.sh" db new-migration add-users > /dev/null
master="$plain/backend/src/main/resources/db/changelog/db.changelog-master.yaml"
[[ "$(head -1 "$master")" == 'databaseChangeLog:' ]] || fail '(e) an empty master list must become a block list'
grep -qx '      file: db/changelog/changes/0001-add-users.yaml' "$master" || fail '(e) the changeset must be included in the master'
grep -qx '      author: plain' "$plain/backend/src/main/resources/db/changelog/changes/0001-add-users.yaml" \
  || fail '(f) outside git the author is the lower-cased directory name'

repo="$tmp/MyApp"
app "$repo"
git -C "$repo" init -q
git -C "$repo" -c user.name=t -c user.email=t@example.invalid add -A
git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q -m init
git -C "$repo" worktree add -q "$repo/.worktrees/feat-x"
bash "$repo/.worktrees/feat-x/scripts/bump-version.sh" db new-migration add-users > /dev/null
changeset="$repo/.worktrees/feat-x/backend/src/main/resources/db/changelog/changes/0001-add-users.yaml"
grep -qx '      author: myapp' "$changeset" || fail "(d) a worktree must write the repository name, got: $(grep author "$changeset")"

echo 'OK: bump-version bumps semver, writes changesets into an empty master and names the repository as author from a worktree'
