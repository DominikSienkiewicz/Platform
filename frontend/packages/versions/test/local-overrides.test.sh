#!/usr/bin/env bash
# The local-overrides block of bin/platform-bump.sh lists every version override in the backend's Gradle
# scripts that the Platform BOMs and platformDependencyCheck cannot see (useVersion, force, strictly,
# extra/ext *.version), so a bump does not end silently on a version the new BOMs already fix. It only
# reports: the exit code stays 0. Cut out between its markers and run on fixture build scripts.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/bin/platform-bump.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { local message="$1"; echo "FAIL: $message"; echo "--- output ---"; echo "$OUT"; exit 1; }

awk '
  index($0, "# platform-bump:local-overrides-end") { exit }
  inside { print }
  index($0, "# platform-bump:local-overrides") { inside = 1 }
' "$SRC" > "$WORK/overrides.sh"
OUT=""
[[ -s "$WORK/overrides.sh" ]] || fail "no '# platform-bump:local-overrides' block in $SRC"

azimuth="$WORK/azimuth"
mkdir -p "$azimuth/backend/build/tmp"
cat > "$azimuth/backend/build.gradle.kts" <<'KTS'
afterEvaluate {
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "com.fasterxml.jackson.core") useVersion("2.21.5")
            if (requested.group == "tools.jackson.core") useVersion("3.1.5")
            if (requested.name == "logback-classic") useVersion("1.5.37")
            if (requested.name == "logback-core") useVersion("1.5.37")
            if (requested.group == "org.postgresql") useVersion("42.7.12")
        }
    }
}
KTS
printf 'useVersion("9.9.9")\n' > "$azimuth/backend/build/tmp/generated.gradle.kts"
OUT=$(cd "$azimuth" && TARGET=1.6.0 bash "$WORK/overrides.sh")
[[ $(grep -c '  backend/build.gradle.kts:' <<<"$OUT") -eq 5 ]] || fail 'every useVersion line must be listed'
grep -q 'build.gradle.kts:8:.*42.7.12' <<<"$OUT" || fail 'each entry must carry its file and line'
grep -q 'dependencyInsight' <<<"$OUT" || fail 'the report must say how to check the selected version'
if grep -q 'generated.gradle.kts' <<<"$OUT"; then fail 'build output must not be scanned'; fi

bos="$WORK/bookofstyling"
mkdir -p "$bos/backend"
printf 'extra["jackson-2-bom.version"] = "2.21.4"\nextra["jackson-bom.version"] = "3.1.4"\n' > "$bos/backend/build.gradle.kts"
OUT=$(cd "$bos" && TARGET=1.6.0 bash "$WORK/overrides.sh")
[[ $(grep -c '  backend/build.gradle.kts:' <<<"$OUT") -eq 2 ]] || fail 'every extra[*.version] must be listed'

clean="$WORK/clean"
mkdir -p "$clean/backend"
printf 'dependencies { implementation(libs.jsoup) }\n' > "$clean/backend/build.gradle.kts"
OUT=$(cd "$clean" && TARGET=1.6.0 bash "$WORK/overrides.sh")
[[ -z "$OUT" ]] || fail 'a backend without overrides must print nothing'

echo 'OK: platform-bump lists the local version overrides the Platform BOMs cannot see'
