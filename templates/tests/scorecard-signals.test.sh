#!/usr/bin/env bash
# Sygnały, po których OpenSSF Scorecard rozpoznaje praktyki Platform (triaż 2026-10-19):
#   Binary-Artifacts — workflow z gradle/actions/wrapper-validation, szybszy niż ci.yml, na każdym pushu do main;
#   SAST — workflow z github/codeql-action/analyze (Semgrepa Scorecard nie widzi);
#   Signed-Releases — bundle atestacji assetów jako *.sigstore.json wśród assetów GitHub Release;
#   Pinned-Dependencies — obraz devcontainera po digeście.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflows="$root/.github/workflows"
fail() { echo "FAIL: $*" >&2; exit 1; }

wrapper=$(grep -l 'uses: gradle/actions/wrapper-validation@' "$workflows"/*.yml | grep -v '/ci\.yml$' || true)
[[ $(wc -l <<<"$wrapper") -eq 1 && -n "$wrapper" ]] || fail 'exactly one workflow besides ci.yml must validate the Gradle wrappers'
grep -qE '^    branches: \[main\]$' "$wrapper" || fail "$(basename "$wrapper") must run on every push to main"
if grep -qE '^    paths(-ignore)?:' "$wrapper"; then fail "$(basename "$wrapper") must not filter paths: Scorecard needs a run on the latest commit"; fi
[[ $(grep -c '^      - uses: ' "$wrapper") -eq 2 ]] || fail "$(basename "$wrapper") must only check out and validate, so it finishes before Scorecard"

grep -lqE 'uses: github/codeql-action/analyze@[0-9a-f]{40} # v' "$workflows"/*.yml || fail 'a workflow must run github/codeql-action/analyze, pinned by commit'

release="$workflows/release.yml"
id=$(awk '/uses: actions\/attest@/ {print prev} {prev=$0}' "$release" | sed -nE 's/^ *id: (attest-assets)$/\1/p')
[[ "$id" == attest-assets ]] || fail 'the attestation of the release assets needs the id attest-assets'
copy=$(grep -n 'steps.attest-assets.outputs.bundle-path' "$release" | cut -d: -f1)
upload=$(grep -n 'gh release upload "v$V" "$RUNNER_TEMP"/assets/\*' "$release" | cut -d: -f1)
[[ -n "$copy" && -n "$upload" && "$copy" -lt "$upload" ]] || fail 'release.yml must put the attestation bundle among the assets before it uploads them'
grep -qF 'cp "$BUNDLE" "$RUNNER_TEMP/assets/platform-$V-assets.sigstore.json"' "$release" \
  || fail 'the bundle must be uploaded as a *.sigstore.json asset, the name Scorecard looks for'

grep -qE '^FROM [^ ]+:[^ @]+@sha256:[0-9a-f]{64}$' "$root/.devcontainer/Dockerfile" || fail '.devcontainer/Dockerfile must pin its base image by digest, keeping the tag'

echo 'OK: wrapper validation, CodeQL, the signed release bundle and the devcontainer digest are where Scorecard looks'
