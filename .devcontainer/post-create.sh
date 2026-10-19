#!/usr/bin/env bash
# Po utworzeniu devcontainera: toolchain JDK 27 zarejestrowany dla Gradle'a jak w ci.yml, artefakty Platform
# w ~/.m2 (buildAndPublishLocal.sh) i zależności frontendu bez skryptów lifecycle.
set -euo pipefail
mkdir -p "$HOME/.gradle"
grep -qs '^org.gradle.java.installations.paths=' "$HOME/.gradle/gradle.properties" \
  || echo "org.gradle.java.installations.paths=/opt/jdk-27" >> "$HOME/.gradle/gradle.properties"
./buildAndPublishLocal.sh --skip-frontend
(cd frontend && pnpm install --frozen-lockfile --ignore-scripts)
