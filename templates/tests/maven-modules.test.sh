#!/usr/bin/env bash
# gradle/maven-modules.txt to jedyna lista publikowanych modułów Maven: dokładnie moduły gradle/*/ z maven-publish,
# każdy z pakietem, którego wersję sprawdza idempotencja release.yml, a skrypty i workflowy czytają ją zamiast
# własnych literałów (kolejny moduł = jedna linijka).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
list="$root/gradle/maven-modules.txt"
fail() { echo "FAIL: $*" >&2; exit 1; }

listed=$(awk '!/^#/ && NF { print $1 }' "$list" | sort)
published=$(grep -l 'maven-publish' "$root"/gradle/*/build.gradle.kts | sed -E 's|.*/gradle/([^/]+)/build.gradle.kts|\1|' | sort)
[[ "$listed" == "$published" ]] || fail "gradle/maven-modules.txt must list exactly the modules with maven-publish:
listed:    $(tr '\n' ' ' <<<"$listed")
published: $(tr '\n' ' ' <<<"$published")"

while read -r module package; do
  case "$module" in
    build-logic) expected=seniordev.settings-conventions.seniordev.settings-conventions.gradle.plugin ;;
    *)
      name=$(sed -n -E 's/^rootProject\.name = "([^"]+)".*/\1/p' "$root/gradle/$module/settings.gradle.kts")
      expected="pl.seniordeveloper.$name"
      ;;
  esac
  [[ "$package" == "$expected" ]] || fail "gradle/$module publishes $expected, but gradle/maven-modules.txt names $package"
done < <(awk '!/^#/ && NF' "$list")
[[ $(awk '!/^#/ && NF { print $1; exit }' "$list") == build-logic ]] || fail 'build-logic must be published first: every other module applies its plugins'

for reader in .github/workflows/ci.yml .github/workflows/release.yml scripts/release-assets.sh \
  scripts/preview-on-consumer.sh scripts/write-verification-metadata.sh; do
  grep -qF 'gradle/maven-modules.txt' "$root/$reader" || fail "$reader must read gradle/maven-modules.txt"
  if grep -qE 'for [a-z]+ in build-logic catalog' "$root/$reader"; then fail "$reader still loops over a literal module list"; fi
done
echo 'OK: gradle/maven-modules.txt lists every published Maven module, and every module loop reads it'
