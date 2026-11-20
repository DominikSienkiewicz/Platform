#!/usr/bin/env bash
# templates/Dockerfile.backend, case by case: the healthcheck, JVM flags and non-root user (the probe runs against a stub
# HTTP server), and the Boot layers with the opt-in AOT cache.
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- healthcheck-and-user ---
# dockerfile-backend.test.sh — kontrakt obrazu z templates/Dockerfile.backend: HEALTHCHECK, flagi JVM i użytkownik
# bez roota, a sonda HEALTHCHECK uruchomiona naprawdę przeciw stubowi HTTP (bez Dockera, bez obrazu).
(
here=$(cd "$(dirname "$0")" && pwd)
dockerfile="$here/../Dockerfile.backend"
work=$(mktemp -d)
server_pid=""
cleanup() {
  [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

grep -qE '^HEALTHCHECK --start-period=60s --interval=10s --timeout=3s --retries=6 ' "$dockerfile" \
  || fail "HEALTHCHECK must give the application 60 s to start and probe every 10 s, 6 times"
grep -qE '^ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:\+ExitOnOutOfMemoryError"$' "$dockerfile" \
  || fail "JAVA_TOOL_OPTIONS must size the heap from the container limit and exit on OutOfMemoryError"
last_user=$(sed -n -E 's/^USER[[:space:]]+([^[:space:]]+).*/\1/p' "$dockerfile" | tail -1)
[[ -n "$last_user" && "$last_user" != root && "$last_user" != 0 ]] || fail "the image must run as a non-root USER"
[[ $(grep -n '^USER ' "$dockerfile" | tail -1 | cut -d: -f1) -lt $(grep -n '^ENTRYPOINT ' "$dockerfile" | cut -d: -f1) ]] \
  || fail "USER must come before ENTRYPOINT"

# Argumenty sondy dokładnie tak, jak Docker czyta formę exec (tablica JSON po złączeniu kontynuacji wiersza).
python3 -I - "$dockerfile" "$work/probe" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read().replace("\\\n", " ")
match = re.search(r"^HEALTHCHECK .*?CMD (\[.*\])\s*$", text, re.M)
if not match:
    sys.exit("FAIL: HEALTHCHECK uses the exec form CMD [...]")
argv = json.loads(match.group(1))
if argv[:2] != ["bash", "-c"] or len(argv) != 3:
    sys.exit("FAIL: HEALTHCHECK runs bash -c <probe>")
if "/actuator/health/liveness" not in argv[2]:
    sys.exit("FAIL: the probe targets /actuator/health/liveness")
open(sys.argv[2], "w").write(argv[2])
PY

# Stub odpowiada kodem z pliku <ścieżka bez /> albo 404; port wypisuje do pliku, gdy już słucha.
cat > "$work/stub.py" <<'PY'
import http.server, os, sys
root = sys.argv[1]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = os.path.join(root, self.path.strip("/").replace("/", "_"))
        code = int(open(path).read()) if os.path.exists(path) else 404
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(os.path.join(root, "port.tmp"), "w") as port:
    port.write(str(server.server_address[1]))
os.rename(os.path.join(root, "port.tmp"), os.path.join(root, "port"))
server.serve_forever()
PY
mkdir "$work/codes"
python3 -I "$work/stub.py" "$work/codes" &
server_pid=$!
for _ in $(seq 1 50); do [[ -f "$work/codes/port" ]] && break; sleep 0.1; done
port=$(cat "$work/codes/port")

# expect <oczekiwany wynik> <liveness> <health> <opis>; "-" = brak endpointu (404 stubu).
expect() {
  local want=$1 liveness=$2 health=$3 label=$4 got
  rm -f "$work/codes/actuator_health_liveness" "$work/codes/actuator_health"
  [[ "$liveness" == - ]] || echo "$liveness" > "$work/codes/actuator_health_liveness"
  [[ "$health" == - ]] || echo "$health" > "$work/codes/actuator_health"
  if env -i PATH="$PATH" SERVER_PORT="$port" bash -c "$(cat "$work/probe")"; then got=healthy; else got=unhealthy; fi
  [[ "$got" == "$want" ]] || fail "$label: the probe reported $got, expected $want"
}
expect healthy 200 503 "liveness UP"
expect unhealthy 503 200 "liveness DOWN"
expect healthy - 200 "probes disabled, health UP"
expect unhealthy - 503 "probes disabled, health DOWN"
expect unhealthy - - "no actuator"

rm -f "$work/codes/actuator_health_liveness"
echo 200 > "$work/codes/actuator_health_liveness"
env -i PATH="$PATH" MANAGEMENT_SERVER_PORT="$port" SERVER_PORT=1 bash -c "$(cat "$work/probe")" \
  || fail "MANAGEMENT_SERVER_PORT must take precedence over SERVER_PORT"

kill "$server_pid"; wait "$server_pid" 2>/dev/null || true; server_pid=""
if env -i PATH="$PATH" SERVER_PORT="$port" bash -c "$(cat "$work/probe")"; then fail "no server: the probe reported healthy"; fi
status=0; env -i PATH="$PATH" SERVER_PORT="$port" bash -c "$(cat "$work/probe")" || status=$?
[[ $status -eq 1 ]] || fail "no server: the probe must exit 1 (Docker reserves 2), got $status"

echo "OK: Dockerfile.backend declares the healthcheck, JVM flags and a non-root user, and its probe answers as expected"
)

# --- layers ---
# Warstwy obrazu z templates/Dockerfile.backend (N-CAP-5): ekstrakcja jara Boota w etapie `layers`, jeden COPY na
# warstwę w kolejności od najrzadziej zmienianej, launcher Boota zamiast `java -jar`, a opcjonalny cache AOT przez
# plik argumentów, pusty domyślnie. Ostatni FROM zostaje obrazem JRE (platformRuntimeImageCheck, PD060).
(
dockerfile="$(cd "$(dirname "$0")/.." && pwd)/Dockerfile.backend"
grep -qE '^FROM sapmachine:[0-9]+-jre AS layers$' "$dockerfile" || fail 'the layers stage extracts on the runtime JRE'
grep -qF 'RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination extracted' "$dockerfile" \
  || fail 'the jar is extracted into its Boot layers with the launcher'
copies=$(sed -n -E 's#^COPY --from=layers /build/extracted/([a-z-]+)/ \./$#\1#p' "$dockerfile" | paste -sd' ' -)
[[ "$copies" == "dependencies spring-boot-loader snapshot-dependencies application" ]] \
  || fail "one COPY per Boot layer, least changing first (got: $copies)"
grep -qxF 'ARG AOT_CACHE=false' "$dockerfile" || fail 'the AOT cache is opt-in'
grep -qF 'java -XX:AOTCacheOutput=/app/app.aot -Dspring.context.exit=onRefresh' "$dockerfile" || fail 'the AOT cache is trained by one context refresh'
grep -qF 'else : > /app/jvm.args; fi' "$dockerfile" || fail 'without the AOT cache the argument file is empty'
grep -qxF 'ENTRYPOINT ["java", "@/app/jvm.args", "org.springframework.boot.loader.launch.JarLauncher"]' "$dockerfile" \
  || fail 'the entrypoint starts the Boot launcher with the argument file'
[[ "$(sed -n -E 's/^FROM[[:space:]]+([^[:space:]]+).*/\1/p' "$dockerfile" | tail -1)" =~ ^sapmachine:[0-9]+-jre$ ]] \
  || fail 'the final FROM stays the JRE image the runtime image gate reads'
echo 'OK: Dockerfile.backend copies each Boot layer once and makes the AOT cache opt-in'
)
