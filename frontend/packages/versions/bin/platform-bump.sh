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
#   platform-bump            # podbij do najnowszej w BIEŻĄCYM majorze (nowy MAJOR tylko jawnie)
#   platform-bump 1.3.0      # podbij do konkretnej wersji
#
# Przed bumpem wypisuje notatki GitHub Releases z zakresu (obecny pin, cel], a na końcu powtarza
# ich "Consumer action required" i podaje link do wydania docelowego (docs/adr/0002-…).
#
# Backend gradle.lockfile jest regenerowany AUTOMATYCZNIE na końcu (--write-locks) — analogicznie do
# npm --package-lock-only dla frontu. Skrypt NIE commituje: diff zostaje do recenzji. Wymaga JDK (Gradle).
# Repo z verification-metadata.xml dostaje DWA przebiegi Gradle (`build`, potem `dependencies`), oba
# z --refresh-dependencies, więc ten krok pobiera metadane od nowa i trwa wyraźnie dłużej niż sam bump
# pinów — to celowe, powody niżej przy bloku. Pierwszy bump po dodaniu drugiego przebiegu poszerza
# gradle.lockfile o konfiguracje spoza grafu `build` (pitest, cyclonedxBom) — jednorazowy, celowy diff.
#
# UWAGA (bootstrap): stub konsumenta odpala ZAINSTALOWANĄ wersję tego skryptu, a kanon bierze ze
# ŚWIEŻO pobranego tarballa. Repo, które ma jeszcze wydanie bez obsługi `overrides`, po pierwszym
# bumpie zaktualizuje tylko dependencies/devDependencies — guard w CI zgłosi wtedy dryf w overrides.
# Lekarstwo: po `npm ci` (już z nową wersją paczki) uruchom platform-bump PONOWNIE. Kolejne bumpy
# działają jednoprzebiegowo.
set -euo pipefail

# Operuj ZAWSZE na roocie repo konsumenta — bin bywa odpalany z node_modules/.bin lub przez stub.
cd "$(git rev-parse --show-toplevel)"

# Pin w stylu szablonu: platformVersion= w backend/gradle.properties (layout produktowy na wiringu
# z templates/jvm) albo w gradle.properties roota (samodzielny layout JVM).
PROPERTY_PINS=()
for props in backend/gradle.properties gradle.properties; do
  [[ -f "$props" ]] && grep -q '^platformVersion=' "$props" && PROPERTY_PINS+=("$props")
done
if [[ ! -f backend/settings.gradle.kts ]] && [[ ! -f frontend/package.json ]] && [[ "${#PROPERTY_PINS[@]}" -eq 0 ]]; then
  echo "No Platform pin found in this layout: expected backend/settings.gradle.kts, frontend/package.json or platformVersion= in gradle.properties." >&2
  exit 1
fi

OWNER="DominikSienkiewicz"
CATALOG_PKG="pl.seniordeveloper.platform-catalog"

TOKEN="${GPR_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" ]] && [[ -f "$HOME/.gradle/gradle.properties" ]]; then
  TOKEN="$(grep -E '^gpr\.key=' "$HOME/.gradle/gradle.properties" | cut -d= -f2- | tr -d ' ')"
fi
[[ -z "$TOKEN" ]] && { echo "Brak tokenu (GPR_TOKEN/GITHUB_TOKEN lub gpr.key w ~/.gradle/gradle.properties)"; exit 1; }

VERSIONS_JSON=""
RELEASES_JSON=""
ACTIONS_FILE=""
trap 'rm -f "$VERSIONS_JSON" "$RELEASES_JSON" "$ACTIONS_FILE"' EXIT

# Obecny pin (przed bumpem) — do granicy MAJOR i notatek wydań, przez które bump przechodzi.
CURRENT=""
if [[ -f backend/settings.gradle.kts ]]; then
  CURRENT="$(grep -oE 'pl\.seniordeveloper:platform-catalog:[0-9]+\.[0-9]+\.[0-9]+' backend/settings.gradle.kts | head -1 | sed 's/.*://' || true)"
fi
if [[ -z "$CURRENT" ]] && [[ "${#PROPERTY_PINS[@]}" -gt 0 ]]; then
  CURRENT="$(sed -n -E 's/^platformVersion=[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "${PROPERTY_PINS[0]}" | head -1)"
