#!/usr/bin/env bash
# Moduły z pętli sonar-modules w ci.yml nie mają pustego publicznego konstruktora bez komentarza w środku.
# javadoc -Werror wymaga jawnego konstruktora, żeby dało się go opisać, a java:S1186 liczy pusty bez komentarza jako
# dług na nowym kodzie: cztery takie dały ocenę C i czerwoną bramkę security-starter. Lokalny build tego nie widzi,
# bo SonarQube Cloud ocenia dopiero po analizie w CI. Niepubliczne konstruktory S1186 pomija, więc test też.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

modules=$(sed -n '/# >>> sonar-modules/,/# <<< sonar-modules/s/^ *for m in \(.*\); do$/\1/p' \
  "$root/.github/workflows/ci.yml")
[[ -n "$modules" ]] || fail 'ci.yml has no module loop between the sonar-modules markers'

empty_public_constructor='^[[:space:]]*public [A-Z][A-Za-z0-9_]*\(\)[[:space:]]*\{[[:space:]]*\}[[:space:]]*$'
found=""
for module in $modules; do
  sources="$root/gradle/$module/src/main/java"
  [[ -d "$sources" ]] || fail "gradle/$module has no src/main/java, so the sonar job's module list is stale"
  hits=$(grep -rnE "$empty_public_constructor" "$sources" || true)
  [[ -z "$hits" ]] || found+="$hits"$'\n'
done

[[ -z "$found" ]] || fail "empty public constructors without a comment inside, which java:S1186 counts as debt:
${found//$root\//}
Add a comment inside each one that says why it is empty."

echo "OK: no module the sonar job analyses ($modules) has an empty public constructor without a comment"
