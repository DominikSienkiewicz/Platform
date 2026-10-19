#!/usr/bin/env bash
# scripts/render-example.sh: platform-example to wynik generatora dla wydania, z lockfile'em frontendu (npm
# na atrapie, bez sieci) i README wskazującym wersję; błąd npm zatrzymuje render.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/bin"
cat > "$tmp/bin/npm" <<'STUB'
#!/usr/bin/env bash
echo "$PWD $*" >> "$NPM_LOG"
[[ "${FAKE_NPM:-ok}" == ok ]] || exit 1
echo '{ "lockfileVersion": 3 }' > package-lock.json
STUB
chmod +x "$tmp/bin/npm"
export PATH="$tmp/bin:$PATH" NPM_LOG="$tmp/npm.log"

bash "$root/scripts/render-example.sh" 1.6.0 "$tmp/example" > /dev/null
[[ -f "$tmp/example/frontend/package-lock.json" ]] || fail 'the example must carry the frontend lockfile'
grep -qF "$tmp/example/frontend install --package-lock-only --ignore-scripts" "$NPM_LOG" || fail 'npm must only write the lockfile, without scripts'
grep -qF 'Platform v1.6.0' "$tmp/example/README.md" || fail 'the README must name the release'
grep -qx 'platformVersion=1.6.0' "$tmp/example/backend/gradle.properties" || fail 'the backend must pin the release'
grep -qF 'backend-ci.yml@v1.6.0' "$tmp/example/.github/workflows/ci.yml" || fail 'CI must call the release tag'
grep -qx 'rootProject.name = "platform-example"' "$tmp/example/backend/settings.gradle.kts" || fail 'the backend must be named platform-example'

if FAKE_NPM=fail bash "$root/scripts/render-example.sh" 1.6.0 "$tmp/broken" > /dev/null 2>&1; then
  fail 'an npm failure must stop the render'
fi
echo 'OK: render-example renders platform-example from the generator with its frontend lockfile'
