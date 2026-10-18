#!/usr/bin/env bash
# release.sh — świadome wydanie Platform (publish-only, deliberate versioning).
#
# Bumpuje platformVersion we wszystkich miejscach, commituje jako "chore(release): platform X.Y.Z"
# z TWOIM message w body, taguje annotated vX.Y.Z treścią sekcji CHANGELOG.md i pcha main + tag.
# Release publikuje Maven+npm dopiero po zielonym CI na tym commicie, tworzy GitHub Release z tej
# samej sekcji i wtedy sam przesuwa ruchomy tag v1 (job move-v1).
#
# Odmawia przed jakąkolwiek zmianą, gdy drzewo robocze nie jest czyste, bieżąca gałąź to nie
# main albo HEAD różni się od origin/main — commit wydania zawiera wyłącznie pliki wersji.
# Kontrakt (docs/adr/0002-release-and-versioning-contract.md) — odmawia też, gdy:
#   - message nie jest angielskim Conventional Commit;
#   - CHANGELOG.md nie ma sekcji "## [X.Y.Z] - YYYY-MM-DD" z podsekcją "### Consumer action required";
#   - wydanie z akcją konsumenta (podsekcja inna niż "None.") miałoby być patchem;
#   - message feat / "!:" / BREAKING CHANGE miałby dostać automatyczny patch (podaj wersję jawnie).
#
# Użycie:
#   ./release.sh "fix: opis zmiany"            # patch +0.0.1 od aktualnej wersji
#   ./release.sh "feat: opis" 1.2.0            # konkretna wersja
#   ./release.sh "..." 1.2.0 -y                # bez pytania o potwierdzenie (też: ASSUME_YES=1)
set -euo pipefail
cd "$(dirname "$0")"   # zawsze z roota Platform

MSG="${1:-}"
VERSION="${2:-}"
[[ -z "$MSG" ]] && { echo "Użycie: ./release.sh \"commit message\" [X.Y.Z] [-y]"; exit 1; }
AUTO_VERSION=0
[[ -z "$VERSION" ]] && AUTO_VERSION=1

# Message wydania = body commita "chore(release): platform X.Y.Z": angielski Conventional Commit.
CONVENTIONAL='^(feat|fix|docs|chore|refactor|test|build|ci|perf|revert)(\([a-z0-9-]+\))?!?: .+'
head -1 <<< "$MSG" | grep -Eq "$CONVENTIONAL" \
  || { echo "The release message must be a Conventional Commit, e.g. \"fix: short description\" (got \"$MSG\")."; exit 1; }
if LC_ALL=C grep -Eq 'ą|ć|ę|ł|ń|ó|ś|ź|ż|Ą|Ć|Ę|Ł|Ń|Ó|Ś|Ź|Ż' <<< "$MSG"; then
  echo "Release messages are in English; this one contains Polish characters."; exit 1
fi

PROP="gradle/build-logic/gradle.properties"
[[ -f "$PROP" ]] || { echo "Brak $PROP — uruchom z roota repo Platform."; exit 1; }
# Każdy plik niosący platformVersion: moduły Gradle, startery JVM i paczki npm (jedna wersja w całym
# drzewie — pilnuje templates/tests/platform-version-sync.test.sh). Globy, nie lista: nowy moduł
# albo paczka wchodzą do wydania same.
shopt -s nullglob
PROPERTY_FILES=(gradle/*/gradle.properties templates/jvm/*/gradle.properties)
PACKAGE_FILES=(frontend/packages/*/package.json)
shopt -u nullglob
[[ "${#PACKAGE_FILES[@]}" -gt 0 ]] || { echo "Brak frontend/packages/*/package.json — uruchom z roota repo Platform."; exit 1; }

BR="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BR" == "main" ]] || { echo "Wydanie tylko z main — bieżąca gałąź: $BR."; exit 1; }
if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "Drzewo robocze nie jest czyste — commit wydania może zawierać wyłącznie podbicie wersji:"
  git status --short --untracked-files=all
  exit 1
fi
git fetch --quiet origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
  || { echo "HEAD różni się od origin/main — zsynchronizuj main przed wydaniem."; exit 1; }

CUR="$(grep -E '^platformVersion=' "$PROP" | cut -d= -f2 | tr -d ' ')"

# Wersja: jawna (arg 2) albo patch +0.0.1 od aktualnej.
if [[ -z "$VERSION" ]]; then
  echo "$CUR" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || { echo "Aktualne platformVersion '$CUR' nie jest X.Y.Z — podaj wersję jawnie."; exit 1; }
  IFS='.' read -r MA MI PA <<< "$CUR"
  VERSION="$MA.$MI.$((PA + 1))"
