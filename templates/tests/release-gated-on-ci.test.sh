#!/usr/bin/env bash
# Release must publish and move `v1` only after green CI on the tagged commit.
#
# Structure: release.yml calls ci.yml as `verify`, every publishing job needs it, the registry
# build runs outside the jobs holding `packages: write`, and only `move-v1` touches `v1`, after
# both publications. Behaviour: the tag<->version guard and the forward-only `v1` move are cut
# out of release.yml between their markers and run as-is, so the test exercises the shipped code.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
release="$root/.github/workflows/release.yml"
ci="$root/.github/workflows/ci.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fail() {
  local message="$1"
  echo "FAIL: $message" >&2
  exit 1
}

job_ids() {
  awk '
    /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
    in_jobs && /^[^[:space:]#]/ { exit }
    in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { sub(/:.*/, ""); print $1 }
  ' "$release"
}

job_block() {
  local job="$1"
  awk -v job="$job" '
    /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
    in_jobs && /^[^[:space:]#]/ { exit }
    in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { selected = ($1 == job ":"); next }
    selected { print }
  ' "$release"
}

# The block goes in as a here-string, not a pipe: awk exits at the first `needs:`, and a job block
# larger than the writer's buffer would then die of SIGPIPE, which pipefail turns into a silent exit.
job_needs() {
  local job="$1"
  local block
  block=$(job_block "$job")
  awk '
    /^    needs:/ {
      line = $0
      sub(/^    needs:[[:space:]]*/, "", line)
      sub(/[[:space:]]*#.*/, "", line)
      if (line == "") { block = 1; next }
      gsub(/[][[:space:]]/, "", line)
      count = split(line, items, ",")
      for (i = 1; i <= count; i++) if (items[i] != "") print items[i]
      exit
    }
    block && /^      - / { item = $0; sub(/^      - /, "", item); print item; next }
    block { exit }
  ' <<<"$block"
}

# Whether a non-comment line of a job, padded with one space on each side, matches the ERE.
# The pattern travels through ENVIRON because `awk -v` would rewrite its backslash escapes.
job_mentions() {
  local job="$1"
  local pattern="$2"
  local block
  block=$(job_block "$job")
  PATTERN="$pattern" awk '
    !/^[[:space:]]*#/ && (" " $0 " ") ~ ENVIRON["PATTERN"] { found = 1 }
    END { exit !found }
  ' <<<"$block"
}

assert_needs() {
  local job="$1"
  local need="$2"
  local needs
  needs=$(job_needs "$job")
  grep -qx -- "$need" <<<"$needs" || fail "release.yml job '$job' must need '$need'"
  return 0
}

extract_block() {
  local marker="$1"
  local target="$2"
  awk -v start_marker="# >>> $marker" -v end_marker="# <<< $marker" '
    index($0, start_marker) { inside = 1; next }
    index($0, end_marker) { inside = 0 }
    inside
  ' "$release" > "$target"
  [[ -s "$target" ]] || fail "release.yml has no '$marker' block between its markers"
  return 0
}

# --- Structure -------------------------------------------------------------------------------
grep -Eq '^  workflow_call:' "$ci" || fail 'ci.yml must be callable (on: workflow_call) so Release can reuse it'

awk '
  /^permissions:[[:space:]]*$/ { selected = 1; next }
  selected && /^[^[:space:]#]/ { exit }
  selected && $2 == "write" { writable = 1 }
  selected && $1 == "contents:" && $2 == "read" { found = 1 }
  END { exit !(found && !writable) }
' "$release" || fail 'release.yml must declare top-level permissions: contents: read and nothing writable'

verify_block=$(job_block verify)
grep -Eq '^    uses: \./\.github/workflows/ci\.yml[[:space:]]*$' <<<"$verify_block" \
  || fail "release.yml job 'verify' must call ./.github/workflows/ci.yml"

for job in gradle npm; do
  assert_needs "$job" version
  assert_needs "$job" verify
  assert_needs "$job" registry-build
done
assert_needs move-v1 gradle
assert_needs move-v1 npm

if job_mentions registry-build 'packages:[[:space:]]*write'; then
  fail "release.yml job 'registry-build' runs third-party build code and must not hold packages: write"
fi
if job_mentions npm '[[:space:]]build[[:space:]]'; then
  fail "release.yml job 'npm' holds packages: write and must not run any build"
fi
for job in $(job_ids); do
  [[ "$job" == move-v1 ]] && continue
  if job_mentions "$job" '[^A-Za-z0-9_.-]v1[^A-Za-z0-9_.-]'; then
    fail "only release.yml job 'move-v1' may touch the moving v1 tag (found in '$job')"
  fi
done

# --- Tag <-> version guard -------------------------------------------------------------------
guard="$tmp/guard.sh"
extract_block tag-version-bijection "$guard"
V=1.2.3 GITHUB_REF=refs/tags/v1.2.3 bash "$guard" >/dev/null || fail 'guard must accept the tag matching platformVersion'
if V=1.2.3 GITHUB_REF=refs/heads/main bash "$guard" >/dev/null 2>&1; then
  fail 'guard must reject a dispatch from a branch'
fi
if V=1.2.3 GITHUB_REF=refs/tags/v1.2.4 bash "$guard" >/dev/null 2>&1; then
  fail 'guard must reject a tag that differs from platformVersion'
fi

# --- Forward-only v1 move --------------------------------------------------------------------
move="$tmp/move-v1.sh"
extract_block move-v1-forward "$move"

origin="$tmp/origin.git"
work="$tmp/work"
git init -q --bare -b main "$origin"
git init -q -b main "$work"
git -C "$work" config user.name 'Release Test'
git -C "$work" config user.email 'release-test@example.invalid'
git -C "$work" remote add origin "$origin"
for n in 1 2 3; do git -C "$work" commit -q --allow-empty -m "c$n"; done
c1=$(git -C "$work" rev-parse HEAD~2)
c2=$(git -C "$work" rev-parse HEAD~1)
c3=$(git -C "$work" rev-parse HEAD)
git -C "$work" switch -q --detach "$c1"
git -C "$work" commit -q --allow-empty -m side
side=$(git -C "$work" rev-parse HEAD)
git -C "$work" switch -q main
git -C "$work" push -q origin main "$side:refs/heads/side"

origin_v1() {
  git -C "$origin" rev-parse -q --verify 'refs/tags/v1^{commit}' || true
  return 0
}

set_origin_v1() {
  local sha="$1"
  if [[ -z "$sha" ]]; then
    git -C "$origin" update-ref -d refs/tags/v1 2>/dev/null || true
  else
    git -C "$origin" update-ref refs/tags/v1 "$sha"
  fi
  return 0
}

run_move() {
  local sha="$1"
  (cd "$work" && GITHUB_SHA="$sha" GITHUB_REF=refs/tags/v9.9.9 bash "$move" >/dev/null 2>&1)
}

set_origin_v1 ""
run_move "$c2" || fail 'move-v1 must create v1 when it does not exist yet'
[[ "$(origin_v1)" == "$c2" ]] || fail 'move-v1 must create v1 at the released commit'

set_origin_v1 "$c1"
run_move "$c3" || fail 'move-v1 must move v1 forward'
[[ "$(origin_v1)" == "$c3" ]] || fail 'move-v1 must point v1 at the released commit'

run_move "$c2" || fail 'move-v1 must not fail when an older tag is released again'
[[ "$(origin_v1)" == "$c3" ]] || fail 'move-v1 must never move v1 backwards'

set_origin_v1 "$side"
if run_move "$c3"; then
  fail 'move-v1 must refuse when v1 is not an ancestor of the released commit'
fi
[[ "$(origin_v1)" == "$side" ]] || fail 'move-v1 must leave a diverged v1 untouched'

echo 'OK: Release publishes and moves v1 only after green CI, forward only'
