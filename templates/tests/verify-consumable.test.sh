#!/usr/bin/env bash
# scripts/verify-consumable.sh na atrapach: gradlew (VERIFY_GRADLEW) odgrywa drzewo zależności, npm instaluje
# paczki z plikami z ich prawdziwych manifestów. Sprawdza wynik dla dobrego wydania, FAILED w drzewie, flakę
# GitHub Packages (jedna powtórka) i tarball bez zadeklarowanego pliku.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "--- output ---" >&2; cat "$tmp/out" >&2; exit 1; }

mkdir -p "$tmp/bin"
# Jak prawdziwy wrapper: bez gradlew i gradle/wrapper/gradle-wrapper.jar w kopii startera Gradle nie rusza.
cat > "$tmp/gradlew" <<'STUB'
#!/usr/bin/env bash
if [[ ! -f gradlew || ! -f gradle/wrapper/gradle-wrapper.jar ]]; then
  echo "Error: Unable to access jarfile $PWD/gradle/wrapper/gradle-wrapper.jar"; exit 1
fi
echo "$PWD $*" >> "$FAKE_LOG"
count=$(grep -c . "$FAKE_LOG")
if [[ "$FAKE_GRADLE" == flaky && "$count" -eq 1 ]]; then echo "Could not resolve: 401"; exit 1; fi
echo "testRuntimeClasspath"
echo "+--- pl.seniordeveloper:platform-test-fixtures:9.9.9"
[[ "$FAKE_GRADLE" == failed ]] && echo "+--- pl.seniordeveloper:platform-security-starter:9.9.9 FAILED"
exit 0
STUB
cat > "$tmp/bin/npm" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  view) echo "sha512-fake"; exit 0 ;;
  install)
    prefix="" spec=""
    while [[ $# -gt 0 ]]; do case "$1" in --prefix) prefix="$2"; shift ;; @*) spec="$1" ;; esac; shift; done
    node - "$prefix" "$spec" "$FAKE_ROOT" "${FAKE_NPM_MISSING:-}" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const [prefix, spec, root, missing] = process.argv.slice(2);
const at = spec.lastIndexOf("@");
const [name, version] = [spec.slice(0, at), spec.slice(at + 1)];
const dir = path.join(root, "frontend/packages");
const source = fs.readdirSync(dir).map((d) => path.join(dir, d, "package.json")).filter(fs.existsSync)
  .map((p) => JSON.parse(fs.readFileSync(p, "utf8"))).find((m) => m.name === name);
const target = path.join(prefix, "node_modules", name);
fs.mkdirSync(target, { recursive: true });
fs.writeFileSync(path.join(target, "package.json"), JSON.stringify({ ...source, version }));
const targets = (v) => (typeof v === "string" ? [v] : v && typeof v === "object" ? Object.values(v).flatMap(targets) : []);
const bin = typeof source.bin === "string" ? [source.bin] : Object.values(source.bin ?? {});
const files = [source.main, ...(name === missing ? [] : bin), ...targets(source.exports)].filter((f) => f && !f.includes("*"));
for (const file of files) {
  fs.mkdirSync(path.dirname(path.join(target, file)), { recursive: true });
  fs.writeFileSync(path.join(target, file), "");
}
NODE
    ;;
esac
STUB
chmod +x "$tmp/gradlew" "$tmp/bin/npm"
export PATH="$tmp/bin:$PATH" VERIFY_GRADLEW="$tmp/gradlew" VERIFY_BACKOFF=0 FAKE_ROOT="$root" FAKE_LOG="$tmp/gradle.log"
check() { : > "$FAKE_LOG"; : > "$tmp/summary"; GITHUB_STEP_SUMMARY="$tmp/summary" bash "$root/scripts/verify-consumable.sh" 9.9.9 > "$tmp/out" 2>&1; }

FAKE_GRADLE=ok check || fail 'a consumable release must pass'
grep -q '/spring-app --no-daemon help dependencies' "$FAKE_LOG" \
  || fail 'spring-app, whose gradle/ holds only the daemon JVM criteria, must get the wrapper of java-library'
[[ $(grep -c 'help dependencies --configuration testRuntimeClasspath --refresh-dependencies' "$FAKE_LOG") -eq 2 ]] \
  || fail 'both starters must resolve testRuntimeClasspath with --refresh-dependencies'
# shellcheck disable=SC2016 # literal backticks of the Markdown row
row='| `@dominiksienkiewicz/versions@9.9.9` | `sha512-fake` |'
grep -qF "$row" "$tmp/summary" || fail 'the summary must list each npm integrity'
if grep -qF '@dominiksienkiewicz/query' "$tmp/summary"; then fail 'private packages are not installed'; fi

if FAKE_GRADLE=failed check; then fail 'a FAILED dependency must fail the check'; fi
grep -qF '::error title=Release not consumable::Gradle: templates/jvm/java-library does not resolve Platform 9.9.9' "$tmp/out" \
  || fail 'the failure must name the starter'
grep -qF 'docs/runbooks/rollback.md' "$tmp/out" || fail 'the failure must point at the rollback runbook'

FAKE_GRADLE=flaky check || fail 'one failed first resolution must be retried'
grep -qF 'Retrying in 0s' "$tmp/out" || fail 'the retry must be reported'

if FAKE_GRADLE=ok FAKE_NPM_MISSING=@dominiksienkiewicz/versions check; then fail 'a tarball without its bin must fail'; fi
grep -qF 'npm: @dominiksienkiewicz/versions@9.9.9 declares files it does not ship: bin/check.mjs' "$tmp/out" \
  || fail 'the failure must name the package and the missing file'

echo 'OK: verify-consumable resolves both starters and every public npm package the way a consumer does'
