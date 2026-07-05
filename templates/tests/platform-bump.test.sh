#!/usr/bin/env bash
# Test template'u platform-bump.sh (kanon: Platform/templates/platform-bump.sh).
#
# Po migracji na model stub+bin: templates/platform-bump.sh to CIENKI STUB, który deleguje
# do binu `platform-bump` pakietu @dominiksienkiewicz/versions (frontend/node_modules/.bin).
# Logika bumpu (Maven catalog + gradle.lockfile + npm) żyje w binie — tu testujemy WYŁĄCZNIE
# kontrakt stuba. Hermetyczny (bez npm/sieci): fake-bin nagrywa argumenty.
#
# Regresja (zachowana z poprzedniej wersji): wywołany SPOZA roota repo skrypt musi operować na
# repo, w którym LEŻY (stub robi `cd "$(dirname "$0")"`), a nie w CWD wywołania.
set -euo pipefail

CANON="$(cd "$(dirname "$0")/.." && pwd)/platform-bump.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- 1) Brak binu -> exit != 0 + komunikat wskazujący brakujący bin ---
REPO1="$WORK/no-bin"
mkdir -p "$REPO1"
cp "$CANON" "$REPO1/platform-bump.sh"; chmod +x "$REPO1/platform-bump.sh"
rc=0
out="$( ( cd "$WORK" && "$REPO1/platform-bump.sh" 1.2.3 ) 2>&1 )" || rc=$?
[[ $rc -ne 0 ]] \
  || { echo "FAIL: brak binu powinien dać exit != 0"; exit 1; }
grep -q 'node_modules/.bin/platform-bump' <<<"$out" \
  || { echo "FAIL: komunikat nie wskazuje brakującego binu"; exit 1; }

# --- 2) Bin obecny -> delegacja + passthrough argumentu + exit 0 (wywołany spoza roota) ---
# Fake-bin zapisuje argumenty do bump-args.txt względem CWD; stub cd-uje do swojego roota PRZED exec,
# więc plik ląduje w REPO2 — to zarazem dowód regresji "operuj na repo skryptu".
REPO2="$WORK/with-bin"
mkdir -p "$REPO2/frontend/node_modules/.bin"
BIN="$REPO2/frontend/node_modules/.bin/platform-bump"
cat > "$BIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > bump-args.txt
exit 0
EOF
chmod +x "$BIN"
cp "$CANON" "$REPO2/platform-bump.sh"; chmod +x "$REPO2/platform-bump.sh"
rc=0
( cd "$WORK" && "$REPO2/platform-bump.sh" 9.9.9 ) >/dev/null 2>&1 || rc=$?
[[ $rc -eq 0 ]] \
  || { echo "FAIL: obecny bin -> oczekiwano exit 0, było $rc"; exit 1; }
grep -qx '9.9.9' "$REPO2/bump-args.txt" \
  || { echo "FAIL: argument nie przekazany do binu lub stub nie cd-nął do roota repo"; exit 1; }

echo "OK: stub deleguje do binu, przekazuje argumenty i failuje czytelnie bez binu"
