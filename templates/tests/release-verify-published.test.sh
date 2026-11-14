#!/usr/bin/env bash
# verify-published in release.yml fails a release unless every published artifact carries the version.
# The block is cut out between its markers and run in a fake checkout against stub gh and npm.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { local message="$1"; echo "FAIL: $message" >&2; echo "--- output ---" >&2; echo "$OUT" >&2; exit 1; }

awk '
  index($0, "# >>> verify-published") { inside = 1; next }
  index($0, "# <<< verify-published") { inside = 0 }
  inside
' "$root/.github/workflows/release.yml" > "$tmp/verify.sh"
OUT=""
[[ -s "$tmp/verify.sh" ]] || fail 'release.yml has no verify-published block between its markers'

checkout="$tmp/checkout"
mkdir -p "$checkout/gradle/build-logic/src/main/kotlin" "$checkout/frontend/packages/eslint-config" "$checkout/frontend/packages/query"
touch "$checkout/gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts" \
      "$checkout/gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts"
printf '{ "name": "@dominiksienkiewicz/eslint-config" }\n' > "$checkout/frontend/packages/eslint-config/package.json"
printf '{ "name": "@dominiksienkiewicz/query", "private": true }\n' > "$checkout/frontend/packages/query/package.json"

# Stubs: gh lists 1.6.0 for every Maven package except $MISSING_MAVEN; npm knows 1.6.0 unless $MISSING_NPM.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
for arg in "$@"; do case "$arg" in */packages/maven/*) package="${arg#*/packages/maven/}"; package="${package%/versions}" ;; esac; done
echo "$package" >> "$CALLS"
[[ "$package" == "${MISSING_MAVEN:-}" ]] && { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
printf '1.5.31\n1.6.0\n'
GH
cat > "$tmp/bin/npm" <<'NPM'
#!/usr/bin/env bash
[[ "$2" == "${MISSING_NPM:-}@1.6.0" ]] && exit 1
echo 1.6.0
NPM
chmod +x "$tmp/bin/gh" "$tmp/bin/npm"

run() {
  : > "$tmp/calls"
  RC=0
  OUT=$(cd "$checkout" && PATH="$tmp/bin:$PATH" CALLS="$tmp/calls" V=1.6.0 GITHUB_TOKEN=dummy GPR_OWNER=owner bash "$tmp/verify.sh" 2>&1) || RC=$?
}

run
[[ $RC -eq 0 ]] || fail "a release where every artifact carries the version must pass (exit $RC)"
for package in pl.seniordeveloper.gradle.build-logic pl.seniordeveloper.platform-catalog \
  seniordev.java-conventions.seniordev.java-conventions.gradle.plugin \
  seniordev.settings-conventions.seniordev.settings-conventions.gradle.plugin; do
  grep -qx "$package" "$tmp/calls" || fail "verify-published must check $package"
done

MISSING_MAVEN=seniordev.settings-conventions.seniordev.settings-conventions.gradle.plugin run
[[ $RC -ne 0 ]] || fail 'a missing plugin marker must fail the release'
grep -q 'settings-conventions.gradle.plugin has no version 1.6.0' <<<"$OUT" || fail 'the error must name the missing package'

MISSING_NPM=@dominiksienkiewicz/eslint-config run
[[ $RC -ne 0 ]] || fail 'a missing npm package must fail the release'
grep -q 'npm @dominiksienkiewicz/eslint-config has no version 1.6.0' <<<"$OUT" || fail 'the error must name the missing npm package'

MISSING_NPM=@dominiksienkiewicz/query run
[[ $RC -eq 0 ]] || fail 'a private package is not published and must not be required'

echo 'OK: verify-published requires the version on every Maven package and every public npm package'
