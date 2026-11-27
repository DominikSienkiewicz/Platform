#!/usr/bin/env bash
# platform-bump — KANON (jedno źródło): bin pakietu @seniordeveloper-pl-dominik-sienkiewicz/versions, publikowany z Platform.
# Repo konsumenckie NIE trzymają kopii logiki — wołają go przez cienki stub -> node_modules/.../bin.
# Podbija piny artefaktów Platform (Maven catalog + settings plugin + npm Platform) do
# NAJNOWSZEJ opublikowanej wersji w GitHub Packages i NAKŁADA kanon wersji frontendu z versions.json.
# Obie operacje obejmują też sekcję `overrides` w package.json (piny CVE paczek transytywnych,
# np. overrides.next.postcss) — pomijając referencje npm w formie "$nazwa".
#
# Token (PAT classic, read:packages): z env GPR_TOKEN lub GITHUB_TOKEN, albo gpr.key z ~/.gradle/gradle.properties.
# Użycie (z dowolnego miejsca w repo):
#   platform-bump            # podbij do najnowszej w BIEŻĄCYM majorze (nowy MAJOR tylko jawnie)
#   platform-bump 1.3.0      # podbij do konkretnej wersji
#   platform-bump --dry-run  # pokaż linie, które bump by zmienił, bez zapisu i bez Gradle
#   --allow-dirty            # pozwól na niezacommitowane zmiany w plikach, które bump przepisuje
#   --allow-yanked           # pozwól na jawny cel z listy wycofanych (releases/yanked.txt)
#   --skip-provenance "<powód>"  # bump bez weryfikacji atestacji pobranej paczki (powód trafia do logu)
#   --report[=plik]          # raport wpływu (obecny pin, cel] na to repo (N-REL-8); bez pliku na stdout
#   --print-target           # tylko wypisz wersję docelową wg reguł niżej, bez zapisu (stub, workflow)
#
# Transakcja: preflight (narzędzia, czyste drzewo, token) idzie przed pierwszym zapisem, a błąd po nim
# przywraca każdy plik, który bump mógł zmienić — drzewo zostaje jak przed bumpem.
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
# Logika wydania DOCELOWEGO (N-DX-4): kopia, która nie jest wydaniem celu, po ustaleniu celu pobiera paczkę
# versions@TARGET z assetów GitHub Release (publiczne, bez PAT-a, SHA256SUMS i atestacja) i oddaje jej sterowanie,
# więc jeden przebieg wykonuje logikę wydania, do którego idzie — także w repo bez frontendu. Wydanie bez assetów
# (sprzed 1.6.0) zostaje przy logice tej kopii, z ostrzeżeniem.
set -euo pipefail

# Paczka, z której biegnie ten skrypt (przez symlink node_modules/.bin albo z cache assetów) — przed cd do repo.
SELF_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")/.." && pwd)"
SELF_VERSION=""
if [[ -f "$SELF_ROOT/package.json" ]]; then
  SELF_VERSION="$(sed -n -E 's/.*"version":[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$SELF_ROOT/package.json" | head -1)"
fi

# Operuj ZAWSZE na roocie repo konsumenta — bin bywa odpalany z node_modules/.bin lub przez stub.
cd "$(git rev-parse --show-toplevel)"

USAGE='Usage: platform-bump [--dry-run] [--allow-dirty] [--allow-yanked] [--skip-provenance "<reason>"] [--report[=<file>]] [--print-target] [X.Y.Z]'
DRY_RUN=false
ALLOW_DIRTY=false
ALLOW_YANKED=false
SKIP_PROVENANCE=""
REPORT=""
PRINT_TARGET=false
TARGET=""
# Argumenty bez wersji: z nimi bin wydania docelowego dostaje ten sam przebieg (handoff niżej).
PASS_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; PASS_ARGS+=("$1") ;;
    --allow-dirty) ALLOW_DIRTY=true; PASS_ARGS+=("$1") ;;
    --allow-yanked) ALLOW_YANKED=true; PASS_ARGS+=("$1") ;;
    --report) REPORT="-"; PASS_ARGS+=("$1") ;;
    --report=*) REPORT="${1#--report=}"; PASS_ARGS+=("$1") ;;
    --print-target) PRINT_TARGET=true; PASS_ARGS+=("$1") ;;
    --skip-provenance)
      [[ -n "${2:-}" ]] || { echo "--skip-provenance needs a reason. $USAGE" >&2; exit 2; }
      SKIP_PROVENANCE="$2"
      PASS_ARGS+=("$1" "$2")
      shift
      ;;
    -*) echo "Unknown option $1. $USAGE" >&2; exit 2 ;;
    *)
      if [[ -n "$TARGET" || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "Expected one X.Y.Z version, got $1. $USAGE" >&2; exit 2; fi
      TARGET="$1"
      ;;
  esac
  shift
done

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

OWNER="SeniorDeveloper-pl-Dominik-Sienkiewicz"
PLATFORM_NPM_PACKAGES="versions eslint-config openapi prettier-config tailwind-preset tsconfig vitest-config"
# Wersje 1.x zachowują nazwę npm i podpis workflow z chwili wydania.
release_owner() {
  if [[ "${1%%.*}" == 1 || "${1%%.*}" == 0 ]]; then printf '%s' DominikSienkiewicz; else printf '%s' "$OWNER"; fi
}
npm_scope() { release_owner "$1" | tr '[:upper:]' '[:lower:]'; }
CATALOG_PKG="pl.seniordeveloper.platform-catalog"

TOKEN="${GPR_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" ]] && [[ -f "$HOME/.gradle/gradle.properties" ]]; then
  TOKEN="$(grep -E '^gpr\.key=' "$HOME/.gradle/gradle.properties" | cut -d= -f2- | tr -d ' ')"
