#!/usr/bin/env bash
# Pełny cykl worktree w repo tymczasowym z lokalnym bare origin: worktree-new.sh tworzy gałąź i worktree
# (kolizja nazwy = -2, jedna linia /.worktrees/ w exclude), worktree-status.sh pokazuje stan, a merge.sh
# integruje gałąź i sprząta worktree.
set -euo pipefail
templates=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_MERGE_AUTOEDIT=no NO_COLOR=1
fail() { echo "FAIL: $*" >&2; exit 1; }

git init -q --bare -b main "$tmp/origin.git"
repo="$tmp/repo"
git init -q -b main "$repo"
git -C "$repo" config user.name 'Lifecycle Test'
git -C "$repo" config user.email 'lifecycle@example.invalid'
git -C "$repo" commit -q --allow-empty -m initial
git -C "$repo" remote add origin "$tmp/origin.git"
git -C "$repo" push -q -u origin main
date=$(date +%F)

path=$(cd "$repo" && bash "$templates/worktree-new.sh" feat demo)
[[ "$path" == "$(cd "$repo" && pwd -P)/.worktrees/demo-$date" ]] || fail "unexpected worktree path: $path"
[[ "$(git -C "$path" branch --show-current)" == "feat/demo-$date" ]] || fail 'the branch must be <type>/<description>-<date>'
second=$(cd "$path" && bash "$templates/worktree-new.sh" feat demo)
[[ "$second" == *"/.worktrees/demo-$date-2" ]] || fail "a taken name must get -2, got $second"
[[ "$(git -C "$second" branch --show-current)" == "feat/demo-$date-2" ]] || fail 'the second branch must carry -2'
[[ $(grep -cx '/.worktrees/' "$repo/.git/info/exclude") -eq 1 ]] || fail 'exactly one /.worktrees/ line in .git/info/exclude'
[[ -z "$(git -C "$repo" status --porcelain)" ]] || fail 'the worktrees must be ignored by the main checkout'

if (cd "$repo" && bash "$templates/worktree-new.sh" feature demo) 2>/dev/null; then fail 'a type that is not Conventional must be refused'; fi
if (cd "$repo" && bash "$templates/worktree-new.sh" fix "Login Bug") 2>/dev/null; then fail 'a description that is not kebab-case must be refused'; fi

echo demo > "$path/demo.txt"
status=$(cd "$repo" && bash "$templates/worktree-status.sh")
grep -E "^\.worktrees/demo-$date +feat/demo-$date +0 +0 +1  dirty$" <<<"$status" >/dev/null || { echo "$status"; fail 'an uncommitted file makes the worktree dirty'; }
grep -E "^\.worktrees/demo-$date-2 +feat/demo-$date-2 +0 +0 +0  empty$" <<<"$status" >/dev/null || { echo "$status"; fail 'a worktree without commits is empty'; }
git -C "$path" add demo.txt
git -C "$path" commit -q -m 'feat: demo'
status=$(cd "$repo" && bash "$templates/worktree-status.sh")
grep -E "^\.worktrees/demo-$date +feat/demo-$date +1 +0 +0  ready for merge.sh$" <<<"$status" >/dev/null || { echo "$status"; fail 'a clean worktree with a commit is ready'; }

(cd "$repo" && bash "$templates/merge.sh" "feat/demo-$date" 'feat: demo') > "$tmp/merge.log" 2>&1 || { cat "$tmp/merge.log"; fail 'merge.sh must integrate the branch'; }
[[ -f "$repo/demo.txt" ]] || fail 'the change must be on main'
[[ ! -d "$path" ]] || fail 'merge.sh must remove the worktree'
status=$(cd "$repo" && bash "$templates/worktree-status.sh" --offline)
if grep -qF "demo-$date " <<<"$status"; then echo "$status"; fail 'the integrated worktree must be gone from the status'; fi

echo 'OK: worktree-new, worktree-status and merge.sh run the whole worktree lifecycle'
