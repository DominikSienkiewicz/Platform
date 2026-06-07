#!/usr/bin/env bash
# release.sh — świadome wydanie Platform (publish-only, deliberate versioning).
#
# Bumpuje platformVersion we wszystkich miejscach, commituje TWOIM message, taguje vX.Y.Z,
# pcha branch + tag (Release publikuje Maven+npm) i przesuwa ruchomy tag v1 (reusable workflows).
#
# Użycie:
#   ./release.sh "fix: opis zmiany"            # patch +0.0.1 od aktualnej wersji
#   ./release.sh "feat: opis" 1.2.0            # konkretna wersja
#   ./release.sh "..." 1.2.0 -y                # bez pytania o potwierdzenie (też: ASSUME_YES=1)
set -euo pipefail
cd "$(dirname "$0")"   # zawsze z roota Platform

MSG="${1:-}"
VERSION="${2:-}"
[ -z "$MSG" ] && { echo "Użycie: ./release.sh \"commit message\" [X.Y.Z] [-y]"; exit 1; }

PROP="gradle/build-logic/gradle.properties"
[ -f "$PROP" ] || { echo "Brak $PROP — uruchom z roota repo Platform."; exit 1; }
CUR="$(grep -E '^platformVersion=' "$PROP" | cut -d= -f2 | tr -d ' ')"

# Wersja: jawna (arg 2) albo patch +0.0.1 od aktualnej.
if [ -z "$VERSION" ]; then
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

BR="$(git rev-parse --abbrev-ref HEAD)"
echo "Plan: $CUR -> $VERSION   branch: $BR   commit: \"$MSG\""
if [ "${3:-}" != "-y" ] && [ "${ASSUME_YES:-}" != "1" ]; then
  read -r -p "Kontynuować (commit + tag v$VERSION + push)? [y/N] " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "Przerwane."; exit 0; }
fi

# Bump: 3× gradle.properties + lustro defaultu w catalogu.
for f in gradle/build-logic/gradle.properties gradle/catalog/gradle.properties gradle/test-fixtures/gradle.properties; do
  [ -f "$f" ] && sed -i.bak -E "s/^platformVersion=.*/platformVersion=$VERSION/" "$f" && rm -f "$f.bak"
done
[ -f gradle/catalog/build.gradle.kts ] && \
  sed -i.bak -E "s/getOrElse\(\"[0-9]+\.[0-9]+\.[0-9]+\"\)/getOrElse(\"$VERSION\")/g" gradle/catalog/build.gradle.kts \
  && rm -f gradle/catalog/build.gradle.kts.bak

git add -A
git commit -m "$MSG"
git push
git tag "v$VERSION" && git push origin "v$VERSION"
git tag -f v1 && git push -f origin v1

echo ""
echo "════════════════════════════════════════════════"
echo "  Platform podbity: $CUR → $VERSION"
echo "  Tag: v$VERSION (+ przesunięty ruchomy v1)"
echo "  Branch: $BR   Commit: \"$MSG\""
echo "════════════════════════════════════════════════"
echo "==> Release publikuje z taga: Actions → Release."
echo "==> U konsumenta: ./platform-bump.sh $VERSION   (podbije piny do $VERSION)"
