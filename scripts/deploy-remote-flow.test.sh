#!/usr/bin/env bash
# Przepływ produkcyjny deploy-remote.sh na atrapach `docker` i `sleep`: bramka migracji przed warstwami app,
# pominięcie niezmienionego backendu, stop po nieudanym update i po backendzie, który nie osiąga healthy.
# Atrapa loguje każde wywołanie; odpowiedzi sterują zmienne FAKE_*.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/bin"
cat > "$tmp/bin/docker" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
args=("$@")
if [[ "${1:-}" == compose ]]; then
  i=1
  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      --env-file | -f | --profile) i=$((i + 2)) ;;
      *) break ;;
    esac
  done
  sub="${args[$i]:-}"
  rest=("${args[@]:$((i + 1))}")
  case "$sub" in
    config) tr ' ' '\n' <<<"$FAKE_SERVICES" ;;
    run)
      case "${rest[2]:-}" in
        status) printf '%s\n' "$FAKE_STATUS_OUT" ;;
        update) exit "${FAKE_UPDATE_RC:-0}" ;;
      esac
      ;;
    ps) [[ "${rest[0]:-}" == -q ]] && echo "cid-${rest[1]}" ;;
  esac
  exit 0
fi
if [[ "${1:-}" == inspect ]]; then
  case "$3" in
    *Config.Image*)
      case "$4" in
        cid-backend) echo "${FAKE_BACKEND_IMAGE:-ghcr.io/x/backend:0.0.1}" ;;
        cid-frontend) echo "${FAKE_FRONTEND_IMAGE:-ghcr.io/x/frontend:0.0.1}" ;;
      esac
      ;;
    *Health*) if [[ "$4" == cid-backend ]]; then echo "${FAKE_HEALTH:-healthy}"; else echo none; fi ;;
  esac
fi
exit 0
FAKE
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/sleep"
chmod +x "$tmp/bin/docker" "$tmp/bin/sleep"

# deploy <case>: uruchamia deploy-remote.sh w świeżym katalogu boksa; zostawia log i kod wyjścia.
deploy() {
  local box="$tmp/$1"
  mkdir -p "$box"
  : > "$box/docker-compose.prod.yml"
  : > "$box/.env.prod"
  printf 'BACKEND_TAG=1.2.3\nFRONTEND_TAG=1.2.3\n' > "$box/.env.deploy"
  log="$box/docker.log"
  : > "$log"
  set +e
  (cd "$box" && PATH="$tmp/bin:$PATH" FAKE_LOG="$log" FAKE_SERVICES="db-migrate backend frontend caddy" \
    bash "$here/deploy-remote.sh" > "$box/out.txt" 2>&1)
  rc=$?
  set -e
}

line_of() { grep -n -F -- "$2" "$1" | head -1 | cut -d: -f1; }

export FAKE_STATUS_OUT="1 changesets have not been applied to app@db"
deploy pending
[[ $rc -eq 0 ]] || fail "(a) a pending migration must deploy: $(cat "$tmp/pending/out.txt")"
update=$(line_of "$log" "run --rm db-migrate update")
first_up=$(line_of "$log" " up -d")
[[ -n "$update" && -n "$first_up" && "$update" -lt "$first_up" ]] || fail "(a) update must run before the first up -d"

export FAKE_STATUS_OUT="Liquibase: app@db is up to date"
deploy uptodate
[[ $rc -eq 0 ]] || fail "(b) an up-to-date database must deploy"
if grep -qF -- "db-migrate update" "$log"; then fail "(b) an up-to-date database must not run update"; fi

export FAKE_STATUS_OUT="Unexpected Liquibase output"
deploy ambiguous
grep -qF -- "run --rm db-migrate update" "$log" || fail "(ambiguous) an unclear status must run update"

export FAKE_STATUS_OUT="1 changesets have not been applied to app@db" FAKE_UPDATE_RC=1
deploy failedupdate
[[ $rc -ne 0 ]] || fail "(c) a failed update must fail the deploy"
if grep -qF -- " up -d" "$log"; then fail "(c) a failed update must leave every application layer untouched"; fi
unset FAKE_UPDATE_RC

export FAKE_STATUS_OUT="Liquibase: app@db is up to date" FAKE_BACKEND_IMAGE="ghcr.io/x/backend:1.2.3"
deploy samebackend
[[ $rc -eq 0 ]] || fail "(d) an unchanged backend must deploy"
if grep -qE -- " up -d .* backend( |$)" "$log"; then fail "(d) an unchanged backend tag must not recreate the backend"; fi
grep -qE -- " up -d .* frontend$" "$log" || fail "(d) a changed frontend tag must still recreate the frontend"
unset FAKE_BACKEND_IMAGE

export FAKE_HEALTH=starting
deploy unhealthy
[[ $rc -ne 0 ]] || fail "(e) a backend that never gets healthy must fail the deploy"
grep -qF "Backend nie osiągnął healthy" "$tmp/unhealthy/out.txt" || fail "(e) the failure must name the unhealthy backend"
if grep -qE -- " up -d .* frontend$" "$log"; then fail "(e) the frontend must not start in front of an unhealthy backend"; fi
if grep -qF -- "caddy reload" "$log"; then fail "(e) caddy must not reload after an unhealthy backend"; fi
unset FAKE_HEALTH

echo 'OK: deploy-remote migrates first, skips unchanged layers and stops on a failed migration or an unhealthy backend'
