#!/usr/bin/env bash
# Migracje wydania (migrations/): każda z test/migrations/<slug>/before daje after przez runner, drugi przebieg
# niczego nie zmienia, bramka SINCE wybiera właściwe migracje, a pełny bump od 1.5.26 wykonuje je z tarballa celu.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=bump-fixture.sh
source "$here/bump-fixture.sh"
runner="$here/../migrations/run.sh"

# fixture <slug> <before|after>: kopia drzewa w katalogu roboczym. Pliki obrazów leżą w repo jako docker-image.fixture,
# bo OpenSSF Scorecard (Pinned-Dependencies) liczy każdy plik z „Dockerfile" w nazwie jako build Platform;
# kopia odzyskuje nazwę Dockerfile, której szuka migracja.
fixture() {
  local copy="$fixture_work/fixture-$1-$2"
  rm -rf "$copy" && cp -R "$here/migrations/$1/$2" "$copy"
  find "$copy" -name docker-image.fixture -exec sh -c 'mv "$1" "$(dirname "$1")/Dockerfile"' _ {} \;
  printf '%s\n' "$copy"
}

# migrate <slug> <current> <target>: kopia before/ w katalogu roboczym, wynik runnera w $fixture_work/<slug>.out
migrate() {
  local tree="$fixture_work/tree-$1"
  rm -rf "$tree" && mv "$(fixture "$1" before)" "$tree"
  (cd "$tree" && PLATFORM_CANON="$here/migrations/$1/versions.json" bash "$runner" apply "$2" "$3") > "$fixture_work/$1.out"
  printf '%s\n' "$tree"
}

for slug in caller-packages-read runtime-image-27 drop-stale-overrides; do
  tree=$(migrate "$slug" 1.5.26 1.6.0)
  after=$(fixture "$slug" after)
  diff -r "$after" "$tree" || fail "$slug: before/ must become after/"
  grep -q "applied  .*$slug" "$fixture_work/$slug.out" || { cat "$fixture_work/$slug.out"; fail "$slug: the runner must report it applied"; }
  (cd "$tree" && PLATFORM_CANON="$here/migrations/$slug/versions.json" bash "$runner" apply 1.5.26 1.6.0) > "$fixture_work/$slug.again"
  diff -r "$after" "$tree" || fail "$slug: a second run must change nothing"
  if grep -q "applied  .*$slug" "$fixture_work/$slug.again"; then cat "$fixture_work/$slug.again"; fail "$slug: a second run must not apply it again"; fi
done

grep -qF ".github/workflows/flow.yml:2: add packages: read to \`permissions: { contents: read }\`" "$fixture_work/caller-packages-read.out" \
  || { cat "$fixture_work/caller-packages-read.out"; fail 'a flow-mapping permissions block must be left for a manual fix'; }
grep -qF "Dockerfile:1: move \`eclipse-temurin:26-jre-alpine\` to a Java 27 runtime" "$fixture_work/runtime-image-27.out" \
  || { cat "$fixture_work/runtime-image-27.out"; fail 'an image variant the migration does not know must be left for a manual fix'; }
grep -qF 'removed overrides.postcss: 8.4.31' "$fixture_work/drop-stale-overrides.out" || fail 'the removed overrides must be listed'

