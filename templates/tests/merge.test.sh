#!/usr/bin/env bash
# Hermetic integration tests for templates/merge.sh. Every case creates its own
# temporary repository; no network, credentials, or developer repository is used.
set -uo pipefail

CANON="${MERGE_SCRIPT:-$(cd "$(dirname "$0")/.." && pwd)/merge.sh}"
PLATFORM_DELEGATE="$(cd "$(dirname "$0")/../.." && pwd)/merge.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
FILTER="${1:-}"

# Tożsamość commitów w atrapach repozytoriów — ustawiana w każdym świeżym klonie,
# bo `git clone` nie dziedziczy user.name/user.email z repozytorium źródłowego.
readonly TEST_AUTHOR_NAME="Merge Test"
readonly TEST_AUTHOR_EMAIL="merge-test@example.invalid"

fail() {
  local message="$1"
  echo "FAIL: $message" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "$actual" == "$expected" ]] || fail "$message (expected '$expected', got '$actual')"
  return $?
}

assert_contains() {
  local text="$1"
  local expected="$2"
  local message="$3"
  grep -Fq -- "$expected" <<<"$text" || fail "$message (missing '$expected')"
  return $?
}

assert_ref_exists() {
  local repo="$1"
  local ref="$2"
  git -C "$repo" show-ref --verify --quiet "$ref" || fail "expected ref '$ref' to exist"
  return $?
}

assert_ref_missing() {
  local repo="$1"
  local ref="$2"
  ! git -C "$repo" show-ref --verify --quiet "$ref" || fail "expected ref '$ref' to be absent"
  return $?
}

new_repo() {
  local name="$1"
  local repo="$WORK/$name"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.name "$TEST_AUTHOR_NAME"
  git -C "$repo" config user.email "$TEST_AUTHOR_EMAIL"
  git -C "$repo" commit -q --allow-empty -m initial
  printf '%s\n' "$repo"
  return $?
}

add_feature_worktree() {
  local repo="$1"
  local branch="$2"
  local worktree="$3"
  local start_ref="${4:-main}"
  git -C "$repo" worktree add -q -b "$branch" "$worktree" "$start_ref"
  git -C "$worktree" commit -q --allow-empty -m "feature commit"
  return $?
}

run_merge() {
  local repo="$1"
  shift
  MERGE_RC=0
  MERGE_OUTPUT="$(cd "$repo" && GIT_MERGE_AUTOEDIT=no bash "$CANON" "$@" 2>&1)" || MERGE_RC=$?
  return $?
}

test_message_is_required() {
  local repo before
  repo="$(new_repo message-required)"
  git -C "$repo" branch feature
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" feature

  assert_eq 2 "$MERGE_RC" "missing merge message should be a usage error"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "missing message must not move main"
  assert_ref_exists "$repo" refs/heads/feature
  return $?
}

test_platform_delegate_exposes_canonical_help() {
  local output
  output="$("$PLATFORM_DELEGATE" --help)"

  assert_contains "$output" "merge.sh — safely integrate" "Platform root delegate should execute the canonical helper"
  assert_contains "$output" "--discard-worktree-changes" "Platform root delegate should expose canonical options"
  return $?
}

test_whitespace_message_is_rejected() {
  local repo
  repo="$(new_repo whitespace-message)"
  git -C "$repo" branch feature

  run_merge "$repo" feature "   "

  assert_eq 2 "$MERGE_RC" "whitespace-only merge message should be rejected"
  assert_contains "$MERGE_OUTPUT" "merge message is required" "message error should be explicit"
  return $?
}

test_release_is_protected() {
  local repo before
  repo="$(new_repo protected-release)"
  git -C "$repo" branch release
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" release "merge release"

  [[ $MERGE_RC -ne 0 ]] || fail "release must be rejected"
  assert_contains "$MERGE_OUTPUT" "protected branch 'release'" "release rejection should explain protection"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "release rejection must not move main"
  assert_ref_exists "$repo" refs/heads/release
  return $?
}

test_target_must_be_a_local_branch() {
  local repo before
  repo="$(new_repo local-target)"
  git -C "$repo" switch -q -c feature
  git -C "$repo" commit -q --allow-empty -m feature
  git -C "$repo" switch -q main
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" feature "merge feature" --into HEAD

  [[ $MERGE_RC -ne 0 ]] || fail "non-branch target HEAD must be rejected"
  assert_contains "$MERGE_OUTPUT" "target branch" "target error should identify the invalid local branch"
  assert_eq main "$(git -C "$repo" symbolic-ref --short HEAD)" "target rejection must keep main checked out"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "target rejection must not move main"
  assert_ref_exists "$repo" refs/heads/feature
  return $?
}