fi
if [[ -z "$CURRENT" ]] && [[ -f frontend/package.json ]]; then
  CURRENT="$(grep -oE '"@dominiksienkiewicz/[a-z-]+": "[0-9]+\.[0-9]+\.[0-9]+"' frontend/package.json | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
fi

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Sprawdzam najnowszą wersję $CATALOG_PKG w GitHub Packages…"
  VERSIONS_JSON="$(mktemp)"
  curl -fsSL --proto '=https' --proto-redir '=https' \
    -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/users/$OWNER/packages/maven/$CATALOG_PKG/versions" -o "$VERSIONS_JSON"
  # Bez argumentu: najnowsze wydanie BIEŻĄCEGO majora; nowy MAJOR tylko jawnie (ADR-0002).
  python3 - "$VERSIONS_JSON" "$CURRENT" > "$VERSIONS_JSON.choice" <<'PY'
# platform-bump:target — marker wycinania dla frontend/packages/versions/test/release-notes.test.sh
import json, re, sys

versions_path, current = sys.argv[1], sys.argv[2]
key = lambda version: [int(part) for part in version.split(".")]
releases = sorted(
    (v["name"] for v in json.load(open(versions_path)) if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", v["name"])),
    key=key,
)
if releases:
    same_major = [v for v in releases if current and v.split(".")[0] == current.split(".")[0]]
    print(same_major[-1] if same_major else releases[-1], releases[-1])
PY
  NEWEST=""
  read -r TARGET NEWEST < "$VERSIONS_JSON.choice" || true
  rm -f "$VERSIONS_JSON.choice"
  if [[ -n "${NEWEST:-}" ]] && [[ "${NEWEST%%.*}" != "${TARGET%%.*}" ]]; then
    echo "NOTE: Platform $NEWEST starts a new MAJOR and is not taken automatically."
    echo "      Read its release notes, then run platform-bump $NEWEST to cross it."
  fi
fi
[[ -z "$TARGET" ]] && { echo "Nie udało się ustalić wersji docelowej"; exit 1; }
echo "==> Podbijam piny Platform do: $TARGET"
# W GitHub Actions (reusable platform-bump.yml) wersja docelowa idzie też do wyjść kroku.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "target=$TARGET" >> "$GITHUB_OUTPUT"; fi

# Notatki każdego wydania z (CURRENT, TARGET] — źródłem są GitHub Releases, czyli sekcje CHANGELOG.md.
ACTIONS_FILE="$(mktemp)"
RELEASES_JSON="$(mktemp)"
if [[ -n "$CURRENT" ]] && curl -fsSL --proto '=https' --proto-redir '=https' \
  -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$OWNER/Platform/releases?per_page=100" -o "$RELEASES_JSON"; then
  echo "==> Release notes from $CURRENT to $TARGET:"
  python3 - "$RELEASES_JSON" "$CURRENT" "$TARGET" "$ACTIONS_FILE" <<'PY'
# platform-bump:notes — marker wycinania dla frontend/packages/versions/test/release-notes.test.sh
import json, re, sys

releases_path, current, target, actions_path = sys.argv[1:5]
key = lambda version: [int(part) for part in version.split(".")]

def consumer_action(body):
    lines, inside = [], False
    for line in body.split("\n"):
        if line.strip() == "### Consumer action required":
            inside = True
            continue
        if inside and (line.startswith("#") or line.startswith("**Full diff:**")):
            break
        if inside:
            lines.append(line)
    return "\n".join(lines).strip()

crossed = []
for release in json.load(open(releases_path)):
    match = re.fullmatch(r"v([0-9]+\.[0-9]+\.[0-9]+)", release.get("tag_name") or "")
    if match and key(current) < key(match.group(1)) <= key(target):
        crossed.append((match.group(1), (release.get("body") or "").replace("\r\n", "\n")))
crossed.sort(key=lambda item: key(item[0]))

if not crossed:
    print(f"No release notes between {current} and {target}.")
actions = []
for version, body in crossed:
    print(f"\n===== Platform {version} =====\n{body.strip()}")
    action = consumer_action(body)
    if action and not re.fullmatch(r"None\.?", action):
        actions.append(f"Platform {version}:\n{action}")
with open(actions_path, "w") as out:
    out.write("\n\n".join(actions))
PY
else
  echo "Release notes unavailable: no current Platform pin found, or the GitHub API did not answer."
fi

# --- Backend: pin platformy żyje TYLKO w settings.gradle.kts (settings plugin + catalog)
#     i settings-gradle.lockfile; conventions w build.gradle.kts są BEZ wersji (classpath settings). ---
# platform-bump:backend-pins — test: frontend/packages/versions/test/backend-literal-pins.test.sh
if [[ -f backend/settings.gradle.kts ]]; then
  sed -i.bak -E \
    -e "s#(pl\.seniordeveloper:platform-catalog:)[0-9]+\.[0-9]+\.[0-9]+#\1$TARGET#" \
    -e "s#(id\(\"seniordev\.settings-conventions\"\)[[:space:]]+version[[:space:]]+\")[0-9]+\.[0-9]+\.[0-9]+#\1$TARGET#" \
    backend/settings.gradle.kts && rm -f backend/settings.gradle.kts.bak
  # Pin zapisany inaczej niż wzorzec zostałby na starej wersji, choć katalog poszedł dalej: zatrzymaj bump.
  stale_pins="$(grep -nE 'seniordev\.settings-conventions"\)[^"]*"[0-9]+\.[0-9]+\.[0-9]+"|platform-catalog:[0-9]+\.[0-9]+\.[0-9]+' backend/settings.gradle.kts | grep -vF "$TARGET" || true)"
  if [[ -n "$stale_pins" ]]; then
    echo "A Platform pin in backend/settings.gradle.kts is written in a form platform-bump does not rewrite, so it stayed behind $TARGET." >&2
    echo "Write it as id(\"seniordev.settings-conventions\") version \"X.Y.Z\" and run the bump again:" >&2
    echo "$stale_pins" >&2
    exit 1
  fi
fi
[[ -f backend/settings-gradle.lockfile ]] && sed -i.bak -E "s#(pl\.seniordeveloper:platform-catalog:)[0-9]+\.[0-9]+\.[0-9]+#\1$TARGET#" backend/settings-gradle.lockfile && rm -f backend/settings-gradle.lockfile.bak
# platform-bump:backend-pins-end
for props in ${PROPERTY_PINS[@]+"${PROPERTY_PINS[@]}"}; do
  sed -i.bak -E "s/^platformVersion=.*/platformVersion=$TARGET/" "$props" && rm -f "$props.bak"
done
# Backend bez żadnego pinu = nic nie zostało podbite; nie udawaj sukcesu.
if [[ -f backend/settings.gradle.kts ]] && ! grep -qF "$TARGET" backend/settings.gradle.kts \
  && ! { [[ -f backend/gradle.properties ]] && grep -qx "platformVersion=$TARGET" backend/gradle.properties; }; then
  echo "No Platform pin found in backend/settings.gradle.kts or backend/gradle.properties; nothing was bumped to $TARGET." >&2
  exit 1
fi

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
  # Tylko brak wydania (E404/ETARGET) jest ostrzeżeniem; 401, sieć i reszta zatrzymują bump z komunikatem npm,
  # bo cicho pominięty kanon wychodzi dopiero jako dryf w CI (test: frontend/packages/versions/test/npm-pack-errors.test.sh).
  if ( cd frontend && GITHUB_TOKEN="$TOKEN" npm pack "@dominiksienkiewicz/versions@$TARGET" --pack-destination "$TMPD" >/dev/null 2>"$TMPD/pack.err" ); then
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
  elif grep -qE 'E404|ETARGET' "$TMPD/pack.err"; then
    echo "WARNING: @dominiksienkiewicz/versions@$TARGET is not published, so the frontend canon was not applied."
  else
    echo "ERROR: npm pack @dominiksienkiewicz/versions@$TARGET failed, so the frontend canon was not applied:" >&2
    cat "$TMPD/pack.err" >&2
    echo "The frontend pins in frontend/package.json already point at $TARGET; fix the error above and run the bump again." >&2
    rm -rf "$TMPD"
    exit 1
  fi
  rm -rf "$TMPD"

  ( cd frontend && GITHUB_TOKEN="$TOKEN" npm install --package-lock-only --ignore-scripts )
fi

# --- Reusable workflows Platform: `uses: …/Platform/.github/workflows/<w>.yml@<ref>` i wejście `platform-ref:`
#     callera deploy.yml idą na v$TARGET razem z pinami (Decyzja 3: dokładny tag przesuwany przez bump). Ruchome
#     @v1 też przechodzi na dokładny tag — to migracja z Decyzji 3; referencje po SHA zostają nietknięte. ---
# platform-bump:workflows
for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
  [[ -f "$workflow" ]] || continue
  sed -i.bak -E \
    -e "s#(uses:[[:space:]]*$OWNER/Platform/\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml@)v[0-9]+(\.[0-9]+\.[0-9]+)?([[:space:]]|\$)#\1v$TARGET\3#" \
    -e "s#^([[:space:]]*platform-ref:[[:space:]]*)[\"']?v[0-9]+(\.[0-9]+\.[0-9]+)?[\"']?[[:space:]]*\$#\1v$TARGET#" \
    "$workflow" && rm -f "$workflow.bak"
done
# platform-bump:workflows-end

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
#   NIGDY z --dry-run: Gradle odkłada wtedy wynik do verification-metadata.dryrun.xml, prawdziwego
#     pliku nie rusza i kończy się BUILD SUCCESSFUL — cicha awaria wyglądająca na sukces.
#
# DWA PRZEBIEGI o rozłącznych rolach — żaden sam nie domyka pliku:
#   1. `build` POBIERA artefakty, więc jako jedyny zapisuje checksumy JARÓW, ale widzi wyłącznie
#      konfiguracje z grafu tego zadania.
#   2. `dependencies` (bez --configuration) rozwiązuje WSZYSTKIE resolvable konfiguracje, ale jako
#      report task nie pobiera artefaktów — domyka więc metadane (.pom/.module), nie jary.
#      Sedno: `junit-bom-<wersja>.pom` jest pobierany dopiero w detached configuration, którą
#      io.spring.dependency-management (MavenPomResolver.resolvePomsLeniently) tworzy przy ustalaniu
#      zależności `:integrationTest`. `.module` tej samej wersji leci normalną ścieżką, więc plik
#      wygląda na kompletny — a CI failuje `One artifact failed verification: junit-bom-6.1.3.pom`
#      (Azimuth/SkillSprintPlus, bump 1.5.26: junit 6.1.0 -> 6.1.3). Ta sama klasa błędu wracała
#      wcześniej dla konfiguracji narzędziowych (Spotless, JaCoCo, CycloneDX) — stąd BRAK zawężenia
#      do `--configuration testRuntimeClasspath`, które domknęłoby wprawdzie junit-bom, ale nie tamte.
#      --write-locks jest tu OBOWIĄZKOWE: lockfile konsumenta (lockAllConfigurations) ma wpisy dla
#      konfiguracji spoza grafu `build` (pitest, cyclonedxBom), więc bez przepisania locka ten
#      przebieg wywracałby bump na niezgodności lock state. Musi iść DRUGI — przy --write-locks
#      wygrywa ostatni przebieg, a jego zbiór konfiguracji jest nadzbiorem zbioru `build`.
# --- Wrapper Gradle: wersja `gradle` z katalogu wydania docelowego (od 1.6.0), z sumą SHA-256 dystrybucji.
#     Konsument jedzie na własnym wrapperze, a Platform kompiluje pluginy (kotlin-dsl) na wersji z katalogu;
#     PlatformMinimumGradleFunctionalTest pilnuje minimum, ten blok trzyma wrapper na wersji testowanej.
#     Katalog bez wpisu `gradle` (starsze wydania) albo niedostępny = wrapper bez zmian. ---
# platform-bump:wrapper
for wrapper_dir in backend .; do
  props="$wrapper_dir/gradle/wrapper/gradle-wrapper.properties"
  [[ -f "$props" && -x "$wrapper_dir/gradlew" ]] || continue
  catalog_toml="$(mktemp)"
  if curl -fsSL --proto '=https' -u "${GITHUB_ACTOR:-platform-bump}:$TOKEN" \
    "https://maven.pkg.github.com/$OWNER/Platform/pl/seniordeveloper/platform-catalog/$TARGET/platform-catalog-$TARGET.toml" \
    -o "$catalog_toml" 2>/dev/null; then
    gradle_target="$(sed -n -E 's/^gradle[[:space:]]*=[[:space:]]*"([0-9.]+)".*/\1/p' "$catalog_toml" | head -1)"
    gradle_current="$(sed -n -E 's#^distributionUrl=.*gradle-([0-9.]+)-(bin|all)\.zip.*#\1#p' "$props" | head -1)"
    if [[ -n "$gradle_target" && "$gradle_target" != "$gradle_current" ]]; then
      echo "==> Gradle wrapper: $gradle_current -> $gradle_target"
      gradle_sum="$(curl -fsSL --proto '=https' "https://services.gradle.org/distributions/gradle-$gradle_target-bin.zip.sha256")"
      ( cd "$wrapper_dir" && ./gradlew wrapper --gradle-version "$gradle_target" --gradle-distribution-sha256-sum "$gradle_sum" --no-daemon )
    fi
  fi
  rm -f "$catalog_toml"
  break
done
# platform-bump:wrapper-end

# platform-bump:gradle
if [[ -f backend/settings.gradle.kts ]]; then
  echo "==> Backend: regeneracja zamrożonego stanu (--write-locks)"
  if [[ -f backend/gradle/verification-metadata.xml ]]; then
    ( cd backend && ./gradlew build --write-locks --write-verification-metadata sha256 --refresh-dependencies --no-daemon )
    echo "==> Backend: domykanie metadanych weryfikacji dla wszystkich konfiguracji (dependencies)"
    ( cd backend && ./gradlew dependencies --write-locks --write-verification-metadata sha256 --refresh-dependencies --no-daemon )
  else
    ( cd backend && ./gradlew dependencies --write-locks --no-daemon )
  fi
fi
# platform-bump:gradle-end

# --- Lokalne nadpisania wersji, których BOM-y Platform i platformDependencyCheck nie widzą (eachDependency/useVersion,
#     force, strictly, extra/ext["….version"]). Bump nie może kończyć się po cichu na wersji, którą nowe BOM-y już
#     łatają — tylko raport, kod wyjścia bez zmian. Wyniki builda (build/, .gradle/) pomijamy. ---
# platform-bump:local-overrides
if [[ -d backend ]]; then
  local_overrides="$(grep -rnE --include='*.gradle.kts' --exclude-dir=build --exclude-dir=.gradle \
    'useVersion\(|force\(|strictly\(|(extra|ext)\["[^"]+\.version"\]' backend 2>/dev/null || true)"
  if [[ -n "$local_overrides" ]]; then
    echo ""
    echo "==> Local version overrides the Platform BOMs do not see. Remove each one the BOMs of $TARGET manage at an equal or higher version:"
    while IFS= read -r hit; do echo "  $hit"; done <<<"$local_overrides"
    echo "  Selected version of a module: (cd backend && ./gradlew dependencyInsight --dependency <group:name> --configuration runtimeClasspath)"
  fi
fi
# platform-bump:local-overrides-end

# --- Kopie szablonów (templates/manifest.json) kontra kanon wydania docelowego: tylko raport, kod wyjścia bez zmian.
#     Bin obok tego skryptu; .bin/platform-bump to symlink, więc najpierw rozwiązujemy prawdziwą ścieżkę. ---
# platform-bump:templates
templates_check="$(dirname "$(node -e 'console.log(require("node:fs").realpathSync(process.argv[1]))' "${BASH_SOURCE[0]}")")/templates-check.mjs"
if [[ -f "$templates_check" ]]; then
  echo ""
  node "$templates_check" --ref "v$TARGET" || true
fi
# platform-bump:templates-end

echo "==> Gotowe. Zrecenzuj diff (gradle.lockfile / verification-metadata.xml) i zacommituj:"
git --no-pager diff --stat

if [[ -s "$ACTIONS_FILE" ]]; then
  echo ""
  echo "==> CONSUMER ACTION REQUIRED by the releases this bump crosses:"
  cat "$ACTIONS_FILE"
  echo ""
fi
echo "Release notes: https://github.com/$OWNER/Platform/releases/tag/v$TARGET"
