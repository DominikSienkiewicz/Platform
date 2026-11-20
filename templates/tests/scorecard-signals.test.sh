#!/usr/bin/env bash
# Sygnał, po którym OpenSSF Scorecard (Signed-Releases) rozpoznaje podpisane wydania Platform: atestacja assetów wydania
# ma id attest-assets, z którego release.yml bierze bundle *.sigstore.json. Że bundle trafia wśród assetów wydania,
# pokazuje sam przebieg Scorecard; wrapper-validation i CodeQL widzi on sam w workflowach (Binary-Artifacts, SAST).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

release="$root/.github/workflows/release.yml"
id=$(awk '/uses: actions\/attest@/ {print prev} {prev=$0}' "$release" | sed -nE 's/^ *id: (attest-assets)$/\1/p')
[[ "$id" == attest-assets ]] || fail 'the attestation of the release assets needs the id attest-assets'

echo 'OK: the attestation of the release assets has the id attest-assets'
