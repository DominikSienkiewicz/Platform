#!/usr/bin/env bash
# Test guardu `platform-versions-check` (bin/check.mjs) — governance sekcji `overrides`.
#
# Hermetyczny: budujemy atrapę zainstalowanej paczki (bin/check.mjs + własny versions.json)
# w tmp i odpalamy ją z CWD ustawionym na atrapę repo konsumenta. Żadnego npm ani sieci.
#
# Regresja: przed tą zmianą `declared` powstawało wyłącznie z dependencies+devDependencies,
# więc pin CVE trzymany w `overrides` (np. overrides.next.postcss) nigdy nie był walidowany
# względem kanonu i dryfował po cichu.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/bin/check.mjs"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PKG="$WORK/versions"
mkdir -p "$PKG/bin"
cp "$SRC" "$PKG/bin/check.mjs"
cat > "$PKG/versions.json" <<'JSON'
{
  "versions": {
    "next": "16.2.12",
    "react": "19.2.7",
    "postcss": "8.5.18",
    "typescript": "6.0.3",
    "sharp": "0.35.0"
  }
}
JSON

fails=0

# Odpala guard na podanym package.json; ustawia globalne RC i OUT.
run_case() {
  local name="$1" json="$2"
  local dir="$WORK/case-$name"
  mkdir -p "$dir"
  printf '%s\n' "$json" > "$dir/package.json"
  RC=0
  OUT="$( ( cd "$dir" && node "$PKG/bin/check.mjs" ) 2>&1 )" || RC=$?
}

fail() { local message="$1"; echo "FAIL: $message"; echo "--- wyjście ---"; echo "$OUT"; fails=1; }

# --- 1) Baseline: same dependencies zgodne z kanonem -> zielono (brak fałszywych alarmów) ---
run_case baseline '{
  "dependencies": { "next": "16.2.12", "react": "19.2.7" },
  "devDependencies": { "typescript": "6.0.3" }
}'
[[ $RC -eq 0 ]] || fail "czyste dependencies powinny przejść (exit $RC)"

# --- 2) Dryf w zagnieżdżonym override (przypadek postcss z Azimutha) -> czerwono + lokalizacja ---
run_case nested-drift '{
  "dependencies": { "next": "16.2.12" },
  "overrides": { "next": { "postcss": "8.5.15" } }
}'
[[ $RC -ne 0 ]] || fail "dryf w overrides.next.postcss powinien failować build"
grep -q 'overrides.next.postcss' <<<"$OUT" || fail "komunikat nie wskazuje ścieżki overrides.next.postcss"
grep -q '8.5.18' <<<"$OUT" || fail "komunikat nie podaje wersji z kanonu"

# --- 3) Override płaski (string) też jest walidowany ---
run_case flat-drift '{
  "overrides": { "postcss": "8.5.15" }
}'
[[ $RC -ne 0 ]] || fail "dryf w płaskim overrides.postcss powinien failować build"
grep -q 'overrides.postcss' <<<"$OUT" || fail "komunikat nie wskazuje ścieżki overrides.postcss"

# --- 4) Override zgodny z kanonem -> zielono ---
run_case nested-ok '{
  "dependencies": { "next": "16.2.12" },
  "overrides": { "next": { "postcss": "8.5.18" } }
}'
[[ $RC -eq 0 ]] || fail "override zgodny z kanonem nie powinien failować (exit $RC)"

# --- 5) Referencja npm "$name" NIE jest dryfem ani brakiem wpisu (npm rozwija ją sam) ---
run_case ref '{
  "devDependencies": { "typescript": "6.0.3" },
  "overrides": { "openapi-typescript": { "typescript": "$typescript" } }
}'
[[ $RC -eq 0 ]] || fail "referencja \$typescript nie powinna być zgłaszana (exit $RC)"

# --- 6) Override bez wpisu w kanonie = twardy błąd (jak zależność bezpośrednia) ---
run_case missing '{
  "overrides": { "next": { "nieznana-paczka": "1.0.0" } }
}'
[[ $RC -ne 0 ]] || fail "override spoza kanonu powinien failować build"
grep -q 'nieznana-paczka' <<<"$OUT" || fail "komunikat nie wymienia paczki spoza kanonu"
grep -q 'BEZ wpisu w kanonie' <<<"$OUT" || fail "override spoza kanonu zgłoszony jako dryf zamiast braku wpisu"

# --- 7) Pin platformy (@dominiksienkiewicz/*) w overrides jest poza governance kanonu ---
run_case platform-scope '{
  "overrides": { "@dominiksienkiewicz/ui": "1.5.14" }
}'
[[ $RC -eq 0 ]] || fail "pin platformy w overrides nie podlega kanonowi (exit $RC)"

# --- 8) Głębokie zagnieżdżenie (overrides.a.b.c) też jest przechodzone ---
run_case deep '{
  "overrides": { "next": { "react": { "postcss": "8.5.15" } } }
}'
[[ $RC -ne 0 ]] || fail "dryf w overrides.next.react.postcss powinien failować build"
grep -q 'overrides.next.react.postcss' <<<"$OUT" || fail "komunikat nie wskazuje pełnej ścieżki zagnieżdżenia"

# --- 9) Klucz "." (npm: sama paczka nadrzędna) mapuje się na paczkę rodzica ---
run_case self-key '{
  "overrides": { "postcss": { ".": "8.5.15", "nano": "1.0.0" } }
}'
[[ $RC -ne 0 ]] || fail "dryf pod kluczem \".\" powinien failować build"
grep -q 'postcss.*8.5.15' <<<"$OUT" || fail "klucz \".\" nie został zmapowany na paczkę rodzica"

[[ $fails -eq 0 ]] || exit 1
echo "OK: guard kanonu waliduje overrides (płaskie, zagnieżdżone, klucz \".\") i pomija referencje \$name oraz piny platformy"
