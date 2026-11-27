#!/usr/bin/env bash
# buildAndPublishLocal.sh — builds and publishes the Platform artifacts to a LOCAL repository, so that
# consumer repositories build locally WITHOUT GitHub (the consumers are listed in scripts/consumers.txt).
#
#   Gradle   -> publishToMavenLocal (~/.m2/repository): every module of gradle/maven-modules.txt, in its order
#               (build-logic first), all at one platformVersion
#   Frontend -> pnpm install (the packages are ready); a consumer installs them with
#               npm install --no-save <path>/Platform/frontend/packages/<name>
#
# A consumer points at this repository explicitly: -PplatformRepository=file:///<home>/.m2/repository (first
# in resolution order); see docs/local-development.md.
#
# Usage:
#   ./buildAndPublishLocal.sh                 # Gradle + frontend
#   ./buildAndPublishLocal.sh --skip-frontend # Gradle only (the modules of gradle/maven-modules.txt)
#   ./buildAndPublishLocal.sh --help
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_FRONTEND=0

for arg in "$@"; do
  case "$arg" in
    --skip-frontend) SKIP_FRONTEND=1 ;;
    -h|--help) awk 'NR>1{ if(/^#/){sub(/^# ?/,"");print} else exit }' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg (see --help)" >&2; exit 2 ;;
  esac
done

log() { local msg="$1"; printf '\n\033[1;36m▶ %s\033[0m\n' "$msg"; }

# --- 1) Gradle: publishToMavenLocal ---
publish_gradle() {
  local module="$1"
  log "Gradle: publishToMavenLocal — gradle/${module}"
  (
    cd "$ROOT/gradle/${module}"
    chmod +x ./gradlew 2>/dev/null || true
    ./gradlew --no-daemon publishToMavenLocal
  )
}

# Lista i kolejność z gradle/maven-modules.txt (pilnuje templates/tests/maven-modules.test.sh), jak w ci.yml i release.yml.
# stdin z /dev/null: Gradle nie zje reszty listy, którą czyta pętla.
while read -r module; do
  publish_gradle "$module" < /dev/null
done < <(awk '!/^#/ && NF { print $1 }' "$ROOT/gradle/maven-modules.txt")

# --- 2) Frontend (pnpm workspace) ---
if [[ "$SKIP_FRONTEND" -eq 0 ]]; then
  if command -v pnpm >/dev/null 2>&1; then
    log "Frontend: pnpm install (shared packages)"
    # --ignore-scripts: spójnie z CI — instalacja nie odpala skryptów lifecycle zależności.
    ( cd "$ROOT/frontend" && pnpm install --ignore-scripts )
  else
    echo "⚠ pnpm not found, skipping the frontend (pass --skip-frontend or install pnpm)." >&2
  fi
fi

VERSION="$(grep -E '^platformVersion=' "$ROOT/gradle/build-logic/gradle.properties" | cut -d= -f2 | tr -d ' ')"
log "Done: the Gradle artifacts of $VERSION are in $HOME/.m2/repository."
cat <<EOF

Next, in a consumer repository (Platform 1.5.31 or newer wiring, see docs/local-development.md):
  Backend : ./gradlew build -PplatformVersion=$VERSION -PplatformRepository=file://$HOME/.m2/repository
            The consumer's pluginManagement must contain the platformRepository line from
            templates/jvm/spring-app/settings.gradle.kts, or plugins still resolve from GitHub Packages.
  Frontend: npm install --no-save $ROOT/frontend/packages/<name>
EOF
