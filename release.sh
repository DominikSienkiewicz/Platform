#!/usr/bin/env bash
# release.sh — świadome wydanie Platform (publish-only, deliberate versioning).
#
# Bumpuje platformVersion we wszystkich miejscach, commituje jako "chore(release): platform X.Y.Z"
# z komunikatem wydania w body, taguje annotated vX.Y.Z treścią sekcji CHANGELOG.md i pcha main + tag atomowo.
# Ręcznie napisana sekcja "## [X.Y.Z] - YYYY-MM-DD" wygrywa; bez niej release.sh składa ją z commitów od taga
# poprzedniego wydania (scripts/release-notes.sh), wstawia pod "## [Unreleased]" i commituje CHANGELOG.md razem
# z plikami wersji.
# Release publikuje Maven+npm dopiero po zielonym CI na tym commicie i tworzy GitHub Release z tej
# samej sekcji.
#
# Odmawia przed jakąkolwiek zmianą, gdy drzewo robocze nie jest czyste, bieżąca gałąź to nie
# main albo HEAD różni się od origin/main. Commit wydania obejmuje wersje, złożone notatki i oczekujący wiersz macierzy zgodności.
# Kontrakt (docs/adr/0002-release-and-versioning-contract.md) — odmawia też, gdy:
#   - message nie jest angielskim Conventional Commit;
#   - ręcznie napisana sekcja wersji nie ma podsekcji "### Consumer action required";
#   - argument spoza formy "<message>" [X.Y.Z] [-y] (np. dawne --skip-canary);
#   - sekcję trzeba złożyć, a CHANGELOG.md nie ma "## [Unreleased]", ma pod nim wpisy, jego najnowsza sekcja
#     wersji nie ma taga, od poprzedniego taga nie ma commitów albo temat commita nie jest Conventional Commit;
#   - wydanie z akcją konsumenta (podsekcja inna niż "None.") miałoby być patchem;
#   - message feat / "!:" / BREAKING CHANGE miałby dostać automatyczny patch (podaj wersję jawnie);
#   - commit od poprzedniego wydania niesie trailer "Consumer-Action:", "!" w temacie albo stopkę
#     BREAKING CHANGE, a wydanie byłoby patchem albo jego sekcja w CHANGELOG mówi "None.".
#
# Użycie:
#   ./release.sh                               # dobiera PATCH lub MINOR z historii i pokazuje plan
#   ./release.sh "fix: opis zmiany"            # patch +0.0.1 od aktualnej wersji
#   ./release.sh "feat: opis" 1.2.0            # konkretna wersja
#   ./release.sh "..." 1.2.0 -y                # bez pytania o potwierdzenie (też: ASSUME_YES=1)
set -euo pipefail
cd "$(dirname "$0")"   # zawsze z roota Platform

