#!/usr/bin/env bash
# Blok npm-publish z release.yml musi podawać `npm publish` jednoznaczną ścieżkę do tarballa.
# npm czyta `dist/x.tgz` jako skrót GitHub `owner/repo` i robi `git ls-remote`, a wydanie 1.6.0
# padło przez to na `Permission denied (publickey)`. Stub odrzuca każdy spec, który nie zaczyna
# się od `./` ani `/`, tak jak prawdziwy npm.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/release.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

awk '/# >>> npm-publish$/ {p=1;next} /# <<< npm-publish$/ {p=0} p {sub(/^          /,""); print}' "$workflow" > "$tmp/publish.sh"
[[ -s "$tmp/publish.sh" ]] || fail 'the npm-publish block is missing'

mkdir -p "$tmp/bin" "$tmp/frontend/dist"
: > "$tmp/frontend/dist/dominiksienkiewicz-versions-9.9.9.tgz"
cat > "$tmp/bin/npm" <<'STUB'
#!/usr/bin/env bash
echo "npm $*" >> "$STUB_LOG"
[[ "$1" == publish ]] || exit 0
case "$2" in
  ./* | /*) [[ -f "$2" ]] || { echo "npm error code ENOENT"; exit 1; } ;;
  *) echo "npm error command git --no-replace-objects ls-remote ssh://git@github.com/$2.git"
     echo "npm error git@github.com: Permission denied (publickey)."
     exit 128 ;;
esac
STUB
chmod +x "$tmp/bin/npm"
export STUB_LOG="$tmp/stub.log" PATH="$tmp/bin:$PATH"

(cd "$tmp/frontend" && bash "$tmp/publish.sh") > "$tmp/out.txt" 2>&1 \
  || fail "npm publish must get a path, not a git spec, for every tarball: $(cat "$tmp/out.txt")"
grep -q '^npm publish .*dominiksienkiewicz-versions-9.9.9.tgz$' "$STUB_LOG" || fail 'the packed tarball was not published'

echo 'OK: release.yml publishes each npm tarball by an unambiguous path'
