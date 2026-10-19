#!/usr/bin/env bash
# scripts/new-consumer.sh --frontend next renderuje kontekst budowania, którego wymaga templates/Dockerfile.frontend:
# każde źródło COPY z kontekstu (poza package-lock.json, który pisze npm install) oraz katalogi, które etap runner
# kopiuje z /app spoza .next/ (public/), z plikiem w środku, bo git nie przechowuje pustego katalogu (N-CAP-6).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
dockerfile="$root/templates/Dockerfile.frontend"

bash "$root/scripts/new-consumer.sh" --name shop --package pl.example.shop --kind java-library --out "$tmp/shop" --frontend next > /dev/null
web="$tmp/shop/frontend"

sources=$(awk '$1 == "COPY" && $2 !~ /^--/ { for (i = 2; i < NF; i++) if ($i != ".") print $i }' "$dockerfile")
[[ -n "$sources" ]] || fail 'Dockerfile.frontend copies no named file from the build context'
while IFS= read -r source; do
  [[ "$source" == package-lock.json ]] && continue
  [[ -e "$web/$source" ]] || fail "frontend/$source is missing, but Dockerfile.frontend copies it from the build context"
done <<<"$sources"

directories=$(awk '$1 == "COPY" && $2 == "--from=builder" {
  for (i = 3; i < NF; i++) if ($i ~ /^\/app\// && $i !~ /^\/app\/\.next/) { sub(/^\/app\//, "", $i); print $i }
}' "$dockerfile")
[[ -n "$directories" ]] || fail 'Dockerfile.frontend copies no directory of the build context into the runner'
while IFS= read -r directory; do
  [[ -n "$(find "$web/$directory" -type f 2>/dev/null)" ]] \
    || fail "frontend/$directory must exist with a file in it: the runner copies /app/$directory, and git keeps no empty directory"
done <<<"$directories"

echo 'OK: new-consumer --frontend next renders every path Dockerfile.frontend copies from the build context'
