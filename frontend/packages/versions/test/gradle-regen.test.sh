#!/usr/bin/env bash
# Test bloku regeneracji zamrożonego stanu backendu z bin/platform-bump.sh — doboru flag `./gradlew`.
#
# Blok jest WYCINANY ze skryptu po markerach (`# platform-bump:gradle` / `# platform-bump:gradle-end`)
# i uruchamiany osobno, przeciwko atrapie `gradlew`, która tylko zapisuje swoje argumenty. Dzięki temu
# testujemy dokładnie ten kod, który leci w produkcji, bez JDK, sieci i realnego builda Gradle.
# Markery to kontrakt: jeśli je usuniesz lub przemianujesz, ten test przestanie znajdować kod i zafailuje.
#
# Regresja: przed tą zmianą wariant z verification-metadata.xml wołał Gradle BEZ --refresh-dependencies.
# Przy ciepłym cache Gradle serwuje metadane modułu ze swojego magazynu i nie dotyka pliku `.module`,
# więc jego checksum nie trafiał do verification-metadata.xml mimo włączonej flagi zapisu. Lokalnie
# build był zielony, a CI na zimnym cache failował `Dependency verification failed` (junit-bom 5.14.4
# zapisany tylko jako `.pom` — BookOfStyling i SkillSprintPlus po bumpie 1.5.4 -> 1.5.22).
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
fail() { echo "FAIL: $1"; echo "--- zapisane wywołanie ---"; cat "$REPO/gradlew.args" 2>/dev/null || echo "(brak — gradlew nie został wywołany)"; fails=1; }

# Atrapa repo konsumenta: `backend/gradlew` zapisuje argumenty zamiast cokolwiek budować.
# $with_metadata decyduje, którą gałąź `if` w bloku wybierzemy.
setup_repo() {
  local case_name="$1" with_metadata="$2"
  REPO="$WORK/repo-$case_name"
  mkdir -p "$REPO/backend/gradle"
  : > "$REPO/backend/settings.gradle.kts"
  [[ "$with_metadata" = "yes" ]] && : > "$REPO/backend/gradle/verification-metadata.xml"
  cat > "$REPO/backend/gradlew" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$(cd "$(dirname "$0")/.." && pwd)/gradlew.args"
STUB
  chmod +x "$REPO/backend/gradlew"
}

run_block() { ( cd "$REPO" && bash "$WORK/gradle.sh" >/dev/null ); }

# --- Przypadek 1: repo Z verification-metadata.xml -------------------------------------------------
# Wszystkie trzy flagi muszą polecieć razem; --refresh-dependencies jest tu sednem regresji.
setup_repo with-metadata yes
run_block
args="$(cat "$REPO/gradlew.args")"
for flag in "build" "--write-locks" "--write-verification-metadata sha256" "--refresh-dependencies" "--no-daemon"; do
  case "$args" in
    *"$flag"*) ;;
    *) fail "repo z verification-metadata: w wywołaniu gradlew brakuje '$flag'" ;;
  esac
done

# --- Przypadek 2: repo BEZ verification-metadata.xml -----------------------------------------------
# Tu nie ma checksumów do zapisania, więc pełne przeliczenie byłoby czystym kosztem — flagi nie ma.
setup_repo without-metadata no
run_block
args="$(cat "$REPO/gradlew.args")"
for flag in "dependencies" "--write-locks" "--no-daemon"; do
  case "$args" in
    *"$flag"*) ;;
    *) fail "repo bez verification-metadata: w wywołaniu gradlew brakuje '$flag'" ;;
  esac
done
case "$args" in
  *--refresh-dependencies*) fail "repo bez verification-metadata: --refresh-dependencies nie powinno tu lecieć" ;;
esac

# --- Przypadek 3: repo bez backendu ----------------------------------------------------------------
# Blok jest wołany też w repo frontendowych — nie może się wywrócić, gdy nie ma settings.gradle.kts.
REPO="$WORK/repo-no-backend"
mkdir -p "$REPO"
run_block || fail "repo bez backendu: blok zakończył się błędem zamiast po prostu nic nie robić"
[[ -f "$REPO/gradlew.args" ]] && fail "repo bez backendu: gradlew nie powinien zostać wywołany"

[[ "$fails" -eq 0 ]] && echo "gradle-regen: OK (3 przypadki)"
exit "$fails"
