#!/usr/bin/env bash
# platform-bump weryfikuje atestację pobranego tarballa wydania (od 1.6.0) przed jego użyciem: nieudana
# weryfikacja zatrzymuje bump bez zmian, --skip-provenance przepuszcza z powodem w logu, starsze wydania
# nie mają czego weryfikować. Cały bin na atrapach (bump-fixture.sh, gh = stub).
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=bump-fixture.sh
source "$(dirname "$0")/bump-fixture.sh"

dir=$(consumer verified)
bump "$dir" 1.6.0
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail 'a verified tarball must let the bump run'; }
grep -qF 'Provenance: dominiksienkiewicz-versions-9.9.9.tgz was built by Platform' "$dir.log" || { cat "$dir.log"; fail 'the verification must be reported'; }
grep -qF -- '--repo DominikSienkiewicz/Platform --signer-workflow DominikSienkiewicz/Platform/.github/workflows/release.yml' "$FAKE_GH_LOG" \
  || { cat "$FAKE_GH_LOG"; fail 'the attestation must be tied to the repository and release.yml'; }

dir=$(consumer forged)
FAKE_PROVENANCE=fail bump "$dir" 1.6.0
[[ $rc -ne 0 ]] || { cat "$dir.log"; fail 'a tarball whose provenance fails must stop the bump'; }
grep -qF 'does not verify, so platform-bump stops before using it' "$dir.log" || { cat "$dir.log"; fail 'the refusal must say why'; }
grep -qF 'no attestation matched' "$dir.log" || fail 'the refusal must show what gh reported'
[[ -z "$(git -C "$dir" status --porcelain)" ]] || fail 'a refused tarball must leave the tree as committed'

FAKE_PROVENANCE=fail bump "$dir" --skip-provenance 'registry outage drill' 1.6.0
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail '--skip-provenance must let the bump run'; }
grep -qF 'WARNING: the provenance of dominiksienkiewicz-versions-9.9.9.tgz was not verified: registry outage drill' "$dir.log" \
  || fail '--skip-provenance must log its reason'

dir=$(consumer old)
: > "$FAKE_GH_LOG"
FAKE_PROVENANCE=fail bump "$dir" 1.5.31
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail 'a release before 1.6.0 has no attestation to verify'; }
grep -qF 'predates the release attestations of 1.6.0' "$dir.log" || fail 'the skip must be explained'
if grep -q 'attestation' "$FAKE_GH_LOG"; then fail 'gh must not be asked for a release before 1.6.0'; fi

bump "$dir" --skip-provenance
[[ $rc -eq 2 ]] || { cat "$dir.log"; fail '--skip-provenance without a reason must exit 2'; }

echo 'OK: platform-bump verifies the provenance of the target package before it uses it'