fi
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Wersja '$VERSION' nie jest X.Y.Z"; exit 1; }

# Wersje są immutable — tag nie może już istnieć.
if git rev-parse "v$VERSION" >/dev/null 2>&1 || git ls-remote --exit-code --tags origin "v$VERSION" >/dev/null 2>&1; then
  echo "Tag v$VERSION już istnieje (wersje immutable). Podaj wyższą."; exit 1
fi

# Notatki wydania: sekcja CHANGELOG.md tej wersji (jedno źródło dla taga, GitHub Release i platform-bump).
CONTRACT="docs/adr/0002-release-and-versioning-contract.md"
SECTION="$(bash scripts/changelog-section.sh "$VERSION" CHANGELOG.md)" || {
  echo "CHANGELOG.md has no \"## [$VERSION] - YYYY-MM-DD\" section. Move the [Unreleased] entries under it in a commit, then release."
  exit 1
}
ACTION="$(bash scripts/changelog-section.sh --consumer-action "$VERSION" CHANGELOG.md)" || {
  echo "The $VERSION section of CHANGELOG.md has no \"### Consumer action required\" subsection; write \"None.\" when nothing is required."
  exit 1
}

# Numeracja (decyzja 2): akcja konsumenta = MINOR w linii 1.x; feat/breaking wymaga jawnej wersji.
IFS='.' read -r VMA VMI _ <<< "$VERSION"
NEXT_MINOR="$VMA.$((VMI + 1)).0"
if [[ "$AUTO_VERSION" == 1 ]] && { grep -Eq '^[a-z]+(\([a-z0-9-]+\))?!:|^feat' <<< "$MSG" || grep -q 'BREAKING CHANGE' <<< "$MSG"; }; then
  echo "A feat or breaking release needs an explicit version: ./release.sh \"$MSG\" <X.Y.Z> (see $CONTRACT)."
  exit 1
fi
if [[ "${VERSION%.*}" == "${CUR%.*}" ]] && ! [[ "$ACTION" =~ ^None\.?$ ]]; then
  echo "CHANGELOG.md lists consumer action for $VERSION, so it must be a MINOR release:"
  echo "  rename the section to $NEXT_MINOR, commit, then: ./release.sh \"$MSG\" $NEXT_MINOR"
  echo "See $CONTRACT."
  exit 1
fi

echo "Plan: $CUR -> $VERSION   branch: $BR   commit: \"chore(release): platform $VERSION\""
echo "Release notes (CHANGELOG.md):"
printf '  %s\n' "${SECTION//$'\n'/$'\n'  }"
if [[ "${3:-}" != "-y" ]] && [[ "${ASSUME_YES:-}" != "1" ]]; then
  read -r -p "Kontynuować (commit + tag v$VERSION + push)? [y/N] " ans
  [[ "$ans" = "y" ]] || [[ "$ans" = "Y" ]] || { echo "Przerwane."; exit 0; }
fi

# Bump: platformVersion w gradle.properties modułów i starterów + "version" paczek npm.
for f in "${PROPERTY_FILES[@]}"; do
  sed -i.bak -E "s/^platformVersion=.*/platformVersion=$VERSION/" "$f"
  rm -f "$f.bak"
done
for f in "${PACKAGE_FILES[@]}"; do
  sed -i.bak -E "s/^(  \"version\": )\"[^\"]*\"/\1\"$VERSION\"/" "$f"
  rm -f "$f.bak"
done

git add -- "${PROPERTY_FILES[@]}" "${PACKAGE_FILES[@]}"
git commit -m "chore(release): platform $VERSION" -m "$MSG"
git push origin main
# --cleanup=verbatim: domyślne "strip" wycina linie zaczynające się od '#', czyli nagłówki Markdown sekcji.
TAG_MESSAGE="$(mktemp)"
trap 'rm -f "$TAG_MESSAGE"' EXIT
printf 'Platform %s\n\n%s\n' "$VERSION" "$SECTION" > "$TAG_MESSAGE"
git tag -a --cleanup=verbatim -F "$TAG_MESSAGE" "v$VERSION"
git push origin "v$VERSION"

echo ""
echo "════════════════════════════════════════════════"
echo "  Platform podbity: $CUR → $VERSION"
echo "  Tag: v$VERSION (v1 przesunie Release po zielonej publikacji)"
echo "  Branch: $BR   Commit: \"chore(release): platform $VERSION\" ($MSG)"
echo "════════════════════════════════════════════════"
echo "==> Release weryfikuje CI i publikuje z taga: Actions → Release."
echo "==> U konsumenta: ./scripts/platform-bump.sh $VERSION   (podbije piny do $VERSION)"
