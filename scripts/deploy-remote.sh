#!/usr/bin/env bash
# Deploy on-box — KANON Platform (wgrywany na boks i uruchamiany przez deploy.yml).
# Uniwersalny dla SkillSprintPlus i BookOfStyling:
#   • nazwy serwisów WYKRYWANE z `compose config --services` (SSP: skillsprintplus-*, BoS: gołe backend/db-migrate),
#   • kontenery przez `compose ps -q` (niezależne od container_name),
#   • baza env z `.env.prod` LUB `.env` (host), tagi warstw z `.env.deploy` (z CI),
#   • zmienne tagów obsłużone dwojako: BACKEND_TAG|BACKEND_VER, FRONTEND_TAG|FRONTEND_VER.
# Kolejność (warunkowo): migracje (bramka) -> backend (+worker) -> frontend -> caddy.
# Baza danych jest ZEWNĘTRZNA (osobny VPS) — tu tylko nanosimy migracje.
set -euo pipefail

[[ -f docker-compose.prod.yml ]] || { echo "BŁĄD: brak docker-compose.prod.yml w $(pwd)"; exit 1; }

# Baza zmiennych: preferuj .env.prod (SSP), w przeciwnym razie host .env (BoS).
if   [[ -f .env.prod ]]; then BASE_ENV=".env.prod"
elif [[ -f .env ]];      then BASE_ENV=".env"
else echo "BŁĄD: brak .env.prod ani .env w $(pwd)"; exit 1; fi

ENV_ARGS=(--env-file "$BASE_ENV")
[[ -f .env.deploy ]] && ENV_ARGS+=(--env-file .env.deploy)
COMPOSE=(docker compose "${ENV_ARGS[@]}" -f docker-compose.prod.yml)

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
  if [[ "$(health "$SVC_BACKEND")" != "none" ]]; then
    log "Czekam na healthy backendu"
    for _ in $(seq 1 40); do [[ "$(health "$SVC_BACKEND")" == "healthy" ]] && break; sleep 3; done
    [[ "$(health "$SVC_BACKEND")" == "healthy" ]] || { echo "Backend nie osiągnął healthy"; exit 1; }
  fi
else
  echo "Backend ${BACKEND_DECL} bez zmian — pomijam."
fi

# ---------- 3) FRONTEND — tylko gdy podbita wersja ----------
if [[ "$(running_tag "$SVC_FRONTEND")" != "$FRONTEND_DECL" ]]; then
  log "Frontend: ${FRONTEND_DECL:-<brak>} -> wymiana"
  "${COMPOSE[@]}" up -d --force-recreate --pull always "$SVC_FRONTEND"
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
