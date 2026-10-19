#!/usr/bin/env bash
# release.yml atestuje dokładnie to, co publikuje: job npm pakuje (bez paczek private i już wydanych),
# atestuje tarballe i publikuje te same pliki; job gradle atestuje pliki po publikacji. Oba mają
# uprawnienia id-token i attestations.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/release.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

block() { awk -v name="$1" '$0 ~ "# >>> " name "$" {p=1;next} $0 ~ "# <<< " name "$" {p=0} p {sub(/^          /,""); print}' "$workflow"; }
block npm-pack > "$tmp/pack.sh"
block npm-publish > "$tmp/publish.sh"
[[ -s "$tmp/pack.sh" && -s "$tmp/publish.sh" ]] || fail 'the npm-pack and npm-publish blocks are missing'

mkdir -p "$tmp/bin" "$tmp/frontend/packages"/{alpha,secret,released}
printf '{ "name": "@x/alpha" }\n' > "$tmp/frontend/packages/alpha/package.json"
printf '{ "name": "@x/secret", "private": true }\n' > "$tmp/frontend/packages/secret/package.json"
printf '{ "name": "@x/released" }\n' > "$tmp/frontend/packages/released/package.json"
cat > "$tmp/bin/npm" <<'STUB'
#!/usr/bin/env bash
echo "npm $*" >> "$STUB_LOG"
case "$1" in
  view) [[ "$2" == "@x/released@"* ]] ;;
  publish)
    case "$2" in
      *conflict*) echo "npm error code E409"; exit 1 ;;
      *broken*) echo "npm error code E500"; exit 1 ;;
    esac ;;
esac
STUB
cat > "$tmp/bin/pnpm" <<'STUB'
#!/usr/bin/env bash
echo "pnpm $* in $(basename "$PWD")" >> "$STUB_LOG"
[[ "$1" == pack && "$2" == --pack-destination ]] && : > "$3/x-$(basename "$PWD")-$V.tgz"
STUB
chmod +x "$tmp/bin/npm" "$tmp/bin/pnpm"
export STUB_LOG="$tmp/stub.log" V=9.9.9 PATH="$tmp/bin:$PATH"

(cd "$tmp/frontend" && bash "$tmp/pack.sh") > "$tmp/out.txt" 2>&1 || fail "packing must succeed: $(cat "$tmp/out.txt")"
[[ "$(ls "$tmp/frontend/dist")" == "x-alpha-9.9.9.tgz" ]] || fail "only the public unreleased package is packed: $(ls "$tmp/frontend/dist")"
grep -q 'private — pomijam' "$tmp/out.txt" || fail 'a private package must be reported as skipped'
grep -q 'released@9.9.9 już w registry' "$tmp/out.txt" || fail 'an already published package must be skipped'

(cd "$tmp/frontend" && bash "$tmp/publish.sh") > "$tmp/out.txt" 2>&1 || fail "publishing the packed tarball must succeed"
grep -qx 'npm publish dist/x-alpha-9.9.9.tgz' "$STUB_LOG" || fail 'the job must publish the attested tarball itself'

: > "$tmp/frontend/dist/x-conflict-9.9.9.tgz"
(cd "$tmp/frontend" && bash "$tmp/publish.sh") > "$tmp/out.txt" 2>&1 || fail 'a version conflict is idempotent, not a failure'
: > "$tmp/frontend/dist/x-broken-9.9.9.tgz"
if (cd "$tmp/frontend" && bash "$tmp/publish.sh") > "$tmp/out.txt" 2>&1; then fail 'another publish error must fail the job'; fi

job() { awk -v name="$1" '$0 == "  " name ":" {p=1;next} /^  [a-z0-9-]+:$/ {p=0} p' "$workflow"; }
for name in gradle npm; do
  body=$(job "$name")
  grep -qx '      id-token: write' <<<"$body" || fail "$name needs id-token: write"
  grep -qx '      attestations: write' <<<"$body" || fail "$name needs attestations: write"
  grep -q 'uses: actions/attest@[0-9a-f]\{40\} # v' <<<"$body" || fail "$name must attest with a SHA-pinned actions/attest"
done
gradle=$(job gradle)
publish=$(grep -n 'name: Publish Maven' <<<"$gradle" | cut -d: -f1)
attest=$(grep -n 'uses: actions/attest@' <<<"$gradle" | cut -d: -f1)
[[ "$attest" -gt "$publish" ]] || fail 'the gradle job attests after it publishes'
npm=$(job npm)
pack=$(grep -n 'name: Pack the packages to publish' <<<"$npm" | cut -d: -f1)
attest=$(grep -n 'uses: actions/attest@' <<<"$npm" | cut -d: -f1)
publish=$(grep -n 'name: Publish (idempotentny)' <<<"$npm" | cut -d: -f1)
[[ "$pack" -lt "$attest" && "$attest" -lt "$publish" ]] || fail 'the npm job packs, attests, then publishes'

echo 'OK: release.yml attests the files it publishes and publishes the attested npm tarballs'