test_dirty_source_is_rejected_before_merge() {
  local repo feature_wt before
  repo="$(new_repo dirty-source)"
  feature_wt="$WORK/dirty source worktree"
  add_feature_worktree "$repo" feature "$feature_wt"
  touch "$feature_wt/uncommitted.txt"
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" feature "merge dirty feature"

  [[ $MERGE_RC -ne 0 ]] || fail "dirty source worktree must be rejected"
  assert_contains "$MERGE_OUTPUT" "source worktree" "dirty-source error should identify the source worktree"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "dirty source must be rejected before main moves"
  assert_ref_exists "$repo" refs/heads/feature
  [[ -e "$feature_wt/uncommitted.txt" ]] || fail "dirty source data must be preserved"
  return $?
}

test_ignored_source_file_is_rejected_before_merge() {
  local repo feature_wt before
  repo="$(new_repo ignored-source)"
  printf '.env.local\n' >"$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" commit -q -m "ignore local environment"
  feature_wt="$WORK/ignored source worktree"
  add_feature_worktree "$repo" feature "$feature_wt"
  printf 'SECRET=preserve-me\n' >"$feature_wt/.env.local"
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" feature "merge ignored source" --offline

  [[ $MERGE_RC -ne 0 ]] || fail "ignored source file must be rejected without explicit discard"
  assert_contains "$MERGE_OUTPUT" ".env.local" "ignored-source error should identify the preserved file"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "ignored source must be rejected before main moves"
  assert_ref_exists "$repo" refs/heads/feature
  [[ -e "$feature_wt/.env.local" ]] || fail "ignored source data must be preserved"
  return $?
}

test_ignored_build_output_does_not_block_merge() {
  local repo feature_wt
  repo="$(new_repo build-output)"
  printf 'build/\n.gradle/\nnode_modules/\n.env.local\n' >"$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" commit -q -m "ignore build output and local environment"
  feature_wt="$WORK/build output worktree"
  add_feature_worktree "$repo" feature "$feature_wt"
  mkdir -p "$feature_wt/backend/build" "$feature_wt/backend/.gradle" "$feature_wt/frontend/node_modules"
  printf 'stale\n' >"$feature_wt/backend/build/app.jar"
  printf 'cache\n' >"$feature_wt/backend/.gradle/cache.bin"
  printf 'dep\n' >"$feature_wt/frontend/node_modules/index.js"

  run_merge "$repo" feature "merge with build output" --offline

  assert_eq 0 "$MERGE_RC" "regenerable build output must not block the merge"
  assert_ref_missing "$repo" refs/heads/feature
  [[ ! -d "$feature_wt" ]] || fail "worktree holding only build output should still be removed"
  return $?
}

test_ignored_secret_still_blocks_alongside_build_output() {
  local repo feature_wt before
  repo="$(new_repo build-output-and-secret)"
  printf 'build/\n.env.local\n' >"$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" commit -q -m "ignore build output and local environment"
  feature_wt="$WORK/build output and secret worktree"
  add_feature_worktree "$repo" feature "$feature_wt"
  mkdir -p "$feature_wt/build"
  printf 'stale\n' >"$feature_wt/build/app.jar"
  printf 'SECRET=preserve-me\n' >"$feature_wt/.env.local"
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" feature "merge with secret" --offline

  [[ $MERGE_RC -ne 0 ]] || fail "an irreplaceable ignored file must still block, even next to build output"
  assert_contains "$MERGE_OUTPUT" ".env.local" "error should name the file that blocks"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "secret must be rejected before main moves"
  [[ -e "$feature_wt/.env.local" ]] || fail "ignored source data must be preserved"
  return $?
}

test_discard_flag_is_explicit_and_effective() {
  local repo feature_wt
  repo="$(new_repo discard-source)"
  feature_wt="$WORK/discard source worktree"
  add_feature_worktree "$repo" feature "$feature_wt"
  touch "$feature_wt/uncommitted.txt"

  run_merge "$repo" feature "merge and discard" --offline --discard-worktree-changes

  assert_eq 0 "$MERGE_RC" "explicit discard should allow merge and cleanup"
  assert_ref_missing "$repo" refs/heads/feature
  [[ ! -d "$feature_wt" ]] || fail "discard should remove the source worktree"
  return $?
}

