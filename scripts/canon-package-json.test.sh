#!/usr/bin/env bash
# canon-package-json.mjs turns the frontend canon into the package.json canon-cve-scan.yml resolves:
# every canon entry as an exact dependency, Platform pins left out, every entry overridden to itself.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { local message="$1"; echo "FAIL: $message" >&2; exit 1; }

cat > "$tmp/versions.json" <<'JSON'
{ "_comment": "fixture", "versions": { "next": "16.4.0", "react": "19.2.8", "@dominiksienkiewicz/ui": "1.6.0" } }
JSON
node "$root/scripts/canon-package-json.mjs" "$tmp/versions.json" > "$tmp/package.json"

check() {
  local expression="$1" message="$2"
  node -e "const m = require(process.argv[1]); if (!($expression)) process.exit(1)" "$tmp/package.json" || fail "$message"
}
check 'm.private === true' 'the probe must be private'
check 'm.dependencies.next === "16.4.0" && m.dependencies.react === "19.2.8"' 'canon entries must be exact dependencies'
check '!("@dominiksienkiewicz/ui" in m.dependencies) && !("@dominiksienkiewicz/ui" in m.overrides)' 'Platform pins are not canon entries'
# shellcheck disable=SC2016 # "$next" is the literal npm override reference, not a shell expansion
check 'm.overrides.next === "$next" && m.overrides.react === "$react"' 'every canon entry must override its transitive copies'

if node "$root/scripts/canon-package-json.mjs" > /dev/null 2>&1; then fail 'a missing argument must exit non-zero'; fi

echo 'OK: canon-package-json writes exact canon dependencies with self-referencing overrides'
