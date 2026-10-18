#!/usr/bin/env bash
# buildAndPublishLocal.sh — buduje i publikuje artefakty Platform do LOKALNEGO repo, żeby repo
# konsumenckie budowały się lokalnie BEZ GitHuba (lista konsumentów: CLAUDE.md).
#
#   Gradle   -> publishToMavenLocal (~/.m2/repository): build-logic (convention plugins) + catalog
#               + test-fixtures + security-starter, wszystkie w jednej platformVersion
#   Frontend -> pnpm install (paczki gotowe); konsument instaluje je przez
#               npm install --no-save <ścieżka>/Platform/frontend/packages/<nazwa>
#
# Konsument wskazuje to repo jawnie: -PplatformRepository=file:///<home>/.m2/repository (pierwsze
# w kolejności rezolucji) — patrz docs/local-development.md.
#
# Użycie:
#   ./buildAndPublishLocal.sh                 # Gradle + frontend
#   ./buildAndPublishLocal.sh --skip-frontend # tylko Gradle (build-logic + catalog + test-fixtures + security-starter)
#   ./buildAndPublishLocal.sh --with-registry # dodatkowo `shadcn build` (public/r/*.json)
#   ./buildAndPublishLocal.sh --help
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_FRONTEND=0
WITH_REGISTRY=0

for arg in "$@"; do
  case "$arg" in
    --skip-frontend) SKIP_FRONTEND=1 ;;
    --with-registry) WITH_REGISTRY=1 ;;
    -h|--help) awk 'NR>1{ if(/^#/){sub(/^# ?/,"");print} else exit }' "$0"; exit 0 ;;
    *) echo "Nieznany argument: $arg (zobacz --help)" >&2; exit 2 ;;
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

publish_gradle "build-logic"
publish_gradle "catalog"
publish_gradle "test-fixtures"
publish_gradle "security-starter"

# --- 2) Frontend (pnpm workspace) ---
if [[ "$SKIP_FRONTEND" -eq 0 ]]; then
  if command -v pnpm >/dev/null 2>&1; then
    log "Frontend: pnpm install (paczki współdzielone)"
    # --ignore-scripts: spójnie z CI — instalacja nie odpala skryptów lifecycle zależności.
    ( cd "$ROOT/frontend" && pnpm install --ignore-scripts )
    if [[ "$WITH_REGISTRY" -eq 1 ]]; then
      log "Frontend: shadcn build (public/r/*.json)"
      ( cd "$ROOT/frontend" && pnpm --filter @dominiksienkiewicz/ui build )
    fi
  else
    echo "⚠ pnpm nie znaleziony — pomijam frontend (użyj --skip-frontend lub zainstaluj pnpm)." >&2
  fi
fi

VERSION="$(grep -E '^platformVersion=' "$ROOT/gradle/build-logic/gradle.properties" | cut -d= -f2 | tr -d ' ')"
log "Gotowe — artefakty Gradle $VERSION w $HOME/.m2/repository."
cat <<EOF

Next, in a consumer repository (Platform 1.5.31 or newer wiring, see docs/local-development.md):
  Backend : ./gradlew build -PplatformVersion=$VERSION -PplatformRepository=file://$HOME/.m2/repository
            The consumer's pluginManagement must contain the platformRepository line from
            templates/jvm/spring-app/settings.gradle.kts, or plugins still resolve from GitHub Packages.
  Frontend: npm install --no-save $ROOT/frontend/packages/<name>
EOF
