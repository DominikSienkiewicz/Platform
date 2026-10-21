#!/usr/bin/env bash
# verify-consumable.sh <version> — czy opublikowane wydanie da się skonsumować tak, jak robi to konsument:
# z prawdziwego GitHub Packages, z czystym GRADLE_USER_HOME i bez -PplatformRepository.
#   Gradle: kopie templates/jvm/java-library (+ test-fixtures i security-starter z katalogu) i spring-app na pinie
#           <version> rozwiązują settings plugin, markery convention pluginów, wariant katalogu i obie biblioteki.
#   npm:    każda publiczna paczka z frontend/packages instaluje się w <version> i zawiera pliki, które deklaruje
#           (main, bin, exports); integralność trafia do podsumowania joba.
# Pierwsza próba każdego rozwiązania dostaje jedną powtórkę: GitHub Packages bywa chwilę za świeżą publikacją.
# Woła go job verify-consumable w release.yml; test: templates/tests/verify-consumable.test.sh.
set -uo pipefail
version=${1:?Usage: verify-consumable.sh <version>}
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GRADLE_USER_HOME="$work/gradle-home"
gradlew=${VERIFY_GRADLEW:-./gradlew}
backoff=${VERIFY_BACKOFF:-30}
failures=()

retry() {
  "$@" && return 0
  echo "Retrying in ${backoff}s: GitHub Packages may still be serving the previous state."
  sleep "$backoff"
  "$@"
}

resolve() {
  (cd "$1" && "$gradlew" --no-daemon help dependencies --configuration testRuntimeClasspath --refresh-dependencies) > "$1.log" 2>&1 \
    && ! grep -q 'FAILED' "$1.log"
}

for starter in java-library spring-app; do
  copy="$work/$starter"
  cp -R "$root/templates/jvm/$starter" "$copy"
  if [[ ! -f "$copy/gradlew" ]]; then
    cp "$root/templates/jvm/java-library/gradlew" "$copy/gradlew"
    # spring-app ma własne gradle/ (kryteria JVM demona): `cp -R gradle gradle` zagnieździłby wrapper w gradle/gradle.
    mkdir -p "$copy/gradle" && cp -R "$root/templates/jvm/java-library/gradle/wrapper" "$copy/gradle/"
  fi
  sed -i.bak "s/^platformVersion=.*/platformVersion=$version/" "$copy/gradle.properties" && rm -f "$copy/gradle.properties.bak"
done
cat >> "$work/java-library/build.gradle.kts" <<'KTS'

dependencies {
	testImplementation(libs.platform.test.fixtures)
	implementation(libs.platform.security.starter)
}
KTS
for starter in java-library spring-app; do
  if ! retry resolve "$work/$starter"; then
    failures+=("Gradle: templates/jvm/$starter does not resolve Platform $version from GitHub Packages")
    tail -40 "$work/$starter.log"
  fi
done

npm_dir="$work/npm"
mkdir -p "$npm_dir"
printf '{ "private": true }\n' > "$npm_dir/package.json"
summary="| npm package | integrity |"$'\n'"|---|---|"
for manifest in "$root"/frontend/packages/*/package.json; do
  [[ "$(node -p 'require(process.argv[1]).private === true' "$manifest")" == true ]] && continue
  name=$(node -p 'require(process.argv[1]).name' "$manifest")
  if ! retry npm install --prefix "$npm_dir" --no-save --ignore-scripts --legacy-peer-deps --no-audit --no-fund \
    "$name@$version" > "$work/npm.log" 2>&1; then
    failures+=("npm: $name@$version does not install")
    tail -20 "$work/npm.log"
    continue
  fi
  # Pliki z main, bin i exports (bez wzorców z *) muszą być w zainstalowanym tarballu.
  problem=$(node - "$npm_dir/node_modules/$name" "$version" <<'NODE'
const { existsSync, readFileSync } = require("node:fs");
const { join } = require("node:path");
const [dir, version] = process.argv.slice(2);
const manifest = JSON.parse(readFileSync(join(dir, "package.json"), "utf8"));
if (manifest.version !== version) {
  console.log(`installed ${manifest.version}, not ${version}`);
  process.exit(0);
}
const targets = (value) =>
  typeof value === "string" ? [value] : value && typeof value === "object" ? Object.values(value).flatMap(targets) : [];
const bin = typeof manifest.bin === "string" ? [manifest.bin] : Object.values(manifest.bin ?? {});
const declared = [manifest.main, ...bin, ...targets(manifest.exports)].filter((file) => file && !file.includes("*"));
const missing = [...new Set(declared)].filter((file) => !existsSync(join(dir, file)));
if (missing.length) console.log(`declares files it does not ship: ${missing.join(", ")}`);
NODE
  )
  if [[ -n "$problem" ]]; then
    failures+=("npm: $name@$version $problem")
  fi
  summary+=$'\n'"| \`$name@$version\` | \`$(npm view "$name@$version" dist.integrity 2>/dev/null)\` |"
done

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '## Platform %s is consumable\n\n%s\n' "$version" "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
if [[ "${#failures[@]}" -gt 0 ]]; then
  for failure in "${failures[@]}"; do
    echo "::error title=Release not consumable::$failure. Yank or replace the release: docs/runbooks/rollback.md"
  done
  exit 1
fi
echo "Platform $version resolves from GitHub Packages as a consumer resolves it."