fi
[[ -z "$TOKEN" ]] && { echo "No token: set GPR_TOKEN or GITHUB_TOKEN, or gpr.key in ~/.gradle/gradle.properties."; exit 1; }

VERSIONS_JSON=""
RELEASES_JSON=""
ACTIONS_FILE=""
YANKED_FILE=""
TARGET_PACKAGE=""
SNAPSHOT="$(mktemp -d)"

# Każdy plik, który bump może przepisać: zbiór kontroli czystego drzewa, migawki i rollbacku.
# platform-bump:candidates
CANDIDATES=()
while IFS= read -r candidate; do CANDIDATES+=("$candidate"); done < <(
  printf '%s\n' backend/settings.gradle.kts backend/settings-gradle.lockfile frontend/package.json frontend/package-lock.json
  for props in ${PROPERTY_PINS[@]+"${PROPERTY_PINS[@]}"}; do printf '%s\n' "$props"; done
  for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do [[ -f "$workflow" ]] && printf '%s\n' "$workflow"; done
  for prefix in backend/ ""; do
    for wrapper_file in gradlew gradlew.bat gradle/wrapper/gradle-wrapper.properties gradle/wrapper/gradle-wrapper.jar; do
      printf '%s\n' "$prefix$wrapper_file"
    done
  done
  if [[ -d backend ]]; then
    find backend \( -name build -o -name .gradle -o -name node_modules \) -prune -o \
      \( -name gradle.lockfile -o -name verification-metadata.xml \) -type f -print
  fi
)
# platform-bump:candidates-end

# platform-bump:transaction
copy_to_snapshot() {
  if [[ -e "$1" ]]; then
    mkdir -p "$SNAPSHOT/files/$(dirname "$1")" && cp -p "$1" "$SNAPSHOT/files/$1"
  else
    printf '%s\n' "$1" >> "$SNAPSHOT/absent"
  fi
}
snapshot() {
  local file
  for file in "${CANDIDATES[@]}"; do copy_to_snapshot "$file"; done
  : > "$SNAPSHOT/taken"
}
# Plik spoza CANDIDATES (np. Dockerfile migracji) dołącza do migawki przed zapisem — pod tym samym warunkiem
# czystego drzewa co preflight; brudny plik zatrzymuje bump z kodem 2, a finish() cofa to, co już zapisano.
snapshot_file() {
  local known
  for known in "${CANDIDATES[@]}"; do [[ "$known" == "$1" ]] && return 0; done
  if [[ "$ALLOW_DIRTY" != true ]] && [[ -n "$(git status --porcelain --untracked-files=no -- "$1")" ]]; then
    echo "Uncommitted changes in $1, which an upgrade migration rewrites; commit or stash them, or pass --allow-dirty." >&2
    exit 2
  fi
  CANDIDATES+=("$1")
  copy_to_snapshot "$1"
}
restore() {
  local file
  for file in "${CANDIDATES[@]}"; do
    rm -f "$file.bak"
    if [[ -e "$SNAPSHOT/files/$file" ]]; then cp -p "$SNAPSHOT/files/$file" "$file"; fi
  done
  if [[ -f "$SNAPSHOT/absent" ]]; then
    while IFS= read -r file; do rm -f "$file"; done < "$SNAPSHOT/absent"
  fi
}
finish() {
  local status=$1
  if [[ -f "$SNAPSHOT/taken" ]]; then
    if [[ $status -ne 0 ]]; then
      restore
      echo "platform-bump failed, so it restored every file it had changed; the working tree is as before the bump." >&2
    elif [[ "$DRY_RUN" == true ]]; then
      restore
    fi
  fi
  rm -rf "$SNAPSHOT" "$TARGET_PACKAGE"
  rm -f "$VERSIONS_JSON" "$RELEASES_JSON" "$ACTIONS_FILE" "$YANKED_FILE"
}
trap 'finish $?' EXIT
# platform-bump:transaction-end

