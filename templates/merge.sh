#!/usr/bin/env bash
#
# merge.sh — integrate a worktree feature branch into main, then clean up.
#
# CANON: this file lives in Platform/templates/merge.sh — do not edit per-repo copies;
# edit here and re-sync to each consumer's scripts/ dir (see templates/README.md).
#
# Usage:
#   ./scripts/merge.sh <branch> [message] [--into <target>] [--force]
#
# Given a feature branch (typically living in a .claude/worktrees/* worktree),
# this, run against the MAIN working tree:
#   1. checks out the target branch (default: main),
#   2. merges <branch> into it with a merge commit (--no-ff); when [message] is
#      given it becomes the merge commit message (git -m), else git's default,
#   3. removes the worktree that had <branch> checked out,
#   4. deletes <branch>.
#
# It is deliberately careful:
#   - refuses if the main working tree is dirty (commit/stash first),
#   - refuses to touch protected branches (main/master/develop/release/*),
#   - on a merge conflict it stops and leaves the conflict for you to resolve,
#   - without --force it will NOT remove a worktree that still has local or
#     untracked changes (re-run with --force to discard them).
#
# Arguments:
#   <branch>          feature branch to merge and delete (required)
#   [message]         optional merge commit message (default: git's
#                     "Merge branch '<branch>'")
#
# Options:
#   --into <target>   branch to merge into (default: main)
#   --force, -f       discard local/untracked changes when removing the worktree
#   -h, --help        show this header

set -euo pipefail

TARGET="main"
FORCE=0
BRANCH=""
MESSAGE=""
MSG_SET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --force|-f) FORCE=1; shift ;;
    --into) TARGET="${2:?--into needs a branch name}"; shift 2 ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *)
      if [ -z "$BRANCH" ]; then
        BRANCH="$1"
      elif [ "$MSG_SET" -eq 0 ]; then
        MESSAGE="$1"; MSG_SET=1
      else
        echo "unexpected extra argument: $1" >&2; exit 2
      fi
      shift ;;
  esac
done

[ -n "$BRANCH" ] || { echo "usage: $0 <branch> [message] [--into <target>] [--force]" >&2; exit 2; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not inside a git repository" >&2; exit 1; }

if [ "$BRANCH" = "$TARGET" ]; then
  echo "refusing to merge '$BRANCH' into itself" >&2; exit 1
fi
case "$BRANCH" in
  main|master|develop|release/*)
    echo "refusing to delete protected branch '$BRANCH'" >&2; exit 1 ;;
esac

git show-ref --verify --quiet "refs/heads/$BRANCH" || { echo "branch '$BRANCH' does not exist" >&2; exit 1; }

# The first entry of the worktree list is the main working tree.
MAIN_WT="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
[ -n "$MAIN_WT" ] || { echo "cannot locate the main working tree" >&2; exit 1; }

# Find the worktree (if any) that has <branch> checked out — space-safe parse.
BRANCH_WT=""
cur=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*) cur="${line#worktree }" ;;
    "branch refs/heads/$BRANCH") BRANCH_WT="$cur"; break ;;
  esac
done < <(git worktree list --porcelain)

cd "$MAIN_WT"

if [ -n "$(git status --porcelain)" ]; then
  echo "main working tree ($MAIN_WT) has uncommitted changes — commit or stash first" >&2
  exit 1
fi

echo ">> checking out $TARGET in $MAIN_WT"
git checkout "$TARGET"

echo ">> merging $BRANCH into $TARGET (--no-ff)"
merge_rc=0
if [ "$MSG_SET" -eq 1 ]; then
  git merge --no-ff -m "$MESSAGE" "$BRANCH" || merge_rc=$?
else
  git merge --no-ff "$BRANCH" || merge_rc=$?
fi
if [ "$merge_rc" -ne 0 ]; then
  echo "!! merge conflict — resolve it and commit, then clean up manually:" >&2
  echo "     git worktree remove ${BRANCH_WT:-<worktree-path>} && git branch -d $BRANCH" >&2
  exit 1
fi

# Remove the branch's worktree (never the main one).
if [ -n "$BRANCH_WT" ] && [ "$BRANCH_WT" != "$MAIN_WT" ]; then
  echo ">> removing worktree $BRANCH_WT"
  if [ "$FORCE" -eq 1 ]; then
    git worktree remove --force "$BRANCH_WT"
  elif ! git worktree remove "$BRANCH_WT"; then
    echo "!! worktree has local/untracked changes; re-run with --force to discard them." >&2
    echo "   (the merge already succeeded; only cleanup was skipped)" >&2
    exit 1
  fi
fi

echo ">> deleting branch $BRANCH"
git branch -d "$BRANCH"

echo "✓ merged $BRANCH into $TARGET and cleaned up"
