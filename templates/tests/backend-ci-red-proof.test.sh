#!/usr/bin/env bash
# red-proof w backend-ci.yml: każdy commit `fix:` pull requesta musi dodać albo zmienić klasę testu, która pada na
# kodzie produkcyjnym rodzica (testy z commita, `src/main` z rodzica). Brak testu = PLAT-RED-001, test zielony na
# rodzicu = PLAT-RED-002, test, który się nie uruchomił = PLAT-RED-003; commity innych typów są pomijane. Blok
# wycinany spomiędzy markerów biegnie w atrapie repo z atrapą ./gradlew, która pisze raport JUnit XML.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/backend-ci.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "$OUT" >&2; exit 1; }
OUT=""
awk 'index($0, "# >>> red-proof") { inside = 1; next } index($0, "# <<< red-proof") { inside = 0 } inside { sub(/^          /, ""); print }' \
  "$workflow" > "$tmp/red-proof.sh"
[[ -s "$tmp/red-proof.sh" ]] || fail 'backend-ci.yml has no red-proof block between its markers'
grep -qF "if: \${{ inputs.red-proof && github.event_name == 'pull_request' }}" "$workflow" \
  || fail 'the job must be opt-in and run only on pull requests'
grep -qF 'fetch-depth: 0' <(sed -n '/^  red-proof:/,$p' "$workflow") || fail 'the job needs the history of the pull request'

repo="$tmp/repo"
mkdir -p "$repo/src/main/java/demo" "$repo/src/test/java/demo"
git -C "$repo" init --quiet
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" config commit.gpgsign false
# Atrapa Gradle'a, nieśledzona, więc przeżywa checkouty: test pada, gdy produkcja niesie słowo "buggy" albo nie ma
# klasy, której test potrzebuje; klasa *BrokenTest nie kompiluje się i nie daje raportu.
cat > "$repo/gradlew" <<'GRADLE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GRADLE_CALLS"
cat src/main/java/demo/*.java >> "$GRADLE_SEEN" 2> /dev/null || true
task=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tests) class="$2"; shift
      [[ "$class" == *BrokenTest ]] && { shift; continue; }
      failures=0
      grep -qs buggy src/main/java/demo/*.java && failures=1
      [[ "$class" == *ParserTest && ! -f src/main/java/demo/Parser.java ]] && failures=1
      mkdir -p "build/test-results/$task"
      printf '<testsuite name="%s" tests="1" failures="%s" errors="0"/>\n' "$class" "$failures" \
        > "build/test-results/$task/TEST-$class.xml" ;;
    -*) ;;
    *) task="$1" ;;
  esac
  shift
done
GRADLE
chmod +x "$repo/gradlew"
printf 'build/\ngradlew\n' > "$repo/.gitignore"
commit() { git -C "$repo" add -A && git -C "$repo" commit --quiet -m "$1" && git -C "$repo" rev-parse HEAD; }

echo 'class Calc { /* good */ }' > "$repo/src/main/java/demo/Calc.java"
base=$(commit 'chore: start')
echo 'class Calc { /* buggy */ }' > "$repo/src/main/java/demo/Calc.java"
echo 'class CalcTest {}' > "$repo/src/test/java/demo/CalcTest.java"
feat=$(commit 'feat: add the calculator')
echo 'class Calc { /* fixed */ }' > "$repo/src/main/java/demo/Calc.java"
echo 'class CalcTest { /* regression */ }' > "$repo/src/test/java/demo/CalcTest.java"
proven=$(commit 'fix(calc): round once')
echo 'class Calc { /* fixed, renamed */ }' > "$repo/src/main/java/demo/Calc.java"
untested=$(commit 'fix: rename a field')
echo 'class Calc { /* fixed, again */ }' > "$repo/src/main/java/demo/Calc.java"
echo 'class CalcTest { /* passes anyway */ }' > "$repo/src/test/java/demo/CalcTest.java"
green=$(commit 'fix: tidy the calculator')
echo 'class OtherBrokenTest {}' > "$repo/src/test/java/demo/OtherBrokenTest.java"
broken=$(commit 'fix: a test that does not compile')
echo 'class Parser {}' > "$repo/src/main/java/demo/Parser.java"
echo 'class ParserTest {}' > "$repo/src/test/java/demo/ParserTest.java"
echo 'class ParserFixture {}' > "$repo/src/test/java/demo/ParserFixture.java"
added=$(commit 'fix(parser)!: parse an empty line')