# 1.8.0: Gradle na JDK 27 (ADR-0034). Callery Platform i .sdkmanrc automatycznie; kryteria demona i setup-java
# poza callerami Platform tylko jako notatka, bo migracja nie wie, czy ten JDK uruchamia Gradle'a.
tree=$(migrate gradle-jdk-27 1.7.0 1.8.0)
diff -r "$(fixture gradle-jdk-27 after)" "$tree" || fail 'gradle-jdk-27: before/ must become after/'
grep -q 'applied  .*gradle-jdk-27' "$fixture_work/gradle-jdk-27.out" || { cat "$fixture_work/gradle-jdk-27.out"; fail 'gradle-jdk-27: the runner must report it applied'; }
(cd "$tree" && bash "$runner" apply 1.7.0 1.8.0) > "$fixture_work/gradle-jdk-27.again"
diff -r "$(fixture gradle-jdk-27 after)" "$tree" || fail 'gradle-jdk-27: a second run must change nothing'
if grep -q 'applied  .*gradle-jdk-27' "$fixture_work/gradle-jdk-27.again"; then cat "$fixture_work/gradle-jdk-27.again"; fail 'gradle-jdk-27: a second run must not apply it again'; fi
for expected in \
  '.github/workflows/ci.yml:27: java-version 21 is set outside a Platform caller; raise it to 27 if this JDK runs Gradle' \
  'backend/gradle/gradle-daemon-jvm.properties: toolchainVersion=25; run ./gradlew updateDaemonJvm --jvm-version=27'; do
  grep -qF -- "$expected" "$fixture_work/gradle-jdk-27.out" || { cat "$fixture_work/gradle-jdk-27.out"; fail "gradle-jdk-27: missing manual note: $expected"; }
  grep -qF -- "$expected" "$fixture_work/gradle-jdk-27.again" || { cat "$fixture_work/gradle-jdk-27.again"; fail "gradle-jdk-27: a second run must repeat: $expected"; }
done
template_sdkman=$(sed -n 's/^java=//p' "$here/../../../../templates/.sdkmanrc")
grep -qx "SDKMAN_JAVA=\"$template_sdkman\"" "$here/../migrations/1.8.0-gradle-jdk-27.sh" \
  || fail "gradle-jdk-27 must write java=$template_sdkman, the value of templates/.sdkmanrc"
tree=$(migrate gradle-jdk-27 1.6.0 1.7.0)
diff -r "$(fixture gradle-jdk-27 before)" "$tree" >/dev/null || fail 'a bump to 1.7.0 must not run 1.8.0 migrations'

# 2.0.0: Platform w organizacji SeniorDeveloper-pl-Dominik-Sienkiewicz (2026-11-13). Scope npm w manifeście, .npmrc,
# importach, extends i CSS frontendu, referencje workflowów Platform, URL GitHub Packages w settings i stub przechodzą
# automatycznie; lockfile i node_modules zostają dla bumpu, a reszta wzmianek o koncie osobistym to notatki.
tree="$fixture_work/tree-organization-scope"
rm -rf "$tree" && mv "$(fixture organization-scope before)" "$tree"
mkdir -p "$tree/frontend/node_modules/@dominiksienkiewicz/versions"
printf '{ "name": "@dominiksienkiewicz/versions" }\n' > "$tree/frontend/node_modules/@dominiksienkiewicz/versions/package.json"
files=$(cd "$tree" && bash "$runner" files 1.10.3 2.0.0)
expected_files='.github/workflows/ci.yml
backend/settings.gradle.kts
frontend/.npmrc
frontend/eslint.config.mjs
frontend/package.json
frontend/src/app/globals.css
frontend/tsconfig.json
frontend/vitest-config.d.ts
frontend/vitest.config.ts
scripts/platform-bump.sh'
[[ "$files" == "$expected_files" ]] || fail "organization-scope: run.sh files must list exactly what it rewrites, got: $files"
(cd "$tree" && bash "$runner" apply 1.10.3 2.0.0) > "$fixture_work/organization-scope.out"
grep -qF '"@dominiksienkiewicz/versions"' "$tree/frontend/node_modules/@dominiksienkiewicz/versions/package.json" \
  || fail 'organization-scope: installed node_modules must stay for npm to replace'
rm -r "$tree/frontend/node_modules"
diff -r "$(fixture organization-scope after)" "$tree" || { cat "$fixture_work/organization-scope.out"; fail 'organization-scope: before/ must become after/'; }
grep -q 'applied  2.0.0-organization-scope' "$fixture_work/organization-scope.out" \
  || { cat "$fixture_work/organization-scope.out"; fail 'organization-scope: the runner must report it applied'; }
