#!/usr/bin/env bash
# Preset Renovate czeka 3 dni na świeże wydania akcji i obrazów (internalChecksFilter strict), a poprawki
# bezpieczeństwa omijają i ten okres, i poniedziałkowe okno (G-16).
set -euo pipefail
preset="$(cd "$(dirname "$0")/../.." && pwd)/default.json"
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ "$(jq -r '.minimumReleaseAge' "$preset")" == "3 days" ]] || fail 'updates wait three days after a release'
[[ "$(jq -r '.internalChecksFilter' "$preset")" == strict ]] || fail 'a pending release age holds the pull request back'
[[ "$(jq -r '.osvVulnerabilityAlerts' "$preset")" == true ]] || fail 'OSV vulnerability alerts are on'
[[ "$(jq -r '.vulnerabilityAlerts | has("minimumReleaseAge") and .minimumReleaseAge == null' "$preset")" == true ]] \
  || fail 'security fixes skip the cooling-off period'
[[ "$(jq -c '.vulnerabilityAlerts.schedule' "$preset")" == '["at any time"]' ]] || fail 'security fixes skip the Monday window'
jq -e '.vulnerabilityAlerts.labels | index("security")' "$preset" > /dev/null || fail 'security fixes carry the security label'

echo 'OK: the Renovate preset delays fresh releases and lets security fixes through at once'
