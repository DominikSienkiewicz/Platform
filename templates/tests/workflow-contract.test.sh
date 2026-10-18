#!/usr/bin/env bash
# The caller contract of every reusable workflow — permissions, inputs and secrets — is pinned in
# templates/tests/fixtures/workflow-contract.txt, and every input and secret has a description.
#
# A caller cannot grant a called workflow more than it grants itself, so a new permission, a new
# required input or secret, or a changed default reaches every caller at once. v1.5.31 added
# `packages: read` to backend-ci.yml and broke a caller that granted only `contents: read`. A change
# to the snapshot is therefore a contract change: update the snapshot, list it under "Consumer
# action required" in CHANGELOG.md and release it as a MINOR (docs/adr/0002-…).
#
# Regenerate the snapshot after an intended change with:
#   UPDATE_SNAPSHOT=1 bash templates/tests/workflow-contract.test.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
snapshot="$root/templates/tests/fixtures/workflow-contract.txt"

fail() {
  local message="$1"
  echo "FAIL: $message" >&2
  exit 1
}

# Prints "<file> <kind> …" lines for one workflow; "missing-description <name>" for undocumented items.
contract() {
  local workflow="$1"
  awk -v workflow="$(basename "$workflow")" '
    function strip_comment(text) { sub(/[[:space:]]+#.*$/, "", text); return text }
    function flush() {
      if (item != "") {
        print workflow " " kind " " item attrs
        if (!described) print workflow " missing-description " item
      }
      item = ""; attrs = ""; described = 0
    }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    /^[^[:space:]]/ { flush(); in_call = 0; kind = ""; top_permissions = 0; in_jobs = 0 }
    /^permissions:[[:space:]]*\{\}[[:space:]]*$/ { print workflow " permissions {}"; next }
    /^permissions:[[:space:]]*$/ { top_permissions = 1; next }
    top_permissions && /^  [a-z-]+:/ { line = $0; sub(/^  /, "", line); print workflow " permissions " strip_comment(line); next }
    /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
    in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; sub(/:$/, "", job); job_permissions = 0; next }
    in_jobs && /^    permissions:[[:space:]]*\{\}[[:space:]]*$/ { print workflow " job " job " permissions {}"; next }
    in_jobs && /^    permissions:[[:space:]]*$/ { job_permissions = 1; next }
    in_jobs && job_permissions && /^      [a-z-]+:/ { line = $0; sub(/^ +/, "", line); print workflow " job " job " permissions " strip_comment(line); next }
    in_jobs && /^    [^[:space:]]/ { job_permissions = 0 }
    /^  workflow_call:[[:space:]]*$/ { in_call = 1; next }
    in_call && /^  [^[:space:]]/ { flush(); in_call = 0 }
    in_call && /^    inputs:[[:space:]]*$/ { flush(); kind = "input"; next }
    in_call && /^    secrets:[[:space:]]*$/ { flush(); kind = "secret"; next }
    in_call && /^    [^[:space:]]/ { flush(); kind = "" }
    in_call && kind != "" && /^      [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); item = $1; sub(/:$/, "", item); next }
    in_call && item != "" && /^        description:/ { line = $0; sub(/^        description:[[:space:]]*/, "", line); if (line != "" && line != "\"\"") described = 1; next }
    in_call && item != "" && /^        (type|default|required):/ { line = strip_comment($0); sub(/^ +/, "", line); sub(/: /, "=", line); attrs = attrs " " line; next }
    END { flush() }
  ' "$workflow"
}

current=$(
  for workflow in "$root"/.github/workflows/*.yml; do
    [[ "$(basename "$workflow")" == ci.yml ]] && continue # Platform-internal; release.yml calls it
    grep -q '^  workflow_call:' "$workflow" || continue
    contract "$workflow"
  done
)
[[ -n "$current" ]] || fail 'no reusable workflow found'

undocumented=$(grep ' missing-description ' <<<"$current" || true)
[[ -z "$undocumented" ]] || fail "every reusable workflow input and secret needs a description:
$undocumented"

if [[ "${UPDATE_SNAPSHOT:-}" == 1 ]]; then
  mkdir -p "$(dirname "$snapshot")"
  printf '%s\n' "$current" > "$snapshot"
  echo "Snapshot updated: ${snapshot#"$root"/}"
  exit 0
fi

[[ -f "$snapshot" ]] || fail "missing snapshot ${snapshot#"$root"/}; create it with UPDATE_SNAPSHOT=1"
if ! diff -u "$snapshot" <(printf '%s\n' "$current") >&2; then
  fail "the reusable workflow contract changed (diff above). A caller-visible change needs a MINOR release with a
'Consumer action required' entry in CHANGELOG.md; then refresh the snapshot with
UPDATE_SNAPSHOT=1 bash templates/tests/workflow-contract.test.sh"
fi

echo "OK: the caller contract of $(cut -d' ' -f1 <<<"$current" | sort -u | wc -l | tr -d ' ') reusable workflows matches the snapshot, every input is described"
