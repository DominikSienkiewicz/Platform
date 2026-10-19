#!/usr/bin/env bash
# Handoff binu platform-bump (N-DX-4): kopia wydania 1.6.0 z celem 1.7.0 oddaje sterowanie binowi 1.7.0 z assetów
# (te same argumenty, PLATFORM_BUMP_HANDOFF), zła suma zatrzymuje bump, brak assetu ostrzega i zostawia logikę tej
# kopii, a --print-target tylko wypisuje cel.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=bump-fixture.sh
source "$here/bump-fixture.sh"
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{ print $1 }'; }

# Bin jako paczka wydania 1.6.0 (z package.json obok), a curl dla file:// to prawdziwy curl.
mkdir -p "$fixture_work/package-1.6.0/bin" "$fixture_work/curl-bin"
cp "$here/../bin/platform-bump.sh" "$fixture_work/package-1.6.0/bin/platform-bump.sh"
printf '{ "name": "@dominiksienkiewicz/versions", "version": "1.6.0" }\n' > "$fixture_work/package-1.6.0/package.json"
real_curl=$(command -v curl)
cat > "$fixture_work/curl-bin/curl" <<STUB
#!/usr/bin/env bash
for argument in "\$@"; do [[ "\$argument" == file://* ]] && exec "$real_curl" "\$@"; done
exec "$fixture_work/bin/curl" "\$@"
STUB
chmod +x "$fixture_work/curl-bin/curl"

releases="$fixture_work/releases"
mkdir -p "$fixture_work/staging/package/bin" "$releases/v1.7.0"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "HANDOFF=$PLATFORM_BUMP_HANDOFF" "$@" > "$BUMP_CALL"\n' > "$fixture_work/staging/package/bin/platform-bump.sh"
printf '{ "name": "@dominiksienkiewicz/versions", "version": "1.7.0" }\n' > "$fixture_work/staging/package/package.json"
tar -czf "$releases/v1.7.0/dominiksienkiewicz-versions-1.7.0.tgz" -C "$fixture_work/staging" package
(cd "$releases/v1.7.0" && printf '%s  %s\n' "$(sha dominiksienkiewicz-versions-1.7.0.tgz)" dominiksienkiewicz-versions-1.7.0.tgz > SHA256SUMS)

repo=$(consumer handoff 1.5.31)
bump() {
  OUT=$(cd "$repo" && PATH="$fixture_work/curl-bin:$fixture_work/bin:$PATH" GPR_TOKEN=token FAKE_USER_CODE=200 FAKE_YANKED='' \
    BUMP_CALL="$fixture_work/call" PLATFORM_RELEASES_URL="file://$releases" PLATFORM_CLI_CACHE="$fixture_work/cache" \
    bash "$fixture_work/package-1.6.0/bin/platform-bump.sh" "$@" 2>&1)
}

bump --print-target 1.7.0 || fail "--print-target must succeed: $OUT"
[[ "$(tail -1 <<<"$OUT")" == 1.7.0 ]] || fail "--print-target must print the target last: $OUT"
[[ ! -e "$fixture_work/call" ]] || fail '--print-target must not hand off'

bump --dry-run 1.7.0 || fail "the handoff must succeed: $OUT"
grep -qF 'Platform 1.7.0 runs its own bump logic (this copy is 1.6.0)' <<<"$OUT" || fail "the handoff must be announced: $OUT"
[[ "$(paste -sd' ' - < "$fixture_work/call")" == "HANDOFF=1.7.0 --dry-run 1.7.0" ]] || fail 'the target bin must get the same arguments'

rm -rf "$fixture_work/cache" "$fixture_work/call"
printf '0000  dominiksienkiewicz-versions-1.7.0.tgz\n' > "$releases/v1.7.0/SHA256SUMS"
if bump --dry-run 1.7.0; then fail 'a checksum mismatch must stop the bump'; fi
grep -qF 'does not match its SHA256SUMS' <<<"$OUT" || fail "the mismatch must be named: $OUT"
[[ ! -e "$fixture_work/call" ]] || fail 'nothing may run after a mismatch'

rm -rf "$releases/v1.7.0"
bump --dry-run 1.7.0 || true
grep -qF 'the release assets of Platform 1.7.0 could not be read, so this bump runs the logic of 1.6.0' <<<"$OUT" \
  || fail "a release without assets must warn and keep this copy's logic: $OUT"
echo 'OK: platform-bump hands off to the bin of the target release, checked against its SHA256SUMS'
