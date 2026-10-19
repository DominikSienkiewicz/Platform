#!/usr/bin/env bash
# Kryteria JVM demona Gradle'a w szablonach (N-DX-2): oba startery mają ten sam plik z `updateDaemonJvm`, wersja
# równa się domyślnemu `java-version` z backend-ci.yml (JDK, na którym biegnie Gradle), a Linux x86-64 ma URL pobrania.
# Że URL to Temurin z glibc, a nie build Alpine, sprawdza się przy generowaniu (docs/versions.md) — ID Foojay offline nic nie mówi.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
library="$root/templates/jvm/java-library/gradle/gradle-daemon-jvm.properties"
spring="$root/templates/jvm/spring-app/gradle/gradle-daemon-jvm.properties"
[[ -f "$library" && -f "$spring" ]] || fail 'both JVM starters need gradle/gradle-daemon-jvm.properties (./gradlew updateDaemonJvm --jvm-version=<N>)'
cmp -s "$library" "$spring" || fail 'the two starters must carry the same daemon JVM criteria'
version=$(sed -n 's/^toolchainVersion=//p' "$library")
ci=$(awk '/^      java-version:/ { inside = 1; next } inside && /default:/ { gsub(/[" ]/, "", $2); print $2; exit }' "$root/.github/workflows/backend-ci.yml")
[[ -n "$version" && "$version" == "$ci" ]] || fail "toolchainVersion=$version must equal the java-version default of backend-ci.yml ($ci)"
grep -q '^toolchainUrl\.LINUX\.X86_64=https' "$library" || fail 'Linux x86-64 needs a download URL, or a fresh runner cannot start the daemon'
echo "OK: both starters pin the Gradle daemon to Java $version, as backend-ci.yml runs it"
