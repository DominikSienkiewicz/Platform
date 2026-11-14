#!/usr/bin/env bash
# scripts/new-consumer.sh renderuje oba rodzaje konsumentów z kanonu: backend/ z podmienionym pakietem, grupą
# i nazwą, wrapper, pin platformVersion, caller CI na dokładnym tagu bez inherit i kopie skryptów bajt w bajt.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

render() { bash "$root/scripts/new-consumer.sh" --name "$1" --package "$2" --kind "$3" --out "$tmp/$1" "${@:4}" > /dev/null; }

render order-service pl.example.orders spring-app --platform-version 1.6.0
out="$tmp/order-service"
for file in backend/src/main/java/pl/example/orders/Application.java backend/src/test/java/pl/example/orders/ApplicationTest.java \
  backend/gradlew backend/gradle/wrapper/gradle-wrapper.properties backend/.gitignore .gitignore .editorconfig .sdkmanrc .github/workflows/ci.yml; do
  [[ -f "$out/$file" ]] || fail "spring-app: $file is missing"
done
[[ ! -d "$out/backend/src/main/java/example" ]] || fail 'the template package must be gone'
grep -qx 'package pl.example.orders;' "$out/backend/src/main/java/pl/example/orders/Application.java" || fail 'the package must be substituted'
grep -qx 'rootProject.name = "order-service"' "$out/backend/settings.gradle.kts" || fail 'rootProject.name must be the name'
grep -qx 'group = "pl.example.orders"' "$out/backend/build.gradle.kts" || fail 'the group must be the package'
grep -qx 'platformVersion=1.6.0' "$out/backend/gradle.properties" || fail 'the pin must be the requested version'
[[ -x "$out/backend/gradlew" ]] || fail 'the wrapper must be executable'
workflow="$out/.github/workflows/ci.yml"
grep -qF 'uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.6.0' "$workflow" || fail 'the caller must use the exact tag'
if grep -qE '@v1$|@v1[^.]|secrets: inherit' "$workflow"; then fail 'no @v1 and no secrets: inherit'; fi
grep -qx '  packages: read' "$workflow" || fail 'the caller must grant packages: read'
grep -qF 'gpr_token: ${{ secrets.GPR_TOKEN }}' "$workflow" || fail 'the caller must pass gpr_token explicitly'
for script in platform-bump.sh merge.sh agent-gradle.sh worktree-new.sh worktree-status.sh; do
  cmp -s "$root/templates/$script" "$out/scripts/$script" || fail "scripts/$script must be the canonical copy"
done
cmp -s "$root/templates/gitignore/backend.gitignore" "$out/backend/.gitignore" || fail 'backend/.gitignore must be the backend set'
if grep -rqF 'example.app' "$out/backend"; then fail 'no reference to the template package may remain'; fi

render greeting-lib pl.example.greeting java-library
lib="$tmp/greeting-lib"
grep -qx 'package pl.example.greeting;' "$lib/backend/src/main/java/pl/example/greeting/Greeting.java" || fail 'java-library: the package must be substituted'
grep -qx "platformVersion=$(sed -n 's/^platformVersion=//p' "$root/gradle/build-logic/gradle.properties")" "$lib/backend/gradle.properties" \
  || fail "without --platform-version the pin is this checkout's version"

if render order-service pl.example.orders spring-app 2>/dev/null; then fail 'an existing directory must be refused'; fi
if render Order pl.example.orders spring-app 2>/dev/null; then fail 'a name that is not kebab-case must be refused'; fi
if render bad-package Example spring-app 2>/dev/null; then fail 'a package that is not a Java package must be refused'; fi
if render other pl.example.other web-app 2>/dev/null; then fail 'an unknown kind must be refused'; fi

echo 'OK: new-consumer renders spring-app and java-library consumers from the canon'
