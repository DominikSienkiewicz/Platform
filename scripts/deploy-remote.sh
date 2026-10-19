#!/usr/bin/env bash
# Deploy on-box — KANON Platform (wgrywany na boks i uruchamiany przez deploy.yml).
# Uniwersalny dla SkillSprintPlus i BookOfStyling:
#   • nazwy serwisów WYKRYWANE z `compose config --services` (SSP: skillsprintplus-*, BoS: gołe backend/db-migrate),
#   • kontenery przez `compose ps -q` (niezależne od container_name),
#   • baza env z `.env.prod` LUB `.env` (host), tagi warstw z `.env.deploy` (z CI),
#   • zmienne tagów obsłużone dwojako: BACKEND_TAG|BACKEND_VER, FRONTEND_TAG|FRONTEND_VER.
# Kolejność (warunkowo): migracje (bramka) -> backend (+worker) -> frontend -> caddy.
# Baza danych jest ZEWNĘTRZNA (osobny VPS) — tu tylko nanosimy migracje.
# Rollback warstw app: przed wymianą tagi działających kontenerów idą do .env.deploy.previous; gdy backend albo
# frontend (z healthcheckiem) nie osiąga healthy, poprzednie tagi wracają z lokalnego obrazu i deploy kończy się
# kodem 1 z "ROLLED BACK to <tag>". Migracji NIE cofamy — zmiany schematu muszą być expand/contract, żeby poprzednia
# wersja aplikacji działała na nowym schemacie (docs/reusable-workflows.md, deploy.yml).
set -euo pipefail

# Nazwa pliku compose i bazowego env-file są konfigurowalne przez env (przekazywane przez
# reusable deploy.yml). Domyślne wartości zachowują dotychczasowe zachowanie (SSP/BoS).
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"

# resolve_base_env: echo nazwy bazowego env-file. Jawny BASE_ENV ma priorytet (musi istnieć);
# w przeciwnym razie preferuj .env.prod (SSP), potem host .env (BoS). Zwraca !=0 gdy brak.
resolve_base_env() {
  if   [[ -n "${BASE_ENV:-}" && -f "${BASE_ENV}" ]]; then printf '%s\n' "${BASE_ENV}"
  elif [[ -z "${BASE_ENV:-}" && -f .env.prod ]];     then printf '%s\n' ".env.prod"
  elif [[ -z "${BASE_ENV:-}" && -f .env ]];          then printf '%s\n' ".env"
  else return 1; fi
}

# Sourcing (testy) ładuje tylko konfigurowalne definicje powyżej i tu wychodzi.
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0 || true

[[ -f "$COMPOSE_FILE" ]] || { echo "BŁĄD: brak $COMPOSE_FILE w $(pwd)"; exit 1; }

BASE_ENV="$(resolve_base_env)" || { echo "BŁĄD: brak bazowego env (.env.prod/.env lub podany BASE_ENV) w $(pwd)"; exit 1; }

ENV_ARGS=(--env-file "$BASE_ENV")
[[ -f .env.deploy ]] && ENV_ARGS+=(--env-file .env.deploy)
COMPOSE=(docker compose "${ENV_ARGS[@]}" -f "$COMPOSE_FILE")

# Do porównań tagów sourcujemy TYLKO .env.deploy (generowany przez CI = czysty KEY=VALUE).
# Host .env/.env.prod czyta compose przez --env-file (nie sourcujemy go do bash — może mieć
# wartości łamiące `source`).
[[ -f .env.deploy ]] && { set -a; . ./.env.deploy; set +a; }
BACKEND_DECL="${BACKEND_TAG:-${BACKEND_VER:-}}"
FRONTEND_DECL="${FRONTEND_TAG:-${FRONTEND_VER:-}}"

log() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
services="$("${COMPOSE[@]}" config --services)"
pick() { local pattern="$1"; grep -iE "$pattern" <<<"$services" | head -1 || true; }
SVC_MIGRATE="$(pick 'migrate')"
SVC_BACKEND="$(pick 'backend')"
SVC_FRONTEND="$(pick 'frontend')"
SVC_CADDY="$(pick 'caddy')"
SVC_WORKER="$(pick 'worker|eval')"

cid() { local svc="$1"; "${COMPOSE[@]}" ps -q "$svc" 2>/dev/null | head -1; }
running_tag() { local svc="$1" id; id="$(cid "$svc")"; [[ -n "$id" ]] && docker inspect -f '{{.Config.Image}}' "$id" 2>/dev/null | sed 's/.*://' || true; }
health() { local svc="$1" id; id="$(cid "$svc")"; [[ -n "$id" ]] && docker inspect -f '{{.State.Health.Status}}' "$id" 2>/dev/null || echo none; }
# wait_healthy <svc>: 0, gdy serwis nie ma healthchecka albo osiąga healthy w 40×3 s.
wait_healthy() {
  local svc="$1"
  [[ "$(health "$svc")" != "none" ]] || return 0
  log "Czekam na healthy: $svc"
  for _ in $(seq 1 40); do [[ "$(health "$svc")" == "healthy" ]] && return 0; sleep 3; done
  [[ "$(health "$svc")" == "healthy" ]]
}

