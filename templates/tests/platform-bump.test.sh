#!/usr/bin/env bash
# Test template'u platform-bump.sh (kanon: Platform/templates/platform-bump.sh).
#
# Regresja: bez `cd "$(dirname "$0")"` skrypt wywołany SPOZA roota repo konsumenta
# po cichu no-opował — guardy `[[ -f backend/... ]]` patrzyły w CWD wywołania,
# a końcowy `git diff --stat` działał w obcym katalogu zamiast w repo skryptu.
#
# Scenariusz: kopia kanonu w roocie fake-repo konsumenta, wywołana z innego katalogu,
# musi podbić piny w repo, w którym leży. Hermetyczny: TARGET podany jawnie (bez sieci),
# gradlew to stub (regen locków nie jest przedmiotem testu).
set -euo pipefail

CANON="$(cd "$(dirname "$0")/.." && pwd)/platform-bump.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/consumer"
mkdir -p "$REPO/backend"
cat > "$REPO/backend/settings.gradle.kts" <<'EOF'
plugins { id("seniordev.settings-conventions") version "1.0.0" }
dependencyResolutionManagement {
  versionCatalogs { create("libs") { from("pl.seniordeveloper:platform-catalog:1.0.0") } }
}
EOF
printf '#!/bin/sh\nexit 0\n' > "$REPO/backend/gradlew"
chmod +x "$REPO/backend/gradlew"

cp "$CANON" "$REPO/platform-bump.sh"
chmod +x "$REPO/platform-bump.sh"

git -C "$REPO" init -q
git -C "$REPO" -c user.email=test@test -c user.name=test add -A
git -C "$REPO" -c user.email=test@test -c user.name=test commit -qm init

mkdir "$REPO-elsewhere"
rc=0
( cd "$REPO-elsewhere" && GPR_TOKEN=dummy "$REPO/platform-bump.sh" 9.9.9 ) >/dev/null 2>&1 || rc=$?

[[ $rc -eq 0 ]] \
  || { echo "FAIL: exit $rc przy wywołaniu spoza roota repo (oczekiwano 0)"; exit 1; }
grep -q 'platform-catalog:9\.9\.9' "$REPO/backend/settings.gradle.kts" \
  || { echo "FAIL: pin platform-catalog nie podbity przy wywołaniu spoza roota repo"; exit 1; }
grep -q 'version "9\.9\.9"' "$REPO/backend/settings.gradle.kts" \
  || { echo "FAIL: wersja settings-conventions nie podbita przy wywołaniu spoza roota repo"; exit 1; }

echo "OK: platform-bump.sh wywołany spoza roota repo operuje na repo skryptu"
