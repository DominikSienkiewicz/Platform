#!/usr/bin/env bash
# Startery templates/jvm/* to repo jednowarstwowe: ich .gitignore = reguły kanonu
# gitignore/root.gitignore + gitignore/backend.gitignore, w tej kolejności (komentarze dowolne).
set -euo pipefail

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
  for path in .secrets.local .env .env.local .idea/workspace.xml bin/main/App.class \
    build/libs/app.jar .gradle/caches out/production; do
    git -C "$WORK" check-ignore -q --no-index -- "$path" || fail "$starter/.gitignore nie ignoruje $path"
  done
  for path in .secrets.local.example .env.example gradle/wrapper/gradle-wrapper.jar src/main/java/App.java; do
    git -C "$WORK" check-ignore -q --no-index -- "$path" && fail "$starter/.gitignore ignoruje $path"
  done
done

echo "OK: .gitignore starterów jvm = reguły root.gitignore + backend.gitignore; sekrety i wyjście IDE ignorowane"
