#!/usr/bin/env bash
# Release must publish only after green CI on the tagged commit.
#
# Structure: release.yml calls ci.yml as `verify`, every publishing job needs it, and the npm job holding
# `packages: write` runs no build. That ci.yml is callable, that a `needs` names a job that exists and that a job
# reads outputs only of jobs it needs is checked by actionlint in CI. Behaviour: the tag<->version guard
# is cut out of release.yml between its markers and run as-is, so the test exercises the shipped code.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
release="$root/.github/workflows/release.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  local message="$1"
  echo "FAIL: $message" >&2
  exit 1
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
  assert_needs "$job" verify
done

if job_mentions npm '[[:space:]]build[[:space:]]'; then
  fail "release.yml job 'npm' holds packages: write and must not run any build"
fi

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

echo 'OK: Release publishes only after green CI on the tagged commit'
