#!/usr/bin/env bash
# merge.sh ostrzega, gdy gałąź źródłowa nakłada commity, których zmiany już są na celu (ten sam patch-id,
# np. cherry-pick wpięty dwiema drogami), i mimo to merguje: hotfix wybrany na main, a potem merge gałęzi
# to legalny wzorzec. Hermetyczne repo, bez origin (--offline).
set -euo pipefail
canon="$(cd "$(dirname "$0")/.." && pwd)/merge.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Runner CI nie ma globalnej tożsamości gita; bez globalnego configu lokalny przebieg widzi to samo.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; echo "$out" >&2; exit 1; }

repo="$work/repo"
git init -q -b main "$repo"
# Tożsamość w configu repo, nie w `-c`: commit merge'a robi git wołany przez merge.sh.
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.invalid
g() { git -C "$repo" "$@"; }
g commit -q --allow-empty -m initial
g switch -q -c feature
echo hotfix > "$repo/hotfix.txt"; g add hotfix.txt; g commit -q -m "fix: hotfix shipped twice"
echo work > "$repo/work.txt"; g add work.txt; g commit -q -m "feat: real feature work"
g switch -q main
g cherry-pick -x feature~1 > /dev/null
g worktree add -q "$work/feature-wt" feature

out=$(cd "$repo" && GIT_MERGE_AUTOEDIT=no bash "$canon" feature "chore: merge feature" --offline --dry-run 2>&1) || fail 'a dry run must succeed'
grep -qF 'feature re-applies 1 commit(s) whose changes are already on main' <<<"$out" || fail 'the dry run must warn about the duplicate'

out=$(cd "$repo" && GIT_MERGE_AUTOEDIT=no bash "$canon" feature "chore: merge feature" --offline 2>&1) || fail 'a duplicate must not stop the merge'
grep -qF 'feature re-applies 1 commit(s) whose changes are already on main' <<<"$out" || fail 'the merge must warn about the duplicate'
grep -qF 'fix: hotfix shipped twice' <<<"$out" || fail 'the warning must list the duplicated commit'
if grep -qF 'feat: real feature work' <<<"$(grep -A3 're-applies' <<<"$out")"; then fail 'a commit new to main is not a duplicate'; fi
grep -qF 'rebase main' <<<"$out" || fail 'the warning must give the rebase that drops the copy'
[[ "$(git -C "$repo" log -1 --format=%s main)" == "chore: merge feature" ]] || fail 'main must carry the merge commit'

g switch -q -c clean
echo more > "$repo/more.txt"; g add more.txt; g commit -q -m "feat: more"
g switch -q main
out=$(cd "$repo" && GIT_MERGE_AUTOEDIT=no bash "$canon" clean "chore: merge clean" --offline 2>&1) || fail 'a clean merge must succeed'
if grep -qF 're-applies' <<<"$out"; then fail 'a branch without duplicates must not warn'; fi

echo 'OK: merge.sh warns when the source re-applies commits already on the target and still merges'
