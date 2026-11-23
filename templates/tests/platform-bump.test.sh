#!/usr/bin/env bash
# templates/platform-bump.sh, przypadek po przypadku: stub deleguje do zainstalowanego binu @dominiksienkiewicz/versions,
# a w repozytorium bez frontendu bierze bin z assetów GitHub Release po sprawdzeniu SHA256SUMS.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

# --- stub-delegates-to-bin ---
# Test template'u platform-bump.sh (kanon: Platform/templates/platform-bump.sh).
#
# Po migracji na model stub+bin: templates/platform-bump.sh to CIENKI STUB, który deleguje
# do binu `platform-bump` pakietu @dominiksienkiewicz/versions (frontend/node_modules/.bin).
# Logika bumpu (Maven catalog + gradle.lockfile + npm) żyje w binie — tu testujemy WYŁĄCZNIE
# kontrakt stuba. Hermetyczny (bez npm/sieci): fake-bin nagrywa argumenty.
#
# Regresja (zachowana z poprzedniej wersji): wywołany SPOZA roota repo skrypt musi operować na
# repo, w którym LEŻY, a nie w CWD wywołania. Stub mieszka w `<repo>/scripts/`, więc dochodzi
# do roota przez `cd "$(dirname "$0")/.."` — ten test pilnuje właśnie tego przeskoku o katalog.
(
CANON="$(cd "$(dirname "$0")/.." && pwd)/platform-bump.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- 1) Brak binu -> exit != 0 + komunikat wskazujący brakujący bin ---
REPO1="$WORK/no-bin"
mkdir -p "$REPO1/scripts"
cp "$CANON" "$REPO1/scripts/platform-bump.sh"; chmod +x "$REPO1/scripts/platform-bump.sh"
rc=0
out="$( ( cd "$WORK" && "$REPO1/scripts/platform-bump.sh" 1.2.3 ) 2>&1 )" || rc=$?
[[ $rc -ne 0 ]] \
  || { echo "FAIL: brak binu powinien dać exit != 0"; exit 1; }
grep -q 'node_modules/.bin/platform-bump' <<<"$out" \
  || { echo "FAIL: komunikat nie wskazuje brakującego binu"; exit 1; }

# --- 2) Bin obecny -> delegacja + passthrough argumentu + exit 0 (wywołany spoza roota) ---
# Fake-bin zapisuje argumenty do bump-args.txt względem CWD; stub cd-uje do swojego roota PRZED exec,
# więc plik ląduje w REPO2 — to zarazem dowód regresji "operuj na repo skryptu".
REPO2="$WORK/with-bin"
mkdir -p "$REPO2/frontend/node_modules/.bin"
BIN="$REPO2/frontend/node_modules/.bin/platform-bump"
cat > "$BIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > bump-args.txt
exit 0
EOF
chmod +x "$BIN"
mkdir -p "$REPO2/scripts"
cp "$CANON" "$REPO2/scripts/platform-bump.sh"; chmod +x "$REPO2/scripts/platform-bump.sh"
rc=0
( cd "$WORK" && "$REPO2/scripts/platform-bump.sh" 9.9.9 ) >/dev/null 2>&1 || rc=$?
[[ $rc -eq 0 ]] \
  || { echo "FAIL: obecny bin -> oczekiwano exit 0, było $rc"; exit 1; }
grep -qx '9.9.9' "$REPO2/bump-args.txt" \
  || { echo "FAIL: argument nie przekazany do binu lub stub nie cd-nął do roota repo"; exit 1; }

echo "OK: stub deleguje do binu, przekazuje argumenty i failuje czytelnie bez binu"
)

# --- bin-from-release-assets ---
# Stub platform-bump.sh w repo bez frontendu (N-DX-4): bin przychodzi z assetów GitHub Release (tu file://), po
# sprawdzeniu sumy z SHA256SUMS, i dostaje argumenty bez zmian; bez wersji stub bierze najnowsze wydanie, a zła
# suma zatrzymuje go, zanim cokolwiek uruchomi. Repo z zainstalowanym binem pilnuje platform-bump.test.sh.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "$OUT" >&2; exit 1; }
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{ print $1 }'; }

# release <version>: asset paczki versions, której bin zapisuje swoje argumenty i własną ścieżkę.
release() {
  local version=$1 staging="$tmp/staging-$1"
  mkdir -p "$staging/package/bin" "$tmp/releases/v$version"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0" "$@" > "$BUMP_CALL"\n' > "$staging/package/bin/platform-bump.sh"
  printf '{ "name": "@dominiksienkiewicz/versions", "version": "%s" }\n' "$version" > "$staging/package/package.json"
  tar -czf "$tmp/releases/v$version/dominiksienkiewicz-versions-$version.tgz" -C "$staging" package
  (cd "$tmp/releases/v$version" && printf '%s  %s\n' "$(sha "dominiksienkiewicz-versions-$version.tgz")" "dominiksienkiewicz-versions-$version.tgz" > SHA256SUMS)
}
release 1.6.0
release 1.7.0
printf '{ "tag_name": "v1.7.0" }\n' > "$tmp/latest.json"

