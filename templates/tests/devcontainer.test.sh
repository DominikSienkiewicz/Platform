#!/usr/bin/env bash
# Devcontainer (N-SHOW-11) nie jest nowym źródłem wersji: JDK toolchainu = `java` katalogu, JDK Gradle'a = domyślne
# `java-version` z backend-ci.yml, Node = frontend/.nvmrc, pnpm = packageManager z frontend/package.json; po
# utworzeniu rejestruje JDK toolchainu dla Gradle'a jak ci.yml, a workflow devcontainer.yml uruchamia w nim build-logic.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
dockerfile="$root/.devcontainer/Dockerfile"
arg() { sed -n -E "s/^ARG $1=([^[:space:]]+)\$/\\1/p" "$dockerfile"; }
catalog_java=$(sed -n -E 's/^java *= *"([0-9]+)".*/\1/p' "$root/gradle/catalog/libs.versions.toml")
gradle_jdk=$(awk '/^      java-version:/ { inside = 1; next } inside && /default:/ { gsub(/[" ]/, "", $2); print $2; exit }' "$root/.github/workflows/backend-ci.yml")
pnpm_version=$(sed -n -E 's/.*"packageManager": "pnpm@([0-9.]+)".*/\1/p' "$root/frontend/package.json")
[[ "$(arg TOOLCHAIN_JDK)" == "$catalog_java" ]] || fail "TOOLCHAIN_JDK=$(arg TOOLCHAIN_JDK) must equal the catalog java ($catalog_java)"
[[ "$(arg GRADLE_JDK)" == "$gradle_jdk" ]] || fail "GRADLE_JDK=$(arg GRADLE_JDK) must equal the java-version default of backend-ci.yml ($gradle_jdk)"
[[ "$(arg NODE_MAJOR)" == "$(tr -d '[:space:]' < "$root/frontend/.nvmrc")" ]] || fail 'NODE_MAJOR must equal frontend/.nvmrc'
[[ "$(arg PNPM_VERSION)" == "$pnpm_version" ]] || fail "PNPM_VERSION must equal packageManager of frontend/package.json ($pnpm_version)"
grep -qF "ENV JAVA_HOME=/opt/jdk-$gradle_jdk" "$dockerfile" || fail 'JAVA_HOME must point at the JDK that runs Gradle'
grep -qF "org.gradle.java.installations.paths=/opt/jdk-$catalog_java" "$root/.devcontainer/post-create.sh" \
  || fail 'post-create must register the toolchain JDK for Gradle'
grep -qF "org.gradle.java.installations.paths=/opt/jdk-$catalog_java" "$root/.github/workflows/devcontainer.yml" \
  || fail 'the CI run must register the toolchain JDK too'
grep -qF 'cd gradle/build-logic && ./gradlew --no-daemon test' "$root/.github/workflows/devcontainer.yml" \
  || fail 'devcontainer.yml must run the build-logic suite inside the container'
grep -qE 'uses: devcontainers/ci@[0-9a-f]{40} # v' "$root/.github/workflows/devcontainer.yml" || fail 'the devcontainers action must be pinned by SHA'
echo "OK: the devcontainer runs Gradle on Java $gradle_jdk with the Java $catalog_java toolchain, Node $(arg NODE_MAJOR) and pnpm $pnpm_version"
