#!/usr/bin/env bash
# Test kroku "Check image is published" w reusable container-scan.yml.
#
# Kontekst (bug): cotygodniowy monitoring pullował :latest z GHCR bez sprawdzenia, czy obraz w ogóle
# został już opublikowany. Zanim ruszy PIERWSZY deploy (push do `release`), :latest nie istnieje —
# `docker pull` failuje z "manifest unknown", a cała bramka container-scan świeci na czerwono co
# poniedziałek. Fix: preflight `docker manifest inspect` klasyfikuje obraz na present/absent i
# traktuje realny brak manifestu jako czysty SKIP (nie failure), ale KAŻDY inny błąd (auth, rate-limit)
# nadal failuje — żeby nie maskować zepsutego deployu.
#
# Test jest hermetyczny: WYCINA prawdziwy blok klasyfikatora z YAML-a (między sentinelami
# `# >>> classify-image-presence` / `# <<< classify-image-presence`) i uruchamia go pod atrapą
# `docker`. Dzięki temu testujemy dokładnie ten kod, który jedzie w CI (zero driftu kopii).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
YAML="$ROOT/.github/workflows/container-scan.yml"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { local message="$1"; echo "FAIL: $message"; exit 1; }

# --- Wytnij blok klasyfikatora z YAML-a (wcięcie z bloku `run:` jest nieszkodliwe dla basha) ---
CLASSIFY="$WORK/classify.sh"
awk '/# >>> classify-image-presence/{f=1;next} /# <<< classify-image-presence/{f=0} f' "$YAML" > "$CLASSIFY"
[[ -s "$CLASSIFY" ]] \
  || fail "nie znaleziono bloku klasyfikatora (sentinele classify-image-presence) w $YAML"

# --- Atrapa `docker`: tryb sterowany przez FAKE_DOCKER_MODE (ok|notfound|auth) ---
mkdir -p "$WORK/bin"
cat > "$WORK/bin/docker" <<'EOF'
#!/usr/bin/env bash
# Obsługuje tylko `docker manifest inspect <img>` — reszta wywołań to błąd testu.
[ "$1" = "manifest" ] && [ "$2" = "inspect" ] || { echo "unexpected docker call: $*" >&2; exit 99; }
case "${FAKE_DOCKER_MODE:-}" in
  ok)       echo '{"schemaVersion":2}'; exit 0 ;;
  notfound) echo "$3: manifest unknown" >&2; exit 1 ;;
  auth)     echo "unauthorized: authentication required" >&2; exit 1 ;;
  *)        echo "FAKE_DOCKER_MODE nieustawiony" >&2; exit 98 ;;
esac
EOF
chmod +x "$WORK/bin/docker"

run_classifier() { # $1=mode  -> ustawia globalne: RC, OUTFILE
  OUTFILE="$WORK/gh_output"; : > "$OUTFILE"
  PATH="$WORK/bin:$PATH" FAKE_DOCKER_MODE="$1" IMAGE="ghcr.io/o/app-backend:latest" \
    GITHUB_OUTPUT="$OUTFILE" bash "$CLASSIFY" >/dev/null 2>&1
  RC=$?
}

# --- 1) Obraz opublikowany -> present=true, exit 0 ---
run_classifier ok
[[ "$RC" -eq 0 ]] || fail "present: oczekiwano exit 0, było $RC"
grep -qx 'present=true' "$OUTFILE" || fail "present: brak 'present=true' w GITHUB_OUTPUT"

# --- 2) Obraz jeszcze nieopublikowany (manifest unknown) -> czysty SKIP: present=false, exit 0 ---
run_classifier notfound
[[ "$RC" -eq 0 ]] || fail "notfound: brak obrazu ma być SKIP-em (exit 0), było $RC"
grep -qx 'present=false' "$OUTFILE" || fail "notfound: brak 'present=false' w GITHUB_OUTPUT"

# --- 3) Błąd auth (NIE brak manifestu) -> twardy fail, żeby nie maskować zepsutego deployu ---
run_classifier auth
[[ "$RC" -ne 0 ]] || fail "auth: błąd inny niż brak manifestu musi failować (exit != 0), było $RC"

echo "OK: preflight klasyfikuje present/absent, skipuje nieopublikowane, failuje na realnych błędach"
