#!/usr/bin/env bash
# Strona dokumentacji per MINOR (N-SHOW-16): scripts/docs-versions.py na repo-fixturze z tagami v1.5.31 (bez narzędzia
# strony), v1.6.0, v1.6.1 i v1.7.0, ruchomym v1 i tagiem rc, ze stubem zensical, który tylko zapisuje, co buduje.
# Sprawdza, które wersje powstają (1.6 z v1.6.1, 1.7 z v1.7.0, unreleased z main, nic starszego), układ /<X.Y>/
# i /unreleased/, przekierowanie roota (także na unreleased, zanim cokolwiek wydano z narzędziem), versions.json
# w formacie mike, site_url i przełącznik każdej wersji oraz to, że każdą wersję przygotowuje docs-site.py z jej
# własnego refu. Nieudany build jednej wersji nie zostawia strony. Prawdziwy build Zensical biegnie w docs-site.yml.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.test
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.test

mkdir "$tmp/bin"
cat > "$tmp/bin/zensical" <<'PY'
#!/usr/bin/env python3
import os, shutil, sys, tomllib
if sys.argv[1:] != ["build", "--strict"]:
    sys.exit(f"stub zensical: expected 'build --strict', got {sys.argv[1:]}")
with open("docs/index.md", encoding="utf-8") as handle:
    index = handle.read()
if "BROKEN" in index:
    sys.exit("stub zensical: a broken anchor fails the strict build")
with open("zensical.toml", "rb") as handle:
    project = tomllib.load(handle)["project"]
site = project["site_dir"]
os.makedirs(site)
for name, text in {"index.html": index, "site_url": project["site_url"],
                   "provider": project.get("extra", {}).get("version", {}).get("provider", "none")}.items():
    with open(os.path.join(site, name), "w", encoding="utf-8") as handle:
        handle.write(text)
shutil.copy("staged-by", os.path.join(site, "staged-by"))
with open(os.environ["ZENSICAL_LOG"], "a", encoding="utf-8") as log:
    log.write(project["site_url"] + "\n")
PY
chmod +x "$tmp/bin/zensical"

