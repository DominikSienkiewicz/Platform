#!/usr/bin/env bash
# consumer-audit.sh na fiksturach, bez sieci: parsowanie (--from) i pobieranie przez atrapę `gh`, która
# serwuje te same pliki i loguje każde wywołanie — audyt wysyła wyłącznie GET i pobiera tylko pliki, które czyta.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

repos="$work/repos"
put() { mkdir -p "$(dirname "$repos/$1")"; cat > "$repos/$1"; }

put acme/alpha/backend/settings.gradle.kts <<'EOF'
plugins {
    id("seniordev.settings-conventions") version "1.5.26"
}
EOF
put acme/alpha/backend/build.gradle.kts <<'EOF'
dependencies {
    implementation(libs.bundles.modulith.web)
    testImplementation(libs.bundles.modulith.web.tests)
    testImplementation(libs.platform.test.fixtures)
}
EOF
put acme/alpha/backend/gradle/wrapper/gradle-wrapper.properties <<'EOF'
distributionUrl=https\://services.gradle.org/distributions/gradle-9.6.1-bin.zip
EOF
put acme/alpha/backend/Dockerfile <<'EOF'
FROM curlimages/curl:8.21.0 AS model
FROM sapmachine:27-jre
EOF
put acme/alpha/frontend/Dockerfile <<'EOF'
FROM node:24-alpine
EOF
put acme/alpha/frontend/package.json <<'EOF'
{ "dependencies": { "next": "16.4.0" },
  "devDependencies": { "@dominiksienkiewicz/versions": "1.5.26", "@dominiksienkiewicz/eslint-config": "1.5.26" } }
EOF
put acme/alpha/.github/workflows/ci.yml <<'EOF'
jobs:
  backend:
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1
  frontend:
    uses: "DominikSienkiewicz/Platform/.github/workflows/frontend-ci.yml@v1" # comment
EOF
put acme/alpha/README.md <<'EOF'
not read by the audit
EOF
printf 'main\nrenovate/actions\nrenovate/docker\n' | put acme/alpha/branches.txt

put acme/beta/backend/settings.gradle.kts <<'EOF'
plugins {
    id("seniordev.settings-conventions") version providers.gradleProperty("platformVersion").get()
}
EOF
put acme/beta/backend/gradle.properties <<'EOF'
platformVersion=1.5.31
EOF
put acme/beta/backend/app/build.gradle.kts <<'EOF'
dependencies { implementation(libs.platform.security.starter) }
EOF
put acme/beta/backend/gradle/wrapper/gradle-wrapper.properties <<'EOF'
distributionUrl=https\://services.gradle.org/distributions/gradle-9.8.1-bin.zip
EOF
put acme/beta/backend/app/Dockerfile <<'EOF'
FROM --platform=linux/amd64 eclipse-temurin:27-jre AS runtime
EOF
put acme/beta/.github/workflows/ci.yml <<'EOF'
jobs:
  backend:
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.5.31
EOF
put acme/beta/.github/workflows/bump.yml <<'EOF'
jobs:
  bump:
    uses: DominikSienkiewicz/Platform/.github/workflows/platform-bump.yml@v1.5.31
EOF
printf 'main\n' | put acme/beta/branches.txt

printf '# fixtures\nacme/alpha\n\nacme/beta\n' > "$work/consumers.txt"

expected=$(cat <<'EOF'
| Repository | Platform pin | Gradle wrapper | Runtime image | test-fixtures | security-starter | Catalog bundles | npm packages | Workflow refs | platform-bump.yml | Renovate branches |
|---|---|---|---|---|---|---|---|---|---|---|
| acme/alpha | 1.5.26 | 9.6.1 | `sapmachine:27-jre` | yes | no | modulith.web, modulith.web.tests | 1.5.26: eslint-config, versions | v1 | no | 2 |
| acme/beta | 1.5.31 | 9.8.1 | `eclipse-temurin:27-jre` | no | yes | — | no frontend | v1.5.31 | yes | 0 |
EOF
)

offline=$(CONSUMERS_FILE="$work/consumers.txt" bash "$root/scripts/consumer-audit.sh" --from "$repos")
[[ "$offline" == "$expected" ]] || fail "offline matrix differs:
$offline"

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_LOG"
for arg in "$@"; do case $arg in repos/*) target=$arg ;; esac; done
rest=${target#repos/}
repo=${rest%%/*}/$(echo "$rest" | cut -d/ -f2)
dir="$FIXTURES/$repo"
case $rest in
  */git/trees/HEAD\?recursive=1) (cd "$dir" && find . -type f ! -name branches.txt | sed 's|^\./||') ;;
  */contents/*) cat "$dir/${rest#*/contents/}" ;;
  */branches) cat "$dir/branches.txt" ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$work/bin/gh"
log="$work/gh.log"
live=$(PATH="$work/bin:$PATH" GH_LOG="$log" FIXTURES="$repos" CONSUMERS_FILE="$work/consumers.txt" \
  bash "$root/scripts/consumer-audit.sh")
[[ "$live" == "$expected" ]] || fail "fetched matrix differs:
$live"

[[ $(grep -c . "$log") -gt 0 ]] || fail 'the live audit made no gh call'
if grep -v -- '--method GET' "$log"; then fail 'every gh call must be an explicit GET'; fi
if grep -E -- '(^| )(-f|-F|--field|--raw-field|--input)( |$)' "$log"; then fail 'a gh call sends a request body'; fi
if grep -F 'README.md' "$log"; then fail 'the audit fetched a file it does not read'; fi

printf 'acme/missing\n' > "$work/missing.txt"
missing=$(PATH="$work/bin:$PATH" GH_LOG="$log" FIXTURES="$repos" CONSUMERS_FILE="$work/missing.txt" \
  bash "$root/scripts/consumer-audit.sh")
grep -q '^| acme/missing | not readable: ' <<< "$missing" || fail "an unreadable repository must get its own row: $missing"

echo 'OK: consumer-audit prints the adoption matrix from fixtures and fetches with GET only'
