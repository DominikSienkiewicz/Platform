#!/usr/bin/env bash
# platform-bump — KANON (jedno źródło): bin pakietu @dominiksienkiewicz/versions, publikowany z Platform.
# Repo konsumenckie NIE trzymają kopii logiki — wołają go przez cienki stub -> node_modules/.../bin.
# Podbija piny artefaktów Platform (Maven catalog + settings plugin + npm @dominiksienkiewicz/*) do
# NAJNOWSZEJ opublikowanej wersji w GitHub Packages i NAKŁADA kanon wersji frontendu z versions.json.
# Obie operacje obejmują też sekcję `overrides` w package.json (piny CVE paczek transytywnych,
# np. overrides.next.postcss) — pomijając referencje npm w formie "$nazwa".
#
# Token (PAT classic, read:packages): z env GPR_TOKEN lub GITHUB_TOKEN, albo gpr.key z ~/.gradle/gradle.properties.
# Użycie (z dowolnego miejsca w repo):
#   platform-bump            # podbij do najnowszej
#   platform-bump 1.3.0      # podbij do konkretnej wersji
#
# Backend gradle.lockfile jest regenerowany AUTOMATYCZNIE na końcu (--write-locks) — analogicznie do
# npm --package-lock-only dla frontu. Skrypt NIE commituje: diff zostaje do recenzji. Wymaga JDK (Gradle).
# Repo z verification-metadata.xml dostaje dodatkowo --refresh-dependencies, więc ten krok pobiera
# metadane od nowa i trwa wyraźnie dłużej niż sam bump pinów — to celowe, powód niżej przy bloku.
#
# UWAGA (bootstrap): stub konsumenta odpala ZAINSTALOWANĄ wersję tego skryptu, a kanon bierze ze
# ŚWIEŻO pobranego tarballa. Repo, które ma jeszcze wydanie bez obsługi `overrides`, po pierwszym
# bumpie zaktualizuje tylko dependencies/devDependencies — guard w CI zgłosi wtedy dryf w overrides.
# Lekarstwo: po `npm ci` (już z nową wersją paczki) uruchom platform-bump PONOWNIE. Kolejne bumpy
# działają jednoprzebiegowo.
set -euo pipefail

# Operuj ZAWSZE na roocie repo konsumenta — bin bywa odpalany z node_modules/.bin lub przez stub.
cd "$(git rev-parse --show-toplevel)"

OWNER="DominikSienkiewicz"
CATALOG_PKG="pl.seniordeveloper.platform-catalog"

TOKEN="${GPR_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" ]] && [[ -f "$HOME/.gradle/gradle.properties" ]]; then
  TOKEN="$(grep -E '^gpr\.key=' "$HOME/.gradle/gradle.properties" | cut -d= -f2- | tr -d ' ')"
fi
[[ -z "$TOKEN" ]] && { echo "Brak tokenu (GPR_TOKEN/GITHUB_TOKEN lub gpr.key w ~/.gradle/gradle.properties)"; exit 1; }

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Sprawdzam najnowszą wersję $CATALOG_PKG w GitHub Packages…"
  TARGET="$(curl -fsSL --proto '=https' --proto-redir '=https' \
    -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/users/$OWNER/packages/maven/$CATALOG_PKG/versions" \
    | python3 -c "import sys,json,re; vs=[v['name'] for v in json.load(sys.stdin)]; vs=[v for v in vs if re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',v)]; vs.sort(key=lambda s:list(map(int,s.split('.')))); print(vs[-1] if vs else '')")"
fi
[[ -z "$TARGET" ]] && { echo "Nie udało się ustalić wersji docelowej"; exit 1; }
echo "==> Podbijam piny Platform do: $TARGET"

# --- Backend: pin platformy żyje TYLKO w settings.gradle.kts (settings plugin + catalog)
#     i settings-gradle.lockfile; conventions w build.gradle.kts są BEZ wersji (classpath settings). ---
[[ -f backend/settings.gradle.kts ]] && sed -i.bak -E "s#(pl\.seniordeveloper:platform-catalog:)[0-9]+\.[0-9]+\.[0-9]+#\1$TARGET#" backend/settings.gradle.kts && rm -f backend/settings.gradle.kts.bak
[[ -f backend/settings.gradle.kts ]] && sed -i.bak -E "s#(id\(\"seniordev\.settings-conventions\"\) version \")[0-9]+\.[0-9]+\.[0-9]+#\1$TARGET#" backend/settings.gradle.kts && rm -f backend/settings.gradle.kts.bak
[[ -f backend/settings-gradle.lockfile ]] && sed -i.bak -E "s#(pl\.seniordeveloper:platform-catalog:)[0-9]+\.[0-9]+\.[0-9]+#\1$TARGET#" backend/settings-gradle.lockfile && rm -f backend/settings-gradle.lockfile.bak

# --- Frontend: piny @dominiksienkiewicz/* + kanon wersji z @dominiksienkiewicz/versions ---
if [[ -f frontend/package.json ]]; then
  python3 - "$TARGET" <<'PY'
# platform-bump:pins — marker wycinania dla frontend/packages/versions/test/apply-canon.test.sh
import json,sys

