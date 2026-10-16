#!/usr/bin/env bash
# release.sh — świadome wydanie Platform (publish-only, deliberate versioning).
#
# Bumpuje platformVersion we wszystkich miejscach, commituje TWOIM message, taguje vX.Y.Z
# i pcha main + tag. Release publikuje Maven+npm dopiero po zielonym CI na tym commicie
# i wtedy sam przesuwa ruchomy tag v1 (job move-v1).
#
# Odmawia przed jakąkolwiek zmianą, gdy drzewo robocze nie jest czyste, bieżąca gałąź to nie
# main albo HEAD różni się od origin/main — commit wydania zawiera wyłącznie pliki wersji.
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

PROP="gradle/build-logic/gradle.properties"
PROPERTY_FILES=("$PROP" gradle/catalog/gradle.properties gradle/test-fixtures/gradle.properties)
CATALOG_BUILD="gradle/catalog/build.gradle.kts"
for f in "${PROPERTY_FILES[@]}" "$CATALOG_BUILD"; do
  [[ -f "$f" ]] || { echo "Brak $f — uruchom z roota repo Platform."; exit 1; }
done

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

echo "Plan: $CUR -> $VERSION   branch: $BR   commit: \"$MSG\""
if [[ "${3:-}" != "-y" ]] && [[ "${ASSUME_YES:-}" != "1" ]]; then
  read -r -p "Kontynuować (commit + tag v$VERSION + push)? [y/N] " ans
  [[ "$ans" = "y" ]] || [[ "$ans" = "Y" ]] || { echo "Przerwane."; exit 0; }
fi

# Bump: 3× gradle.properties + lustro defaultu w catalogu.
for f in "${PROPERTY_FILES[@]}"; do
  sed -i.bak -E "s/^platformVersion=.*/platformVersion=$VERSION/" "$f"
  rm -f "$f.bak"
done
sed -i.bak -E "s/getOrElse\(\"[0-9]+\.[0-9]+\.[0-9]+\"\)/getOrElse(\"$VERSION\")/g" "$CATALOG_BUILD"
rm -f "$CATALOG_BUILD.bak"

git add -- "${PROPERTY_FILES[@]}" "$CATALOG_BUILD"
git commit -m "$MSG"
git push origin main
git tag "v$VERSION"
git push origin "v$VERSION"

echo ""
echo "════════════════════════════════════════════════"
echo "  Platform podbity: $CUR → $VERSION"
echo "  Tag: v$VERSION (v1 przesunie Release po zielonej publikacji)"
echo "  Branch: $BR   Commit: \"$MSG\""
echo "════════════════════════════════════════════════"
echo "==> Release weryfikuje CI i publikuje z taga: Actions → Release."
echo "==> U konsumenta: ./scripts/platform-bump.sh $VERSION   (podbije piny do $VERSION)"
