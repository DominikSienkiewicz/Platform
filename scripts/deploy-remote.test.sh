#!/usr/bin/env bash
# Testy rezolucji nazw artefaktów w deploy-remote.sh — bez wykonywania flow docker.
# Skrypt jest sourcowany (guard w deploy-remote.sh zatrzymuje wykonanie po definicjach),
# więc testujemy COMPOSE_FILE + resolve_base_env; guard braku compose testujemy wykonaniem.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/deploy-remote.sh"
fails=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then echo "ok  - $1"
  else echo "NIE - $1: oczekiwano '$2', jest '$3'"; fails=$((fails+1)); fi
}

# 1) Domyślnie: COMPOSE_FILE=docker-compose.prod.yml, base env=.env.prod
out="$( tmp="$(mktemp -d)"; cd "$tmp"; touch .env.prod
        unset COMPOSE_FILE BASE_ENV
        source "$SCRIPT"; set +euo pipefail
        printf '%s|%s' "$COMPOSE_FILE" "$(resolve_base_env)" )"
check "default compose file" "docker-compose.prod.yml" "${out%%|*}"
check "default base env"     ".env.prod"               "${out##*|}"

# 2) Override: COMPOSE_FILE=docker-compose.dev.yml, BASE_ENV=.env.dev (istnieje)
out="$( tmp="$(mktemp -d)"; cd "$tmp"; touch .env.dev
        export COMPOSE_FILE=docker-compose.dev.yml BASE_ENV=.env.dev
        source "$SCRIPT"; set +euo pipefail
        printf '%s|%s' "$COMPOSE_FILE" "$(resolve_base_env)" )"
check "override compose file" "docker-compose.dev.yml" "${out%%|*}"
check "override base env"     ".env.dev"               "${out##*|}"

# 3) Fallback .env gdy brak .env.prod i BASE_ENV puste
out="$( tmp="$(mktemp -d)"; cd "$tmp"; touch .env
        unset COMPOSE_FILE BASE_ENV
        source "$SCRIPT"; set +euo pipefail
        resolve_base_env )"
check "fallback to .env" ".env" "$out"

# 4) Brak compose → wykonanie skryptu kończy się kodem !=0
( tmp="$(mktemp -d)"; cd "$tmp"; touch .env.prod
  COMPOSE_FILE=docker-compose.dev.yml bash "$SCRIPT" >/dev/null 2>&1 )
check "missing compose exits nonzero" "nonzero" "$([[ $? -ne 0 ]] && echo nonzero || echo zero)"

[[ $fails -eq 0 ]] && { echo "WSZYSTKIE OK"; exit 0; } || { echo "FAILED: $fails"; exit 1; }