# Preflight przed pierwszym zapisem: brakujące narzędzie, cudze zmiany albo zły token zatrzymują bump z kodem 2,
# zanim cokolwiek zostanie przepisane. Token bez nagłówka x-oauth-scopes (fine-grained, GITHUB_TOKEN w Actions)
# i brak odpowiedzi GitHuba tylko ostrzegają.
# platform-bump:preflight
preflight() {
  local missing=() tool dirty code scopes headers
  for tool in git curl python3; do command -v "$tool" >/dev/null 2>&1 || missing+=("$tool"); done
  if [[ -f frontend/package.json ]]; then
    for tool in node npm; do command -v "$tool" >/dev/null 2>&1 || missing+=("$tool"); done
  fi
  if [[ -f backend/settings.gradle.kts ]] && [[ ! -x backend/gradlew ]]; then missing+=("an executable backend/gradlew"); fi
  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "platform-bump needs ${missing[*]}; nothing was changed." >&2
    exit 2
  fi
  if [[ -f backend/settings.gradle.kts ]] && [[ "$DRY_RUN" != true ]] && ! (cd backend && ./gradlew --version --quiet >/dev/null 2>&1); then
    echo "backend/gradlew --version failed: Gradle needs a JDK to regenerate the lockfiles; nothing was changed." >&2
    exit 2
  fi

  if [[ "$ALLOW_DIRTY" != true ]]; then
    dirty="$(git status --porcelain --untracked-files=no -- "${CANDIDATES[@]}")"
    if [[ -n "$dirty" ]]; then
      echo "Uncommitted changes in files platform-bump rewrites; commit or stash them, or pass --allow-dirty. Nothing was changed:" >&2
      printf '%s\n' "$dirty" >&2
      exit 2
    fi
  fi

  headers="$(mktemp)"
  code="$(curl -s -o /dev/null -D "$headers" -w '%{http_code}' --proto '=https' \
    -H "Authorization: Bearer $TOKEN" https://api.github.com/user 2>/dev/null || true)"
  scopes="$(tr -d '\r' < "$headers" | sed -n -E 's/^[Xx]-[Oo][Aa]uth-[Ss]copes:[[:space:]]*//p')"
  if [[ "$code" == 401 ]]; then
    rm -f "$headers"
    echo "GitHub rejected the token (401): it is invalid or expired. Nothing was changed." >&2
    exit 2
  elif [[ "$code" == 200 ]] && grep -qi '^x-oauth-scopes:' "$headers" && [[ ! "$scopes" =~ (^|[ ,])(read|write):packages($|[ ,]) ]]; then
    rm -f "$headers"
    echo "The token lacks the read:packages scope that GitHub Packages needs (scopes: ${scopes:-none}). Nothing was changed." >&2
    exit 2
  elif [[ "$code" != 200 ]]; then
    echo "WARNING: GitHub did not confirm the token (HTTP ${code:-no answer}); continuing."
  fi
  rm -f "$headers"
}
preflight
# platform-bump:preflight-end

# Proweniencja (SLSA, wydania od 1.6.0): pobrany tarball celu musi pochodzić z release.yml Platform, zanim bump
# z niego skorzysta. Nieudana weryfikacja zatrzymuje bump (finish() cofa zapisy), chyba że --skip-provenance;
# brak gh tylko ostrzega, bo bump działał dotąd bez niego.
# platform-bump:provenance
version_key() { local IFS=.; read -r -a part <<<"$1"; printf '%05d%05d%05d' "${part[0]}" "${part[1]}" "${part[2]}"; }
verify_provenance() {
  local file=$1 version=${2:-$TARGET} name signer
  signer="$(release_owner "$version")"
  name=$(basename "$file")
  if [[ -n "$SKIP_PROVENANCE" ]]; then
    echo "WARNING: the provenance of $name was not verified: $SKIP_PROVENANCE"
  elif [[ "$(version_key "$version")" < "$(version_key 1.6.0)" ]]; then
    echo "Provenance: Platform $version predates the release attestations of 1.6.0, so $name is not verified."
  elif ! command -v gh >/dev/null 2>&1; then
    if [[ "${version%%.*}" -ge 2 ]]; then echo "gh is required to verify the provenance of $name." >&2; return 1; fi
    echo "WARNING: gh is not installed, so the provenance of $name was not verified."
  elif GH_TOKEN="${GH_TOKEN:-$TOKEN}" gh attestation verify "$file" --repo "$signer/Platform" --source-ref "refs/tags/v$version" \
    --signer-workflow "$signer/Platform/.github/workflows/release.yml" >/dev/null 2>"$file.provenance"; then
    echo "Provenance: $name was built by Platform's release.yml."
  else
    echo "The provenance of $name does not verify, so platform-bump stops before using it:" >&2
    cat "$file.provenance" >&2
    echo "Pass --skip-provenance \"<reason>\" to bump anyway." >&2
    return 1
  fi
}
# platform-bump:provenance-end

