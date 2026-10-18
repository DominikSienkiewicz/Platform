#!/usr/bin/env bash
# Snyk runs from a digest-pinned image: the Snyk Docker action executed the moving snyk/snyk:docker tag,
# so pinning the action's SHA pinned nothing. Both workflows that run Snyk must name the same digest,
# and no Snyk step may run in a job that holds packages: write.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflows="$root/.github/workflows"

fail() { local message="$1"; echo "FAIL: $message" >&2; exit 1; }

if grep -n 'snyk/actions' "$workflows"/*.yml; then
  fail 'run Snyk from the digest-pinned SNYK_IMAGE, not from a Snyk action'
fi

pins=$(grep -h 'SNYK_IMAGE: ' "$workflows/deploy.yml" "$workflows/container-scan.yml" | sed 's/^ *SNYK_IMAGE: *//' | sort -u)
[[ $(grep -c . <<<"$pins") -eq 1 ]] || fail "deploy.yml and container-scan.yml must pin one Snyk image, found: $pins"
[[ "$pins" =~ ^snyk/snyk:docker@sha256:[0-9a-f]{64}$ ]] || fail "the Snyk image must be pinned by digest, found: $pins"

# Jobs of deploy.yml that mention Snyk must not hold packages: write.
awk '
  /^jobs:/ { in_jobs = 1; next }
  in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; next }
  in_jobs && !/^[[:space:]]*#/ && /packages:[[:space:]]*write/ { writes[job] = 1 }
  in_jobs && !/^[[:space:]]*#/ && /SNYK_IMAGE/ { snyk[job] = 1 }
  END { for (j in snyk) if (j in writes) { print j; bad = 1 } exit bad }
' "$workflows/deploy.yml" || fail 'a deploy.yml job runs Snyk while holding packages: write'

echo 'OK: Snyk runs from one digest-pinned image, outside any job that can write packages'
