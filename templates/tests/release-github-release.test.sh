#!/usr/bin/env bash
# release.yml creates the GitHub Release of a version from its CHANGELOG.md section, after both
# publications, and only once.
#
# Structure: the github-release job needs version, gradle and npm, holds contents: write and
# nothing writable for packages. Behaviour: the notes step is cut out of release.yml between its
# markers and run against a throwaway repository with a stubbed gh, so the test exercises the
# shipped code.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
release="$root/.github/workflows/release.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

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

# --- Structure -------------------------------------------------------------------------------
block=$(job_block github-release)
[[ -n "$block" ]] || fail "release.yml must have a github-release job"
grep -Eq '^    needs: \[version, gradle, npm\][[:space:]]*$' <<<"$block" \
  || fail "github-release must need version, gradle and npm, so a Release describes a published version"
grep -Eq '^      contents: write[[:space:]]*$' <<<"$block" || fail "github-release must hold contents: write"
if grep -Eq 'packages:[[:space:]]*write' <<<"$block"; then
  fail "github-release must not hold packages: write"
fi

# --- Behaviour -------------------------------------------------------------------------------
step="$tmp/notes-step.sh"
awk '
  index($0, "# >>> github-release-notes") { inside = 1; next }
  index($0, "# <<< github-release-notes") { inside = 0 }
  inside
' "$release" > "$step"
[[ -s "$step" ]] || fail "release.yml has no github-release-notes block between its markers"

work="$tmp/repo"
git init -q -b main "$work"
git -C "$work" config user.name 'Release Test'
git -C "$work" config user.email 'release-test@example.invalid'
mkdir -p "$work/scripts"
cp "$root/scripts/changelog-section.sh" "$work/scripts/changelog-section.sh"
printf '# Changelog\n\n## [1.1.0] - 2026-10-18\n\n### Consumer action required\n\n- Grant packages: read.\n\n## [1.0.0] - 2026-10-01\n\n### Consumer action required\n\nNone.\n' \
  > "$work/CHANGELOG.md"
git -C "$work" add -A
git -C "$work" commit -q -m 'chore(release): platform 1.0.0'
git -C "$work" tag -a -m 'Platform 1.0.0' v1.0.0
git -C "$work" commit -q --allow-empty -m 'chore(release): platform 1.1.0'
git -C "$work" tag -a -m 'Platform 1.1.0' v1.1.0

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
if [ "$1 $2" = "release view" ]; then exit "${GH_RELEASE_EXISTS:-1}"; fi
if [ "$1 $2" = "release create" ]; then cp notes.md "$GH_NOTES_COPY"; fi
exit 0
STUB
chmod +x "$tmp/bin/gh"

run_step() {
  (cd "$work" && PATH="$tmp/bin:$PATH" VERSION=1.1.0 GITHUB_REPOSITORY=owner/platform bash -e "$step")
}

export GH_CALLS="$tmp/gh-calls" GH_NOTES_COPY="$tmp/notes.md"
GH_RELEASE_EXISTS=1 run_step >/dev/null || fail 'the notes step must succeed when the Release does not exist yet'
grep -q '^release create v1.1.0 --title Platform 1.1.0 --notes-file notes.md --verify-tag$' "$GH_CALLS" \
  || { cat "$GH_CALLS" >&2; fail 'the notes step must create the Release of the tag with its title and notes'; }
grep -qx -- '- Grant packages: read.' "$GH_NOTES_COPY" || fail 'the Release notes must carry the CHANGELOG section'
grep -qx '### Consumer action required' "$GH_NOTES_COPY" || fail 'the Release notes must keep the section headings'
grep -q 'compare/v1.0.0...v1.1.0' "$GH_NOTES_COPY" || fail 'the Release notes must link the diff from the previous version'
if grep -q '1.0.0 - 2026-10-01' "$GH_NOTES_COPY"; then
  fail 'the Release notes must stop at the next version section'
fi

: > "$GH_CALLS"
GH_RELEASE_EXISTS=0 run_step >/dev/null || fail 'the notes step must succeed when the Release already exists'
if grep -q '^release create' "$GH_CALLS"; then
  fail 'a re-run must not create the Release twice'
fi

echo 'OK: release.yml creates one GitHub Release per version from its CHANGELOG section'
