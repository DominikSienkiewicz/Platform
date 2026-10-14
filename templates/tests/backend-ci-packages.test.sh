#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

for permission in contents packages; do
  if ! awk -v permission="$permission:" '
    /^permissions:[[:space:]]*$/ { selected = 1; next }
    selected && /^[^[:space:]#]/ { exit }
    selected && $1 == permission && $2 == "read" { found = 1 }
    END { exit !found }
  ' "$root/.github/workflows/backend-ci.yml"; then
    printf 'Backend CI must explicitly grant %s: read for its automatic token.\n' "$permission" >&2
    exit 1
  fi
done
