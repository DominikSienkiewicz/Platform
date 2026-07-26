#!/usr/bin/env bash
# Test bloków python z bin/platform-bump.sh — nakładania pinów platformy i kanonu wersji
# na frontend/package.json, ze szczególnym uwzględnieniem sekcji `overrides`.
#
# Bloki są WYCINANE ze skryptu po markerach (`# platform-bump:pins` / `# platform-bump:canon`)
# i uruchamiane osobno — dzięki temu testujemy dokładnie ten kod, który leci w produkcji, bez
# odpalania całego platform-bump.sh (sieć, npm pack, Gradle). Markery to kontrakt: jeśli je
# usuniesz lub zmienisz terminator heredoca (`PY`), ten test przestanie znajdować kod i zafailuje.
#
# Regresja: przed tą zmianą blok kanonu iterował tylko po ("dependencies","devDependencies"),
# więc pin CVE w `overrides` nigdy nie był przepisywany przy ruchu kanonu.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/bin/platform-bump.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Wycina ciało heredoca od linii z markerem do terminatora `PY` (bez niego).
extract() { awk -v m="$1" 'index($0, m) { f = 1 } f && $0 == "PY" { exit } f' "$SRC"; }

extract '# platform-bump:pins'  > "$WORK/pins.py"
extract '# platform-bump:canon' > "$WORK/canon.py"
[[ -s "$WORK/pins.py" ]]  || { echo "FAIL: nie znaleziono bloku '# platform-bump:pins' w $SRC"; exit 1; }
[[ -s "$WORK/canon.py" ]] || { echo "FAIL: nie znaleziono bloku '# platform-bump:canon' w $SRC"; exit 1; }

cat > "$WORK/versions.json" <<'JSON'
{
  "versions": {
    "next": "16.2.12",
    "react": "19.2.7",
    "postcss": "8.5.18",
    "typescript": "6.0.3"
  }
}
JSON

fails=0
fail() { echo "FAIL: $1"; echo "--- package.json ---"; cat "$REPO/frontend/package.json"; fails=1; }

# Przygotowuje atrapę repo konsumenta i zwraca ścieżkę w globalnym REPO.
setup_repo() {
  REPO="$WORK/repo-$1"
  mkdir -p "$REPO/frontend"
  printf '%s\n' "$2" > "$REPO/frontend/package.json"
}

# Odczytuje wartość spod ścieżki kluczy w package.json (np. overrides next postcss).
value_at() { ( cd "$REPO" && python3 -c '
import json,sys
d=json.load(open("frontend/package.json"))
for k in sys.argv[1:]: d=d[k]
print(d)' "$@" ); }

# --- 1) Kanon: dryf w zagnieżdżonym override zostaje przepisany (przypadek postcss z Azimutha) ---
setup_repo canon-nested '{
  "dependencies": { "next": "16.2.7" },
  "devDependencies": { "typescript": "6.0.3" },
  "overrides": {
    "next": { "postcss": "8.5.15" },
    "openapi-typescript": { "typescript": "$typescript" }
  }
}'
OUT="$( cd "$REPO" && python3 "$WORK/canon.py" "$WORK/versions.json" )"
[[ "$(value_at overrides next postcss)" == "8.5.18" ]] || fail "overrides.next.postcss nie został nałożony z kanonu"
[[ "$(value_at overrides openapi-typescript typescript)" == '$typescript' ]] || fail "referencja \$typescript została nadpisana"
[[ "$(value_at dependencies next)" == "16.2.12" ]] || fail "regresja: zwykła zależność przestała być nakładana"
grep -q 'overrides.next.postcss' <<<"$OUT" || { echo "FAIL: raport zmian nie wymienia overrides.next.postcss"; echo "$OUT"; fails=1; }

# --- 2) Kanon: override płaski, głęboko zagnieżdżony i klucz "." ---
setup_repo canon-shapes '{
  "overrides": {
    "postcss": "8.5.15",
    "next": { "react": { "postcss": "8.5.15" } },
    "typescript": { ".": "5.0.0", "next": "16.2.7" }
  }
}'
( cd "$REPO" && python3 "$WORK/canon.py" "$WORK/versions.json" ) >/dev/null
[[ "$(value_at overrides postcss)" == "8.5.18" ]] || fail "płaski overrides.postcss nie został nałożony"
[[ "$(value_at overrides next react postcss)" == "8.5.18" ]] || fail "głęboko zagnieżdżony override nie został nałożony"
[[ "$(value_at overrides typescript .)" == "6.0.3" ]] || fail "klucz \".\" nie został zmapowany na paczkę rodzica"
[[ "$(value_at overrides typescript next)" == "16.2.12" ]] || fail "sąsiad klucza \".\" nie został nałożony"

# --- 3) Kanon: paczka spoza kanonu w overrides zostaje nietknięta (governance zgłasza to guard) ---
setup_repo canon-unknown '{
  "overrides": { "next": { "nieznana-paczka": "1.0.0" } }
}'
( cd "$REPO" && python3 "$WORK/canon.py" "$WORK/versions.json" ) >/dev/null
[[ "$(value_at overrides next nieznana-paczka)" == "1.0.0" ]] || fail "paczka spoza kanonu została zmieniona"

# --- 4) Kanon: brak sekcji overrides nie tworzy jej sztucznie ---
setup_repo canon-no-overrides '{
  "dependencies": { "next": "16.2.7" }
}'
( cd "$REPO" && python3 "$WORK/canon.py" "$WORK/versions.json" ) >/dev/null
if grep -q 'overrides' "$REPO/frontend/package.json"; then fail "pusta sekcja overrides została dopisana"; fi

# --- 5) Piny platformy: @dominiksienkiewicz/* w overrides też idą do wersji docelowej ---
setup_repo pins '{
  "devDependencies": { "@dominiksienkiewicz/versions": "1.5.4" },
  "overrides": {
    "next": { "@dominiksienkiewicz/ui": "1.5.4" },
    "@dominiksienkiewicz/query": "1.5.4",
    "react": "19.2.7"
  }
}'
( cd "$REPO" && python3 "$WORK/pins.py" 9.9.9 ) >/dev/null
[[ "$(value_at devDependencies @dominiksienkiewicz/versions)" == "9.9.9" ]] || fail "regresja: pin platformy w devDependencies nie został podbity"
[[ "$(value_at overrides next @dominiksienkiewicz/ui)" == "9.9.9" ]] || fail "pin platformy w zagnieżdżonym override nie został podbity"
[[ "$(value_at overrides @dominiksienkiewicz/query)" == "9.9.9" ]] || fail "pin platformy w płaskim override nie został podbity"
[[ "$(value_at overrides react)" == "19.2.7" ]] || fail "blok pinów ruszył paczkę spoza scope'u platformy"

[[ $fails -eq 0 ]] || exit 1
echo "OK: platform-bump nakłada piny platformy i kanon również na overrides (płaskie, zagnieżdżone, klucz \".\"), pomijając referencje \$name"
