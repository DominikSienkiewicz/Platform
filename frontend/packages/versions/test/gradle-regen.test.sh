#!/usr/bin/env bash
# Test bloku regeneracji zamrożonego stanu backendu z bin/platform-bump.sh — doboru flag `./gradlew`.
#
# Blok jest WYCINANY ze skryptu po markerach (`# platform-bump:gradle` / `# platform-bump:gradle-end`)
# i uruchamiany osobno, przeciwko atrapie `gradlew`, która tylko zapisuje swoje argumenty. Dzięki temu
# testujemy dokładnie ten kod, który leci w produkcji, bez JDK, sieci i realnego builda Gradle.
# Markery to kontrakt: jeśli je usuniesz lub przemianujesz, ten test przestanie znajdować kod i zafailuje.
# Atrapa DOPISUJE (>>) kolejne wywołania, po jednym w linii — kolejność przebiegów jest częścią kontraktu.
#
# Regresja 1: wariant z verification-metadata.xml wołał Gradle BEZ --refresh-dependencies.
# Przy ciepłym cache Gradle serwuje metadane modułu ze swojego magazynu i nie dotyka pliku `.module`,
# więc jego checksum nie trafiał do verification-metadata.xml mimo włączonej flagi zapisu. Lokalnie
# build był zielony, a CI na zimnym cache failował `Dependency verification failed` (junit-bom 5.14.4
# zapisany tylko jako `.pom` — BookOfStyling i SkillSprintPlus po bumpie 1.5.4 -> 1.5.22).
#
# Regresja 2: wariant z verification-metadata.xml miał TYLKO przebieg `build`, więc domykał wyłącznie
# konfiguracje z grafu tego zadania. `junit-bom-<wersja>.pom` jest pobierany dopiero w detached
# configuration, którą io.spring.dependency-management (MavenPomResolver.resolvePomsLeniently) tworzy
# przy ustalaniu zależności `:integrationTest` — a `.module` tej samej wersji leci normalną ścieżką,
# więc plik wygląda na kompletny. Po bumpie 1.5.26 (junit 6.1.0 -> 6.1.3) CI Azimutha i SkillSprintPlus
# padło na `One artifact failed verification: junit-bom-6.1.3.pom`. Drugi przebieg (`dependencies` bez
# --configuration) domyka metadane WSZYSTKICH resolvable konfiguracji — również narzędziowych
# (checkstyle/spotbugs/jacoco/pitest/cyclonedx), które wracały jako ta sama klasa błędu.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/bin/platform-bump.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Wycina ciało bloku między markerem otwierającym a zamykającym (bez samych markerów).
extract() {
  awk '
    index($0, "# platform-bump:gradle-end") { exit }
    f { print }
    index($0, "# platform-bump:gradle")     { f = 1 }
  ' "$SRC"
}

extract > "$WORK/gradle.sh"
[[ -s "$WORK/gradle.sh" ]] || { echo "FAIL: nie znaleziono bloku '# platform-bump:gradle' w $SRC"; exit 1; }

fails=0
fail() { echo "FAIL: $1"; echo "--- zapisane wywołania ---"; cat "$REPO/gradlew.args" 2>/dev/null || echo "(brak — gradlew nie został wywołany)"; fails=1; }

# Atrapa repo konsumenta: `backend/gradlew` dopisuje argumenty zamiast cokolwiek budować.
# $with_metadata decyduje, którą gałąź `if` w bloku wybierzemy.
setup_repo() {
  local case_name="$1" with_metadata="$2"
  REPO="$WORK/repo-$case_name"
  mkdir -p "$REPO/backend/gradle"
  : > "$REPO/backend/settings.gradle.kts"
  [[ "$with_metadata" = "yes" ]] && : > "$REPO/backend/gradle/verification-metadata.xml"
  cat > "$REPO/backend/gradlew" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$(cd "$(dirname "$0")/.." && pwd)/gradlew.args"
STUB
  chmod +x "$REPO/backend/gradlew"
}

run_block() { ( cd "$REPO" && bash "$WORK/gradle.sh" >/dev/null ); }

# Argumenty n-tego wywołania gradlew (1-indeksowane) oraz ich liczba.
call() { sed -n "${1}p" "$REPO/gradlew.args"; }
call_count() { wc -l < "$REPO/gradlew.args" | tr -d ' '; }

