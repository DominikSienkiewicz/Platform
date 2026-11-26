#!/usr/bin/env bash
# write-verification-metadata.sh — regeneruje gradle/verification-metadata.xml modułów Platform po zmianie
# katalogu, lockfile'a albo pluginów (docs/versions.md, „Dependency verification”).
#
#   scripts/write-verification-metadata.sh                  # każdy moduł z gradle/maven-modules.txt z plikiem metadanych
#   scripts/write-verification-metadata.sh build-logic      # wybrane moduły
#   scripts/write-verification-metadata.sh --write-locks    # odtwarza również blokady po aktualizacji katalogu
#
# Dwa przebiegi, jak `platform-bump` u konsumentów: build (artefakty i konfiguracje odłączone, które tworzą
# taski), potem `dependencies` (każda resolvable konfiguracja). Oba z --refresh-dependencies, bo przy ciepłym
# cache Gradle nie dopisuje sum plików metadanych (.pom/.module), które serwuje z własnego magazynu.
# build-logic buduje bez `test`: jego testy to głównie TestKit, którego wewnętrzne buildy mają własne
# repozytoria i tego pliku nie czytają, a testRuntimeClasspath domyka przebieg `dependencies`.
# gradle/catalog nie ma pliku: plugin version-catalog niczego nie pobiera (pusty gradle.lockfile).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
flags=(--write-verification-metadata sha256 --refresh-dependencies --no-daemon)
report=/dev/null
if [[ ${1:-} == --write-locks ]]; then
  shift
  flags+=(--write-locks --console=plain)
  report=$(mktemp)
  trap 'rm -f "$report"' EXIT
fi
if [[ $# -gt 0 ]]; then
  modules=("$@")
else
  modules=()
  while read -r module _; do
    [[ -n "$module" && "$module" != \#* ]] || continue
    [[ -f "$root/gradle/$module/gradle/verification-metadata.xml" ]] && modules+=("$module")
  done < "$root/gradle/maven-modules.txt"
fi
for module in "${modules[@]}"; do
  case "$module" in
    build-logic) first=(build -x test) ;;
    *) [[ -f "$root/gradle/$module/gradle/verification-metadata.xml" ]] \
      || { echo "Unknown module: $module (a gradle/ module with gradle/verification-metadata.xml)" >&2; exit 2; }
      first=(build) ;;
  esac
  echo "==> gradle/$module: ${first[*]}"
  (cd "$root/gradle/$module" && ./gradlew "${first[@]}" "${flags[@]}")
  echo "==> gradle/$module: dependencies"
  (cd "$root/gradle/$module" && ./gradlew dependencies "${flags[@]}") > "$report" || {
    status=$?
    if [[ $report != /dev/null ]]; then cat "$report" >&2; fi
    exit "$status"
  }
  # Raport dependencies może zakończyć się kodem 0 mimo nierozwiązanej zależności.
  if [[ $report != /dev/null ]] && grep -E '[[:space:]]FAILED([[:space:]]|$)' "$report" >&2; then
    echo "Cannot refresh dependency locks for $module with unresolved dependencies." >&2
    exit 1
  fi
done
echo "Review and commit gradle/*/gradle/verification-metadata.xml."
