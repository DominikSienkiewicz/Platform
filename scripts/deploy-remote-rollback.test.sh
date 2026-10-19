#!/usr/bin/env bash
# Rollback w deploy-remote.sh na stanowej atrapie `docker`: atrapa pamięta tag każdego serwisu z ostatniego `up`
# (z ostatniego --env-file, który go ustawia), a healthy zwraca tylko dla tagów z FAKE_HEALTHY_TAGS. Nowy backend,
# który nie osiąga healthy, wraca do poprzedniego tagu z lokalnego obrazu, a deploy kończy się kodem 1.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$box/out.txt" >&2 2>/dev/null; exit 1; }

mkdir -p "$tmp/bin"
cat > "$tmp/bin/docker" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
args=("$@")
tag_from() { # ostatni --env-file ustawiający <zmienną> wygrywa, jak w compose
  local variable=$1 value="" i
  for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[$i]}" == --env-file ]]; then
      line=$(grep -E "^$variable=" "${args[$((i + 1))]}" 2>/dev/null | tail -1 || true)
      [[ -n "$line" ]] && value=${line#*=}
    fi
  done
  printf '%s' "$value"
}
if [[ "${1:-}" == compose ]]; then
  i=1
  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in --env-file | -f | --profile) i=$((i + 2)) ;; *) break ;; esac
  done
  sub="${args[$i]:-}"
  rest=("${args[@]:$((i + 1))}")
  case "$sub" in
    config) tr ' ' '\n' <<<"$FAKE_SERVICES" ;;
    run) [[ "${rest[2]:-}" == status ]] && echo "Liquibase: app@db is up to date" ;;
    ps) [[ "${rest[0]:-}" == -q ]] && echo "cid-${rest[1]}" ;;
    up)
      for service in "${rest[@]}"; do
        case "$service" in
          backend) tag_from BACKEND_TAG > "$FAKE_STATE/backend" ;;
          frontend) tag_from FRONTEND_TAG > "$FAKE_STATE/frontend" ;;
        esac
      done
      ;;
  esac
  exit 0
fi
if [[ "${1:-}" == inspect ]]; then
  service=${4#cid-}
  tag=$(cat "$FAKE_STATE/$service" 2>/dev/null || true)
  case "$3" in
    *Config.Image*) [[ -n "$tag" ]] && echo "ghcr.io/x/$service:$tag" ;;
    *Health*)
      if [[ "$service" == frontend && -z "${FAKE_FRONTEND_HEALTHCHECK:-}" ]]; then echo none
      elif [[ " $FAKE_HEALTHY_TAGS " == *" $service:$tag "* ]]; then echo healthy
      else echo unhealthy; fi
      ;;
  esac
fi
exit 0
FAKE
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/sleep"
chmod +x "$tmp/bin/docker" "$tmp/bin/sleep"

# deploy <case> <running backend> <running frontend>: boks z działającymi tagami i .env.deploy na 2.0.0
deploy() {
  box="$tmp/$1"
  mkdir -p "$box/state"
  : > "$box/docker-compose.prod.yml"
  : > "$box/.env.prod"
  printf 'BACKEND_TAG=2.0.0\nFRONTEND_TAG=2.0.0\n' > "$box/.env.deploy"
  [[ -z "$2" ]] || printf '%s' "$2" > "$box/state/backend"
  [[ -z "$3" ]] || printf '%s' "$3" > "$box/state/frontend"
  set +e
  (cd "$box" && PATH="$tmp/bin:$PATH" FAKE_LOG="$box/docker.log" FAKE_STATE="$box/state" \
    FAKE_SERVICES="db-migrate backend frontend caddy" bash "$here/deploy-remote.sh" > "$box/out.txt" 2>&1)
  rc=$?
  set -e
}

# (a) nowy backend nie osiąga healthy: wraca 1.9.0, deploy = 1, frontend i caddy nietknięte
FAKE_HEALTHY_TAGS="backend:1.9.0" deploy backend 1.9.0 1.9.0
[[ $rc -eq 1 ]] || fail "(a) a rolled-back deploy must exit 1, got $rc"
grep -qF 'ROLLED BACK to 1.9.0: Backend runs its previous version again.' "$box/out.txt" || fail '(a) the rollback must be reported'
[[ "$(cat "$box/state/backend")" == 1.9.0 ]] || fail '(a) the backend must run the previous tag again'
grep -qF -- '--env-file .env.deploy.previous -f docker-compose.prod.yml up -d --force-recreate --pull never backend' "$box/docker.log" \
  || fail '(a) the rollback must recreate the backend from the local image with the previous tags'
[[ "$(cat "$box/state/frontend")" == 1.9.0 ]] || fail '(a) the frontend must stay on its version'
if grep -qF 'caddy reload' "$box/docker.log"; then fail '(a) caddy must not reload after a rollback'; fi
grep -qx 'BACKEND_TAG=1.9.0' "$box/.env.deploy.previous" || fail '(a) the previous tags must be written before the swap'

# (b) poprzednia wersja też nie wstaje: dalej 1, z komunikatem do logów
FAKE_HEALTHY_TAGS="" deploy both-down 1.9.0 1.9.0
[[ $rc -eq 1 ]] || fail "(b) a failed rollback must exit 1, got $rc"
grep -qF 'Rollback do 1.9.0 też nie osiągnął healthy' "$box/out.txt" || fail '(b) a failed rollback must say so'

# (c) pierwszy deploy bez poprzedniej wersji: nie ma do czego wracać
FAKE_HEALTHY_TAGS="" deploy first "" ""
[[ $rc -eq 1 ]] || fail "(c) a first deploy that never gets healthy must exit 1, got $rc"
grep -qF 'nie ma poprzedniej wersji do przywrócenia' "$box/out.txt" || fail '(c) a first deploy has nothing to roll back to'

# (d) frontend z healthcheckiem, który nie wstaje, też wraca
FAKE_FRONTEND_HEALTHCHECK=1 FAKE_HEALTHY_TAGS="backend:2.0.0 frontend:1.9.0" deploy frontend 1.9.0 1.9.0
[[ $rc -eq 1 ]] || fail "(d) a rolled-back frontend must exit 1, got $rc"
grep -qF 'ROLLED BACK to 1.9.0: Frontend runs its previous version again.' "$box/out.txt" || fail '(d) the frontend rollback must be reported'
[[ "$(cat "$box/state/backend")" == 2.0.0 ]] || fail '(d) the healthy new backend stays'

# (e) wszystko zdrowe: deploy OK bez rollbacku
FAKE_FRONTEND_HEALTHCHECK=1 FAKE_HEALTHY_TAGS="backend:2.0.0 frontend:2.0.0" deploy healthy 1.9.0 1.9.0
[[ $rc -eq 0 ]] || fail "(e) a healthy deploy must succeed, got $rc"
if grep -qF '.env.deploy.previous -f docker-compose.prod.yml up' "$box/docker.log"; then fail '(e) a healthy deploy must not roll back'; fi

echo 'OK: deploy-remote rolls an unhealthy backend or frontend back to the previous tag and exits 1'
