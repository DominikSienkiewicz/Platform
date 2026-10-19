#!/usr/bin/env bash
# docs-site-requirements.sh <zensical-version> — docs/requirements-site.txt od nowa (N-SHOW-16): Zensical w tymczasowym
# venv, jego zależności z `pip freeze` i dla każdej paczki hashe WSZYSTKICH plików wydania z PyPI, więc
# `pip install --require-hashes` działa na każdej platformie. Wersja co najmniej dwa tygodnie po wydaniu.
set -euo pipefail
version=${1:?Usage: scripts/docs-site-requirements.sh <zensical-version>}
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 -m venv "$work/venv"
"$work/venv/bin/pip" install -q "zensical==$version"
{
  echo "# Narzędzie strony dokumentacji (N-SHOW-16): Zensical $version z zależnościami, każda paczka przypięta z hashami"
  echo "# wszystkich plików wydania (pip install --require-hashes). Regeneracja: scripts/docs-site-requirements.sh."
  "$work/venv/bin/pip" freeze --all | grep -viE '^(pip|setuptools|wheel)==' | while IFS='=' read -r name _ pinned; do
    curl -fsSL "https://pypi.org/pypi/$name/$pinned/json" -o "$work/release.json"
    python3 -I - "$name" "$pinned" "$work/release.json" <<'PY'
import json, sys
name, version, path = sys.argv[1:4]
hashes = sorted({file["digests"]["sha256"] for file in json.load(open(path))["urls"]})
print(f"{name}=={version} \\")
print(" \\\n".join(f"    --hash=sha256:{digest}" for digest in hashes))
PY
  done
} > "$root/docs/requirements-site.txt"
echo "Wrote docs/requirements-site.txt for Zensical $version."
