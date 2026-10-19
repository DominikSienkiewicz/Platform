#!/usr/bin/env bash
# Po utworzeniu devcontainera konsumenta (N-SHOW-11, incubating): toolchain JDK zarejestrowany dla Gradle'a jak w ci.yml
# (to nie wymaga poświadczeń) i zależności frontendu przez `npm ci --ignore-scripts`, ale tylko gdy istnieje
# frontend/package-lock.json i GITHUB_TOKEN jest ustawiony. Token przychodzi z remoteEnv (devcontainer.json), nigdy
# z obrazu ani z pliku; bez niego skrypt niczego z GitHub Packages nie pobiera i wypisuje podpowiedź.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)

mkdir -p "$HOME/.gradle"
grep -qs '^org.gradle.java.installations.paths=' "$HOME/.gradle/gradle.properties" \
  || echo "org.gradle.java.installations.paths=${TOOLCHAIN_JAVA_HOME:?TOOLCHAIN_JAVA_HOME is set by the Dockerfile}" >> "$HOME/.gradle/gradle.properties"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  cat <<'HINT'
GITHUB_TOKEN is not set in this container, so nothing was fetched from GitHub Packages.
Export GITHUB_ACTOR (your GitHub login) and GITHUB_TOKEN (a classic token with read:packages) in the shell that
starts the container, then rebuild it. See https://github.com/DominikSienkiewicz/Platform/blob/main/docs/consuming.md#devcontainer-incubating
HINT
  if [[ -f "$root/frontend/package-lock.json" ]]; then
    echo "Skipped: npm ci --ignore-scripts in frontend/ (run it by hand once the token is set)."
  fi
  exit 0
fi

if [[ -f "$root/frontend/package-lock.json" ]]; then
  (cd "$root/frontend" && npm ci --ignore-scripts)
fi
