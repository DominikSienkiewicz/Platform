#!/usr/bin/env bash
# verify-provenance of backend-ci.yml (N-REL-16): every Platform jar in the Gradle cache must verify against the
# attestations of Platform's release.yml, under the organization or, for a release before the transfer of
# 2026-11-13, under the personal account; sources and javadoc jars are skipped, an unverified jar or an empty cache
# fails with PLAT-PROV-001. The block is cut out between its markers and run against a stub gh.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/backend-ci.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "$OUT" >&2; exit 1; }
OUT=""
awk 'index($0, "# >>> verify-provenance") { inside = 1; next } index($0, "# <<< verify-provenance") { inside = 0 } inside { sub(/^          /, ""); print }' \
  "$workflow" > "$tmp/verify.sh"
[[ -s "$tmp/verify.sh" ]] || fail 'backend-ci.yml has no verify-provenance block between its markers'
grep -qF 'if: ${{ inputs.verify-provenance }}' <(sed -n '/- name: Verify the provenance of the Platform artifacts/,/run:/p' "$workflow") \
  || fail 'the check must be opt-in'

mkdir -p "$tmp/bin"
# A jar named *-personal-* carries only the attestation of the personal account's release.yml (built before the
# transfer of 2026-11-13), *-organization-* only that of the organization's; *unattested* carries none.
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
[[ "$3" == *unattested* ]] && exit 1
[[ "$3" == *-personal-* && "$5" != DominikSienkiewicz/Platform ]] && exit 1
[[ "$3" == *-organization-* && "$5" != SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform ]] && exit 1
exit 0
GH
chmod +x "$tmp/bin/gh"
cache="$tmp/home/caches/modules-2/files-2.1"
jar() { mkdir -p "$cache/$1/$2/1.6.0/abc"; : > "$cache/$1/$2/1.6.0/abc/$2-1.6.0$3.jar"; }
run() { : > "$tmp/calls"; RC=0; OUT=$(GRADLE_USER_HOME="$tmp/home" GH_CALLS="$tmp/calls" PATH="$tmp/bin:$PATH" bash "$tmp/verify.sh" 2>&1) || RC=$?; }

run
[[ $RC -eq 1 ]] && grep -qF '[PLAT-PROV-001] No Platform jar in the Gradle cache' <<<"$OUT" || fail 'an empty cache must fail'

jar pl.seniordeveloper platform-test-fixtures ""
jar pl.seniordeveloper platform-test-fixtures -sources
jar pl.seniordeveloper.gradle build-logic ""
jar org.example other ""
run
[[ $RC -eq 0 ]] || fail 'attested Platform jars must pass'
[[ $(wc -l < "$tmp/calls") -eq 2 ]] || fail 'only the two Platform main jars are verified'
grep -qF -- '--signer-workflow SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/.github/workflows/release.yml' "$tmp/calls" \
  || fail 'the signer must be release.yml'

jar pl.seniordeveloper platform-personal-fixtures ""
jar pl.seniordeveloper platform-organization-fixtures ""
run
[[ $RC -eq 0 ]] || fail 'a jar attested by either owner of Platform must pass'
grep -qF -- 'platform-personal-fixtures-1.6.0.jar --repo DominikSienkiewicz/Platform --signer-workflow DominikSienkiewicz/Platform/.github/workflows/release.yml' "$tmp/calls" \
  || fail 'a jar released before the transfer must be checked against the old release.yml'

jar pl.seniordeveloper platform-unattested ""
run
[[ $RC -eq 1 ]] || fail 'an unattested jar must fail'
grep -qF '[PLAT-PROV-001] platform-unattested-1.6.0.jar carries no attestation' <<<"$OUT" || fail 'the failure must name the jar'
echo 'OK: backend-ci verify-provenance checks every Platform jar against release.yml attestations'
