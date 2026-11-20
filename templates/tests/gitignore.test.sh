#!/usr/bin/env bash
# .gitignore, przypadek po przypadku: żaden śledzony plik nie pasuje do reguł ignorowania, sekcje systemu i edytora
# równają się kanonowi, a startery JVM niosą reguły root.gitignore plus backend.gitignore.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- hygiene ---
# Żaden śledzony plik nie pasuje do reguł ignorowania (raz wpadł wynik Buildship w gradle/*/bin/), a sekcje
# systemu i edytora w .gitignore Platform równają się kanonicznemu templates/gitignore/root.gitignore.
(
tracked=$(git -C "$root" ls-files -ci --exclude-standard)
[[ -z "$tracked" ]] || fail "tracked files match .gitignore; untrack them with git rm --cached:
$tracked"

# section <prefiks nagłówka> <plik>: wiersze tej sekcji, do następnego pustego wiersza
section() {
  local heading="$1" file="$2"
  awk -v heading="$heading" 'index($0, heading) == 1 { inside = 1 } inside && /^$/ { exit } inside' "$file"
}
for heading in '# === OS junk ===' '# === IDE / editors ==='; do
  diff <(section "$heading" "$root/templates/gitignore/root.gitignore") <(section "$heading" "$root/.gitignore") \
    || fail "the '$heading' section of .gitignore differs from templates/gitignore/root.gitignore"
done
# Wyjście IntelliJ w drzewie Platform (root i moduły gradle/*) dalej jest ignorowane; ścieżki bez .class,
# bo klasy i tak ignoruje *.class.
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
git -C "$work" init -q
cp "$root/.gitignore" "$work/.gitignore"
for path in out/production/resources/x gradle/test-fixtures/out/production/resources/x \
  gradle/test-fixtures/out/test/resources/x; do
  git -C "$work" check-ignore -q --no-index -- "$path" || fail ".gitignore does not ignore the IntelliJ output $path"
done
echo 'OK: no tracked file is ignored, IntelliJ output is, and the OS and editor ignores match the canon'
)

# --- jvm-starters ---
# Startery templates/jvm/* to repo jednowarstwowe: ich .gitignore = reguły kanonu
# gitignore/root.gitignore + gitignore/backend.gitignore, w tej kolejności (komentarze dowolne).
(
TEMPLATES="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

fail() { local message="$1"; echo "FAIL: $message"; exit 1; }
rules() { grep -vE '^[[:space:]]*(#|$)' "$@"; }

expected="$(rules "$TEMPLATES/gitignore/root.gitignore"; rules "$TEMPLATES/gitignore/backend.gitignore")"
git -C "$WORK" init -q

for starter in java-library spring-app; do
  gitignore="$TEMPLATES/jvm/$starter/.gitignore"
  [[ "$(rules "$gitignore")" == "$expected" ]] \
    || fail "$starter/.gitignore rozjechał się z root.gitignore + backend.gitignore"
  cp "$gitignore" "$WORK/.gitignore"
  for path in .env .env.local .idea/workspace.xml bin/main/App.class \
    build/libs/app.jar .gradle/caches out/production modules/orders/out/production/resources/application.yml \
    modules/orders/out/test/resources/data.sql; do
    git -C "$WORK" check-ignore -q --no-index -- "$path" || fail "$starter/.gitignore nie ignoruje $path"
  done
  # Pakiety heksagonu adapter/out i port/out (ADR-0038) to źródła, nie wyjście IntelliJ.
  for path in .env.example gradle/wrapper/gradle-wrapper.jar src/main/java/App.java \
    src/main/java/x/adapter/out/Foo.java src/main/java/x/application/port/out/Bar.java \
    modules/orders/src/test/java/x/adapter/out/FooTest.java; do
    git -C "$WORK" check-ignore -q --no-index -- "$path" && fail "$starter/.gitignore ignoruje $path"
  done
done

echo "OK: .gitignore starterów jvm = reguły root.gitignore + backend.gitignore; sekrety i wyjście IDE ignorowane"
)
