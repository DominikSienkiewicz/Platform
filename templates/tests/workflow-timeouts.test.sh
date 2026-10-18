#!/usr/bin/env bash
# Every job that runs steps sets timeout-minutes; without it GitHub waits 360 minutes for a hung step.
# A job that calls a reusable workflow (uses:) cannot set one, so each reusable workflow takes the limit
# as a timeout-minutes input instead, and its callers can raise it.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

missing=""
for workflow in "$root"/.github/workflows/*.yml; do
  jobs=$(awk '
    function report() { if (job != "" && !calls && !limited) print job }
    /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
    in_jobs && /^[^[:space:]#]/ { in_jobs = 0 }
    in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { report(); job = $1; sub(/:$/, "", job); calls = 0; limited = 0; next }
    in_jobs && /^    uses:/ { calls = 1 }
    in_jobs && /^    timeout-minutes:/ { limited = 1 }
    END { report() }
  ' "$workflow")
  for job in $jobs; do missing+="  ${workflow##*/}: $job"$'\n'; done
done

if [[ -n "$missing" ]]; then
  printf 'Jobs without timeout-minutes:\n%s' "$missing" >&2
  exit 1
fi

# Reusable workflows take the limit as an input, so a caller can raise it.
for workflow in "$root"/.github/workflows/*.yml; do
  grep -q '^  workflow_call:' "$workflow" || continue
  case "${workflow##*/}" in
    ci.yml) continue ;;    # Platform's own CI; only release.yml calls it, as verify
    sonar.yml) continue ;; # fixed limits of its own, older than this guard
  esac
  grep -q 'inputs\.timeout-minutes\|inputs\.[a-z-]*timeout-minutes' "$workflow" \
    || { echo "${workflow##*/} must let callers set the limit with a timeout-minutes input" >&2; exit 1; }
done
echo 'OK: every job that runs steps sets timeout-minutes, and reusable workflows let callers raise it'
