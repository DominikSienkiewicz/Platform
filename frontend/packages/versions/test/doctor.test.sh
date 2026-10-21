#!/usr/bin/env bash
# platform-doctor na atrapach java/curl/npm: repo z rozjechanymi pinami, @v1, starym obrazem, brakiem lockfile'a,
# nieignorowanym .secrets.local i odrzuconym tokenem (401) — każdy FAIL z ID i naprawą; drugie repo przechodzi.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" >&2; exit 1; }
: > "$tmp/out"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/java" <<'STUB'
#!/usr/bin/env bash
echo "openjdk version \"${FAKE_JAVA:-27.0.1}\" 2026-10-14" >&2
STUB
cat > "$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo called >> "$FAKE_CURL_LOG"
printf '%s' "${FAKE_CODE:-200}"
STUB
cat > "$tmp/bin/npm" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == view ]] && exit "${FAKE_NPM:-0}"
exit 0
STUB
chmod +x "$tmp/bin/java" "$tmp/bin/curl" "$tmp/bin/npm"
export FAKE_CURL_LOG="$tmp/curl.log"

repo() {
  local dir="$tmp/$1"
  mkdir -p "$dir/backend" "$dir/frontend" "$dir/.github/workflows"
  git -C "$dir" init -q
  printf 'plugins { id("seniordev.settings-conventions") version "1.6.0" }\nfrom("pl.seniordeveloper:platform-catalog:1.6.0")\n' > "$dir/backend/settings.gradle.kts"
  printf '#!/usr/bin/env bash\n' > "$dir/backend/gradlew" && chmod +x "$dir/backend/gradlew"
  printf '@dominiksienkiewicz:registry=https://npm.pkg.github.com\n' > "$dir/frontend/.npmrc"
  printf 'FROM sapmachine:27-jre\n' > "$dir/backend/Dockerfile"
  printf '{ "devDependencies": { "@dominiksienkiewicz/versions": "1.6.0", "@dominiksienkiewicz/eslint-config": "1.6.0" } }\n' > "$dir/frontend/package.json"
  echo '{}' > "$dir/frontend/package-lock.json"
  printf 'jobs:\n  ci:\n    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.6.0\n' > "$dir/.github/workflows/ci.yml"
  printf '%s\n' "$dir"
}
doctor() { (cd "$1" && PATH="$tmp/bin:$PATH" GPR_TOKEN=s3cr3t-value bash "$here/../bin/platform-doctor.sh" "${@:2}") > "$tmp/out" 2>&1; }

good=$(repo good)
doctor "$good" || fail 'a coherent repository must pass'
grep -qF 'PASS PD020 every Platform pin is 1.6.0 (4 pins)' "$tmp/out" || fail 'the pins must be counted'
grep -qF 'PASS PD030 credentials come from GPR_TOKEN' "$tmp/out" || fail 'the credential source must be named'
grep -qF 'PASS PD031 the catalog 1.6.0 resolves from GitHub Packages' "$tmp/out" || fail 'the catalog must be checked'
if grep -qF 's3cr3t-value' "$tmp/out"; then fail 'the token value must never be printed'; fi

bad=$(repo bad)
printf '{ "devDependencies": { "@dominiksienkiewicz/versions": "1.5.30", "@dominiksienkiewicz/eslint-config": "1.6.0" } }\n' > "$bad/frontend/package.json"
rm "$bad/frontend/package-lock.json"
printf 'FROM eclipse-temurin:26-jre\n' > "$bad/backend/Dockerfile"
printf 'jobs:\n  ci:\n    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1\n' > "$bad/.github/workflows/ci.yml"
touch "$bad/.secrets.local"
if FAKE_CODE=401 FAKE_JAVA=25.0.3 doctor "$bad"; then fail 'a broken repository must fail'; fi
for expected in \
  'FAIL PD020 the Platform pins disagree' \
  'WARN PD021 reusable workflow references: v1 (1)' \
  "FAIL PD010 java on PATH is 25; Platform's plugins are compiled for 27" \
  'FAIL PD031 GitHub Packages rejected the credentials from GPR_TOKEN (401)' \
  'fix: use a classic PAT, not a fine-grained one, and check that it has not expired' \
  'FAIL PD060 backend/Dockerfile runs eclipse-temurin:26-jre, older than the Java 27 toolchain of 1.6.0' \
  'FAIL PD050 .secrets.local is not ignored' \
  'FAIL PD042 frontend/package-lock.json is missing'; do
  grep -qF -- "$expected" "$tmp/out" || fail "missing line: $expected"
done
grep -qE '^[0-9]+ check\(s\) failed' "$tmp/out" || fail 'the summary must count the failures'

: > "$FAKE_CURL_LOG"
doctor "$good" --offline || fail '--offline must still pass a good repository'
[[ ! -s "$FAKE_CURL_LOG" ]] || fail '--offline must not call GitHub Packages'

for id in $(grep -oE 'PD[0-9]{3}' "$here/../bin/platform-doctor.sh" | sort -u); do
  grep -qE "^\| $id \|" "$here/../../../../docs/consuming.md" || fail "check $id has no row in docs/consuming.md (Troubleshooting)"
done

echo 'OK: platform-doctor names each broken precondition with its ID and fix'