# Wszystkie wymienione flagi muszą wystąpić w podanym wywołaniu.
expect_flags() {
  local args="$1" label="$2" flag
  shift 2
  for flag in "$@"; do
    case "$args" in
      *"$flag"*) ;;
      *) fail "$label: w wywołaniu gradlew brakuje '$flag'" ;;
    esac
  done
}

# --dry-run z --write-verification-metadata NIE zapisuje metadanych (Gradle odkłada je do
# verification-metadata.dryrun.xml) i kończy się BUILD SUCCESSFUL — cicha awaria, której ten
# test ma nie przepuścić do kanonu.
expect_no_dry_run() {
  case "$(cat "$REPO/gradlew.args" 2>/dev/null || true)" in
    *--dry-run*) fail "$1: --dry-run pomija zapis metadanych i kończy się BUILD SUCCESSFUL" ;;
  esac
}

# --- Przypadek 1: repo Z verification-metadata.xml -------------------------------------------------
# Dwa przebiegi o rozłącznych rolach; kolejność jest istotna, bo przy --write-locks wygrywa OSTATNI,
# a `dependencies` rozwiązuje nadzbiór konfiguracji zadania `build`.
setup_repo with-metadata yes
run_block
if [[ "$(call_count)" -ne 2 ]]; then
  fail "repo z verification-metadata: oczekiwano 2 wywołań gradlew, było $(call_count)"
fi

# Przebieg 1 — `build`: jako jedyny POBIERA artefakty, więc tylko on zapisuje checksumy jarów.
expect_flags "$(call 1)" "repo z verification-metadata, przebieg 1 (build)" \
  "build" "--write-locks" "--write-verification-metadata sha256" "--refresh-dependencies" "--no-daemon"

# Przebieg 2 — `dependencies` BEZ --configuration: domyka metadane (.pom/.module) wszystkich
# resolvable konfiguracji, także tych spoza grafu `build`. --write-locks jest tu obowiązkowe:
# lockfile konsumenta ma wpisy dla konfiguracji, których `build` nie rozwiązuje (pitest,
# cyclonedxBom), więc bez przepisania locka ten przebieg wywaliłby się na niezgodności lock state.
args="$(call 2)"
expect_flags "$args" "repo z verification-metadata, przebieg 2 (dependencies)" \
  "dependencies" "--write-locks" "--write-verification-metadata sha256" "--refresh-dependencies" "--no-daemon"
case "$args" in
  *--configuration*) fail "repo z verification-metadata, przebieg 2: --configuration zawęża przebieg do jednej konfiguracji" ;;
esac
expect_no_dry_run "repo z verification-metadata"

# --- Przypadek 2: repo BEZ verification-metadata.xml -----------------------------------------------
# Nie ma checksumów do zapisania, więc drugi przebieg i pełne przeliczenie byłyby czystym kosztem.
setup_repo without-metadata no
run_block
if [[ "$(call_count)" -ne 1 ]]; then
  fail "repo bez verification-metadata: oczekiwano 1 wywołania gradlew, było $(call_count)"
fi
args="$(call 1)"
expect_flags "$args" "repo bez verification-metadata" "dependencies" "--write-locks" "--no-daemon"
case "$args" in
  *--refresh-dependencies*) fail "repo bez verification-metadata: --refresh-dependencies nie powinno tu lecieć" ;;
esac
case "$args" in
  *--write-verification-metadata*) fail "repo bez verification-metadata: nie ma pliku, który miałby powstać" ;;
esac
expect_no_dry_run "repo bez verification-metadata"

# --- Przypadek 3: repo bez backendu ----------------------------------------------------------------
# Blok jest wołany też w repo frontendowych — nie może się wywrócić, gdy nie ma settings.gradle.kts.
REPO="$WORK/repo-no-backend"
mkdir -p "$REPO"
run_block || fail "repo bez backendu: blok zakończył się błędem zamiast po prostu nic nie robić"
[[ -f "$REPO/gradlew.args" ]] && fail "repo bez backendu: gradlew nie powinien zostać wywołany"

[[ "$fails" -eq 0 ]] && echo "gradle-regen: OK (3 przypadki)"
exit "$fails"
