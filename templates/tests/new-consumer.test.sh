#!/usr/bin/env bash
# scripts/new-consumer.sh, przypadek po przypadku: wyrenderowani konsumenci spring-app i java-library, kontekst
# budowania, którego wymaga Dockerfile.frontend, frontend Next.js w trybie strict, kolejność importów wyrenderowanych
# źródeł i podpakiety startera.
# shellcheck disable=SC2016 # dosłowne wyrażenia GitHuba
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- rendered-consumers ---
# scripts/new-consumer.sh renderuje oba rodzaje konsumentów z kanonu: backend/ z podmienionym pakietem, grupą
# i nazwą, wrapper, pin platformVersion, caller CI na dokładnym tagu bez inherit i kopie skryptów bajt w bajt.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

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
grep -qF 'uses: SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.6.0' "$workflow" || fail 'the caller must use the exact tag'
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
)

# --- frontend-image ---
# scripts/new-consumer.sh --frontend next renderuje kontekst budowania, którego wymaga templates/Dockerfile.frontend:
# każde źródło COPY z kontekstu (poza package-lock.json, który pisze npm install) oraz katalogi, które etap runner
# kopiuje z /app spoza .next/ (public/), z plikiem w środku, bo git nie przechowuje pustego katalogu (N-CAP-6).
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
dockerfile="$root/templates/Dockerfile.frontend"

bash "$root/scripts/new-consumer.sh" --name shop --package pl.example.shop --kind java-library --out "$tmp/shop" --frontend next > /dev/null
web="$tmp/shop/frontend"

sources=$(awk '$1 == "COPY" && $2 !~ /^--/ { for (i = 2; i < NF; i++) if ($i != ".") print $i }' "$dockerfile")
[[ -n "$sources" ]] || fail 'Dockerfile.frontend copies no named file from the build context'
while IFS= read -r source; do
  [[ "$source" == package-lock.json ]] && continue
  [[ -e "$web/$source" ]] || fail "frontend/$source is missing, but Dockerfile.frontend copies it from the build context"
done <<<"$sources"

directories=$(awk '$1 == "COPY" && $2 == "--from=builder" {
  for (i = 3; i < NF; i++) if ($i ~ /^\/app\// && $i !~ /^\/app\/\.next/) { sub(/^\/app\//, "", $i); print $i }
}' "$dockerfile")
[[ -n "$directories" ]] || fail 'Dockerfile.frontend copies no directory of the build context into the runner'
while IFS= read -r directory; do
  [[ -n "$(find "$web/$directory" -type f 2>/dev/null)" ]] \
    || fail "frontend/$directory must exist with a file in it: the runner copies /app/$directory, and git keeps no empty directory"
done <<<"$directories"

echo 'OK: new-consumer --frontend next renders every path Dockerfile.frontend copies from the build context'
)

# --- frontend ---
# scripts/new-consumer.sh --frontend next: frontend/ z konfiguracjami paczek Platform, skryptami trybu strict
# i package.json, który przechodzi platform-versions-check kanonu tego checkoutu (każda zależność z kanonu,
# każda paczka Platform w zakresie npm wydania), plus caller frontend-ci.yml ze strict: true.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
version=$(sed -n 's/^platformVersion=//p' "$root/gradle/build-logic/gradle.properties")

bash "$root/scripts/new-consumer.sh" --name shop --package pl.example.shop --kind spring-app --out "$tmp/shop" --frontend next > "$tmp/out"
web="$tmp/shop/frontend"
for file in package.json .npmrc .gitignore .nvmrc tsconfig.json eslint.config.mjs postcss.config.mjs vitest.config.ts next.config.ts \
  Dockerfile src/app/layout.tsx src/app/page.tsx src/app/page.test.tsx src/app/globals.css; do
  [[ -f "$web/$file" ]] || fail "frontend/$file is missing"
done
scope=@seniordeveloper-pl-dominik-sienkiewicz
if [[ $version == 1.* ]]; then scope=@dominiksienkiewicz; fi
cmp -s <(sed "s/@seniordeveloper-pl-dominik-sienkiewicz:/$scope:/" "$root/templates/npmrc") "$web/.npmrc" \
  || fail 'frontend/.npmrc must contain the canonical configuration for its release scope'
cmp -s "$root/templates/Dockerfile.frontend" "$web/Dockerfile" || fail 'frontend/Dockerfile must be the canonical copy'
cmp -s "$root/templates/frontend/next.config.ts" "$web/next.config.ts" || fail 'next.config.ts must be the canonical copy'
for script in lint typecheck test build format:check; do
  node -e 'const s = require(process.argv[1]).scripts; if (!s[process.argv[2]]) process.exit(1)' "$web/package.json" "$script" \
    || fail "strict frontend-ci needs the $script script"
done
node -e 'const m = require(process.argv[1]); if (m.devDependencies[process.argv[3] + "/versions"] !== process.argv[2]) process.exit(1)' \
  "$web/package.json" "$version" "$scope" || fail "$scope/versions must be pinned at $version"