(cd "$tree" && bash "$runner" apply 1.10.3 2.0.0) > "$fixture_work/organization-scope.again"
diff -r "$(fixture organization-scope after)" "$tree" || fail 'organization-scope: a second run must change nothing'
if grep -q 'applied  .*organization-scope' "$fixture_work/organization-scope.again"; then
  cat "$fixture_work/organization-scope.again"; fail 'organization-scope: a second run must not apply it again'
fi
for expected in \
  ".github/workflows/ci.yml:14: still names the personal account: images: '[\"ghcr.io/dominiksienkiewicz/app-backend:latest\"]'" \
  '.github/workflows/ci.yml:19: still names the personal account: infra-repository: DominikSienkiewicz/Infrastructure' \
  'frontend/README.md:3: still names the personal account: Shared configuration comes from the `@dominiksienkiewicz/*` presets.'; do
  grep -qF -- "$expected" "$fixture_work/organization-scope.out" \
    || { cat "$fixture_work/organization-scope.out"; fail "organization-scope: missing note: $expected"; }
  grep -qF -- "$expected" "$fixture_work/organization-scope.again" \
    || { cat "$fixture_work/organization-scope.again"; fail "organization-scope: a second run must repeat: $expected"; }
done
if grep -qF 'package-lock.json' "$fixture_work/organization-scope.out"; then fail 'organization-scope: the lockfile is the bump''s to regenerate'; fi
tree=$(migrate organization-scope 1.10.3 1.10.4)
diff -r "$(fixture organization-scope before)" "$tree" >/dev/null || fail 'a bump below 2.0.0 must not move the scope'

# Obraz migracji = ostatni FROM szablonu, z którego biorą go konsumenci.
template_image=$(sed -n -E 's/^FROM[[:space:]]+([^[:space:]]+).*/\1/p' "$here/../../../../templates/Dockerfile.backend" | tail -1)
grep -qx "RUNTIME_IMAGE=\"$template_image\"" "$here/../migrations/1.6.0-runtime-image-27.sh" \
  || fail "runtime-image-27 must move to $template_image, the final FROM of templates/Dockerfile.backend"

# Bramka SINCE: CUR < SINCE <= TARGET; every-* przy każdym bumpie.
tree=$(migrate caller-packages-read 1.6.0 1.6.1)
diff -r "$(fixture caller-packages-read before)" "$tree" >/dev/null || fail 'a bump from 1.6.0 must not run 1.6.0 migrations'
tree=$(migrate caller-packages-read 1.5.26 1.5.31)
diff -r "$(fixture caller-packages-read before)" "$tree" >/dev/null || fail 'a bump to 1.5.31 must not run 1.6.0 migrations'
tree=$(migrate drop-stale-overrides 1.6.0 1.6.1)
diff -r "$(fixture drop-stale-overrides after)" "$tree" || fail 'every-* migrations run on every bump'
files=$(cd "$(fixture runtime-image-27 before)" && bash "$runner" files 1.5.26 1.6.0)
[[ "$files" == $'Dockerfile\nbackend/Dockerfile' ]] || fail "run.sh files must list what the migrations may change, got: $files"

# Pełny bump w kształcie Attestate (1.5.26): referencje, packages: read i obraz runtime w jednym przebiegu.
attestate() {
  mkdir -p "$1/backend"
  printf 'FROM eclipse-temurin:26-jre\nCOPY app.jar app.jar\n' > "$1/backend/Dockerfile"
  printf 'permissions:\n  contents: read\njobs:\n  backend:\n    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1\n' > "$1/.github/workflows/backend.yml"
}
export FAKE_MIGRATIONS="$here/../migrations" FAKE_PACKAGE="$here/.."
dir=$(FIXTURE_EXTRA=attestate consumer attestate 1.5.26)
bump "$dir" --dry-run 1.6.0
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail 'the dry run of the Attestate bump must succeed'; }
grep -qF '+FROM sapmachine:27-jre' "$dir.log" || { cat "$dir.log"; fail 'the dry run must show the migrated Dockerfile'; }
[[ -z "$(git -C "$dir" status --porcelain)" ]] || fail 'the dry run must restore what the migrations changed'
bump "$dir" 1.6.0
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail 'the Attestate bump must succeed'; }
grep -qx 'FROM sapmachine:27-jre' "$dir/backend/Dockerfile" || fail 'the runtime image must move'
grep -qx '  packages: read' "$dir/.github/workflows/backend.yml" || fail 'the backend-ci caller must get packages: read'
grep -qF 'backend-ci.yml@v1.6.0' "$dir/.github/workflows/backend.yml" || fail 'the workflow ref must move to the exact target'
grep -qF 'applied  1.6.0-caller-packages-read' "$dir.log" || { cat "$dir.log"; fail 'the bump must list the applied migrations'; }
grep -qF "==> Callers of Platform's reusable workflows against the contract of v1.6.0:" "$dir.log" \
  || { cat "$dir.log"; fail 'the bump must check the callers against the target contract'; }