test_force_remains_a_deprecated_alias() {
  local repo feature_wt
  repo="$(new_repo force-alias)"
  feature_wt="$WORK/force alias worktree"
  add_feature_worktree "$repo" feature "$feature_wt"
  touch "$feature_wt/uncommitted.txt"

  run_merge "$repo" feature "merge through alias" --offline --force

  assert_eq 0 "$MERGE_RC" "legacy --force alias should remain compatible"
  assert_contains "$MERGE_OUTPUT" "deprecated" "legacy --force should advertise the safer option name"
  assert_ref_missing "$repo" refs/heads/feature
  return $?
}

test_locked_source_is_rejected_before_merge() {
  local repo feature_wt before
  repo="$(new_repo locked-source)"
  feature_wt="$WORK/locked source worktree"
  add_feature_worktree "$repo" feature "$feature_wt"
  git -C "$repo" worktree lock --reason "test lock" "$feature_wt"
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" feature "merge locked feature" --offline

  [[ $MERGE_RC -ne 0 ]] || fail "locked source worktree must be rejected"
  assert_contains "$MERGE_OUTPUT" "locked" "locked-source error should explain the blocker"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "locked source must be rejected before main moves"
  assert_ref_exists "$repo" refs/heads/feature
  return $?
}

test_dry_run_has_no_worktree_or_ref_side_effects() {
  local repo feature_wt before
  repo="$(new_repo dry-run)"
  feature_wt="$WORK/dry run worktree"
  add_feature_worktree "$repo" feature "$feature_wt"
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" feature "preview merge" --offline --dry-run

  assert_eq 0 "$MERGE_RC" "dry-run should succeed"
  assert_contains "$MERGE_OUTPUT" "DRY RUN" "dry-run should label its output"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "dry-run must not move main"
  assert_ref_exists "$repo" refs/heads/feature
  [[ -d "$feature_wt" ]] || fail "dry-run must keep the source worktree"
  return $?
}

test_origin_is_required_without_offline_mode() {
  local repo before
  repo="$(new_repo origin-required)"
  git -C "$repo" switch -q -c feature
  git -C "$repo" commit -q --allow-empty -m feature
  git -C "$repo" switch -q main
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" feature "merge without origin"

  [[ $MERGE_RC -ne 0 ]] || fail "missing origin must fail closed"
  assert_contains "$MERGE_OUTPUT" "remote 'origin' is not configured" "missing-origin error should explain --offline"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "missing origin must not move main"
  assert_ref_exists "$repo" refs/heads/feature
  return $?
}

test_remote_ahead_is_rejected() {
  local origin seed repo feature_wt before
  origin="$WORK/remote-ahead-origin.git"
  git init -q --bare "$origin"
  seed="$(new_repo remote-ahead-seed)"
  git -C "$seed" remote add origin "$origin"
  git -C "$seed" push -q -u origin main
  git --git-dir="$origin" symbolic-ref HEAD refs/heads/main

  repo="$WORK/remote-ahead-clone"
  git clone -q "$origin" "$repo"
  git -C "$repo" config user.name "$TEST_AUTHOR_NAME"
  git -C "$repo" config user.email "$TEST_AUTHOR_EMAIL"
  feature_wt="$WORK/remote ahead feature"
  add_feature_worktree "$repo" feature "$feature_wt" origin/main
  git -C "$seed" commit -q --allow-empty -m "remote advanced"
  git -C "$seed" push -q origin main
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" feature "stale target merge"

  [[ $MERGE_RC -ne 0 ]] || fail "remote-ahead target must be rejected"
  assert_contains "$MERGE_OUTPUT" "behind or diverged" "remote freshness error should explain the state"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "freshness failure must not move main"
  assert_ref_exists "$repo" refs/heads/feature
  return $?
}