repo="$tmp/jvm-only"
mkdir -p "$repo/scripts" "$repo/backend"
cp "$root/templates/platform-bump.sh" "$repo/scripts/platform-bump.sh"
printf 'platformVersion=1.5.31\n' > "$repo/backend/gradle.properties"
run() {
  OUT=$(cd "$tmp" && BUMP_CALL="$tmp/call" PLATFORM_RELEASES_URL="file://$tmp/releases" PLATFORM_RELEASES_API="file://$tmp/latest.json" \
    PLATFORM_CLI_CACHE="$tmp/cache" bash "$repo/scripts/platform-bump.sh" "$@" 2>&1)
}

run 1.6.0 --dry-run || fail 'a JVM-only repo must bump through the release assets'
[[ "$(sed -n 1p "$tmp/call")" == "$tmp/cache/1.6.0/package/bin/platform-bump.sh" ]] || fail 'the bin of the requested release must run'
[[ "$(sed -n '2,$p' "$tmp/call" | paste -sd' ' -)" == "1.6.0 --dry-run" ]] || fail 'the arguments must reach the bin unchanged'
grep -qF 'Running the platform-bump of Platform 1.6.0 from its release assets' <<<"$OUT" || fail 'the stub must say where the bin comes from'

rm -f "$tmp/call"
run --dry-run || fail 'without a version the stub takes the latest release'
[[ "$(sed -n 1p "$tmp/call")" == "$tmp/cache/1.7.0/package/bin/platform-bump.sh" ]] || fail 'the latest release must run without a version'

release 1.8.0
printf '0000  dominiksienkiewicz-versions-1.8.0.tgz\n' > "$tmp/releases/v1.8.0/SHA256SUMS"
rm -f "$tmp/call"
if run 1.8.0; then fail 'a checksum mismatch must stop the stub'; fi
grep -qF 'does not match its SHA256SUMS' <<<"$OUT" || fail 'the mismatch must be named'
[[ ! -e "$tmp/call" ]] || fail 'nothing may run after a mismatch'
# Zainstalowany CLI 1.x ufa poprzedniemu sygnatariuszowi i nie potrafi sam pobrać narzędzia 2.x.
release 2.0.0
asset=seniordeveloper-pl-dominik-sienkiewicz-versions-2.0.0.tgz
mv "$tmp/releases/v2.0.0/dominiksienkiewicz-versions-2.0.0.tgz" "$tmp/releases/v2.0.0/$asset"
(cd "$tmp/releases/v2.0.0" && printf '%s  %s\n' "$(sha "$asset")" "$asset" > SHA256SUMS)
mkdir -p "$tmp/bin" "$repo/frontend/node_modules/@dominiksienkiewicz/versions" "$repo/frontend/node_modules/.bin"
printf '#!/usr/bin/env bash\nexit 99\n' > "$repo/frontend/node_modules/.bin/platform-bump"
printf '{}\n' > "$repo/frontend/node_modules/@dominiksienkiewicz/versions/package.json"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$STUB_GH_LOG"\n[[ ${REJECT:-0} == 0 ]]\n' > "$tmp/bin/gh"
chmod +x "$tmp/bin/gh" "$repo/frontend/node_modules/.bin/platform-bump"
export STUB_GH_LOG="$tmp/gh.log"
mkdir -p "$tmp/cache/2.0.0/package/bin"
printf '#!/usr/bin/env bash\necho cached > "$BUMP_CALL"\n' > "$tmp/cache/2.0.0/package/bin/platform-bump.sh"
if REJECT=1 PATH="$tmp/bin:$PATH" run 2.0.0 --dry-run; then fail 'a forged v2 release must be refused'; fi
[[ ! -e "$tmp/call" ]] || fail 'a rejected release must not execute'
PATH="$tmp/bin:$PATH" run 2.0.0 --dry-run || fail 'the v2 stub must bootstrap even if the installed frontend bin is from v1'
grep -qF -- '--signer-workflow SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/.github/workflows/release.yml' "$STUB_GH_LOG" || fail 'the v2 bootstrap must verify the new signer'
grep -qF /2.0.0/package/bin/platform-bump.sh "$tmp/call" || fail 'the verified 2.0.0 CLI must run'
echo 'OK: a JVM-only repo bumps with the bin of the release assets, checked against SHA256SUMS'
)
