#!/usr/bin/env bash
# Digest porażek backend-ci.yml (blok między markerami ci-digest) na raportach dwóch modułów: adnotacje z plikiem
# i linią, tabela w podsumowaniu joba, sekcja „What went wrong” Gradle, limit adnotacji. Do tego globy uploadu.
# shellcheck disable=SC2016 # literal GitHub expressions and Markdown backticks
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/backend-ci.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "--- output ---" >&2; cat "$tmp/out" "$tmp/summary" >&2 2>/dev/null; exit 1; }
: > "$tmp/out"

awk '
  index($0, "# >>> ci-digest") { inside = 1; next }
  index($0, "# <<< ci-digest") { inside = 0 }
  inside { sub(/^          /, ""); print }
' "$workflow" > "$tmp/digest.py"
[[ -s "$tmp/digest.py" ]] || fail 'backend-ci.yml has no ci-digest block between its markers'
grep -qF 'if: ${{ failure() }}' <(sed -n '/- name: Summarise the failures/,/run:/p' "$workflow") || fail 'the digest must run only on failure'
for glob in '**/build/reports/tests/' '**/build/test-results/' '**/build/reports/checkstyle/'; do
  grep -qF "\${{ inputs.working-directory }}/$glob" "$workflow" || fail "the upload must collect $glob of every module"
done

work="$tmp/repo"
mkdir -p "$work/app/src/test/java/pl/example" "$work/app/build/test-results/test" "$work/lib/build/reports/checkstyle"
touch "$work/app/src/test/java/pl/example/OrderTest.java"
cat > "$work/app/build/test-results/test/TEST-pl.example.OrderTest.xml" <<'XML'
<testsuite name="pl.example.OrderTest" tests="2" failures="1">
  <testcase classname="pl.example.OrderTest" name="totalsTheLines()"/>
  <testcase classname="pl.example.OrderTest" name="rejectsAnEmptyOrder()">
    <failure message="expected: &lt;400&gt; but was: &lt;200&gt;">org.opentest4j.AssertionFailedError: expected: &lt;400&gt; but was: &lt;200&gt;
	at pl.example.OrderTest.rejectsAnEmptyOrder(OrderTest.java:27)</failure>
  </testcase>
</testsuite>
XML
cat > "$work/lib/build/reports/checkstyle/main.xml" <<XML
<checkstyle version="13.0">
  <file name="$work/lib/src/main/java/pl/example/Money.java">
    <error line="14" column="5" severity="error" message="Missing a Javadoc comment." source="com.puppycrawl.tools.checkstyle.checks.javadoc.MissingJavadocMethodCheck"/>
  </file>
</checkstyle>
XML
printf 'BUILD FAILED\n\n* What went wrong:\nExecution failed for task :app:platformDependencyCheck.\n> Dependency versions outside the Platform catalog\n\n* Try:\n> Run with --stacktrace\n' > "$tmp/gradle.log"

(cd "$work" && GITHUB_WORKSPACE="$work" GITHUB_STEP_SUMMARY="$tmp/summary" GRADLE_OUTPUT="$tmp/gradle.log" python3 "$tmp/digest.py") > "$tmp/out"
grep -qxF '::error file=app/src/test/java/pl/example/OrderTest.java,line=27,title=Test failed: pl.example.OrderTest.rejectsAnEmptyOrder()::expected: <400> but was: <200>' "$tmp/out" \
  || fail 'a failed test must be annotated at its source line'
grep -qxF '::error file=lib/src/main/java/pl/example/Money.java,line=14,title=Checkstyle MissingJavadocMethod::Missing a Javadoc comment.' "$tmp/out" \
  || fail 'a Checkstyle violation must be annotated at its line'
grep -qF '| `pl.example.OrderTest.rejectsAnEmptyOrder()` | expected: <400> but was: <200> | `app/src/test/java/pl/example/OrderTest.java:27` |' "$tmp/summary" \
  || fail 'the summary must list the failed test'
grep -qF 'Execution failed for task :app:platformDependencyCheck.' "$tmp/summary" || fail 'the summary must repeat what went wrong'
if grep -qF 'totalsTheLines' "$tmp/out" "$tmp/summary"; then fail 'passing tests are not reported'; fi

for i in $(seq 1 12); do
  printf '<testsuite><testcase classname="pl.example.Many" name="case%s"><failure message="boom %s"/></testcase></testsuite>\n' "$i" "$i" \
    > "$work/app/build/test-results/test/TEST-many-$i.xml"
done
(cd "$work" && GITHUB_WORKSPACE="$work" python3 "$tmp/digest.py") > "$tmp/out"
[[ $(grep -c '^::error file=\|^::error title=Test failed\|^::error title=Checkstyle' "$tmp/out") -eq 10 ]] || fail 'annotations must be capped at 10'
grep -qF '::error title=More failures::4 more' "$tmp/out" || fail 'the cap must say how many were left out'

echo 'OK: the backend-ci digest annotates failed tests and Checkstyle violations from every module and summarises them'