test_local_target_ahead_of_remote_is_allowed() {
  local origin seed repo feature_wt before source_oid
  origin="$WORK/local-ahead-origin.git"
  git init -q --bare "$origin"
  seed="$(new_repo local-ahead-seed)"
  git -C "$seed" remote add origin "$origin"
  git -C "$seed" push -q -u origin main
  git --git-dir="$origin" symbolic-ref HEAD refs/heads/main
  repo="$WORK/local-ahead-clone"
  git clone -q "$origin" "$repo"
  git -C "$repo" config user.name "$TEST_AUTHOR_NAME"
  git -C "$repo" config user.email "$TEST_AUTHOR_EMAIL"
  git -C "$repo" commit -q --allow-empty -m "local target ahead"
  feature_wt="$WORK/local ahead feature"
  add_feature_worktree "$repo" feature "$feature_wt" main
  before="$(git -C "$repo" rev-parse main)"
  source_oid="$(git -C "$repo" rev-parse feature)"

  run_merge "$repo" feature "merge exact message"

  assert_eq 0 "$MERGE_RC" "local target ahead of origin should be allowed"
  assert_eq "$before" "$(git -C "$repo" rev-parse main^1)" "merge first parent should be the old target"
  assert_eq "$source_oid" "$(git -C "$repo" rev-parse main^2)" "merge second parent should be the source tip"
  assert_eq "merge exact message" "$(git -C "$repo" log -1 --format=%s main)" "merge subject should preserve the requested message"
  assert_ref_missing "$repo" refs/heads/feature
  return $?
}

test_conflict_is_reported_and_preserved() {
  local repo feature_wt
  repo="$(new_repo conflict)"
  printf 'base\n' >"$repo/value.txt"
  git -C "$repo" add value.txt
  git -C "$repo" commit -q -m base
  feature_wt="$WORK/conflict feature"
  git -C "$repo" worktree add -q -b feature "$feature_wt" main
  printf 'feature\n' >"$feature_wt/value.txt"
  git -C "$feature_wt" commit -qam feature
  printf 'main\n' >"$repo/value.txt"
  git -C "$repo" commit -qam main

  run_merge "$repo" feature "conflicting merge" --offline

  [[ $MERGE_RC -ne 0 ]] || fail "conflicting merge must fail"
  assert_contains "$MERGE_OUTPUT" "merge conflict" "real conflict should be reported as a conflict"
  assert_contains "$MERGE_OUTPUT" "merge --abort" "conflict output should include recovery"
  assert_ref_exists "$repo" refs/heads/feature
  [[ -d "$feature_wt" ]] || fail "conflict must preserve the source worktree"
  [[ ! -d "$(git -C "$repo" rev-parse --absolute-git-dir)/merge-helper.lock" ]] || fail "conflict must release the helper lock"
  return $?
}

test_non_conflict_merge_failure_is_not_mislabeled() {
  local repo feature_wt hook
  repo="$(new_repo hook-failure)"
  feature_wt="$WORK/hook failure feature"
  add_feature_worktree "$repo" feature "$feature_wt"
  hook="$(git -C "$repo" rev-parse --absolute-git-dir)/hooks/pre-merge-commit"
  git -C "$repo" config core.hooksPath "$(dirname "$hook")"
  printf '#!/usr/bin/env bash\nexit 17\n' >"$hook"
  chmod +x "$hook"

  run_merge "$repo" feature "hook must fail" --offline

  [[ $MERGE_RC -ne 0 ]] || fail "failing commit hook must fail the merge"
  assert_contains "$MERGE_OUTPUT" "merge failed" "non-conflict failure should be reported generically"
  [[ "$MERGE_OUTPUT" != *"merge conflict"* ]] || fail "hook failure must not be mislabeled as a conflict"
  assert_ref_exists "$repo" refs/heads/feature
  [[ -d "$feature_wt" ]] || fail "merge failure must preserve the source worktree"
  [[ ! -d "$(git -C "$repo" rev-parse --absolute-git-dir)/merge-helper.lock" ]] || fail "merge failure must release the helper lock"
  return $?
}

test_repository_lock_blocks_parallel_helper() {
  local repo common_dir lock_dir before
  repo="$(new_repo helper-lock)"
  git -C "$repo" branch feature
  common_dir="$(git -C "$repo" rev-parse --git-common-dir)"
  lock_dir="$repo/$common_dir/merge-helper.lock"
  mkdir "$lock_dir"
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" feature "locked helper" --offline --dry-run

  [[ $MERGE_RC -ne 0 ]] || fail "existing helper lock must reject another run"
  assert_contains "$MERGE_OUTPUT" "another merge helper" "lock error should explain concurrent execution"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "lock failure must not move main"
  [[ -d "$lock_dir" ]] || fail "a lock owned by another process must not be removed"
  return $?
}

