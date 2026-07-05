#!/usr/bin/env bash
# platform-bump.sh — cienki STUB: deleguje do binu `platform-bump` pakietu @dominiksienkiewicz/versions.
# KANON LOGIKI bumpu żyje w Platform/frontend/packages/versions/bin/platform-bump.sh i dociera tu
# przez npm (frontend/node_modules/.bin) — NIE wklejaj logiki do tego pliku ani do kopii per-repo.
# CANON: to jest kanon stuba (Platform/templates/platform-bump.sh) — kopiowany do roota każdego repo.
#
# Użycie (jak dotąd):
#   ./platform-bump.sh            # podbij do najnowszej
#   ./platform-bump.sh 1.3.0      # podbij do konkretnej wersji
set -euo pipefail

# Stub żyje w roocie repo konsumenta — operuj ZAWSZE tam, niezależnie skąd wywołano
# (bin dziedziczy CWD i przez `git rev-parse --show-toplevel` trafia we właściwe repo).
cd "$(dirname "$0")"

BIN="frontend/node_modules/.bin/platform-bump"
if [[ ! -x "$BIN" ]]; then
  echo "Brak $BIN — zainstaluj zależności frontendu: (cd frontend && npm install)." >&2
  echo "Bin istnieje od @dominiksienkiewicz/versions 1.3.8 — starszy pin w frontend/package.json" >&2
  echo "podbij ręcznie do najnowszej wersji platformy i powtórz npm install." >&2
  exit 1
fi
exec "$BIN" "$@"
