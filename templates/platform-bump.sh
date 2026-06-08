#!/usr/bin/env bash
# platform-bump.sh — podbija piny artefaktów Platform (Maven catalog + convention pluginy + settings
# plugin + npm) do NAJNOWSZEJ opublikowanej wersji w GitHub Packages i NAKŁADA kanon wersji frontendu
# z @dominiksienkiewicz/versions (publish-only: GitHub = źródło prawdy).
# KANON tego pliku żyje w Platform/templates/platform-bump.sh — nie edytuj kopii per-repo.
#
# Token (PAT classic, read:packages): z env GPR_TOKEN lub GITHUB_TOKEN, albo gpr.key z ~/.gradle/gradle.properties.
# Użycie:
#   ./platform-bump.sh            # podbij do najnowszej
#   ./platform-bump.sh 1.3.0      # podbij do konkretnej wersji
#
# Po skrypcie (backend): cd backend && ./gradlew build --write-locks  — gdy bump platformy zmienia
# wersje zarządzane BOM-em/nadpisaniami (gradle.lockfile musi dogonić rzeczywistość).
set -euo pipefail

OWNER="DominikSienkiewicz"
CATALOG_PKG="pl.seniordeveloper.platform-catalog"

TOKEN="${GPR_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$TOKEN" ] && [ -f "$HOME/.gradle/gradle.properties" ]; then
  TOKEN="$(grep -E '^gpr\.key=' "$HOME/.gradle/gradle.properties" | cut -d= -f2- | tr -d ' ')"
fi
[ -z "$TOKEN" ] && { echo "Brak tokenu (GPR_TOKEN/GITHUB_TOKEN lub gpr.key w ~/.gradle/gradle.properties)"; exit 1; }

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "Sprawdzam najnowszą wersję $CATALOG_PKG w GitHub Packages…"
  TARGET="$(curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/users/$OWNER/packages/maven/$CATALOG_PKG/versions" \
    | python3 -c "import sys,json,re; vs=[v['name'] for v in json.load(sys.stdin)]; vs=[v for v in vs if re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',v)]; vs.sort(key=lambda s:list(map(int,s.split('.')))); print(vs[-1] if vs else '')")"
fi
[ -z "$TARGET" ] && { echo "Nie udało się ustalić wersji docelowej"; exit 1; }
echo "==> Podbijam piny Platform do: $TARGET"

# --- Backend: pin platformy żyje TYLKO w settings.gradle.kts (settings plugin + catalog)
#     i settings-gradle.lockfile; conventions w build.gradle.kts są BEZ wersji (classpath settings). ---
[ -f backend/settings.gradle.kts ] && sed -i.bak -E "s#(pl\.seniordeveloper:platform-catalog:)[0-9]+\.[0-9]+\.[0-9]+#\1$TARGET#" backend/settings.gradle.kts && rm -f backend/settings.gradle.kts.bak
[ -f backend/settings.gradle.kts ] && sed -i.bak -E "s#(id\(\"seniordev\.settings-conventions\"\) version \")[0-9]+\.[0-9]+\.[0-9]+#\1$TARGET#" backend/settings.gradle.kts && rm -f backend/settings.gradle.kts.bak
[ -f backend/settings-gradle.lockfile ] && sed -i.bak -E "s#(pl\.seniordeveloper:platform-catalog:)[0-9]+\.[0-9]+\.[0-9]+#\1$TARGET#" backend/settings-gradle.lockfile && rm -f backend/settings-gradle.lockfile.bak

# --- Frontend: piny @dominiksienkiewicz/* + kanon wersji z @dominiksienkiewicz/versions ---
if [ -f frontend/package.json ]; then
  python3 - "$TARGET" <<'PY'
import json,sys
t=sys.argv[1]; p="frontend/package.json"; d=json.load(open(p))
for sec in ("dependencies","devDependencies"):
    for k in list(d.get(sec,{})):
        if k.startswith("@dominiksienkiewicz/"): d[sec][k]=t
json.dump(d,open(p,"w"),indent=2,ensure_ascii=False); open(p,"a").write("\n")
PY

  # Kanon: pobierz tarball versions@TARGET, nałóż versions.json na package.json (tylko wspólne klucze).
  TMPD="$(mktemp -d)"
  if ( cd frontend && GITHUB_TOKEN="$TOKEN" npm pack "@dominiksienkiewicz/versions@$TARGET" --pack-destination "$TMPD" >/dev/null 2>&1 ); then
    tar -xzf "$TMPD"/dominiksienkiewicz-versions-*.tgz -C "$TMPD"
    python3 - "$TMPD/package/versions.json" <<'PY'
import json,sys
canon=json.load(open(sys.argv[1]))["versions"]
p="frontend/package.json"; d=json.load(open(p)); changed=[]
for sec in ("dependencies","devDependencies"):
    for k,v in list(d.get(sec,{}).items()):
        if k in canon and v!=canon[k]:
            d[sec][k]=canon[k]; changed.append(f"{k}: {v} -> {canon[k]}")
json.dump(d,open(p,"w"),indent=2,ensure_ascii=False); open(p,"a").write("\n")
print("Kanon frontendu:", *changed, sep="\n  ") if changed else print("Kanon frontendu: bez zmian")
PY
  else
    echo "UWAGA: @dominiksienkiewicz/versions@$TARGET niedostępne — kanon nie nałożony (stare wydanie platformy?)"
  fi
  rm -rf "$TMPD"

  ( cd frontend && GITHUB_TOKEN="$TOKEN" npm install --package-lock-only )
fi

echo "==> Gotowe. Sprawdź i zacommituj:"
git --no-pager diff --stat
echo "Pamiętaj (backend): cd backend && ./gradlew build --write-locks  — jeśli bump zmienia wersje z BOM-ów."
