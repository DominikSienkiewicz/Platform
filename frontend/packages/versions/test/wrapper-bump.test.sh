#!/usr/bin/env bash
# The wrapper block of bin/platform-bump.sh moves the consumer's Gradle wrapper to the gradle version of
# the target release's catalog, with the distribution's SHA-256, and leaves it alone when it already runs
# that version or the catalog has no gradle entry (releases before 1.6.0). Cut out between its markers and
# run against stub curl and gradlew.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/bin/platform-bump.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { local message="$1"; echo "FAIL: $message"; exit 1; }

awk '
  index($0, "# platform-bump:wrapper-end") { exit }
  inside { print }
  index($0, "# platform-bump:wrapper") { inside = 1 }
' "$SRC" > "$WORK/wrapper.sh"
[[ -s "$WORK/wrapper.sh" ]] || fail "no '# platform-bump:wrapper' block in $SRC"

mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<'CURL'
#!/usr/bin/env bash
out="" url=""
while [[ $# -gt 0 ]]; do case "$1" in -o) out="$2"; shift 2 ;; -u|-H|--proto) shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
echo "$url" >> "$CURL_LOG"
case "$url" in
  *platform-catalog-*.toml) body="${CATALOG_TOML:-}" ; [[ -n "$body" ]] || exit 22 ;;
  *.sha256) body="0123abcd" ;;
  *) exit 22 ;;
esac
if [[ -n "$out" ]]; then printf '%s\n' "$body" > "$out"; else printf '%s' "$body"; fi
CURL
chmod +x "$WORK/bin/curl"

# layout <name> <wrapper version>: backend with a wrapper and a stub gradlew that records its arguments.
layout() {
  local dir="$WORK/$1"
  mkdir -p "$dir/backend/gradle/wrapper"
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-%s-bin.zip\n' "$2" > "$dir/backend/gradle/wrapper/gradle-wrapper.properties"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$dir/gradlew.log" > "$dir/backend/gradlew"
  chmod +x "$dir/backend/gradlew"
  printf '%s\n' "$dir"
}
run() {
  local dir="$1"
  : > "$WORK/curl.log"
  (cd "$dir" && PATH="$WORK/bin:$PATH" CURL_LOG="$WORK/curl.log" OWNER=DominikSienkiewicz TARGET=1.6.0 TOKEN=dummy bash "$WORK/wrapper.sh")
}

# (a) an older wrapper moves to the catalog's gradle with its checksum
dir=$(layout older 9.6.1)
CATALOG_TOML=$'[versions]\ngradle = "9.8.1"                         # mirror\njava = "27"' run "$dir"
grep -qx 'wrapper --gradle-version 9.8.1 --gradle-distribution-sha256-sum 0123abcd --no-daemon' "$dir/gradlew.log" \
  || fail "the wrapper must move to 9.8.1 with its SHA-256: $(cat "$dir/gradlew.log" 2>/dev/null)"
grep -q 'platform-catalog/1.6.0/platform-catalog-1.6.0.toml' "$WORK/curl.log" || fail 'the catalog of the target release must be read'

# (b) the wrapper already runs that version
dir=$(layout current 9.8.1)
CATALOG_TOML=$'[versions]\ngradle = "9.8.1"' run "$dir"
[[ ! -s "$dir/gradlew.log" ]] || fail 'a wrapper on the catalog version must stay'

# (c) a catalog without a gradle entry, or one that cannot be fetched
dir=$(layout old-catalog 9.6.1)
CATALOG_TOML=$'[versions]\njava = "27"' run "$dir"
[[ ! -s "$dir/gradlew.log" ]] || fail 'a catalog without gradle must leave the wrapper alone'
CATALOG_TOML="" run "$dir"
[[ ! -s "$dir/gradlew.log" ]] || fail 'an unreachable catalog must leave the wrapper alone'

echo 'OK: platform-bump moves the Gradle wrapper to the catalog version of the target release'
