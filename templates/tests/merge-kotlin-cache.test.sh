#!/usr/bin/env bash
# merge.sh traktuje `.kotlin/` jak `build/`: to cache pluginu Kotlina dla Gradle (sessions/, errors/), który zostaje
# w każdym module kompilującym Kotlina (gradle/build-logic, buildSrc konsumenta) i odtwarza się przy następnym buildzie.
# 2026-10-19 sam pusty `gradle/build-logic/.kotlin/sessions/` zablokował merge gałęzi Platform komunikatem
# "has local or ignored files: !! gradle/build-logic/.kotlin/". Podobna nazwa, która nie jest tym cache'em,
# nadal blokuje. Hermetyczne repo, bez origin (--offline).
set -euo pipefail
canon="$(cd "$(dirname "$0")/.." && pwd)/merge.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
out=""
fail() { echo "FAIL: $*" >&2; echo "$out" >&2; exit 1; }

new_repo() {
  local repo="$work/$1"
  git init -q -b main "$repo"
  printf '%s\n' "$2" > "$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q -m "chore: ignore local output"
  git -C "$repo" worktree add -q -b feature "$work/$1-wt"
  git -C "$work/$1-wt" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "feat: work"
  printf '%s\n' "$repo"
}
merge() { (cd "$1" && GIT_MERGE_AUTOEDIT=no bash "$canon" feature "chore: merge feature" --offline 2>&1); }

repo=$(new_repo kotlin-cache '.kotlin/')
mkdir -p "$work/kotlin-cache-wt/gradle/build-logic/.kotlin/sessions" "$work/kotlin-cache-wt/gradle/build-logic/.kotlin/errors"
: > "$work/kotlin-cache-wt/gradle/build-logic/.kotlin/sessions/kotlin-compiler-4242.salive"
out=$(merge "$repo") || fail 'a worktree whose only leftover is the Kotlin cache must merge'
grep -qF 'holds only regenerable build output' <<<"$out" || fail 'the Kotlin cache must be reported as regenerable output'
grep -qF 'gradle/build-logic/.kotlin/' <<<"$out" || fail 'the report must name the .kotlin/ directory'
[[ "$(git -C "$repo" log -1 --format=%s main)" == "chore: merge feature" ]] || fail 'main must carry the merge commit'
[[ ! -d "$work/kotlin-cache-wt" ]] || fail 'the worktree goes, together with its Kotlin cache'
if git -C "$repo" show-ref --verify --quiet refs/heads/feature; then fail 'the merged branch must be deleted'; fi

repo=$(new_repo look-alike '.kotlin-notes')
printf 'my notes\n' > "$work/look-alike-wt/.kotlin-notes"
if out=$(merge "$repo"); then fail 'an ignored file that only looks like the Kotlin cache must still block'; fi
grep -qF '.kotlin-notes' <<<"$out" || fail 'the refusal must name the preserved file'
[[ -f "$work/look-alike-wt/.kotlin-notes" ]] || fail 'the preserved file must survive the refusal'
echo 'OK: merge.sh removes the Kotlin cache like other build output and still blocks look-alike files'
