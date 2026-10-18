#!/usr/bin/env bash
# platform-bump bumps a template-style pin (platformVersion= in backend/gradle.properties) and
# refuses to report success when it found nothing to bump.
#
# The whole bin runs against throwaway repositories; curl (GitHub API) is stubbed to fail, so the
# release notes are skipped, and backend/gradlew is a stub, so no Gradle runs.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/bin/platform-bump.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { local message="$1"; echo "FAIL: $message"; exit 1; }

mkdir -p "$WORK/bin"
printf '#!/usr/bin/env bash\nexit 22\n' > "$WORK/bin/curl"
chmod +x "$WORK/bin/curl"

# repo <name>: an empty git repository; prints its path.
repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf '%s\n' "$dir"
}

backend() {
  local dir="$1"
  mkdir -p "$dir/backend"
  printf '#!/usr/bin/env bash\necho "gradlew $*"\n' > "$dir/backend/gradlew"
  chmod +x "$dir/backend/gradlew"
  cat > "$dir/backend/settings.gradle.kts" <<'KTS'
plugins { id("seniordev.settings-conventions") version providers.gradleProperty("platformVersion").get() }
KTS
}

run_bump() {
  local dir="$1"
  (cd "$dir" && GPR_TOKEN=dummy PATH="$WORK/bin:$PATH" bash "$SRC" 1.6.0) > "$dir.log" 2>&1
}

# (a) template-style pin in backend/gradle.properties
dir=$(repo template)
backend "$dir"
printf 'platformVersion=1.5.31\norg.gradle.caching=true\n' > "$dir/backend/gradle.properties"
run_bump "$dir" || { cat "$dir.log"; fail 'a template-style pin must be bumped'; }
grep -qx 'platformVersion=1.6.0' "$dir/backend/gradle.properties" || { cat "$dir.log"; fail 'backend/gradle.properties must carry the target'; }
grep -qx 'org.gradle.caching=true' "$dir/backend/gradle.properties" || fail 'other properties must stay untouched'

# (b) a backend whose settings carry no literal and no gradle.properties pin
dir=$(repo no-pin)
backend "$dir"
if run_bump "$dir"; then
  cat "$dir.log"; fail 'a backend without any Platform pin must not report success'
fi
grep -q 'No Platform pin found in backend/settings.gradle.kts or backend/gradle.properties' "$dir.log" \
  || { cat "$dir.log"; fail 'the refusal must say where it looked'; }

# (c) a layout without backend/, frontend/ or a root pin
dir=$(repo empty)
if run_bump "$dir"; then
  cat "$dir.log"; fail 'an empty layout must not report success'
fi
grep -q 'No Platform pin found in this layout' "$dir.log" || { cat "$dir.log"; fail 'the refusal must name the empty layout'; }

echo 'OK: platform-bump bumps a platformVersion= pin and refuses layouts where it bumps nothing'