(cd "$web" && node "$root/frontend/packages/versions/bin/check.mjs") > "$tmp/check" 2>&1 \
  || { cat "$tmp/check" >&2; fail 'the generated package.json must pass platform-versions-check of this canon'; }
grep -qF 'Frontend: (cd' "$tmp/out" || fail 'the generator must say how to create package-lock.json'

workflow="$tmp/shop/.github/workflows/ci.yml"
grep -qF "uses: SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/.github/workflows/frontend-ci.yml@v$version" "$workflow" || fail 'the frontend caller must use the exact tag'
grep -qx '      strict: true' "$workflow" || fail 'the frontend caller must run strict'
[[ $(grep -c 'gpr_token: ${{ secrets.GPR_TOKEN }}' "$workflow") -eq 2 ]] || fail 'both callers pass gpr_token explicitly'

if bash "$root/scripts/new-consumer.sh" --name other --package pl.example.other --kind spring-app --out "$tmp/other" --frontend vue 2>/dev/null; then
  fail 'an unknown frontend must be refused'
fi
echo 'OK: new-consumer --frontend next renders a strict Next.js frontend that passes the version canon'
)

# --- import-order ---
# scripts/new-consumer.sh zostawia importy w kolejności google-java-format także wtedy, gdy nowy pakiet sortuje się
# za org.* (pl.example.bank): podmieniony prefiks nie może zostać na starym miejscu, bo spotlessCheck świeżo
# wygenerowanego repo byłby czerwony (GeneratedConsumerFunctionalTest w build-logic).
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

static_imports() { sed -nE 's/^import static ([^ ;]+);$/\1/p' "$1"; }
plain_imports() { sed -nE '/^import static /d; s/^import ([^ ;]+);$/\1/p' "$1"; }

for package in pl.example.bank com.acme.orders; do
  name="${package##*.}-service"
  bash "$root/scripts/new-consumer.sh" --name "$name" --package "$package" --kind spring-app --out "$tmp/$name" > /dev/null
  while IFS= read -r -d '' file; do
    for group in static_imports plain_imports; do
      actual=$("$group" "$file")
      expected=$(LC_ALL=C sort <<< "$actual")
      [[ "$actual" == "$expected" ]] || fail "${file#"$tmp"/}: the imports must keep the google-java-format order:
$expected
instead of
$actual"
    done
  done < <(find "$tmp/$name/backend/src" -name '*.java' -print0)
done

welcome="$tmp/bank-service/backend/src/main/java/pl/example/bank/notifications/WelcomeNotifications.java"
[[ "$(plain_imports "$welcome" | tail -n 1)" == pl.example.bank.accounts.AccountOpened ]] \
  || fail 'an import of a package that sorts after org.* must come after the org.* imports'

echo 'OK: new-consumer keeps the imports of the rendered starter in google-java-format order'
)

# --- modules ---
# scripts/new-consumer.sh przenosi podpakiety startera (moduły Spring Modulith spring-app) razem z katalogami
# i podmienia prefiks pakietu w deklaracjach package i w importach, także gdy nowy pakiet leży pod katalogiem
# szablonu (example.shop).
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

render() { bash "$root/scripts/new-consumer.sh" --name "$1" --package "$2" --kind spring-app --out "$tmp/$1" > /dev/null; }
sources() { (cd "$1" && find . -type f | sort); }

render account-service pl.example.bank
backend="$tmp/account-service/backend"
for source_set in main test; do
  expected=$(sources "$root/templates/jvm/spring-app/src/$source_set/java/example/app")
  actual=$(sources "$backend/src/$source_set/java/pl/example/bank")
  [[ "$actual" == "$expected" ]] || fail "src/$source_set: every file of the starter must keep its sub-package:
$actual
instead of
$expected"
done
main="$backend/src/main/java/pl/example/bank"
grep -qx 'package pl.example.bank.accounts;' "$main/accounts/Accounts.java" || fail 'a module must get the new package'
grep -qx 'package pl.example.bank.notifications;' "$main/notifications/WelcomeNotifications.java" \
  || fail 'every module must get the new package'
grep -qx 'import pl.example.bank.accounts.AccountOpened;' "$main/notifications/WelcomeNotifications.java" \
  || fail 'an import between modules must get the new package'
grep -qx 'package pl.example.bank;' "$backend/src/test/java/pl/example/bank/ApplicationTest.java" \
  || fail 'the test sources must get the new package'
if grep -rqF 'example.app' "$backend/src"; then fail 'no reference to the template package may remain'; fi
[[ ! -e "$backend/src/main/java.rendered" ]] || fail 'the staging directory must be gone'

render shop-service example.shop
shop="$tmp/shop-service/backend/src/main/java/example"
[[ -f "$shop/shop/Application.java" && -f "$shop/shop/accounts/Accounts.java" ]] \
  || fail 'a package under the template directory must keep the rendered files'
[[ ! -d "$shop/app" ]] || fail 'the template package must be gone'
grep -qx 'import example.shop.accounts.AccountOpened;' "$shop/shop/notifications/WelcomeNotifications.java" \
  || fail 'the import must point at the new package'

echo 'OK: new-consumer renders the sub-packages of the starter with the new package'
)
