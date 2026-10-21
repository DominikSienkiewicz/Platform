#!/usr/bin/env bash
# Jeden JDK wszędzie (ADR-0034): JDK, na którym biegnie Gradle, bytecode build-logic i modułów Platform, workflowy,
# SDKMAN, devcontainery i kryteria demona starterów równają się wpisowi `java` katalogu (toolchain kanonu).
# Najstarszy Gradle konsumenta musi umieć wystartować na tym JDK (9.6.1 pada na JDK 27: Groovy, class file 71).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

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

for dockerfile in "$root/.devcontainer/Dockerfile" "$root/templates/devcontainer/Dockerfile"; do
  jdk=$(sed -n 's/^ARG GRADLE_JDK=//p' "$dockerfile")
  [[ "$jdk" == "$canon" ]] || fail "${dockerfile#"$root"/}: GRADLE_JDK=$jdk; the devcontainer must run Gradle on Java $canon"
done

for criteria in "$root"/templates/jvm/*/gradle/gradle-daemon-jvm.properties; do
  daemon=$(sed -n 's/^toolchainVersion=//p' "$criteria")
  [[ "$daemon" == "$canon" ]] || fail "${criteria#"$root"/}: toolchainVersion=$daemon; the daemon must run on Java $canon"
done

minimum=$(sed -n 's/^minimumConsumerGradle=//p' "$root/gradle/build-logic/gradle.properties")
[[ "$(printf '%s\n%s\n' "$gradle_floor" "$minimum" | sort -V | head -n 1)" == "$gradle_floor" ]] ||
  fail "minimumConsumerGradle=$minimum cannot start on Java $canon; the floor is Gradle $gradle_floor"

echo "OK: Gradle, build-logic, workflows, SDKMAN, devcontainers and daemon criteria all use Java $canon"
