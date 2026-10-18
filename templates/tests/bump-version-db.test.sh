#!/usr/bin/env bash
# bump-version.sh db new-migration numbers the new Liquibase changeset after the highest existing
# 4-digit prefix and ignores files without one.
set -euo pipefail
canon="$(cd "$(dirname "$0")/.." && pwd)/bump-version.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { local message="$1"; echo "FAIL: $message" >&2; exit 1; }

repo="$tmp/app"
changes="$repo/backend/src/main/resources/db/changelog/changes"
mkdir -p "$repo/scripts" "$changes"
cp "$canon" "$repo/scripts/bump-version.sh"
printf 'databaseChangeLog: []\n' > "$repo/backend/src/main/resources/db/changelog/db.changelog-master.yaml"
touch "$changes/0001-baseline.yaml" "$changes/0009-index.yaml" "$changes/0010-users.yaml" "$changes/README.md"

bash "$repo/scripts/bump-version.sh" db new-migration orders > /dev/null
[[ -f "$changes/0011-orders.yaml" ]] || fail "the next changeset after 0010 must be 0011-orders.yaml: $(ls "$changes")"
grep -q 'file: db/changelog/changes/0011-orders.yaml' "$repo/backend/src/main/resources/db/changelog/db.changelog-master.yaml" \
  || fail 'the new changeset must be included in the master changelog'

empty="$tmp/empty"
mkdir -p "$empty/scripts" "$empty/backend/src/main/resources/db/changelog"
cp "$canon" "$empty/scripts/bump-version.sh"
printf 'databaseChangeLog: []\n' > "$empty/backend/src/main/resources/db/changelog/db.changelog-master.yaml"
bash "$empty/scripts/bump-version.sh" db new-migration first > /dev/null
[[ -f "$empty/backend/src/main/resources/db/changelog/changes/0001-first.yaml" ]] || fail 'the first changeset must be 0001'

echo 'OK: bump-version numbers new changesets after the highest existing prefix'