test_tracked_feature_branch_is_deleted_safely() {
  local origin seed repo feature_wt
  origin="$WORK/tracked-origin.git"
  git init -q --bare "$origin"
  seed="$(new_repo tracked-seed)"
  git -C "$seed" remote add origin "$origin"
  git -C "$seed" push -q -u origin main
  git --git-dir="$origin" symbolic-ref HEAD refs/heads/main
  repo="$WORK/tracked-clone"
  git clone -q "$origin" "$repo"
  git -C "$repo" config user.name "$TEST_AUTHOR_NAME"
  git -C "$repo" config user.email "$TEST_AUTHOR_EMAIL"
  feature_wt="$WORK/tracked feature worktree"
  add_feature_worktree "$repo" feature "$feature_wt" origin/main

  run_merge "$repo" feature "merge tracked feature" --offline

  assert_eq 0 "$MERGE_RC" "tracked feature should merge and clean up"
  assert_ref_missing "$repo" refs/heads/feature
  [[ ! -d "$feature_wt" ]] || fail "successful merge should remove tracked feature worktree"
  git -C "$repo" merge-base --is-ancestor origin/main main || fail "merged main should retain remote history"
  ! git -C "$repo" config --get-regexp '^branch\.feature\.' >/dev/null 2>&1 ||
    fail "successful branch deletion should remove branch.feature configuration"
  return $?
}

test_invocation_from_source_worktree_succeeds() {
  local repo feature_wt
  repo="$(new_repo invoked-from-source)"
  feature_wt="$WORK/invoked from source worktree"
  add_feature_worktree "$repo" feature "$feature_wt"

  MERGE_RC=0
  MERGE_OUTPUT="$(cd "$feature_wt" && GIT_MERGE_AUTOEDIT=no bash "$CANON" feature "merge from linked worktree" --offline 2>&1)" || MERGE_RC=$?

  assert_eq 0 "$MERGE_RC" "helper should remain operational after removing its original working directory"
  assert_ref_missing "$repo" refs/heads/feature
  [[ ! -d "$feature_wt" ]] || fail "invocation from source should still clean up its worktree"
  return $?
}

assert_not_contains() {
  local text="$1"
  local unexpected="$2"
  local message="$3"
  ! grep -Fq -- "$unexpected" <<<"$text" || fail "$message (unexpected '$unexpected')"
  return $?
}

test_success_is_marked_with_a_check() {
  local repo feature_wt
  repo="$(new_repo success-glyph)"
  feature_wt="$WORK/success glyph worktree"
  add_feature_worktree "$repo" feature "$feature_wt"

  run_merge "$repo" feature "merge with a check mark" --offline

  assert_eq 0 "$MERGE_RC" "a clean merge should succeed"
  assert_contains "$MERGE_OUTPUT" "✓ merged feature into main" "success should be marked with a check"
  assert_not_contains "$MERGE_OUTPUT" "✗" "a successful merge must not emit a failure mark"
  return $?
}

test_failure_is_marked_with_a_cross() {
  local repo before
  repo="$(new_repo failure-glyph)"
  git -C "$repo" branch feature
  before="$(git -C "$repo" rev-parse main)"

  run_merge "$repo" feature

  assert_eq 2 "$MERGE_RC" "missing merge message should be a usage error"
  assert_contains "$MERGE_OUTPUT" "✗ merge message is required" "failure should be marked with a cross"
  assert_not_contains "$MERGE_OUTPUT" "✓" "a failed run must not emit a success mark"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "a failed run must not move main"
  return $?
}

test_conflict_is_marked_with_a_cross() {
  local repo feature_wt
  repo="$(new_repo conflict-glyph)"
  feature_wt="$WORK/conflict glyph worktree"
  git -C "$repo" worktree add -q -b feature "$feature_wt" main
  printf 'theirs\n' >"$feature_wt/collide.txt"
  git -C "$feature_wt" add collide.txt
  git -C "$feature_wt" commit -q -m "feature side"
  printf 'ours\n' >"$repo/collide.txt"
  git -C "$repo" add collide.txt
  git -C "$repo" commit -q -m "main side"

  run_merge "$repo" feature "merge that conflicts" --offline

  [[ "$MERGE_RC" -ne 0 ]] || fail "a conflicting merge should not report success"
  assert_contains "$MERGE_OUTPUT" "✗ merge conflict" "a conflict should be marked with a cross"
  assert_ref_exists "$repo" refs/heads/feature
  return $?
}