run() {
  : > "$tmp/calls"
  : > "$tmp/seen"
  : > "$tmp/summary"
  git -C "$repo" checkout --quiet --detach "$2"
  RC=0
  OUT=$(cd "$repo" && BASE_SHA="$1" HEAD_SHA="$2" RED_PROOF_TASKS="${3:-test}" GRADLE_CALLS="$tmp/calls" \
    GRADLE_SEEN="$tmp/seen" GITHUB_STEP_SUMMARY="$tmp/summary" RUNNER_TEMP="$tmp" bash "$tmp/red-proof.sh" 2>&1) || RC=$?
}

run "$base" "$feat"
[[ $RC -eq 0 && ! -s "$tmp/calls" ]] || fail 'a pull request without a fix: commit runs no test and passes'
grep -qF 'no fix: commit' <<<"$OUT" || fail 'it must say there was nothing to prove'

run "$feat" "$proven"
[[ $RC -eq 0 ]] || fail 'a regression test that fails on the parent must pass the proof'
[[ "$(cat "$tmp/calls")" == 'test --tests demo.CalcTest --continue --no-daemon -Pplatform.test.retry=off' ]] \
  || fail "only the test class of the commit runs: $(cat "$tmp/calls")"
grep -qF buggy "$tmp/seen" || fail 'the test must run against the production code of the parent'
grep -qF '/* fixed */' "$repo/src/main/java/demo/Calc.java" || fail 'the checkout must be back at the head afterwards'
[[ -z "$(git -C "$repo" status --porcelain)" ]] || fail 'the work tree must be clean afterwards'
grep -qF '| `'"${proven:0:7}"'` | `demo.CalcTest` | red |' "$tmp/summary" || fail 'the summary lists the class as red'

run "$proven" "$untested"
[[ $RC -eq 1 && ! -s "$tmp/calls" ]] || fail 'a fix: commit without a test class must fail without running Gradle'
grep -qF "[PLAT-RED-001] ${untested:0:7} \"fix: rename a field\" adds or changes no test class" <<<"$OUT" \
  || fail 'PLAT-RED-001 names the commit'

run "$untested" "$green"
[[ $RC -eq 1 ]] || fail 'a test that passes on the parent must fail the proof'
grep -qF "[PLAT-RED-002] ${green:0:7} \"fix: tidy the calculator\": demo.CalcTest pass on the parent commit" <<<"$OUT" \
  || fail 'PLAT-RED-002 names the commit and the class'

run "$green" "$broken"
[[ $RC -eq 1 ]] || fail 'a test that does not run on the parent must fail the proof'
grep -qF "[PLAT-RED-003] ${broken:0:7} \"fix: a test that does not compile\": demo.OtherBrokenTest did not run" <<<"$OUT" \
  || fail 'PLAT-RED-003 names the commit and the class'

run "$broken" "$added" 'test integrationTest'
[[ $RC -eq 0 ]] || fail 'a test of a class the parent lacks must fail there and pass the proof'
[[ "$(cat "$tmp/calls")" == 'test --tests demo.ParserTest integrationTest --tests demo.ParserTest --continue --no-daemon -Pplatform.test.retry=off' ]] \
  || fail "every task of red-proof-tasks gets the filter, and a fixture is no test class: $(cat "$tmp/calls")"
[[ -f "$repo/src/main/java/demo/Parser.java" ]] || fail 'a production file the commit added is back afterwards'

run "$base" "$added"
[[ $RC -eq 1 ]] || fail 'one unproven fix: commit fails the whole pull request'
grep -qF '[PLAT-RED-001]' <<<"$OUT" && grep -qF '[PLAT-RED-002]' <<<"$OUT" && grep -qF '[PLAT-RED-003]' <<<"$OUT" \
  || fail 'every fix: commit of the pull request is checked'
echo 'OK: backend-ci red-proof runs the tests of each fix: commit against its parent and requires them to fail'
