#!/usr/bin/env bash
# One JDK everywhere (ADR-0034), case by case: the workflows, build-logic, modules, SDKMAN and daemon criteria equal the
# catalog's java entry, and both starters pin the Gradle daemon JVM.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- one-jdk ---
# Jeden JDK wszędzie (ADR-0034): JDK, na którym biegnie Gradle, bytecode build-logic i modułów Platform, workflowy,
# SDKMAN i kryteria demona starterów równają się wpisowi `java` katalogu (toolchain kanonu).
# Najstarszy Gradle konsumenta musi umieć wystartować na tym JDK (9.6.1 pada na JDK 27: Groovy, class file 71).
(
canon=$(sed -n 's/^java = "\([0-9][0-9]*\)".*/\1/p' "$root/gradle/catalog/libs.versions.toml")
[[ -n "$canon" ]] || fail 'gradle/catalog/libs.versions.toml has no java entry'
# Pierwszy Gradle, który uruchamia się na JDK z kanonu; podnieś razem z kanonem java.
gradle_floor=9.8.1

for workflow in "$root"/.github/workflows/*.yml; do
  name=$(basename "$workflow")
  # Domyślna wartość inputu java-version (JDK uruchamiający Gradle'a).
  default=$(awk '/^      java-version:/ { inside = 1; next } inside && /^      [a-z]/ { inside = 0 } inside && /default:/ { gsub(/[" ]/, "", $2); print $2; exit }' "$workflow")
  [[ -z "$default" || "$default" == "$canon" ]] ||
    fail "$name: input java-version defaults to $default; Gradle must run on Java $canon (catalog entry java)"
  # Literalne java-version w krokach setup-java; wyrażenia (${{ … }}) i wersje EA canary pomija.
  while IFS= read -r literal; do
    [[ "$literal" == "$canon" ]] ||
      fail "$name: setup-java installs java-version $literal; every JDK of the workflows must be Java $canon"
  done < <(sed -n 's/^ *java-version: *"\([0-9][0-9]*\)" *$/\1/p' "$workflow")
done

while IFS= read -r build; do
  while IFS= read -r version; do
    [[ "$version" == "$canon" ]] ||
      fail "${build#"$root"/}: JavaLanguageVersion.of($version); Platform's modules target Java $canon bytecode"
  done < <(sed -n 's/.*JavaLanguageVersion\.of(\([0-9][0-9]*\)).*/\1/p' "$build")
done < <(find "$root/gradle" -maxdepth 2 -name build.gradle.kts)

while IFS= read -r sdkmanrc; do
  java=$(sed -n 's/^java=\([0-9][0-9]*\).*/\1/p' "$sdkmanrc")
  [[ "$java" == "$canon" ]] || fail "${sdkmanrc#"$root"/}: java=$java; SDKMAN must select Java $canon"
done < <(find "$root/templates" "$root/gradle" -maxdepth 2 -name .sdkmanrc)

for criteria in "$root"/templates/jvm/*/gradle/gradle-daemon-jvm.properties; do
  daemon=$(sed -n 's/^toolchainVersion=//p' "$criteria")
  [[ "$daemon" == "$canon" ]] || fail "${criteria#"$root"/}: toolchainVersion=$daemon; the daemon must run on Java $canon"
done

minimum=$(sed -n 's/^minimumConsumerGradle=//p' "$root/gradle/build-logic/gradle.properties")
[[ "$(printf '%s\n%s\n' "$gradle_floor" "$minimum" | sort -V | head -n 1)" == "$gradle_floor" ]] ||
  fail "minimumConsumerGradle=$minimum cannot start on Java $canon; the floor is Gradle $gradle_floor"

echo "OK: Gradle, build-logic, workflows, SDKMAN and daemon criteria all use Java $canon"
)

# --- daemon-jvm-criteria ---
# Kryteria JVM demona Gradle'a w szablonach (N-DX-2): oba startery mają ten sam plik z `updateDaemonJvm`, wersja
# równa się domyślnemu `java-version` z backend-ci.yml (JDK, na którym biegnie Gradle), a Linux x86-64 ma URL pobrania.
# Że URL to Temurin z glibc, a nie build Alpine, sprawdza się przy generowaniu (docs/versions.md) — ID Foojay offline nic nie mówi.
(
library="$root/templates/jvm/java-library/gradle/gradle-daemon-jvm.properties"
spring="$root/templates/jvm/spring-app/gradle/gradle-daemon-jvm.properties"
[[ -f "$library" && -f "$spring" ]] || fail 'both JVM starters need gradle/gradle-daemon-jvm.properties (./gradlew updateDaemonJvm --jvm-version=<N>)'
cmp -s "$library" "$spring" || fail 'the two starters must carry the same daemon JVM criteria'
version=$(sed -n 's/^toolchainVersion=//p' "$library")
ci=$(awk '/^      java-version:/ { inside = 1; next } inside && /default:/ { gsub(/[" ]/, "", $2); print $2; exit }' "$root/.github/workflows/backend-ci.yml")
[[ -n "$version" && "$version" == "$ci" ]] || fail "toolchainVersion=$version must equal the java-version default of backend-ci.yml ($ci)"
grep -q '^toolchainUrl\.LINUX\.X86_64=https' "$library" || fail 'Linux x86-64 needs a download URL, or a fresh runner cannot start the daemon'
echo "OK: both starters pin the Gradle daemon to Java $version, as backend-ci.yml runs it"
)
