#!/usr/bin/env bash
# version_exists in release.yml decides whether a Maven module is already published and skipped on a
# re-run. The block is cut out of release.yml between its markers and run against a stub gh.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { local message="$1"; echo "FAIL: $message" >&2; exit 1; }

awk '
  index($0, "# >>> version-exists") { inside = 1; next }
  index($0, "# <<< version-exists") { inside = 0 }
  inside
' "$root/.github/workflows/release.yml" > "$tmp/version-exists.sh"
[[ -s "$tmp/version-exists.sh" ]] || fail 'release.yml has no version-exists block between its markers'

# Stub gh: prints the names in $STUB_NAMES_FILE (one per line), or fails like a 404 when STUB_STATUS != 0.
# A file, not an environment variable: Linux refuses to exec with one variable over 128 KiB (MAX_ARG_STRLEN),
# and the long list below is larger than that.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
[[ "${STUB_STATUS:-0}" -eq 0 ]] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
cat "$STUB_NAMES_FILE"
GH
chmod +x "$tmp/bin/gh"

published() { printf '%s\n' "$@" > "$tmp/names"; }

check() {
  PATH="$tmp/bin:$PATH" GITHUB_TOKEN=dummy GPR_OWNER=owner STUB_NAMES_FILE="$tmp/names" V="$1" bash -c \
    "set -uo pipefail; source '$tmp/version-exists.sh'; version_exists pl.seniordeveloper.platform-catalog"
}

published 1.5.30 1.5.31
check 1.5.31 || fail 'a published version must be found'
if check 1.5.3; then fail 'a prefix of a published version is not that version'; fi
published 1.5.30
if check 1.5.31; then fail 'an unpublished version must not be found'; fi
if STUB_STATUS=1 check 1.5.31; then fail 'a missing package (404) means not published'; fi
# Many versions, the match first: grep stops early, which must not turn into "not published".
{ printf '1.6.0\n'; seq -f '0.%g.0' 1 50000; } > "$tmp/names"
check 1.6.0 || fail 'an early match in a long version list must be found'

echo 'OK: version_exists finds published versions by exit code and treats a missing package as unpublished'