# npm `overrides`: wartość to wersja (string) albo zagnieżdżony obiekt zawężający kontekst.
# Klucz "." oznacza paczkę nadrzędną, wartość "$nazwa" to referencja npm (nie ruszamy jej).
def walk(node, path, parent, visit):
    for k, v in list(node.items()):
        name = parent if k == "." else k
        at = path if k == "." else f"{path}.{k}"
        if isinstance(v, dict): walk(v, at, name, visit)
        elif isinstance(v, str) and name and not v.startswith("$"): visit(node, k, name, v, at)

t=sys.argv[1]; p="frontend/package.json"; d=json.load(open(p))
def to_target(node, key, name, version, at):
    if name.startswith("@dominiksienkiewicz/"): node[key]=t
for sec in ("dependencies","devDependencies"):
    for k in list(d.get(sec,{})):
        if k.startswith("@dominiksienkiewicz/"): d[sec][k]=t
walk(d.get("overrides",{}), "overrides", None, to_target)
json.dump(d,open(p,"w"),indent=2,ensure_ascii=False); open(p,"a").write("\n")
PY

  # Kanon: pobierz tarball versions@TARGET, nałóż versions.json na package.json (tylko wspólne klucze).
  TMPD="$(mktemp -d)"
  if ( cd frontend && GITHUB_TOKEN="$TOKEN" npm pack "@dominiksienkiewicz/versions@$TARGET" --pack-destination "$TMPD" >/dev/null 2>&1 ); then
    tar -xzf "$TMPD"/dominiksienkiewicz-versions-*.tgz -C "$TMPD"
    python3 - "$TMPD/package/versions.json" <<'PY'
# platform-bump:canon — marker wycinania dla frontend/packages/versions/test/apply-canon.test.sh
import json,sys

# npm `overrides`: wartość to wersja (string) albo zagnieżdżony obiekt zawężający kontekst
# (overrides.next.postcss = "postcss tylko pod next"). Klucz "." oznacza paczkę nadrzędną,
# wartość "$nazwa" to referencja npm — npm rozwija ją sam, więc nie wolno jej przepisywać.
def walk(node, path, parent, visit):
    for k, v in list(node.items()):
        name = parent if k == "." else k
        at = path if k == "." else f"{path}.{k}"
        if isinstance(v, dict): walk(v, at, name, visit)
        elif isinstance(v, str) and name and not v.startswith("$"): visit(node, k, name, v, at)

canon=json.load(open(sys.argv[1]))["versions"]
p="frontend/package.json"; d=json.load(open(p)); changed=[]
def to_canon(node, key, name, version, at):
    if name in canon and version!=canon[name]:
        node[key]=canon[name]; changed.append(f"{at}: {version} -> {canon[name]}")
for sec in ("dependencies","devDependencies"):
    for k,v in list(d.get(sec,{}).items()):
        if k in canon and v!=canon[k]:
            d[sec][k]=canon[k]; changed.append(f"{k}: {v} -> {canon[k]}")
walk(d.get("overrides",{}), "overrides", None, to_canon)
json.dump(d,open(p,"w"),indent=2,ensure_ascii=False); open(p,"a").write("\n")
print("Kanon frontendu:", *changed, sep="\n  ") if changed else print("Kanon frontendu: bez zmian")
PY
  else
    echo "UWAGA: @dominiksienkiewicz/versions@$TARGET niedostępne — kanon nie nałożony (stare wydanie platformy?)"
  fi
  rm -rf "$TMPD"

  ( cd frontend && GITHUB_TOKEN="$TOKEN" npm install --package-lock-only --ignore-scripts )
fi

# --- Backend: regen ZAMROŻONEGO STANU (analogicznie do `npm install --package-lock-only` dla frontu) ---
# --write-locks przelicza CAŁY graf (też transytywny: checker-qual itp.), nie tylko podbite wpisy.
# Gdy jest verification-metadata: WSZYSTKIE TRZY flagi RAZEM.
#   --write-locks + --write-verification-metadata muszą iść w parze — osobno = deadlock (lock chce
#     nowych artefaktów, verification je blokuje); verification dorzuca checksumy nowych wersji.
#   --refresh-dependencies jest tu OBOWIĄZKOWE, nie optymalizacją: przy CIEPŁYM cache Gradle serwuje
#     metadane modułu ze swojego magazynu i w ogóle nie dotyka pliku `.module`, więc jego checksum
#     NIE trafia do verification-metadata.xml — mimo że flaga zapisu jest włączona. Efekt: lokalnie
#     build zielony, a CI (zimny cache) pobiera `.module` i failuje `Dependency verification failed`.
#     Realny przypadek: junit-bom 5.14.4 zapisany tylko jako `.pom` (BookOfStyling/SkillSprintPlus,
#     bump 1.5.4 -> 1.5.22). Kosztem jest jedno pełne przeliczenie na bump — bumpy są rzadkie.
# platform-bump:gradle
if [[ -f backend/settings.gradle.kts ]]; then
  echo "==> Backend: regeneracja zamrożonego stanu (--write-locks)"
  if [[ -f backend/gradle/verification-metadata.xml ]]; then
    ( cd backend && ./gradlew build --write-locks --write-verification-metadata sha256 --refresh-dependencies --no-daemon )
  else
    ( cd backend && ./gradlew dependencies --write-locks --no-daemon )
  fi
fi
# platform-bump:gradle-end

echo "==> Gotowe. Zrecenzuj diff (gradle.lockfile / verification-metadata.xml) i zacommituj:"
git --no-pager diff --stat
