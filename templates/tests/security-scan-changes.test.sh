#!/usr/bin/env bash
# The deps-changed step of security-scan.yml, cut out between its markers and run in a real repository
# with the workflow's default deps-pattern: a scan runs when a dependency manifest changed, is skipped
# otherwise, and always runs when the filter is off or the event is not a push or pull request.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/security-scan.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fail() { local message="$1"; echo "FAIL: $message" >&2; exit 1; }

awk '
  index($0, "# >>> deps-changed") { inside = 1; next }
  index($0, "# <<< deps-changed") { inside = 0 }
  inside
' "$workflow" > "$tmp/filter.sh"
[[ -s "$tmp/filter.sh" ]] || fail 'security-scan.yml has no deps-changed block between its markers'
pattern=$(awk '/^      deps-pattern:/ { inside = 1 } inside && /default:/ { sub(/^[^'"'"']*'"'"'/, ""); sub(/'"'"'[[:space:]]*$/, ""); print; exit }' "$workflow")
[[ -n "$pattern" ]] || fail 'no default deps-pattern in security-scan.yml'

repo="$tmp/repo"
git init -q -b main "$repo"
commit() { git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q -m "$1"; git -C "$repo" rev-parse HEAD; }
mkdir -p "$repo/backend" "$repo/frontend" "$repo/.github/workflows"
echo base > "$repo/README.md"; echo 'lock' > "$repo/backend/gradle.lockfile"; echo '{}' > "$repo/frontend/package-lock.json"
base=$(commit base)
echo docs >> "$repo/README.md"
docs=$(commit docs)
echo 'lock 2' > "$repo/backend/gradle.lockfile"
deps=$(commit deps)

# filter <before> <head> [event] [enabled]: prints the deps output for a push of before...head
filter() {
  local before="$1" head="$2" event="${3:-push}" enabled="${4:-true}"
  git -C "$repo" checkout -q "$head"
  : > "$tmp/output"
  (cd "$repo" && GITHUB_OUTPUT="$tmp/output" ONLY_IF_CHANGED="$enabled" DEPS_PATTERN="$pattern" EVENT="$event" \
    BASE_REF=main BEFORE="$before" bash "$tmp/filter.sh" > /dev/null)
  sed -n 's/^deps=//p' "$tmp/output"
}

[[ "$(filter "$base" "$docs")" == false ]] || fail 'a push that changes only docs must skip the scan'
[[ "$(filter "$docs" "$deps")" == true ]] || fail 'a push that changes backend/gradle.lockfile must scan'
[[ "$(filter "$base" "$deps")" == true ]] || fail 'a push range that includes a lockfile change must scan'
[[ "$(filter 0000000000000000000000000000000000000000 "$docs")" == false ]] || fail 'a new branch push compares HEAD^...HEAD'
[[ "$(filter "$base" "$docs" schedule)" == true ]] || fail 'a scheduled run always scans'
[[ "$(filter "$base" "$docs" push false)" == true ]] || fail 'with the filter off every run scans'
for path in backend/settings.gradle.kts backend/settings-gradle.lockfile backend/gradle/verification-metadata.xml \
  frontend/package.json frontend/package-lock.json .github/workflows/ci.yml .github/workflows/security.yaml; do
  grep -qE -- "$pattern" <<<"$path" || fail "the default deps-pattern must match $path"
done
for path in backend/src/main/java/App.java frontend/app/page.tsx docs/README.md; do
  if grep -qE -- "$pattern" <<<"$path"; then fail "the default deps-pattern must not match $path"; fi
done
echo 'OK: security-scan runs only when a dependency manifest changed, and always on schedules and with the filter off'
