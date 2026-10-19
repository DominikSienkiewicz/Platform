#!/usr/bin/env bash
# Profil observability w infra/docker-compose.yml (N-CAP-4): cztery serwisy tylko w tym profilu, każdy montowany
# plik konfiguracji istnieje, a domyślne `docker compose up` dalej startuje samego PostgreSQL. Z Dockerem w PATH
# compose musi też przejść `config` z profilem.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compose="$root/infra/docker-compose.yml"
fail() { echo "FAIL: $*" >&2; exit 1; }
for service in otel-collector tempo prometheus grafana; do
  block=$(awk -v name="  $service:" '$0 == name { inside = 1; print; next } inside && /^  [a-z]/ { exit } inside' "$compose")
  [[ -n "$block" ]] || fail "infra/docker-compose.yml must define $service"
  grep -qF 'profiles: ["observability"]' <<<"$block" || fail "$service must run only with the observability profile"
  while IFS= read -r mount; do
    [[ -e "$root/infra/$mount" ]] || fail "$service mounts infra/$mount, which does not exist"
  done < <(sed -n -E 's#^ *- \./([^:]+):.*#\1#p' <<<"$block")
done
default_services=$(awk '/^services:/ { inside = 1; next } /^volumes:/ { inside = 0 } inside && /^  [a-z]/ { name = $1 } inside && /profiles:/ { profiled[name] = 1 } inside && /^  [a-z]/ { names[++count] = $1 } END { for (i = 1; i <= count; i++) if (!profiled[names[i]]) print names[i] }' "$compose" | paste -sd' ' -)
[[ "$default_services" == "postgres:" ]] || fail "a plain docker compose up must start only postgres (got: $default_services)"
if command -v docker > /dev/null 2>&1 && docker compose version > /dev/null 2>&1; then
  docker compose -f "$compose" --profile observability config -q || fail 'the observability profile must be valid compose'
fi
echo 'OK: the observability profile of infra/docker-compose.yml is opt-in and every mounted config exists'
