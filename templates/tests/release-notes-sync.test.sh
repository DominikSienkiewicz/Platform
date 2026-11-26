#!/usr/bin/env bash
set -euo pipefail
generator=$(cd "$(dirname "$0")/../.." && pwd)/scripts/release-notes.sh
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git init -q -b main "$fixture"
cd "$fixture"
git config user.name Fixture
git config user.email fixture@example.invalid
git commit --allow-empty -qm 'chore: initial release'
base=$(git rev-parse HEAD)

git switch -qc pgvector
echo '0.8.7' > image
git add image
git commit -qm 'chore: adjust the fixture'
git switch -q main
git merge -q --no-ff pgvector -m 'Merge pull request #15 from example/pgvector' -m 'chore(deps): update pgvector'
git branch upstream
git commit --allow-empty -qm 'fix: keep a local change'
git switch -qc scanner upstream
echo '7.4.3' > scanner-version
git add scanner-version
git commit -qm 'chore: adjust the scanner'
git switch -q upstream
git merge -q --no-ff scanner -m 'Merge pull request #14 from example/scanner' -m 'fix(ci): update Anchore'
git switch -q main
git merge -q --no-ff upstream -m "Merge remote-tracking branch 'origin/main'"

notes=$(bash "$generator" "$base..HEAD")
[[ $(grep -c '^- update Anchore (' <<< "$notes") == 1 ]] || { echo 'FAIL: the synchronized GitHub PR title must appear once' >&2; exit 1; }
[[ $(grep -c '^- update pgvector (' <<< "$notes") == 1 ]]
[[ "$notes" == *'keep a local change'* && "$notes" != *'adjust the scanner'* && "$notes" != *Unclassified* ]]
notes=$(bash "$generator" 'upstream..HEAD')
[[ "$notes" != *'update Anchore'* && "$notes" != *'update pgvector'* && "$notes" == *'keep a local change'* ]]

echo 'manual edit during the merge' >> scanner-version
git commit -qa --amend --no-edit
notes=$(bash "$generator" "$base..HEAD")
[[ "$notes" == *'### Unclassified'* && "$notes" == *"Merge remote-tracking branch 'origin/main'"* ]]
echo 'OK: synchronized PRs retain their reviewed titles, range and manual-review guard'
