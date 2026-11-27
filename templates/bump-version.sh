#!/usr/bin/env bash
# bump-version.sh — CANON (Platform/templates/bump-version.sh, copied to scripts/ of every repository).
# Bumps the version of the APPLICATION LAYER (the single source of truth for the GHCR image tags / deploy.yml).
# This is NOT platform-bump.sh, which bumps the Platform layer (dependencies and conventions).
#
# Usage:
#   scripts/bump-version.sh backend  <patch|minor|major|X.Y.Z>
#   scripts/bump-version.sh frontend <patch|minor|major|X.Y.Z>
#   scripts/bump-version.sh db new-migration <slug-kebab>
#
# Backend  → version= in backend/gradle.properties
# Frontend → version in frontend/package.json (npm version --no-git-tag-version)
# DB       → a new Liquibase changeset (adding the file IS the schema bump; forward-only).
#            Repositories on Flyway replace the `db` block with V<n>__<slug>.sql in db/migration.
# After the bump: commit on main, PR main → release; the merge starts the conditional deploy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAYER="${1:-}"
ACTION="${2:-}"
ARG="${3:-}"
# The changeset author is the repository name (nothing hard-coded per repository; the canon is
# repository-agnostic). In a worktree (<repo>/.worktrees/<name>) ROOT is the worktree directory, so the
# name comes from the main working tree: the first entry of `git worktree list`. Outside Git it is the
# directory above scripts/.
main_worktree="$({ git -C "$ROOT" worktree list --porcelain 2>/dev/null || true; } | sed -n '1s/^worktree //p')"
AUTHOR="$(basename "${main_worktree:-$ROOT}" | tr '[:upper:]' '[:lower:]')"

usage() {
  grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

# Computes the new semver version from the current one and the action (patch|minor|major|X.Y.Z).
bump_semver() {
  local current="$1" action="$2"
  if [[ "$action" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$action"
    return
  fi
  # IFS jako prefiks polecenia: rozdziela "X.Y.Z" tylko na czas tego `read`, bez zmiennej pomocniczej.
  IFS=. read -r major minor patch <<<"$current"
  case "$action" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *) echo "Unknown action: $action (patch|minor|major|X.Y.Z)" >&2; exit 1 ;;
  esac
}

# Portable in-place sed (GNU and BSD) through a temporary file.
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
    [[ -n "$current" ]] || { echo "No 'version=' in $file" >&2; exit 1; }
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
    # następny 4-cyfrowy numer sekwencji: glob zamiast `ls | grep`, który psuje się na nazwach ze znakami specjalnymi
    last=0
    for path in "$changes_dir"/[0-9][0-9][0-9][0-9]*; do
      [[ -e "$path" ]] || continue
      name="${path##*/}"
      if ((10#${name:0:4} > 10#$last)); then last="${name:0:4}"; fi
    done
    seq="$(printf '%04d' "$((10#$last + 1))")"
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
    echo "db: new changeset → changes/${file} (included in master; a changeset is the schema bump)"
    ;;

  *) usage ;;
esac
