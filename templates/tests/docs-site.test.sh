#!/usr/bin/env bash
# Strona dokumentacji (N-SHOW-16): każda strona nawigacji zensical.toml istnieje, scripts/docs-site.py zamienia link
# spoza docs/ na GitHub przy podanym ref i zostawia linki wewnątrz, Zensical jest przypięty z hashami, a deploy na
# Pages czeka na właściciela (PAGES_ENABLED). Sam build strict (z samotestem zepsutej kotwicy) biegnie w docs-site.yml;
# tutaj tylko wtedy, gdy zensical jest w PATH.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
while IFS= read -r page; do
  [[ -f "$root/docs/$page" ]] || fail "zensical.toml lists docs/$page, which does not exist"
done < <(grep -oE '= "[A-Za-z0-9/_.-]+\.md"' "$root/zensical.toml" | sed -E 's/= "(.*)"/\1/')

python3 -I "$root/scripts/docs-site.py" v9.9.9 "$tmp/site-src" > /dev/null
[[ -f "$tmp/site-src/zensical.toml" && -f "$tmp/site-src/docs/index.md" ]] || fail 'the site source must hold the config and the docs'
[[ ! -e "$tmp/site-src/docs/concepts" ]] || fail 'docs/concepts/ stays local and out of the site'
grep -qF '](https://github.com/DominikSienkiewicz/Platform/blob/v9.9.9/RELEASING.md' "$tmp/site-src/docs/consuming.md" \
  || fail 'a link out of docs/ must point at the file on GitHub at the ref'
grep -qF '](reference.md' "$tmp/site-src/docs/consuming.md" || fail 'a link inside docs/ stays relative'
grep -q '](\.\./' "$tmp/site-src/docs/consuming.md" && fail 'no link may leave the site source'

grep -qE '^zensical==[0-9.]+ \\$' "$root/docs/requirements-site.txt" || fail 'Zensical must be pinned'
requirements=$(grep -cE '^[A-Za-z0-9_.-]+==' "$root/docs/requirements-site.txt")
hashed=$(grep -cE '^[A-Za-z0-9_.-]+==[^ ]+ \\$' "$root/docs/requirements-site.txt")
[[ "$requirements" -gt 0 && "$requirements" == "$hashed" ]] || fail 'every requirement must carry hashes'
workflow="$root/.github/workflows/docs-site.yml"
grep -qF 'pip install --require-hashes -r docs/requirements-site.txt' "$workflow" || fail 'the build must install with --require-hashes'
grep -qF 'zensical build --strict' "$workflow" || fail 'the site builds in strict mode'
grep -qF "vars.PAGES_ENABLED == 'true'" "$workflow" || fail 'the Pages deploy waits for the owner'

if command -v zensical > /dev/null 2>&1; then
  (cd "$tmp/site-src" && zensical build --strict > /dev/null 2>&1) || fail 'the site must build in strict mode'
fi
echo 'OK: the docs site sources resolve, links out of docs/ point at GitHub and the toolchain is pinned with hashes'