MSG="${1:-}"
VERSION="${2:-}"
LATEST=0
if [[ $# -eq 0 ]]; then
  LATEST=1
  MSG="chore: release the latest changes on main"
fi
[[ -z "$MSG" ]] && { echo "Użycie: ./release.sh \"commit message\" [X.Y.Z] [-y]"; exit 1; }
# Gdy podano argumenty, obowiązuje forma "<message>" [X.Y.Z] [-y]: inny argument (np. dawne --skip-canary) to pomyłka, której nie wolno pominąć.
STRAY=""
if [[ "${2:-}" == -* ]]; then STRAY="$2"
elif [[ $# -ge 3 ]] && [[ "$3" != "-y" ]]; then STRAY="$3"
elif [[ $# -gt 3 ]]; then STRAY="$4"
fi
if [[ -n "$STRAY" ]]; then
  echo "Unexpected argument \"$STRAY\". Usage: ./release.sh \"commit message\" [X.Y.Z] [-y]"
  if [[ "$STRAY" == "-y" ]]; then
    echo "-y comes after the version: ./release.sh \"$MSG\" X.Y.Z -y, or ASSUME_YES=1 ./release.sh \"$MSG\" for the next patch."
  fi
  exit 1
fi
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
# Tagi wydań z origin: git describe i bramka historii czytają tagi lokalne, a tag wypchnięty po pobraniu jego commita
# nie przychodzi z samym "fetch origin main" — sekcja złożyłaby się od starszego taga i powtórzyła wydane commity.
git fetch --quiet --tags origin || {
  echo "Could not fetch the release tags from origin (a local tag that differs from origin also stops it)."
  echo "Fix that, then release: the composed notes and the history check start at the previous release's tag."
  exit 1
}
planned_head="$(git rev-parse HEAD)"
[[ "$planned_head" == "$(git rev-parse origin/main)" ]] \
  || { echo "HEAD różni się od origin/main — zsynchronizuj main przed wydaniem."; exit 1; }

CUR="$(grep -E '^platformVersion=' "$PROP" | cut -d= -f2 | tr -d ' ')"

# Tylko tryb bezargumentowy dobiera MINOR z historii lub przygotowanej sekcji.
NEWEST="$(awk '/^## \[[0-9]+\.[0-9]+\.[0-9]+\] - / { print substr($2, 2, length($2) - 2); exit }' CHANGELOG.md)"
if [[ -z "$VERSION" ]]; then
  [[ "$CUR" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
    || { echo "Aktualne platformVersion '$CUR' nie jest X.Y.Z — podaj wersję jawnie."; exit 1; }
  IFS='.' read -r MA MI PA <<< "$CUR"
  VERSION="$MA.$MI.$((PA + 1))"
  if [[ "$LATEST" == 1 ]]; then
    previous="refs/tags/v$CUR"
    if ! git ls-remote --exit-code --refs origin "$previous" > /dev/null || ! git merge-base --is-ancestor "$previous" HEAD; then
      echo "Cannot select a release: confirm v$CUR is published on origin and belongs to main."
      exit 1
    fi
    if [[ "$(git rev-parse "$previous^{commit}")" == "$(git rev-parse HEAD)" ]]; then
      echo "Nothing to release: main is already tagged v$CUR."
      exit 0
    fi
    next_minor="$MA.$((MI + 1)).0"
    markers="$(bash scripts/release-notes.sh --markers "$previous..HEAD")"
    # Gotowa sekcja następnego PATCH/MINOR przechodzi dalej do wspólnych bramek wydania.
    if [[ "$NEWEST" == "$next_minor" ]]; then
      VERSION="$NEWEST"
    elif [[ "$NEWEST" != "$VERSION" && -n "$markers" ]]; then
      VERSION="$next_minor"
    fi
  fi
fi
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Wersja '$VERSION' nie jest X.Y.Z"; exit 1; }

# Wersje są immutable — tag nie może już istnieć.
if git rev-parse "v$VERSION" >/dev/null 2>&1 || git ls-remote --exit-code --tags origin "v$VERSION" >/dev/null 2>&1; then
  echo "Tag v$VERSION już istnieje (wersje immutable). Podaj wyższą."; exit 1
fi

# Notatki wydania: sekcja CHANGELOG.md tej wersji (jedno źródło dla taga, GitHub Release i platform-bump).
# Niczego tu nie zapisuje: złożony CHANGELOG.md powstaje w katalogu tymczasowym i trafia do drzewa dopiero
# po wszystkich odmowach i potwierdzeniu.
CONTRACT="docs/adr/0002-release-and-versioning-contract.md"
WORK_DIR="$(mktemp -d)"
trap 'rm -r "$WORK_DIR"' EXIT
CHANGELOG=CHANGELOG.md
RELEASE_DATE=$(date +%Y-%m-%d)
COMPOSED_FROM=""
if ! bash scripts/changelog-section.sh "$VERSION" CHANGELOG.md > /dev/null; then
  if [[ "$LATEST" == 1 ]]; then
    LAST_TAG="v$CUR"
  else
    LAST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' HEAD 2>/dev/null || true)"
  fi
  COMPOSED_FROM="${LAST_TAG:-the first commit}"
  # Najnowsza sekcja bez taga to niewydana ręczna sekcja (np. 1.13.0 przed wydaniem): nowa sekcja stanęłaby nad nią.
  if [[ -n "$NEWEST" ]] && ! git rev-parse -q --verify "refs/tags/v$NEWEST" > /dev/null \
    && ! git ls-remote --exit-code --tags origin "v$NEWEST" > /dev/null 2>&1; then
    echo "The newest section of CHANGELOG.md, \"## [$NEWEST]\", has no v$NEWEST tag: release $NEWEST first"
    echo "(./release.sh \"<message>\" $NEWEST), then $VERSION. Composing $VERSION now would bury $NEWEST unreleased under it."
    exit 1
  fi
  if [[ -n "$LAST_TAG" ]] && [[ "$(git rev-list --count "$LAST_TAG..HEAD")" == 0 ]]; then
    echo "Nothing to release: there are no commits since $LAST_TAG."
    exit 1
  fi
  bash scripts/release-notes.sh "${LAST_TAG:+$LAST_TAG..}HEAD" > "$WORK_DIR/notes.md"
  if grep -q '^### Unclassified' "$WORK_DIR/notes.md"; then
    echo "CHANGELOG.md has no \"## [$VERSION]\" section, and these subjects since $COMPOSED_FROM are not Conventional Commits:"
    sed -n '/^### Unclassified/,$p' "$WORK_DIR/notes.md" | grep '^- ' | sed 's/^/  /'
    echo "Write the $VERSION section of CHANGELOG.md by hand and merge it, then release."
    exit 1
  fi
  compose_status=0
  awk -v heading="## [$VERSION] - $RELEASE_DATE" -v notes="$WORK_DIR/notes.md" '
    /^## \[Unreleased\][[:space:]]*$/ {
      found = 1; inside = 1
      print; print ""; print heading; print ""
      while ((getline line < notes) > 0) print line
      next
    }
    inside && /^## / { inside = 0; print "" }
    inside { if ($0 ~ /[^[:space:]]/) entries = 1; next }
    { print }
    END { if (!found) exit 3; if (entries) exit 4 }
  ' CHANGELOG.md > "$WORK_DIR/CHANGELOG.md" || compose_status=$?
  case "$compose_status" in
    0) CHANGELOG="$WORK_DIR/CHANGELOG.md" ;;
    3)
      echo "CHANGELOG.md has no \"## [$VERSION] - YYYY-MM-DD\" section and no \"## [Unreleased]\" heading to compose it under."
      echo "Add \"## [Unreleased]\" above the newest version, or write the $VERSION section by hand."
      exit 1
      ;;
    4)
      echo "CHANGELOG.md has no \"## [$VERSION] - YYYY-MM-DD\" section, but it has entries under \"## [Unreleased]\"."
      echo "Rename that heading to \"## [$VERSION] - YYYY-MM-DD\" with a \"### Consumer action required\" subsection,"
      echo "or remove the entries to compose the section from the commits since $COMPOSED_FROM; merge it, then release."
      exit 1
      ;;
    *) echo "Composing the $VERSION section of CHANGELOG.md failed."; exit 1 ;;
  esac
fi
SECTION="$(bash scripts/changelog-section.sh "$VERSION" "$CHANGELOG")"
ACTION="$(bash scripts/changelog-section.sh --consumer-action "$VERSION" "$CHANGELOG")" || {
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
# Akcja konsumenta zapisana w historii od poprzedniego wydania (N-REL-7): trailer "Consumer-Action: …", "!"
# w temacie albo stopka "BREAKING CHANGE:"/"BREAKING-CHANGE:" na dowolnym commicie, także merge commicie merge.sh.
# Znaczniki czyta scripts/release-notes.sh --markers, to samo źródło co złożona sekcja. Bez taga poprzedniego
# wydania nie ma zakresu.
history_reasons() {
  bash scripts/release-notes.sh --markers "$1" | awk -v FS=$'\037' '
    $3 == "trailer" { print "  " $1 " " $2 " (Consumer-Action: " $4 ")" }
    $3 == "footer" { print "  " $1 " " $2 " (BREAKING CHANGE footer)" }
    $3 == "bang" { print "  " $1 " " $2 " (\"!\" marks a breaking change)" }'
}
if git rev-parse -q --verify "refs/tags/v$CUR" >/dev/null; then
  REASONS="$(history_reasons "v$CUR..HEAD")"
  if [[ -n "$REASONS" ]] && [[ "${VERSION%.*}" == "${CUR%.*}" ]]; then
    echo "Commits since v$CUR record consumer action, so this must be a MINOR release ($NEXT_MINOR):"
    echo "$REASONS"
    echo "See $CONTRACT."
    exit 1
  fi
  if [[ -n "$REASONS" ]] && [[ "$ACTION" =~ ^None\.?$ ]]; then
    echo "Commits since v$CUR record consumer action, but the $VERSION section of CHANGELOG.md says None."
    echo "Describe it under ### Consumer action required:"
    echo "$REASONS"
    exit 1
  fi
fi
if [[ "${VERSION%.*}" == "${CUR%.*}" ]] && ! [[ "$ACTION" =~ ^None\.?$ ]]; then
  echo "CHANGELOG.md lists consumer action for $VERSION, so it must be a MINOR release:"
  if [[ -n "$COMPOSED_FROM" ]]; then
    echo "  ./release.sh \"$MSG\" $NEXT_MINOR"
  else
    echo "  rename the section to $NEXT_MINOR, commit, then: ./release.sh \"$MSG\" $NEXT_MINOR"
  fi
  echo "See $CONTRACT."
  exit 1
fi

echo "Plan: $CUR -> $VERSION   branch: $BR   commit: \"chore(release): platform $VERSION\""
if [[ -n "$COMPOSED_FROM" ]]; then
  echo "Release notes (composed from the commits since $COMPOSED_FROM; the release commit adds them to CHANGELOG.md):"
else
  echo "Release notes (CHANGELOG.md):"
fi
printf '  %s\n' "${SECTION//$'\n'/$'\n'  }"
if [[ "${3:-}" != "-y" ]] && [[ "${ASSUME_YES:-}" != "1" ]]; then
  read -r -p "Kontynuować (commit + tag v$VERSION + push)? [y/N] " ans
  [[ "$ans" = "y" ]] || [[ "$ans" = "Y" ]] || { echo "Przerwane."; exit 0; }
fi

if [[ "$(git symbolic-ref --quiet --short HEAD)" != main || "$(git rev-parse HEAD)" != "$planned_head" || -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "The checkout changed after planning the release. Review the changes and run release.sh again." >&2
  exit 1
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
if [[ -n "$COMPOSED_FROM" ]]; then
  cp "$WORK_DIR/CHANGELOG.md" CHANGELOG.md
  git add -- CHANGELOG.md
fi
# Pierwszy wiersz macierzy opisuje wydawany stos tylko wtedy, gdy oznaczono go jako oczekujący.
MATRIX=docs/compatibility.md
if [[ -f "$MATRIX" ]]; then
  awk -v replacement="| $VERSION | $RELEASE_DATE |" '
    /^<!-- compatibility-matrix -->$/ { first_row = NR + 3 }
    NR == first_row { sub(/^\| [Uu]nreleased \| [Pp]ending \|/, replacement) }
    { print }
  ' "$MATRIX" > "$WORK_DIR/matrix.md"
  if ! cmp -s "$MATRIX" "$WORK_DIR/matrix.md"; then
    cp "$WORK_DIR/matrix.md" "$MATRIX"
    git add -- "$MATRIX"
  fi
fi
git commit -m "chore(release): platform $VERSION" -m "$MSG"
# --cleanup=verbatim: domyślne "strip" wycina linie zaczynające się od '#', czyli nagłówki Markdown sekcji.
TAG_MESSAGE="$WORK_DIR/tag-message"
printf 'Platform %s\n\n%s\n' "$VERSION" "$SECTION" > "$TAG_MESSAGE"
release_commit=$(git rev-parse HEAD)
git tag -a --cleanup=verbatim -F "$TAG_MESSAGE" "v$VERSION" "$release_commit"
if ! git push --atomic origin "$release_commit:refs/heads/main" "refs/tags/v$VERSION"; then
  echo "The release commit and annotated tag are ready locally. Check origin/main and v$VERSION before retrying:" >&2
  echo "  git push --atomic origin $release_commit:refs/heads/main refs/tags/v$VERSION" >&2
  exit 1
fi

echo ""
echo "════════════════════════════════════════════════"
echo "  Platform podbity: $CUR → $VERSION"
echo "  Tag: v$VERSION (Release opublikuje po zielonym CI)"
echo "  Branch: $BR   Commit: \"chore(release): platform $VERSION\" ($MSG)"
echo "════════════════════════════════════════════════"
echo "==> Release weryfikuje CI i publikuje z taga: Actions → Release."
echo "==> U konsumenta: ./scripts/platform-bump.sh $VERSION   (podbije piny do $VERSION)"
