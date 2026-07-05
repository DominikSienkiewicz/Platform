#!/usr/bin/env bash
# bump-version.sh — CANON (Platform/templates/bump-version.sh, kopiowany do scripts/ każdego repo).
# Bumpuje wersję WARSTWY APLIKACJI (single source of truth dla tagów obrazów GHCR / deploy.yml).
# To NIE jest platform-bump.sh (tamten bumpuje warstwę Platform: zależności/konwencje).
#
# Użycie:
#   scripts/bump-version.sh backend  <patch|minor|major|X.Y.Z>
#   scripts/bump-version.sh frontend <patch|minor|major|X.Y.Z>
#   scripts/bump-version.sh db new-migration <slug-kebab>
#
# Backend  → version= w backend/gradle.properties
# Frontend → version w frontend/package.json (npm version --no-git-tag-version)
# DB       → nowy changeset Liquibase (dodanie pliku JEST podbiciem schematu; forward-only).
#            Repo na Flyway podmieniają blok `db` na V<n>__<slug>.sql w db/migration.
# Po bumpie: commit na main, PR main → release; merge odpala warunkowy deploy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAYER="${1:-}"
ACTION="${2:-}"
ARG="${3:-}"
# Autor changesetu = nazwa repo (bez hardkodu per-repo — kanon jest repo-agnostyczny).
AUTHOR="$(basename "$ROOT" | tr '[:upper:]' '[:lower:]')"

usage() {
  grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

# Oblicza nową wersję semver z bieżącej i akcji (patch|minor|major|X.Y.Z).
bump_semver() {
  local current="$1" action="$2"
  if [[ "$action" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$action"
    return
  fi
  local IFS=.
  read -r major minor patch <<<"$current"
  case "$action" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *) echo "Nieznana akcja: $action (patch|minor|major|X.Y.Z)" >&2; exit 1 ;;
  esac
}

# Przenośny sed in-place (GNU/BSD) przez plik tymczasowy.
sed_inplace() {
  local expr="$1" file="$2" tmp
  tmp="$(mktemp)"
  sed "$expr" "$file" >"$tmp" && mv "$tmp" "$file"
}

case "$LAYER" in
  backend)
    [[ -n "$ACTION" ]] || usage
    file="$ROOT/backend/gradle.properties"
    current="$(grep -E '^version=' "$file" | head -1 | cut -d= -f2 | tr -d '[:space:]')"
    [[ -n "$current" ]] || { echo "Brak 'version=' w $file" >&2; exit 1; }
    next="$(bump_semver "$current" "$ACTION")"
    sed_inplace "s/^version=.*/version=${next}/" "$file"
    echo "backend: ${current} → ${next} (backend/gradle.properties)"
    ;;

  frontend)
    [[ -n "$ACTION" ]] || usage
    (cd "$ROOT/frontend" && npm version "$ACTION" --no-git-tag-version >/dev/null)
    next="$(node -e "console.log(require('$ROOT/frontend/package.json').version)")"
    echo "frontend: → ${next} (frontend/package.json)"
    ;;

  db)
    [[ "$ACTION" == "new-migration" && -n "$ARG" ]] || usage
    changes_dir="$ROOT/backend/src/main/resources/db/changelog/changes"
    master="$ROOT/backend/src/main/resources/db/changelog/db.changelog-master.yaml"
    mkdir -p "$changes_dir"
    # następny 4-cyfrowy numer sekwencji
    last="$(ls "$changes_dir" 2>/dev/null | grep -oE '^[0-9]{4}' | sort -n | tail -1 || true)"
    seq="$(printf '%04d' "$((10#${last:-0} + 1))")"
    file="${seq}-${ARG}.yaml"
    cat >"$changes_dir/$file" <<YAML
databaseChangeLog:
  - changeSet:
      id: ${seq}-${ARG}
      author: ${AUTHOR}
      changes: []
      # TODO: dodaj operacje (createTable/addColumn/sql...) — migracje forward-only.
YAML
    # master może być pustą listą "[]" — zamień na blok listowy zanim dopniesz include
    if grep -qE '^databaseChangeLog:[[:space:]]*\[[[:space:]]*\][[:space:]]*$' "$master"; then
      sed_inplace 's/^databaseChangeLog:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/databaseChangeLog:/' "$master"
    fi
    printf '  - include:\n      file: db/changelog/changes/%s\n' "$file" >>"$master"
    echo "db: nowy changeset → changes/${file} (dopięty do master; changeset = schema bump)"
    ;;

  *) usage ;;
esac
