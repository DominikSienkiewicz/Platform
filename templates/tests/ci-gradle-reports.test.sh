#!/usr/bin/env bash
# Czerwony test modułu Maven da się zdiagnozować z samego przebiegu ci.yml: build-logic loguje porażki pełnym
# formatem (komunikat UnexpectedBuildFailure niesie wyjście builda TestKit), a job gradle przy porażce wgrywa
# raporty testów wszystkich modułów jako artefakt.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

job=$(awk '
  /^  gradle:[[:space:]]*$/ { inside = 1; print; next }
  inside && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { exit }
  inside { print }
' "$root/.github/workflows/ci.yml")
[[ -n "$job" ]] || fail 'ci.yml has no gradle job'
upload=$(sed -n '/- name: Upload test reports/,/retention-days:/p' <<< "$job")
[[ -n "$upload" ]] || fail 'the gradle job must upload the test reports'
grep -qxF '        if: failure()' <<< "$upload" || fail 'the reports must be uploaded when a module fails'
grep -qE '^        uses: actions/upload-artifact@[0-9a-f]{40} # v' <<< "$upload" \
  || fail 'the upload must use actions/upload-artifact pinned by commit'
grep -qxF '            gradle/*/build/reports/tests/' <<< "$upload" || fail 'the upload must cover every module of gradle/'

build_logic="$root/gradle/build-logic/build.gradle.kts"
grep -qF 'exceptionFormat = TestExceptionFormat.FULL' "$build_logic" \
  || fail 'build-logic must log a failing test with its full message, which carries the TestKit build output'
grep -qF 'events(TestLogEvent.FAILED)' "$build_logic" || fail 'build-logic must log every failing test'

echo 'OK: a failing module test shows its TestKit output in the log and its reports in an artifact'
