#!/usr/bin/env bash
# scripts/check-doc-links.py: wszystkie linki względne i kotwice w śledzonych *.md Platform się rozwiązują,
# a na repo-atrapie zepsuty plik i zepsuta kotwica są wskazane z file:line; kod i linki zewnętrzne pomijane.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" >&2 2>/dev/null; exit 1; }

python3 "$root/scripts/check-doc-links.py" "$root" > "$tmp/out" || fail "Platform's Markdown has broken links"

repo="$tmp/repo"
mkdir -p "$repo/docs"
git -C "$repo" init -q
cat > "$repo/docs/guide.md" <<'MD'
# Guide

## Set `up` the repo

## Usage

## Usage
MD
cat > "$repo/README.md" <<'MD'
# Readme

[ok](docs/guide.md#set-up-the-repo) [second usage](docs/guide.md#usage-1) [self](#readme) [site](https://example.test/x.md)
[missing file](docs/nope.md)
[missing anchor](docs/guide.md#install)

```markdown
[inside a fence](docs/fence.md)
```

Inline `[code](docs/inline.md)` is not a link.
MD
git -C "$repo" add -A
if python3 "$root/scripts/check-doc-links.py" "$repo" > "$tmp/out"; then fail 'broken links must fail the check'; fi
grep -qxF 'README.md:4: docs/nope.md (no such file)' "$tmp/out" || fail 'a missing file must be named with its line'
grep -qxF 'README.md:5: docs/guide.md#install (no heading #install)' "$tmp/out" || fail 'a missing anchor must be named'
[[ $(grep -c '^README.md:' "$tmp/out") -eq 2 ]] || fail 'valid links, fences, inline code and external links must pass'

echo "OK: check-doc-links resolves every relative link and anchor of the Markdown files"
