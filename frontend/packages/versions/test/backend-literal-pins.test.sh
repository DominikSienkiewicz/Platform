#!/usr/bin/env bash
# platform-bump podbija dosłowne piny backendu w formie konsumentów (settings plugin, katalog, settings-gradle.lockfile)
# i nie kończy się sukcesem, gdy któryś pin pluginu ustawień został w starej wersji, bo jego zapis odbiega od wzorca.
# Cały bin biegnie na kopii bez sąsiedniego templates-check.mjs; curl i gradlew to atrapy, więc bez sieci i Gradle.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$work/bin" "$work/tool"
printf '#!/usr/bin/env bash\nexit 22\n' > "$work/bin/curl"
chmod +x "$work/bin/curl"
cp "$here/../bin/platform-bump.sh" "$work/tool/platform-bump.sh"

# consumer <name> <plugin line>: backend w formie Attestate/Azimuth/BookOfStyling/SkillSprintPlus.
consumer() {
  local dir="$work/$1"
  mkdir -p "$dir/backend"
  git -C "$dir" init -q
  printf '#!/usr/bin/env bash\necho "gradlew $*"\n' > "$dir/backend/gradlew"
  chmod +x "$dir/backend/gradlew"
  cat > "$dir/backend/settings.gradle.kts" <<KTS
plugins {
$2
}
dependencyResolutionManagement {
	versionCatalogs { create("libs") { from("pl.seniordeveloper:platform-catalog:1.5.26") } }
}
KTS
  printf 'pl.seniordeveloper:platform-catalog:1.5.30=incomingCatalogForLibs0\nempty=\n' > "$dir/backend/settings-gradle.lockfile"
  printf '%s\n' "$dir"
}
bump() { (cd "$1" && GPR_TOKEN=x PATH="$work/bin:$PATH" bash "$work/tool/platform-bump.sh" 9.9.9) > "$1.log" 2>&1; }

dir=$(consumer standard $'\tid("seniordev.settings-conventions") version "1.5.26"')
bump "$dir" || { cat "$dir.log"; fail '(a) the consumer form must bump'; }
grep -qF 'id("seniordev.settings-conventions") version "9.9.9"' "$dir/backend/settings.gradle.kts" || fail '(a) the settings plugin pin must move'
grep -qF 'platform-catalog:9.9.9")' "$dir/backend/settings.gradle.kts" || fail '(a) the catalog pin must move'
grep -qx 'pl.seniordeveloper:platform-catalog:9.9.9=incomingCatalogForLibs0' "$dir/backend/settings-gradle.lockfile" || fail '(a) the settings lockfile must move'

dir=$(consumer spaced $'\tid("seniordev.settings-conventions")  version  "1.5.26"')
bump "$dir" || { cat "$dir.log"; fail '(b) extra spaces around version must still bump'; }
grep -qE 'seniordev\.settings-conventions"\) +version +"9\.9\.9"' "$dir/backend/settings.gradle.kts" \
  || { cat "$dir/backend/settings.gradle.kts"; fail '(b) the spaced plugin pin must move with the catalog'; }

dir=$(consumer method $'\tid("seniordev.settings-conventions").version("1.5.26")')
if bump "$dir"; then cat "$dir.log"; fail '(c) a plugin pin the bump cannot rewrite must fail, not leave 1.5.26 behind'; fi
grep -qF 'seniordev.settings-conventions' "$dir.log" || { cat "$dir.log"; fail '(c) the failure must name the settings plugin pin'; }

echo 'OK: platform-bump moves literal backend pins and fails on a settings plugin pin it cannot rewrite'
