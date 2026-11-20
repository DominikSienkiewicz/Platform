#!/usr/bin/env bash
# .gitignore, case by case: no tracked file matches the ignore rules and the OS and editor sections equal the canon, and the
# JVM starters carry the rules of root.gitignore plus backend.gitignore.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- hygiene ---
# No tracked file matches the ignore rules (Buildship output under gradle/*/bin/ once slipped in), and the
# OS and editor sections of Platform's .gitignore equal the canonical templates/gitignore/root.gitignore.
(
tracked=$(git -C "$root" ls-files -ci --exclude-standard)
[[ -z "$tracked" ]] || fail "tracked files match .gitignore; untrack them with git rm --cached:
$tracked"

# section <heading prefix> <file>: the lines of that section, up to the next blank line
section() {
  local heading="$1" file="$2"
  awk -v heading="$heading" 'index($0, heading) == 1 { inside = 1 } inside && /^$/ { exit } inside' "$file"
}
for heading in '# === OS junk ===' '# === IDE / editors ==='; do
  diff <(section "$heading" "$root/templates/gitignore/root.gitignore") <(section "$heading" "$root/.gitignore") \
    || fail "the '$heading' section of .gitignore differs from templates/gitignore/root.gitignore"
done
echo 'OK: no tracked file is ignored, and the OS and editor ignores match the canon'
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
    build/libs/app.jar .gradle/caches out/production; do
    git -C "$WORK" check-ignore -q --no-index -- "$path" || fail "$starter/.gitignore nie ignoruje $path"
  done
  for path in .env.example gradle/wrapper/gradle-wrapper.jar src/main/java/App.java; do
    git -C "$WORK" check-ignore -q --no-index -- "$path" && fail "$starter/.gitignore ignoruje $path"
  done
done

echo "OK: .gitignore starterów jvm = reguły root.gitignore + backend.gitignore; sekrety i wyjście IDE ignorowane"
)
