#!/usr/bin/env bash
# Zdrowie testów w backend-ci.yml (blok między markerami test-health, N-REL-13): test, który przeszedł dopiero po
# powtórzeniu, dostaje ::warning i wiersz w podsumowaniu; wynik quarantineTest i terminy z platformQuarantineCheck
# trafiają do tabel; zielony build bez nich nie dopisuje niczego. Do tego PLATFORM_TEST_RETRY=detect w kroku Gradle.
# shellcheck disable=SC2016 # literal GitHub expressions and Markdown backticks
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/backend-ci.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "--- output ---" >&2; cat "$tmp/out" "$tmp/summary" >&2 2>/dev/null; exit 1; }
: > "$tmp/out"

awk '
  index($0, "# >>> test-health") { inside = 1; next }
  index($0, "# <<< test-health") { inside = 0 }
  inside { sub(/^          /, ""); print }
' "$workflow" > "$tmp/health.py"
[[ -s "$tmp/health.py" ]] || fail 'backend-ci.yml has no test-health block between its markers'
grep -qF 'if: ${{ !cancelled() }}' <(sed -n '/- name: Summarise flaky and quarantined tests/,/run:/p' "$workflow") \
  || fail 'the summary must run on green builds too'
grep -qxF '          PLATFORM_TEST_RETRY: detect' <(sed -n '/- name: .\/gradlew ${{ inputs.gradle-task }}/,/- name: Upload test reports/p' "$workflow") \
  || fail 'the Gradle step must turn on retry detection through PLATFORM_TEST_RETRY, leaving the arguments alone'

work="$tmp/repo"
mkdir -p "$work/app/build/test-results/test" "$work/app/build/test-results/quarantineTest" "$work/app/build/reports/platform"
cat > "$work/app/build/test-results/test/TEST-pl.example.OrderTest.xml" <<'XML'
<testsuite name="pl.example.OrderTest" tests="3" failures="1">
  <testcase classname="pl.example.OrderTest" name="totalsTheLines()"/>
  <testcase classname="pl.example.OrderTest" name="settlesInTime()"><failure message="timeout">timeout</failure></testcase>
  <testcase classname="pl.example.OrderTest" name="settlesInTime()"/>
</testsuite>
XML
cat > "$work/app/build/test-results/quarantineTest/TEST-pl.example.FlakyTest.xml" <<'XML'
<testsuite name="pl.example.FlakyTest" tests="1" failures="1">
  <testcase classname="pl.example.FlakyTest" name="racesTheClock()"><failure message="race">race</failure></testcase>
</testsuite>
XML
printf 'pl/example/FlakyTest.java:12 https://github.com/example/app/issues/7 2026-11-30\n' > "$work/app/build/reports/platform/quarantine.txt"

(cd "$work" && GITHUB_STEP_SUMMARY="$tmp/summary" python3 "$tmp/health.py") > "$tmp/out"
grep -qxF '::warning title=Flaky test::pl.example.OrderTest.settlesInTime() failed, then passed on retry in test' "$tmp/out" \
  || fail 'a test that passed on retry must get a warning annotation'
grep -qF 'totalsTheLines' "$tmp/out" "$tmp/summary" && fail 'a test that passed at once is not flaky'
grep -qxF '| `pl.example.OrderTest.settlesInTime()` | `test` |' "$tmp/summary" || fail 'the flaky test must be in the summary'
grep -qxF '| `pl.example.FlakyTest.racesTheClock()` | failed |' "$tmp/summary" || fail 'the quarantineTest result must be in the summary'
grep -qxF '| `app` | `pl/example/FlakyTest.java:12` | https://github.com/example/app/issues/7 | 2026-11-30 |' "$tmp/summary" \
  || fail 'the quarantine deadline must be in the summary'

rm -rf "$work/app/build/test-results/quarantineTest" "$work/app/build/reports/platform"
printf '<testsuite><testcase classname="pl.example.OrderTest" name="totalsTheLines()"/></testsuite>\n' \
  > "$work/app/build/test-results/test/TEST-pl.example.OrderTest.xml"
rm -f "$tmp/summary"
(cd "$work" && GITHUB_STEP_SUMMARY="$tmp/summary" python3 "$tmp/health.py") > "$tmp/out"
[[ ! -s "$tmp/out" && ! -e "$tmp/summary" ]] || fail 'a healthy build must add nothing'
echo 'OK: backend-ci names flaky tests, the quarantineTest result and every quarantine deadline'
