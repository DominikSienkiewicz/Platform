#!/usr/bin/env bash
# Digest backend-ci.yml nazywa kodem bramki porażki Gradle'a, które własnego kodu nie drukują (N-SHOW-8):
# weryfikacja zależności i próg pokrycia JaCoCo, przed adnotacjami testów i poza ich limitem.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" >&2; exit 1; }
awk '
  index($0, "# >>> ci-digest") { inside = 1; next }
  index($0, "# <<< ci-digest") { inside = 0 }
  inside { sub(/^          /, ""); print }
' "$root/.github/workflows/backend-ci.yml" > "$tmp/digest.py"
cat > "$tmp/gradle.log" <<'LOG'
> Task :compileJava FAILED

FAILURE: Build failed with an exception.

* What went wrong:
Dependency verification failed for configuration ':compileClasspath'
One artifact failed verification: jackson-core-3.1.8.jar

* Try:
> Run with --stacktrace.

* What went wrong:
Execution failed for task ':jacocoTestCoverageVerification'.
> Rule violated for bundle app: instructions covered ratio is 0.41, but expected minimum is 0.80

* Try:
> Run with --info.
LOG
(cd "$tmp" && GITHUB_WORKSPACE="$tmp" GRADLE_OUTPUT="$tmp/gradle.log" python3 -I digest.py) > "$tmp/out"
grep -qxF "::error title=PLAT-VER-001::[PLAT-VER-001] Dependency verification failed for configuration ':compileClasspath'" "$tmp/out" \
  || fail 'dependency verification must be annotated as PLAT-VER-001'
grep -qF "::error title=PLAT-COV-003::[PLAT-COV-003] Execution failed for task ':jacocoTestCoverageVerification'." "$tmp/out" \
  || fail 'the coverage threshold must be annotated as PLAT-COV-003'
echo 'OK: the backend-ci digest names Gradle failures without a code of their own with their gate code'