if grep -q '^ERROR ' "$dir.log"; then cat "$dir.log"; fail 'after the migrations the callers must meet the contract'; fi

# Pełny bump przez przeniesienie do organizacji: frontend bez backendu na 1.10.3, pod starym scope, ownerem i stubem.
# Bin wydania docelowego czyta stary pin jako obecny, podbija go do celu, a migracja przenosi scope, workflowy i stub.
personal_account() {
  printf '{\n  "devDependencies": {\n    "@dominiksienkiewicz/eslint-config": "1.10.3",\n    "@dominiksienkiewicz/versions": "1.10.3",\n    "react": "19.0.0"\n  }\n}\n' \
    > "$1/frontend/package.json"
  printf '@dominiksienkiewicz:registry=https://npm.pkg.github.com\n' > "$1/frontend/.npmrc"
  mkdir -p "$1/scripts"
  cp "$here/migrations/organization-scope/before/scripts/platform-bump.sh" "$1/scripts/platform-bump.sh"
}
dir=$(FIXTURE_EXTRA=personal_account consumer personal-account 1.10.3)
bump "$dir" 2.0.0
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail 'the bump across the organization move must succeed'; }
grep -qF 'Upgrade migrations from 1.10.3 to 2.0.0:' "$dir.log" || { cat "$dir.log"; fail 'a pin under the old scope must count as the current pin'; }
grep -qF 'applied  2.0.0-organization-scope' "$dir.log" || { cat "$dir.log"; fail 'the bump must apply the organization migration'; }
for pin in versions eslint-config; do
  grep -qF "\"@seniordeveloper-pl-dominik-sienkiewicz/$pin\": \"2.0.0\"" "$dir/frontend/package.json" \
    || { cat "$dir/frontend/package.json"; fail "the $pin pin must move to the organization scope at the target"; }
done
if grep -qF '@dominiksienkiewicz' "$dir/frontend/package.json" "$dir/frontend/.npmrc"; then fail 'no old scope may stay in the manifest or .npmrc'; fi
grep -qx '    uses: SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/.github/workflows/frontend-ci.yml@v2.0.0' "$dir/.github/workflows/ci.yml" \
  || { cat "$dir/.github/workflows/ci.yml"; fail 'the caller must name the organization at the exact target'; }
grep -qx 'OWNER="SeniorDeveloper-pl-Dominik-Sienkiewicz"' "$dir/scripts/platform-bump.sh" || fail 'the stub must point at the organization'
# frontend/.npmrc zna jeszcze tylko stary scope, gdy bin pobiera kanon celu: rejestr nowego scope idzie w poleceniu.
grep -F 'npm pack @seniordeveloper-pl-dominik-sienkiewicz/versions@2.0.0' "$FAKE_NPM_LOG" \
  | grep -qF -- '--@seniordeveloper-pl-dominik-sienkiewicz:registry=https://npm.pkg.github.com' \
  || { cat "$FAKE_NPM_LOG"; fail 'npm pack of the target canon must name the registry of the organization scope'; }

echo 'OK: upgrade migrations turn before/ into after/, are idempotent, honour SINCE and run from the target release'
