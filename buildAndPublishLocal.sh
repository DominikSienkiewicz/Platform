#!/usr/bin/env bash
# buildAndPublishLocal.sh — buduje i publikuje artefakty Platform do LOKALNEGO repo, żeby repo
# konsumenckie (Attestate / SkillSprintPlus / BookOfStyling) budowały się lokalnie BEZ GitHuba.
#
#   Gradle   -> publishToMavenLocal (~/.m2/repository): build-logic (convention plugins) + catalog
#   Frontend -> pnpm install (paczki gotowe); konsument linkuje je przez `npm run platform:link`
#
# Local-first: konsument ma mavenLocal() jako pierwszy + GitHub Packages tylko gdy są creds,
# więc po tym skrypcie backendy resolvują platformę lokalnie i nie łączą się z GitHubem.
#
# Użycie:
#   ./buildAndPublishLocal.sh                 # Gradle + frontend
#   ./buildAndPublishLocal.sh --skip-frontend # tylko Gradle (build-logic + catalog)
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

log() { printf '\n\033[1;36m▶ %s\033[0m\n' "$1"; }

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

# --- 2) Frontend (pnpm workspace) ---
if [[ "$SKIP_FRONTEND" -eq 0 ]]; then
  if command -v pnpm >/dev/null 2>&1; then
    log "Frontend: pnpm install (paczki współdzielone)"
    ( cd "$ROOT/frontend" && pnpm install )
    if [[ "$WITH_REGISTRY" -eq 1 ]]; then
      log "Frontend: shadcn build (public/r/*.json)"
      ( cd "$ROOT/frontend" && pnpm --filter @dominiksienkiewicz/ui build )
    fi
  else
    echo "⚠ pnpm nie znaleziony — pomijam frontend (użyj --skip-frontend lub zainstaluj pnpm)." >&2
  fi
fi

log "Gotowe — artefakty Gradle w ~/.m2/repository (mavenLocal)."
cat <<'EOF'

Następnie w repo konsumenta:
  Backend  : ./gradlew build                                  # platforma z mavenLocal (bez GitHuba)
  Frontend : npm run platform:link && npm install && npm test # lokalne paczki przez symlink
EOF
