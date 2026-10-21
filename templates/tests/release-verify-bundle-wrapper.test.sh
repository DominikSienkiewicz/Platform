#!/usr/bin/env bash
# Job verify-bundle w release.yml składa starter spring-app z wrapperem java-library. spring-app ma własne gradle/
# (kryteria JVM demona), więc `cp -R …/gradle "$app/gradle"` zagnieżdżało wrapper w gradle/gradle/wrapper i build
# wydania 1.8.0 padł na "Unable to access jarfile". Kroki przygotowania (do `cd "$app"`) biegną na zasianym drzewie.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

awk '
  /- name: Build the spring-app starter from the bundle alone$/ { step = 1; next }
  step && /^          cd "\$app"$/ { exit }
  step && /^        run: \|$/ { body = 1; next }
  body { sub(/^          /, ""); print }
' "$root/.github/workflows/release.yml" > "$tmp/prepare.sh"
[[ -s "$tmp/prepare.sh" ]] || fail 'release.yml has no "Build the spring-app starter from the bundle alone" step'

tree="$tmp/tree"
mkdir -p "$tree/templates/jvm/spring-app/gradle" "$tree/templates/jvm/java-library/gradle/wrapper" "$tmp/runner"
echo 'toolchainVersion=27' > "$tree/templates/jvm/spring-app/gradle/gradle-daemon-jvm.properties"
echo 'platformVersion=1.0.0' > "$tree/templates/jvm/spring-app/gradle.properties"
echo '#!/bin/sh' > "$tree/templates/jvm/java-library/gradlew"
: > "$tree/templates/jvm/java-library/gradle/wrapper/gradle-wrapper.jar"
: > "$tree/templates/jvm/java-library/gradle/wrapper/gradle-wrapper.properties"

# sed -i bez sufiksu działa tylko w GNU sed (runner); na macOS zastępuje go atrapa.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/sed" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == -i ]]; then shift; file="${*: -1}"; "$REAL_SED" "${@:1:$#-1}" "$file" > "$file.new" && mv "$file.new" "$file"; else "$REAL_SED" "$@"; fi
STUB
chmod +x "$tmp/bin/sed"
(cd "$tree" && REAL_SED="$(command -v sed)" PATH="$tmp/bin:$PATH" RUNNER_TEMP="$tmp/runner" V=9.9.9 bash -e "$tmp/prepare.sh") || fail 'the preparation steps failed'

app="$tmp/runner/spring-app"
[[ -f "$app/gradle/wrapper/gradle-wrapper.jar" ]] \
  || fail "the wrapper jar must land in spring-app/gradle/wrapper, found: $(cd "$app" && find gradle -type f | sort | tr '\n' ' ')"
[[ -f "$app/gradle/gradle-daemon-jvm.properties" ]] || fail 'the daemon JVM criteria of spring-app must stay'
[[ -f "$app/gradlew" ]] || fail 'spring-app must get gradlew'
grep -qx 'platformVersion=9.9.9' "$app/gradle.properties" || fail 'the starter must be pinned at the release'

echo 'OK: verify-bundle gives spring-app the wrapper of java-library next to its own gradle/ files'
