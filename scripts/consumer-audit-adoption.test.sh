#!/usr/bin/env bash
# consumer-audit.sh --adoption na fiksturach, bez sieci: status z README kontra użycie u konsumentów (Maven, bundle
# katalogu, npm), warunek wygaszenia v1 i najstarszy pin jako próg sprzątania paczek.
# shellcheck disable=SC2016 # expected lines carry literal Markdown backticks
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; echo "$out" >&2; exit 1; }

cat > "$work/README.md" <<'MD'
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` | GitHub Packages (Maven) | all five |
| `gradle/security-starter/` | `pl.seniordeveloper:platform-security-starter` (*incubating*) | GitHub Packages (Maven) | none |
| `gradle/catalog/` | its bundles `modulith-web` and `dev-docker-compose` are *incubating* | GitHub Packages (Maven) | none |
| `frontend/packages/versions/` | `@acme/versions` | GitHub Packages (npm) | all |
| `frontend/packages/query/` | `@acme/query` (*incubating*) | not published | none |
MD
cat > "$work/libs.versions.toml" <<'TOML'
[versions]
x = "1"
[bundles]
modulith-web = ["a"]
dev-docker-compose = ["b"]
[plugins]
TOML
mkdir -p "$work/packages/versions" "$work/packages/query"
echo '{ "name": "@acme/versions" }' > "$work/packages/versions/package.json"
echo '{ "name": "@acme/query" }' > "$work/packages/query/package.json"

repos="$work/repos"
put() { mkdir -p "$(dirname "$repos/$1")"; cat > "$repos/$1"; }
put acme/one/backend/settings.gradle.kts <<'EOF'
plugins { id("seniordev.settings-conventions") version "1.5.30" }
EOF
put acme/one/backend/build.gradle.kts <<'EOF'
dependencies {
    implementation(libs.bundles.modulith.web)
    testImplementation(libs.platform.test.fixtures)
}
EOF
put acme/one/frontend/package.json <<'EOF'
{ "devDependencies": { "@acme/query": "1.5.30" } }
EOF
put acme/one/.github/workflows/ci.yml <<'EOF'
jobs:
  a:
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1
EOF
put acme/two/backend/gradle.properties <<'EOF'
platformVersion=1.5.26
EOF
put acme/two/backend/build.gradle.kts <<'EOF'
dependencies { testImplementation(libs.platform.test.fixtures) }
EOF
printf 'acme/one\nacme/two\n' > "$work/consumers.txt"

audit() {
  CONSUMERS_FILE="$work/consumers.txt" PLATFORM_README="$work/README.md" PLATFORM_CATALOG="$work/libs.versions.toml" \
    PLATFORM_PACKAGES="$work/packages" bash "$root/scripts/consumer-audit.sh" --adoption --from "$repos"
}
out=$(audit)
for expected in \
  '| `platform-test-fixtures` | adopted | acme/one, acme/two | ok |' \
  '| `platform-security-starter` | incubating | — | ok |' \
  '| `modulith-web` | incubating | acme/one | adopted: drop the incubating label |' \
  '| `dev-docker-compose` | incubating | — | ok |' \
  '| `@acme/versions` | adopted | — | no consumer: label it incubating |' \
  '| `@acme/query` | incubating | acme/one | adopted: drop the incubating label |' \
  '`v1` references: 1 in 1 repositories; `move-v1` retires when this reaches 0 (Decision 3).' \
  'Oldest pinned release: 1.5.26 (acme/two); keep it and every later version in GitHub Packages (C-12).'; do
  grep -qxF -- "$expected" <<<"$out" || fail "missing line: $expected"
done

rm "$repos/acme/one/.github/workflows/ci.yml"
out=$(audit)
grep -qxF '`v1` references: none, so `move-v1` can retire and `v1` can be frozen (Decision 3).' <<<"$out" || fail 'no @v1 reference means v1 can retire'

echo 'OK: consumer-audit --adoption compares declared status with real use and reports the v1 and cleanup conditions'