test_marks_are_plain_when_output_is_captured() {
  local repo feature_wt
  repo="$(new_repo plain-glyph)"
  feature_wt="$WORK/plain glyph worktree"
  add_feature_worktree "$repo" feature "$feature_wt"

  run_merge "$repo" feature "merge without a terminal" --offline

  assert_eq 0 "$MERGE_RC" "a clean merge should succeed"
  assert_contains "$MERGE_OUTPUT" "✓" "the mark itself must survive capture so output stays greppable"
  assert_not_contains "$MERGE_OUTPUT" "$(printf '\033')" "a non-interactive stream must not receive colour escapes"
  return $?
}

# Guards the trap that command substitution sets: computing a mark inside $(...) makes
# `[ -t 1 ]` false regardless of the caller's stream, which silently drops the colour.
test_forced_colour_reaches_both_marks() {
  local repo feature_wt
  repo="$(new_repo forced-colour)"
  feature_wt="$WORK/forced colour worktree"
  add_feature_worktree "$repo" feature "$feature_wt"

  export FORCE_COLOR=1
  run_merge "$repo" feature "merge with forced colour" --offline
  assert_eq 0 "$MERGE_RC" "a clean merge should succeed"
  assert_contains "$MERGE_OUTPUT" "$(printf '\033[32m✓\033[0m')" "forced colour should reach the success mark"

  run_merge "$repo" absent "merge with forced colour" --offline
  assert_contains "$MERGE_OUTPUT" "$(printf '\033[31m✗\033[0m')" "forced colour should reach the failure mark"
  unset FORCE_COLOR
  return $?
}

test_no_colour_wins_over_forced_colour() {
  local repo
  repo="$(new_repo no-colour-precedence)"

  export NO_COLOR=1 FORCE_COLOR=1
  run_merge "$repo" absent "merge without colour" --offline
  unset NO_COLOR FORCE_COLOR

  assert_contains "$MERGE_OUTPUT" "✗" "the glyph must survive with colour disabled"
  assert_not_contains "$MERGE_OUTPUT" "$(printf '\033')" "NO_COLOR must win over FORCE_COLOR"
  return $?
}

run_test() {
  local name="$1"
  local function_name="$2"
  if [[ -n "$FILTER" && "$FILTER" != "$name" ]]; then
    return
  fi
  if (set -euo pipefail; "$function_name"); then
    echo "ok - $name"
  else
    echo "not ok - $name"
    FAILURES=$((FAILURES + 1))
  fi
}

run_test message-required test_message_is_required
run_test platform-delegate test_platform_delegate_exposes_canonical_help
run_test whitespace-message test_whitespace_message_is_rejected
run_test protected-release test_release_is_protected
run_test local-target test_target_must_be_a_local_branch
run_test dirty-source test_dirty_source_is_rejected_before_merge
run_test ignored-source test_ignored_source_file_is_rejected_before_merge
run_test build-output test_ignored_build_output_does_not_block_merge
run_test build-output-and-secret test_ignored_secret_still_blocks_alongside_build_output
run_test discard-source test_discard_flag_is_explicit_and_effective
run_test force-alias test_force_remains_a_deprecated_alias
run_test locked-source test_locked_source_is_rejected_before_merge
run_test dry-run test_dry_run_has_no_worktree_or_ref_side_effects
run_test origin-required test_origin_is_required_without_offline_mode
run_test remote-ahead test_remote_ahead_is_rejected
run_test local-ahead test_local_target_ahead_of_remote_is_allowed
run_test conflict test_conflict_is_reported_and_preserved
run_test hook-failure test_non_conflict_merge_failure_is_not_mislabeled
run_test helper-lock test_repository_lock_blocks_parallel_helper
run_test tracked-feature test_tracked_feature_branch_is_deleted_safely
run_test invoked-from-source test_invocation_from_source_worktree_succeeds
run_test success-glyph test_success_is_marked_with_a_check
run_test failure-glyph test_failure_is_marked_with_a_cross
run_test conflict-glyph test_conflict_is_marked_with_a_cross
run_test plain-glyph test_marks_are_plain_when_output_is_captured
run_test forced-colour test_forced_colour_reaches_both_marks
run_test no-colour-precedence test_no_colour_wins_over_forced_colour

if [[ -n "$FILTER" && $FAILURES -eq 0 ]]; then
  echo "OK: selected merge.sh test passed"
elif [[ $FAILURES -eq 0 ]]; then
  echo "OK: merge.sh safety and cleanup contract verified"
else
  echo "FAIL: $FAILURES merge.sh test(s) failed" >&2
  exit 1
fi
