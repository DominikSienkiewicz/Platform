#!/usr/bin/env bash
# Job sonar w ci.yml czeka na wynik SonarQube Cloud: scanner tylko wysyła raport, a serwer przetwarza go
# asynchronicznie. Bez sonar.qualitygate.wait odrzucona analiza (np. gałąź `main` przy gałęzi głównej projektu
# `master`) zostawiała zielone CI i pusty dashboard.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

job=$(awk '
  /^  sonar:[[:space:]]*$/ { inside = 1; print; next }
  inside && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { exit }
  inside { print }
' "$root/.github/workflows/ci.yml")
[[ -n "$job" ]] || fail 'ci.yml has no sonar job'
analysis=$(grep -E '\./gradlew .*\bsonar\b' <<< "$job") || fail 'the sonar job must run the sonar task through ./gradlew'
grep -qF -- '-Dsonar.qualitygate.wait=true' <<< "$analysis" \
  || fail 'the sonar job must wait for SonarQube Cloud to process the analysis (-Dsonar.qualitygate.wait=true)'

echo 'OK: the sonar job fails when SonarQube Cloud rejects the analysis or the quality gate is red'
