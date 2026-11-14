#!/usr/bin/env bash
# scripts/cleanup-packages.sh deletes old Platform package versions only deliberately:
#
# - it refuses to run without --protect, the versions consumers still pin;
# - a protected version is never deleted, whatever its age;
# - without --execute it only prints the plan;
# - packages outside Platform are never touched.
#
# gh is stubbed: it answers the package and version listings from fixtures and records every
# DELETE, so the test never reaches GitHub.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/scripts/cleanup-packages.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  local message="$1"
  echo "FAIL: $message" >&2
  exit 1
}

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
url=""
for arg in "$@"; do case "$arg" in /*) url="$arg" ;; esac; done
if [ "${1:-}" = api ] && [ "${2:-}" = --method ] && [ "${3:-}" = DELETE ]; then
  printf '%s\n' "$url" >> "$GH_DELETES"
  exit 0
fi
case "$url" in
  "/user/packages?package_type=maven") printf '%s\n' pl.seniordeveloper.platform-catalog com.example.other ;;
  "/user/packages?package_type=npm") ;;
  /user/packages/maven/pl.seniordeveloper.platform-catalog/versions)
    for entry in 1:1.5.25 2:1.5.26 3:1.5.27 4:1.5.28 5:1.5.29 6:1.5.30 7:1.5.31; do
      printf '{"id": %s, "name": "%s", "created_at": "2026-0%s-01T00:00:00Z"}\n' "${entry%%:*}" "${entry#*:}" "${entry%%:*}"
    done ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"
export GH_DELETES="$tmp/deletes"

run_cleanup() {
  : > "$GH_DELETES"
  PATH="$tmp/bin:$PATH" bash "$script" "$@" > "$tmp/out" 2>&1
}

# --- Refusals --------------------------------------------------------------------------------
if run_cleanup --keep 2; then
  fail 'cleanup must refuse to run without --protect'
fi
grep -q -- '--protect is required' "$tmp/out" || fail 'the refusal must ask for the versions consumers pin'
if run_cleanup --keep 2 --protect 'latest'; then
  fail 'cleanup must refuse a --protect value that is not a list of versions'
fi
[[ ! -s "$GH_DELETES" ]] || fail 'a refused run must not delete anything'

# --- Dry run (the default) -------------------------------------------------------------------
run_cleanup --keep 2 --protect '1.5.26, 1.5.29' || { cat "$tmp/out" >&2; fail 'a dry run must succeed'; }
[[ ! -s "$GH_DELETES" ]] || fail 'a dry run must not delete anything'
for version in 1.5.25 1.5.27 1.5.28; do
  grep -q "would delete $version " "$tmp/out" || { cat "$tmp/out" >&2; fail "the plan must list $version"; }
done
if grep -Eq 'would delete 1\.5\.(26|29|30|31) ' "$tmp/out"; then
  fail 'the plan must keep the protected and the newest versions'
fi
grep -q 'com.example.other' "$tmp/out" && fail 'packages outside Platform must not appear in the plan'

# --- Execute ---------------------------------------------------------------------------------
run_cleanup --keep 2 --protect 1.5.26,1.5.29 --execute || { cat "$tmp/out" >&2; fail 'an executed run must succeed'; }
expected=$(printf '/user/packages/maven/pl.seniordeveloper.platform-catalog/versions/%s\n' 4 3 1)
[[ "$(cat "$GH_DELETES")" == "$expected" ]] \
  || { cat "$GH_DELETES" >&2; fail 'an executed run must delete exactly the planned versions, newest first'; }

echo 'OK: cleanup refuses without --protect, never deletes a protected version and defaults to a dry run'