# Poprzednie tagi (przed wymianą) — ostatni --env-file nadpisuje .env.deploy, więc rollback podaje oba warianty
# nazw zmiennych. Pusty tag (pierwszy deploy) = nie ma do czego wracać.
PREVIOUS_BACKEND="$(running_tag "$SVC_BACKEND")"
PREVIOUS_FRONTEND="$(running_tag "$SVC_FRONTEND")"
printf 'BACKEND_TAG=%s\nBACKEND_VER=%s\nFRONTEND_TAG=%s\nFRONTEND_VER=%s\n' \
  "$PREVIOUS_BACKEND" "$PREVIOUS_BACKEND" "$PREVIOUS_FRONTEND" "$PREVIOUS_FRONTEND" > .env.deploy.previous
ROLLBACK=(docker compose "${ENV_ARGS[@]}" --env-file .env.deploy.previous -f "$COMPOSE_FILE")

# roll_back <label> <previous tag> <svc…>: poprzedni tag z lokalnego obrazu (bez pull), potem bramka healthy.
roll_back() {
  local label="$1" previous="$2"
  shift 2
  if [[ -z "$previous" ]]; then
    echo "$label nie osiągnął healthy, a nie ma poprzedniej wersji do przywrócenia (pierwszy deploy)."
    exit 1
  fi
  log "$label nie osiągnął healthy — rollback do $previous"
  "${ROLLBACK[@]}" up -d --force-recreate --pull never "$@"
  if wait_healthy "$1"; then
    echo "ROLLED BACK to $previous: $label runs its previous version again."
  else
    echo "Rollback do $previous też nie osiągnął healthy — sprawdź logi: docker compose logs $1"
  fi
  exit 1
}

log "Pull obrazów (łącznie z profilem migrate)"
"${COMPOSE[@]}" --profile migrate pull

# ---------- 1) MIGRACJE — bramka przed warstwami aplikacyjnymi ----------
if [[ -n "$SVC_MIGRATE" ]]; then
  log "Migracje: liquibase status ($SVC_MIGRATE)"
  out="$("${COMPOSE[@]}" run --rm "$SVC_MIGRATE" status --verbose 2>&1 || true)"; echo "$out"
  if grep -qiE "have not been applied|pending" <<<"$out"; then
    log "Pending changesety -> update (BRAMKA: błąd = stop, warstwy app nietknięte)"
    "${COMPOSE[@]}" run --rm "$SVC_MIGRATE" update
  elif grep -qiE "is up to date|are up to date" <<<"$out"; then
    echo "Brak pending changesetów — pomijam migrację."
  else
    log "Status niejednoznaczny -> update (bezpieczna bramka)"
    "${COMPOSE[@]}" run --rm "$SVC_MIGRATE" update
  fi
fi

# ---------- 2) BACKEND (+worker, jeśli wykryty) — tylko gdy podbita wersja ----------
if [[ "$(running_tag "$SVC_BACKEND")" != "$BACKEND_DECL" ]]; then
  log "Backend: ${BACKEND_DECL:-<brak>} -> wymiana"
  up_targets=("$SVC_BACKEND"); [[ -n "$SVC_WORKER" ]] && up_targets+=("$SVC_WORKER")
  "${COMPOSE[@]}" up -d --force-recreate --pull always "${up_targets[@]}"
  if ! wait_healthy "$SVC_BACKEND"; then
    echo "Backend nie osiągnął healthy"
    roll_back Backend "$PREVIOUS_BACKEND" "${up_targets[@]}"
  fi
else
  echo "Backend ${BACKEND_DECL} bez zmian — pomijam."
fi

# ---------- 3) FRONTEND — tylko gdy podbita wersja ----------
if [[ "$(running_tag "$SVC_FRONTEND")" != "$FRONTEND_DECL" ]]; then
  log "Frontend: ${FRONTEND_DECL:-<brak>} -> wymiana"
  "${COMPOSE[@]}" up -d --force-recreate --pull always "$SVC_FRONTEND"
  if ! wait_healthy "$SVC_FRONTEND"; then
    echo "Frontend nie osiągnął healthy"
    roll_back Frontend "$PREVIOUS_FRONTEND" "$SVC_FRONTEND"
  fi
else
  echo "Frontend ${FRONTEND_DECL} bez zmian — pomijam."
fi

# ---------- 4) CADDY — utrzymanie + reload (no-op gdy bez zmian) ----------
if [[ -n "$SVC_CADDY" ]]; then
  log "Caddy: up -d + reload"
  "${COMPOSE[@]}" up -d "$SVC_CADDY"
  "${COMPOSE[@]}" exec -T "$SVC_CADDY" caddy reload --config /etc/caddy/Caddyfile 2>/dev/null \
    || "${COMPOSE[@]}" up -d --force-recreate "$SVC_CADDY"
fi

docker image prune -f
log "Stan końcowy"; "${COMPOSE[@]}" ps
echo "deploy OK"