repo="$tmp/repo"
git init -q -b main "$repo"
docs() {
  mkdir -p "$repo/docs"
  printf '# Docs of %s\n\n[Releasing](../RELEASING.md)\n' "$1" > "$repo/docs/index.md"
}
# tooling <etykieta> [selector]: docs-site.py tej wersji (z markerem, kto przygotował stronę) i jej zensical.toml.
tooling() {
  mkdir -p "$repo/scripts"
  { cat "$root/scripts/docs-site.py"
    printf '\nwith open(os.path.join(out, "staged-by"), "w") as marker:\n    marker.write("%s")\n' "$1"
  } > "$repo/scripts/docs-site.py"
  printf '[project]\nsite_name = "Fixture"\nsite_url = "https://example.test/Platform/"\ndocs_dir = "docs"\nsite_dir = "site"\n' \
    > "$repo/zensical.toml"
  if [[ "${2:-}" == selector ]]; then printf '\n[project.extra.version]\nprovider = "mike"\n' >> "$repo/zensical.toml"; fi
}
commit() { git -C "$repo" add -A && git -C "$repo" commit -q -m "$1"; }
release() { git -C "$repo" tag -a -m "Platform ${1#v}" "$1"; }
assemble() {
  local out=$1
  shift
  PATH="$tmp/bin:$PATH" ZENSICAL_LOG="$tmp/${out##*/}.log" python3 -I "$root/scripts/docs-versions.py" --repo "$repo" "$@" "$out"
}
first_line() { head -1 "$1"; }
entries() { (cd "$1" && printf '%s\n' * | paste -sd' ' -); }
versions_json() { python3 -I -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$1"; }

docs 1.5.31
commit 'docs before the site tooling'
release v1.5.31
if assemble "$tmp/none" > /dev/null 2>&1; then fail 'main without zensical.toml and docs-site.py must be refused'; fi

tooling main
docs 'main before 1.6.0'
commit 'the site tooling'
assemble "$tmp/first" > /dev/null
[[ "$(entries "$tmp/first")" == 'index.html unreleased versions.json' ]] \
  || fail "before any release with the tooling only /unreleased/ exists, got: $(entries "$tmp/first")"
grep -qF 'content="0; url=unreleased/"' "$tmp/first/index.html" || fail 'the root redirects to unreleased while nothing is released'
[[ "$(versions_json "$tmp/first/versions.json")" == '[{"aliases": [], "title": "unreleased (main)", "version": "unreleased"}]' ]] \
  || fail "versions.json before a release: $(cat "$tmp/first/versions.json")"

docs 1.6.0; tooling v1.6.0; commit 'release 1.6.0'; release v1.6.0
docs 1.6.1; tooling v1.6.1; commit 'release 1.6.1'; release v1.6.1
docs 1.7.0; tooling v1.7.0 selector; commit 'release 1.7.0'; release v1.7.0
git -C "$repo" tag v1
docs 1.8.0-rc.1; commit 'release candidate'; release v1.8.0-rc.1
docs main; tooling main selector; commit 'unreleased work'
main_sha=$(git -C "$repo" rev-parse main)

assemble "$tmp/site" > /dev/null
site="$tmp/site"
[[ "$(entries "$site")" == '1.6 1.7 index.html unreleased versions.json' ]] \
  || fail "one version per MINOR with the tooling plus unreleased, got: $(entries "$site")"
[[ "$(first_line "$site/1.6/index.html")" == '# Docs of 1.6.1' ]] || fail '/1.6/ is built from the newest patch, v1.6.1'
[[ "$(first_line "$site/1.7/index.html")" == '# Docs of 1.7.0' ]] || fail '/1.7/ is built from v1.7.0, not from the rc tag'
[[ "$(first_line "$site/unreleased/index.html")" == '# Docs of main' ]] || fail '/unreleased/ is built from main'
for version in 1.6:v1.6.1 1.7:v1.7.0 unreleased:main; do
  [[ "$(cat "$site/${version%%:*}/staged-by")" == "${version#*:}" ]] \
    || fail "/${version%%:*}/ must be staged by the docs-site.py of ${version#*:}"
  [[ "$(cat "$site/${version%%:*}/site_url")" == "https://example.test/Platform/${version%%:*}/" ]] \
    || fail "/${version%%:*}/ needs its own subpath as site_url, got $(cat "$site/${version%%:*}/site_url")"
  [[ "$(cat "$site/${version%%:*}/provider")" == mike ]] || fail "/${version%%:*}/ needs the mike version selector"
done
grep -qF "](https://github.com/DominikSienkiewicz/Platform/blob/v1.6.1/RELEASING.md)" "$site/1.6/index.html" \
  || fail 'a released version links out of docs/ at its own tag'
grep -qF "](https://github.com/DominikSienkiewicz/Platform/blob/$main_sha/RELEASING.md)" "$site/unreleased/index.html" \
  || fail 'the unreleased channel links out of docs/ at the commit of main'
[[ "$(sort "$tmp/site.log" | paste -sd' ' -)" == 'https://example.test/Platform/1.6/ https://example.test/Platform/1.7/ https://example.test/Platform/unreleased/' ]] \
  || fail "exactly three builds, nothing older than 1.6: $(paste -sd' ' - < "$tmp/site.log")"
expected='[{"aliases": [], "title": "unreleased (main)", "version": "unreleased"}, {"aliases": [], "title": "1.7 (latest)", "version": "1.7"}, {"aliases": [], "title": "1.6", "version": "1.6"}]'
[[ "$(versions_json "$site/versions.json")" == "$expected" ]] || fail "versions.json in the mike format: $(cat "$site/versions.json")"
grep -qF 'content="0; url=1.7/"' "$site/index.html" || fail 'the root redirects to the newest released MINOR'
grep -qF 'location.replace("1.7/" + location.hash)' "$site/index.html" || fail 'the root redirect keeps the anchor'
grep -qF '<link rel="canonical" href="https://example.test/Platform/1.7/">' "$site/index.html" || fail 'the redirect names its canonical URL'

git -C "$repo" switch -q -c broken
printf '\nBROKEN\n' >> "$repo/docs/index.md"
commit 'a broken anchor'
git -C "$repo" switch -q main
if assemble "$tmp/broken" --unreleased broken > /dev/null 2>&1; then fail 'a version that fails the strict build fails the assembly'; fi
[[ ! -e "$tmp/broken" ]] || fail 'a failed assembly leaves no half-built site behind'

mkdir "$tmp/used"
touch "$tmp/used/keep"
if assemble "$tmp/used" > /dev/null 2>&1; then fail 'an output directory that is not empty must be refused'; fi
[[ -f "$tmp/used/keep" ]] || fail 'a refused output directory stays untouched'
echo 'OK: docs-versions builds the newest patch of every MINOR with the site tooling plus unreleased, with versions.json and a root redirect'