# Paczka versions@<wersja> z assetów GitHub Release: SHA256SUMS tego wydania, atestacja jak wyżej, cache w
# ~/.cache/platform-cli/<wersja>. Wypisuje katalog paczki; kod 1 = brak assetu (stare wydanie, sieć), kod 2 = suma
# się nie zgadza, czyli bump musi stanąć. PLATFORM_RELEASES_URL podmienia źródło (testy).
# platform-bump:cli
fetch_platform_cli() {
  local version=$1 base="${PLATFORM_RELEASES_URL:-https://github.com/$OWNER/Platform/releases/download}"
  local cache_root="${PLATFORM_CLI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/platform-cli}" cache
  if [[ "${version%%.*}" -ge 2 ]]; then
    if [[ -z "$SKIP_PROVENANCE" ]]; then cache_root="$cache_root/verified-organization"; else cache_root="$cache_root/unverified-organization"; fi
  fi
  cache="$cache_root/$version"
  local asset proto="=https" work expected actual
  asset="$(npm_scope "$version")-versions-$version.tgz"
  [[ "$base" == file://* ]] && proto="=file"
  if [[ -f "$cache/package/bin/platform-bump.sh" ]]; then
    printf '%s\n' "$cache/package"
    return 0
  fi
  mkdir -p "$cache" || return 2
  work="$(mktemp -d "$cache/.install.XXXXXXXX")" || return 2
  if ! curl -fsSL --proto "$proto" --proto-redir "$proto" "$base/v$version/$asset" -o "$work/$asset" 2>/dev/null \
    || ! curl -fsSL --proto "$proto" --proto-redir "$proto" "$base/v$version/SHA256SUMS" -o "$work/SHA256SUMS" 2>/dev/null; then
    rm -rf "$work"
    return 1
  fi
  expected="$(awk -v name="$asset" '$2 == name || $2 == "*" name { print $1 }' "$work/SHA256SUMS")"
  actual="$( (sha256sum "$work/$asset" 2>/dev/null || shasum -a 256 "$work/$asset") | awk '{ print $1 }')"
  if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    echo "The release asset $asset of Platform $version does not match its SHA256SUMS, so platform-bump stops." >&2
    rm -rf "$work"
    return 2
  fi
  if ! verify_provenance "$work/$asset" "$version" >&2 || ! tar -xzf "$work/$asset" -C "$work" || [[ ! -f "$work/package/bin/platform-bump.sh" ]]; then
    rm -rf "$work"
    return 2
  fi
  if ! mv "$work/package" "$cache/" 2>/dev/null && [[ ! -f "$cache/package/bin/platform-bump.sh" ]]; then
    rm -rf "$work"
    return 2
  fi
  rm -rf "$work"
  printf '%s\n' "$cache/package"
}
# platform-bump:cli-end

# Obecny pin (przed bumpem) — do granicy MAJOR i notatek wydań, przez które bump przechodzi.
CURRENT=""
if [[ -f backend/settings.gradle.kts ]]; then
  CURRENT="$(grep -oE 'pl\.seniordeveloper:platform-catalog:[0-9]+\.[0-9]+\.[0-9]+' backend/settings.gradle.kts | head -1 | sed 's/.*://' || true)"
fi
if [[ -z "$CURRENT" ]] && [[ "${#PROPERTY_PINS[@]}" -gt 0 ]]; then
  CURRENT="$(sed -n -E 's/^platformVersion=[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "${PROPERTY_PINS[0]}" | head -1)"
fi
if [[ -z "$CURRENT" ]] && [[ -f frontend/package.json ]]; then
  CURRENT="$(python3 - "$PLATFORM_NPM_PACKAGES" <<'PY'
import json, re, sys

with open("frontend/package.json") as file:
    manifest = json.load(file)
for name in sys.argv[1].split():
    for group in ("devDependencies", "dependencies", "optionalDependencies", "peerDependencies"):
        deps = manifest.get(group, {})
        for owner in ("seniordeveloper-pl-dominik-sienkiewicz", "dominiksienkiewicz"):
            pin = deps.get(f"@{owner}/{name}", "")
            if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", pin):
                print(pin)
                sys.exit(0)
PY
)"
fi

# Lista wycofanych wydań (releases/yanked.txt na main, publiczne repo): bump bez argumentu je omija, a jawny cel
# z listy wymaga --allow-yanked. Brak listy (sieć) = głośne ostrzeżenie i bump bez niej (fail-open).
# platform-bump:yanked
YANKED_FILE="$(mktemp)"
if ! curl -fsSL --proto '=https' --proto-redir '=https' \
  "https://raw.githubusercontent.com/$OWNER/Platform/main/releases/yanked.txt" -o "$YANKED_FILE" 2>/dev/null; then
  : > "$YANKED_FILE"
  echo "WARNING: could not read the list of yanked Platform releases (releases/yanked.txt); the bump continues without it."
fi
yanked_line() { awk -v version="$1" '{ sub(/#.*/, "") } $1 == version { $1 = ""; sub(/^[[:space:]]+/, ""); print; exit }' "$YANKED_FILE"; }
# platform-bump:yanked-end

if [[ -z "$TARGET" ]]; then
  echo "Looking up the newest version of $CATALOG_PKG in GitHub Packages…"
  VERSIONS_JSON="$(mktemp)"
  extra_pages=()
  page=1
  output="$VERSIONS_JSON"
  while :; do
    : > "$SNAPSHOT/package-headers"
    curl -fsSL --proto '=https' --proto-redir '=https' \
      -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -D "$SNAPSHOT/package-headers" \
      "https://api.github.com/orgs/$OWNER/packages/maven/$CATALOG_PKG/versions?per_page=100&page=$page" -o "$output"
    grep -Eiq '^link:.*rel="next"' "$SNAPSHOT/package-headers" || break
    page=$((page + 1))
    output="$SNAPSHOT/package-versions-$page.json"
    extra_pages+=("$output")
  done
  # Bez argumentu: najnowsze wydanie BIEŻĄCEGO majora; nowy MAJOR tylko jawnie (ADR-0002).
  python3 - "$VERSIONS_JSON" "$CURRENT" "$YANKED_FILE" ${extra_pages[@]+"${extra_pages[@]}"} > "$SNAPSHOT/choice" <<'PY'
# platform-bump:target — marker wycinania dla frontend/packages/versions/test/release-notes.test.sh
import json, re, sys

versions_path, current = sys.argv[1], sys.argv[2]
# Opcjonalna lista wycofanych wydań: pierwsze słowo linii to wersja, # zaczyna komentarz.
yanked = set()
if len(sys.argv) > 3:
    for line in open(sys.argv[3]):
        words = line.split("#", 1)[0].split()
        if words:
            yanked.add(words[0])
key = lambda version: [int(part) for part in version.split(".")]
releases = sorted(
    (
        v["name"]
        for page in [versions_path, *sys.argv[4:]]
        for v in json.load(open(page))
        if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", v["name"]) and v["name"] not in yanked
    ),
    key=key,
)
if releases:
    same_major = [v for v in releases if current and v.split(".")[0] == current.split(".")[0]]
    if current and not same_major:
        sys.exit(f"No published release for major {current.split('.')[0]} in the package listing. Pass an explicit version to change major.")
    print(same_major[-1] if same_major else releases[-1], releases[-1])
PY
  NEWEST=""
  read -r TARGET NEWEST < "$SNAPSHOT/choice" || true
  if [[ -n "${NEWEST:-}" ]] && [[ "${NEWEST%%.*}" != "${TARGET%%.*}" ]]; then
    echo "NOTE: Platform $NEWEST starts a new MAJOR and is not taken automatically."
    echo "      Read its release notes, then run platform-bump $NEWEST to cross it."
  fi
fi
[[ -z "$TARGET" ]] && { echo "Could not determine the target version."; exit 1; }
TARGET_SCOPE="$(npm_scope "$TARGET")"
YANKED_REASON="$(yanked_line "$TARGET")"
if [[ -n "$YANKED_REASON" ]]; then
  if [[ "$ALLOW_YANKED" != true ]]; then
    echo "Platform $TARGET is yanked: $YANKED_REASON" >&2
    echo "Bump to the replacement it names, or pass --allow-yanked to take it anyway. Nothing was changed." >&2
    exit 1
  fi
  echo "WARNING: Platform $TARGET is yanked ($YANKED_REASON); --allow-yanked takes it anyway."
fi
if [[ "$PRINT_TARGET" == true ]]; then
  echo "$TARGET"
  exit 0
fi

# Handoff (N-DX-4): ta kopia nie jest wydaniem celu, więc dalej biegnie bin z paczki versions@TARGET.
# platform-bump:handoff
if [[ -n "$SELF_VERSION" && "$SELF_VERSION" != "$TARGET" && "${PLATFORM_BUMP_HANDOFF:-}" != "$TARGET" ]]; then
  handoff_status=0
  handoff_root="$(fetch_platform_cli "$TARGET")" || handoff_status=$?
  [[ "$handoff_status" -eq 2 ]] && exit 1
  if [[ "$handoff_status" -eq 0 ]]; then
    echo "==> Platform $TARGET runs its own bump logic (this copy is $SELF_VERSION)"
    rm -rf "$SNAPSHOT"
    rm -f "$VERSIONS_JSON" "$YANKED_FILE"
    PLATFORM_BUMP_HANDOFF="$TARGET" exec bash "$handoff_root/bin/platform-bump.sh" ${PASS_ARGS[@]+"${PASS_ARGS[@]}"} "$TARGET"
  fi
  if [[ "${TARGET%%.*}" -ge 2 ]]; then
    echo "Could not authenticate and load the CLI from the Platform $TARGET release assets; the bump cannot continue." >&2
    exit 1
  fi
  echo "WARNING: the release assets of Platform $TARGET could not be read, so this bump runs the logic of $SELF_VERSION."
fi
# Logika celu bez frontendu: ta kopia JEST wydaniem celu, więc migracje i kontrakt workflowów są tutaj.
TARGET_ROOT=""
[[ -n "$SELF_VERSION" && "$SELF_VERSION" == "$TARGET" ]] && TARGET_ROOT="$SELF_ROOT"
# platform-bump:handoff-end
echo "==> Moving the Platform pins to: $TARGET"
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

# Raport wpływu (N-REL-8): katalogi obu wydań z GitHub Packages, kanon i kontrakt workflowów z paczek versions
# (cel: ta kopia albo asset, obecny pin: asset), przecięte z tym, czego repo używa. Przed pierwszym zapisem.
# platform-bump:report
if [[ -n "$REPORT" ]]; then
  report_dir="$(mktemp -d)"
  for side in old new; do
    version="$CURRENT"; [[ "$side" == new ]] && version="$TARGET"
    [[ -n "$version" ]] || continue
    curl -fsSL --proto '=https' -u "${GITHUB_ACTOR:-platform-bump}:$TOKEN" \
      "https://maven.pkg.github.com/seniordeveloper-pl-dominik-sienkiewicz/Platform/pl/seniordeveloper/platform-catalog/$version/platform-catalog-$version.toml" \
      -o "$report_dir/$side.toml" 2>/dev/null || rm -f "$report_dir/$side.toml"
    root=""
    if [[ "$side" == new && -n "$TARGET_ROOT" ]]; then
      root="$TARGET_ROOT"
    else
      root="$(fetch_platform_cli "$version" 2>/dev/null)" || root=""
    fi
    if [[ -n "$root" ]]; then
      cp "$root/versions.json" "$report_dir/$side.json" 2>/dev/null || true
      cp "$root/workflow-contract.txt" "$report_dir/$side.txt" 2>/dev/null || true
    fi
  done
  report_args=(--repo . --current "${CURRENT:-unknown}" --target "$TARGET")
  for part in catalog:toml canon:json contract:txt; do
    report_args+=("--${part%%:*}-old" "$report_dir/old.${part##*:}" "--${part%%:*}-new" "$report_dir/new.${part##*:}")
  done
  if [[ -f "$SELF_ROOT/bin/bump-report.py" ]]; then
    python3 "$SELF_ROOT/bin/bump-report.py" "${report_args[@]}" > "$report_dir/report.md"
    if [[ "$REPORT" == "-" ]]; then
      echo ""
      cat "$report_dir/report.md"
    else
      cp "$report_dir/report.md" "$REPORT"
      echo "==> Impact report on this repository: $REPORT"
    fi
  else
    echo "WARNING: this copy of platform-bump has no bump-report.py, so --report has nothing to print."
  fi
  rm -rf "$report_dir"
fi
# platform-bump:report-end

# Od tego miejsca bump pisze: migawka każdego pliku-kandydata, który błąd albo --dry-run przywraca.
snapshot

if [[ "${TARGET%%.*}" -ge 2 ]]; then
  coordinates="$SELF_ROOT/migrations/lib/organization.py"
  python3 "$coordinates" files "$PLATFORM_NPM_PACKAGES" > "$SNAPSHOT/coordinates"
  while IFS= read -r -d '' migrated; do snapshot_file "$migrated"; done < "$SNAPSHOT/coordinates"
  python3 "$coordinates" apply "$PLATFORM_NPM_PACKAGES" < "$SNAPSHOT/coordinates"
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

# --- Frontend: piny pakietów Platform i kanon z wydania docelowego ---
if [[ -f frontend/package.json ]]; then
  python3 - "$TARGET" "$PLATFORM_NPM_PACKAGES" <<'PY'
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

t=sys.argv[1]
scope = "@dominiksienkiewicz/" if int(t.split(".")[0]) < 2 else "@seniordeveloper-pl-dominik-sienkiewicz/"
packages = {scope + name for name in sys.argv[2].split()}
p="frontend/package.json"
d=json.load(open(p))
def to_target(node, key, name, version, at):
    if name in packages: node[key]=t
for sec in ("dependencies","devDependencies","optionalDependencies","peerDependencies"):
    for k in list(d.get(sec,{})):
        if k in packages: d[sec][k]=t
walk(d.get("overrides",{}), "overrides", None, to_target)
json.dump(d,open(p,"w"),indent=2,ensure_ascii=False); open(p,"a").write("\n")
PY

  # Kanon: pobierz tarball versions@TARGET, nałóż versions.json na package.json (tylko wspólne klucze).
  TMPD="$(mktemp -d)"
  TARGET_PACKAGE="$TMPD"
  # Tylko brak wydania (E404/ETARGET) jest ostrzeżeniem; 401, sieć i reszta zatrzymują bump z komunikatem npm,
  # bo cicho pominięty kanon wychodzi dopiero jako dryf w CI (test: frontend/packages/versions/test/npm-pack-errors.test.sh).
  if ( cd frontend && GITHUB_TOKEN="$TOKEN" npm pack "@$TARGET_SCOPE/versions@$TARGET" --pack-destination "$TMPD" >/dev/null 2>"$TMPD/pack.err" ); then
    verify_provenance "$TMPD/$TARGET_SCOPE-versions-$TARGET.tgz"
    tar -xzf "$TMPD/$TARGET_SCOPE-versions-$TARGET.tgz" -C "$TMPD"
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
print("Frontend canon:", *changed, sep="\n  ") if changed else print("Frontend canon: no changes")
PY
  elif [[ "${TARGET%%.*}" -lt 2 ]] && grep -qE 'E404|ETARGET' "$TMPD/pack.err"; then
    echo "WARNING: @$TARGET_SCOPE/versions@$TARGET is not published, so the frontend canon was not applied."
  else
    echo "ERROR: npm pack @$TARGET_SCOPE/versions@$TARGET failed, so the frontend canon was not applied:" >&2
    cat "$TMPD/pack.err" >&2
    echo "Fix the error above and run the bump again." >&2
    rm -rf "$TMPD"
    exit 1
  fi
fi

# --- Reusable workflows Platform: `uses: …/Platform/.github/workflows/<w>.yml@<ref>` i wejście `platform-ref:`
#     callera promote.yml idą na v$TARGET razem z pinami (Decyzja 3: dokładny tag przesuwany przez bump). Ruchome
#     @v1 też przechodzi na dokładny tag — to migracja z Decyzji 3; referencje po SHA zostają nietknięte. ---
# platform-bump:workflows
for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
  [[ -f "$workflow" ]] || continue
  sed -i.bak -E \
    -e "s#(uses:[[:space:]]*)DominikSienkiewicz/Platform/(\.github/workflows/)#\1$OWNER/Platform/\2#" \
    -e "s#(uses:[[:space:]]*$OWNER/Platform/\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml@)v[0-9]+(\.[0-9]+\.[0-9]+)?([[:space:]]|\$)#\1v$TARGET\3#" \
    -e "s#^([[:space:]]*platform-ref:[[:space:]]*)[\"']?v[0-9]+(\.[0-9]+\.[0-9]+)?[\"']?[[:space:]]*\$#\1v$TARGET#" \
    "$workflow" && rm -f "$workflow.bak"
done
# platform-bump:workflows-end

# --- Migracje wydania docelowego (versions/migrations): runner i migracje z rozpakowanego tarballa celu, nie
#     z zainstalowanej kopii, więc bump zawsze wykonuje logikę wydania, do którego idzie. Bez tarballa (wydanie
#     sprzed migracji, repo bez frontendu) nie ma czego uruchomić. ---
# platform-bump:migrations
TARGET_LOGIC="${TARGET_PACKAGE:+$TARGET_PACKAGE/package}"
TARGET_LOGIC="${TARGET_LOGIC:-$TARGET_ROOT}"
MIGRATIONS="${TARGET_LOGIC:+$TARGET_LOGIC/migrations/run.sh}"
if [[ -n "$MIGRATIONS" ]] && [[ -f "$MIGRATIONS" ]]; then
  while IFS= read -r migrated; do snapshot_file "$migrated"; done < <(bash "$MIGRATIONS" files "$CURRENT" "$TARGET")
  echo "==> Upgrade migrations from ${CURRENT:-an unknown pin} to $TARGET:"
  PLATFORM_CANON="$TARGET_LOGIC/versions.json" bash "$MIGRATIONS" apply "$CURRENT" "$TARGET"
fi
# platform-bump:migrations-end

# --- Bloki platform-agents (N-SHOW-1): reguły dla agentów z wydania docelowego, tylko między markerami; reszta pliku
#     bez zmian, brak markerów = blok dopisany na końcu, brak pliku = nowy plik. Główny blok trafia do AGENTS.md, blok
#     backendu do backend/AGENTS.md (albo do AGENTS.md, gdy Gradle stoi w korzeniu), blok frontendu do
#     frontend/AGENTS.md; stos biorą ze stack.json i versions.json wydania docelowego. Obok każdego z tych plików
#     powstaje CLAUDE.md z `@AGENTS.md`, gdy go nie ma; istniejącego CLAUDE.md bump nie zmienia. ---
# platform-bump:agents
agents_dir="${TARGET_LOGIC:+$TARGET_LOGIC/agents}"
sync_agents_block() {
  local template="$agents_dir/$1" target=$2 outcome claude
  shift 2
  [[ -f "$template" ]] || return 0
  snapshot_file "$target"
  outcome=$(python3 "$TARGET_LOGIC/bin/sync-agents-block.py" "$template" "$TARGET" "$target" "$@") \
    || outcome="not written (see the error above)"
  echo "==> $target, $(sed -n -E '1s/^<!-- BEGIN ([a-z-]+) .*/\1/p' "$template") block of $TARGET: $outcome"
  claude="$(dirname "$target")/CLAUDE.md"
  claude="${claude#./}"
  if [[ ! -e "$claude" ]]; then
    snapshot_file "$claude"
    printf '@AGENTS.md\n' > "$claude"
    echo "==> $claude created: it imports @AGENTS.md, so Claude Code reads the same guidance"
  elif ! grep -qE '^@(\./)?AGENTS\.md[[:space:]]*$' "$claude"; then
    echo "==> $claude does not import @AGENTS.md; add that line so Claude Code reads the Platform block"
  fi
}
if [[ -n "$agents_dir" ]] && [[ -f "$TARGET_LOGIC/bin/sync-agents-block.py" ]]; then
  sync_agents_block platform-block.md AGENTS.md
  if [[ -f backend/build.gradle.kts || -f backend/settings.gradle.kts ]]; then
    sync_agents_block backend-block.md backend/AGENTS.md "$agents_dir/stack.json"
  elif [[ -f settings.gradle.kts || -f build.gradle.kts ]]; then
    sync_agents_block backend-block.md AGENTS.md "$agents_dir/stack.json"
  fi
  if [[ -f frontend/package.json ]]; then
    sync_agents_block frontend-block.md frontend/AGENTS.md "$TARGET_LOGIC/versions.json"
  fi
fi
# platform-bump:agents-end

# --- Callerzy reusable workflowów Platform kontra kontrakt wydania docelowego (workflow-contract.txt z tarballa):
#     brak uprawnienia, nieznane wejście albo sekret = startup_failure bez logu. Tylko raport, kod wyjścia bez zmian,
#     bo błąd cofnąłby cały bump; samodzielny platform-workflows-check kończy się wtedy kodem 1. ---
# platform-bump:workflows-check
checker="${TARGET_LOGIC:+$TARGET_LOGIC/bin/workflows-check.py}"
if [[ -n "$checker" ]] && [[ -f "$checker" ]] && compgen -G ".github/workflows/*.y*ml" >/dev/null; then
  echo ""
  echo "==> Callers of Platform's reusable workflows against the contract of v$TARGET:"
  python3 "$checker" --ref "v$TARGET" --contract "$TARGET_LOGIC/workflow-contract.txt" \
    || echo "Fix the ERROR lines before you push: GitHub ends those runs in startup_failure."
fi
# platform-bump:workflows-check-end

# --- Dry run: pokaż zmienione linie względem migawki i zakończ; finish() przywraca pliki, Gradle nie rusza. ---
# platform-bump:dry-run
if [[ "$DRY_RUN" == true ]]; then
  echo "==> Dry run: proposed changes for $TARGET"
  for file in "${CANDIDATES[@]}"; do
    if [[ -s "$SNAPSHOT/coordinates" || "$file" == *.npmrc ]]; then
      [[ -f "$file" ]] && ! cmp -s "$SNAPSHOT/files/$file" "$file" || continue
      printf 'Updated %s\n' "$file"
      case "$file" in
        frontend/package.json)
          diff -U0 "$SNAPSHOT/files/$file" "$file" | grep -E '^[-+][[:space:]]*"[@a-zA-Z0-9_./-]+":[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+",?$' || true ;;
        .github/workflows/*.yml|.github/workflows/*.yaml)
          diff -U0 "$SNAPSHOT/files/$file" "$file" | grep -E '^[-+][[:space:]]*uses: (DominikSienkiewicz|SeniorDeveloper-pl-Dominik-Sienkiewicz)/Platform/\.github/workflows/[a-zA-Z0-9_-]+\.ya?ml@[a-zA-Z0-9.]+[[:space:]]*$' || true ;;
      esac
    elif [[ -e "$SNAPSHOT/files/$file" ]]; then
      diff -u --label "a/$file" --label "b/$file" "$SNAPSHOT/files/$file" "$file" || true
    elif [[ -e "$file" ]]; then
      diff -u --label /dev/null --label "b/$file" /dev/null "$file" || true
    fi
  done
  echo "A real bump also runs npm install --package-lock-only, updates the Gradle wrapper and regenerates the lockfiles and verification metadata."
  if [[ -s "$ACTIONS_FILE" ]]; then
    echo ""
    echo "==> CONSUMER ACTION REQUIRED by the releases this bump crosses:"
    cat "$ACTIONS_FILE"
  fi
  exit 0
fi
# platform-bump:dry-run-end

# Lockfile npm po pinach, kanonie i migracjach (migracje wydania mogą zmienić rozwiązywanie).
if [[ -f frontend/package.json ]]; then
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
#     Katalog bez wpisu `gradle` (starsze wydania) albo niedostępny = wrapper bez zmian. Tylko w górę: wrapper
#     nowszy niż kanon to świadomy wybór repo (Training jechał na 9.8.2, gdy kanon miał 9.8.1), więc zostaje. ---
# platform-bump:wrapper
# 0, gdy wersja $1 jest nowsza niż $2; pola X.Y.Z porównane jako liczby, brakujące pole = 0.
gradle_newer() {
  local -a newer older
  local field
  IFS=. read -r -a newer <<<"$1"
  IFS=. read -r -a older <<<"$2"
  for field in 0 1 2; do
    (( ${newer[field]:-0} > ${older[field]:-0} )) && return 0
    (( ${newer[field]:-0} < ${older[field]:-0} )) && return 1
  done
  return 1
}
for wrapper_dir in backend .; do
  props="$wrapper_dir/gradle/wrapper/gradle-wrapper.properties"
  [[ -f "$props" && -x "$wrapper_dir/gradlew" ]] || continue
  catalog_toml="$(mktemp)"
  if curl -fsSL --proto '=https' -u "${GITHUB_ACTOR:-platform-bump}:$TOKEN" \
    "https://maven.pkg.github.com/seniordeveloper-pl-dominik-sienkiewicz/Platform/pl/seniordeveloper/platform-catalog/$TARGET/platform-catalog-$TARGET.toml" \
    -o "$catalog_toml" 2>/dev/null; then
    gradle_target="$(sed -n -E 's/^gradle[[:space:]]*=[[:space:]]*"([0-9.]+)".*/\1/p' "$catalog_toml" | head -1)"
    gradle_current="$(sed -n -E 's#^distributionUrl=.*gradle-([0-9.]+)-(bin|all)\.zip.*#\1#p' "$props" | head -1)"
    if [[ -n "$gradle_target" && "$gradle_target" != "$gradle_current" ]]; then
      if [[ -n "$gradle_current" ]] && gradle_newer "$gradle_current" "$gradle_target"; then
        echo "==> Gradle wrapper: $gradle_current is newer than $gradle_target of the catalog, so it stays"
      else
        echo "==> Gradle wrapper: $gradle_current -> $gradle_target"
        gradle_sum="$(curl -fsSL --proto '=https' "https://services.gradle.org/distributions/gradle-$gradle_target-bin.zip.sha256")"
        ( cd "$wrapper_dir" && ./gradlew wrapper --gradle-version "$gradle_target" --gradle-distribution-sha256-sum "$gradle_sum" --no-daemon )
      fi
    fi
  fi
  rm -f "$catalog_toml"
  break
done
# platform-bump:wrapper-end

# platform-bump:gradle
if [[ -f backend/settings.gradle.kts ]]; then
  echo "==> Backend: regenerating the locked state (--write-locks)"
  if [[ -f backend/gradle/verification-metadata.xml ]]; then
    ( cd backend && ./gradlew build --write-locks --write-verification-metadata sha256 --refresh-dependencies --no-daemon )
    echo "==> Backend: completing the verification metadata for every configuration (dependencies)"
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

echo "==> Done. Review the diff (gradle.lockfile, verification-metadata.xml) and commit it:"
git --no-pager diff --stat

if [[ -s "$ACTIONS_FILE" ]]; then
  echo ""
  echo "==> CONSUMER ACTION REQUIRED by the releases this bump crosses:"
  cat "$ACTIONS_FILE"
  echo ""
fi
echo "Release notes: https://github.com/$OWNER/Platform/releases/tag/v$TARGET"
