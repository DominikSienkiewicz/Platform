#!/usr/bin/env bash
# write-verification-metadata.sh — regeneruje gradle/verification-metadata.xml modułów Platform po zmianie
# katalogu, lockfile'a albo pluginów (docs/versions.md, „Dependency verification”).
#
#   scripts/write-verification-metadata.sh                  # build-logic, test-fixtures, security-starter
#   scripts/write-verification-metadata.sh build-logic      # wybrane moduły
#
# Dwa przebiegi, jak `platform-bump` u konsumentów: build (artefakty i konfiguracje odłączone, które tworzą
# taski), potem `dependencies` (każda resolvable konfiguracja). Oba z --refresh-dependencies, bo przy ciepłym
# cache Gradle nie dopisuje sum plików metadanych (.pom/.module), które serwuje z własnego magazynu.
# build-logic buduje bez `test`: jego testy to głównie TestKit, którego wewnętrzne buildy mają własne
# repozytoria i tego pliku nie czytają, a testRuntimeClasspath domyka przebieg `dependencies`.
# gradle/catalog nie ma pliku: plugin version-catalog niczego nie pobiera (pusty gradle.lockfile).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -gt 0 ]]; then modules=("$@"); else modules=(build-logic test-fixtures security-starter); fi
flags=(--write-verification-metadata sha256 --refresh-dependencies --no-daemon)

for module in "${modules[@]}"; do
  case "$module" in
    build-logic) first=(build -x test) ;;
    test-fixtures | security-starter) first=(build) ;;
    *) echo "Unknown module: $module (build-logic, test-fixtures, security-starter)" >&2; exit 2 ;;
  esac
  echo "==> gradle/$module: ${first[*]}"
  (cd "$root/gradle/$module" && ./gradlew "${first[@]}" "${flags[@]}")
  echo "==> gradle/$module: dependencies"
  (cd "$root/gradle/$module" && ./gradlew dependencies "${flags[@]}" > /dev/null)
done
echo "Review and commit gradle/*/gradle/verification-metadata.xml."
