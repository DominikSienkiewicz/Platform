#!/usr/bin/env bash
# Łańcuch dostaw w deploy.yml (etap 5.2): build-push ustala digest każdego skanowanego obrazu, Grype i Trivy skanują ten
# digest jako bramka, a osobny job sign podpisuje cosign keyless dokładnie te digesty, dopiero gdy obie bramki przeszły.
# sign nie uruchamia kodu repozytorium i tylko on ma id-token: write, więc kod zależności w buildzie nie dostaje
# tożsamości podpisu. Bloki digestów, Trivy i podpisu są wycinane między znacznikami i uruchamiane z atrapami docker,
# trivy i cosign.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/deploy.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" 2>/dev/null >&2 || true; exit 1; }
block() {
  awk -v from="# >>> $1" -v to="# <<< $1" \
    'index($0, from) { inside = 1; next } index($0, to) { inside = 0 } inside { sub(/^          /, ""); print }' "$workflow"
}
job() { awk -v start="  $1:" '$0 == start { p = 1; next } /^  [a-z-]+:$/ { p = 0 } p' "$workflow"; }
# step JOB NAME: krok joba od wiersza `- name: NAME…` do następnego kroku.
step() { awk -v name="      - name: $2" 'index($0, name) == 1 { p = 1; print; next } p && /^      - / { p = 0 } p' <<< "$(job "$1")"; }
line_of() { grep -nF -- "$2" <<< "$(job "$1")" | head -1 | cut -d: -f1; }
pinned() { grep -qE "^        uses: $1@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$" <<< "$2"; }

backend_digest="sha256:$(printf 'b%.0s' {1..64})"
frontend_digest="sha256:$(printf 'f%.0s' {1..64})"
backend="ghcr.io/owner/app-backend@$backend_digest"
frontend="ghcr.io/owner/app-frontend@$frontend_digest"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/docker" <<'STUB'
#!/usr/bin/env bash
# docker buildx imagetools inspect REF --format '{{json .Manifest}}': indeks obrazu z digestem zależnym od nazwy.
[[ "$1 $2 $3" == "buildx imagetools inspect" && "$5" == "--format" && "$6" == '{{json .Manifest}}' ]] || exit 2
case "$4" in
  ghcr.io/owner/app-backend:2.0.0) hex=b ;;
  ghcr.io/owner/app-frontend:3.0.0) hex=f ;;
  *) echo "no such manifest: $4" >&2; exit 1 ;;
esac
printf '{"mediaType":"application/vnd.oci.image.index.v1+json","digest":"sha256:%s","size":856}\n' "$(printf "$hex%.0s" {1..64})"
STUB
cat > "$tmp/bin/trivy" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
[[ -n "${FAIL_ON:-}" && "${!#}" == *"$FAIL_ON"* ]] && exit 1
exit 0
STUB
cat > "$tmp/bin/cosign" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
STUB
chmod +x "$tmp/bin/docker" "$tmp/bin/trivy" "$tmp/bin/cosign"

# --- build-push: digesty skanowanych obrazów ---
build_push=$(job build-push)
digests_step=$(step build-push 'Resolve the digests of the scanned images')
[[ -n "$digests_step" ]] || fail "build-push must have the step 'Resolve the digests of the scanned images'"
grep -qFx '        id: digests' <<< "$digests_step" || fail 'the digest step must have the id digests'
grep -qFx '        if: ${{ inputs.scan-images }}' <<< "$digests_step" || fail 'the digests are resolved exactly when the images are scanned'
grep -qFx '          SINGLE_IMAGE: ${{ inputs.single-image }}' <<< "$digests_step" \
  || fail 'the digest step must pass inputs.single-image as SINGLE_IMAGE in its env:'
block image-digests > "$tmp/digests.sh"
[[ -s "$tmp/digests.sh" ]] || fail 'deploy.yml has no image-digests block between its markers'
digests() {
  : > "$tmp/github-output"
  (env PATH="$tmp/bin:$PATH" GITHUB_OUTPUT="$tmp/github-output" REGISTRY=ghcr.io OWNER=owner APP=app BACKEND_VER=2.0.0 \
    FRONTEND_VER=3.0.0 "$@" bash "$tmp/digests.sh") > "$tmp/out" 2>&1 || return 1
  paste -sd'|' - < "$tmp/github-output"
}
outputs=$(digests SINGLE_IMAGE=false) || fail 'the image-digests block must run for two images'
[[ "$outputs" == "backend=$backend|frontend=$frontend|images=$backend $frontend" ]] \
  || fail "two images must resolve to the digest references of the backend and the frontend, got: $outputs"
outputs=$(digests SINGLE_IMAGE=true FRONTEND_VER='') || fail 'the image-digests block must run for a single image'
[[ "$outputs" == "backend=$backend|frontend=|images=$backend" ]] \
  || fail "a single image must resolve only the backend, got: $outputs"
digests SINGLE_IMAGE=false BACKEND_VER=9.9.9 > /dev/null && fail 'a tag missing from GHCR must fail the digest step'

last_build=$(grep -nF -- '- name: Build & push' <<< "$build_push" | tail -1 | cut -d: -f1)
digests_line=$(line_of build-push '- name: Resolve the digests of the scanned images')
grype_line=$(line_of build-push '- name: Grype scan — backend (gate)')
[[ "$last_build" -lt "$digests_line" && "$digests_line" -lt "$grype_line" ]] \
  || fail 'the digests are resolved after every image is pushed and before the first scan'

# --- bramka Grype: skanuje digest, który potem jest podpisany ---
grep -qFx '          image: ${{ steps.digests.outputs.backend }}' <<< "$(step build-push 'Grype scan — backend (gate)')" \
  || fail 'Grype must scan the backend by its digest, the one the sign job signs'
grep -qFx '          image: ${{ steps.digests.outputs.frontend }}' <<< "$(step build-push 'Grype scan — frontend (gate)')" \
  || fail 'Grype must scan the frontend by its digest, the one the sign job signs'

# --- bramka Trivy obok Grype ---
setup_trivy=$(step build-push 'Set up Trivy')
[[ -n "$setup_trivy" ]] || fail "build-push must have the step 'Set up Trivy'"
grep -qFx '        if: ${{ inputs.scan-images }}' <<< "$setup_trivy" || fail 'Trivy is installed exactly when the images are scanned'
pinned aquasecurity/setup-trivy "$setup_trivy" || fail 'setup-trivy must be pinned to a commit SHA with a # vX.Y.Z comment'
grep -qE '^          version: v[0-9]+\.[0-9]+\.[0-9]+$' <<< "$setup_trivy" \
  || fail 'Trivy must be pinned to an exact version, never latest'
trivy_step=$(step build-push 'Trivy scan — scanned images (gate)')
[[ -n "$trivy_step" ]] || fail "build-push must have the step 'Trivy scan — scanned images (gate)'"
grep -qFx '        if: ${{ inputs.scan-images }}' <<< "$trivy_step" || fail 'the Trivy gate runs exactly when the images are scanned'
grep -qFx '          IMAGES: ${{ steps.digests.outputs.images }}' <<< "$trivy_step" \
  || fail 'Trivy must scan the digest references the digest step resolved'
grep -qFx '          SCAN_SEVERITY: ${{ inputs.scan-severity }}' <<< "$trivy_step" \
  || fail 'Trivy must take its threshold from inputs.scan-severity, as Grype does'
grep -qF 'continue-on-error' <<< "$trivy_step" && fail 'the Trivy scan is a gate and must not continue on error'
trivy_line=$(line_of build-push '- name: Trivy scan — scanned images (gate)')
[[ "$(line_of build-push '- name: Set up Trivy')" -lt "$trivy_line" && "$digests_line" -lt "$trivy_line" ]] \
  || fail 'Trivy is set up and the digests resolved before the Trivy scan'

block trivy-scan > "$tmp/trivy.sh"
[[ -s "$tmp/trivy.sh" ]] || fail 'deploy.yml has no trivy-scan block between its markers'
trivy_scan() {
  : > "$tmp/calls"
  mkdir -p "$tmp/checkout"
  (cd "$tmp/checkout" && env PATH="$tmp/bin:$PATH" CALLS="$tmp/calls" IMAGES="$backend $frontend" SCAN_SEVERITY=high "$@" \
    bash "$tmp/trivy.sh") > "$tmp/out" 2>&1
}
trivy_scan || fail 'the trivy-scan block must pass when Trivy finds nothing'
[[ $(grep -c . "$tmp/calls") -eq 2 ]] || fail "Trivy must scan each image once, got: $(paste -sd'|' - < "$tmp/calls")"
for image in "$backend" "$frontend"; do
  call=$(grep -F -- " $image" "$tmp/calls") || fail "Trivy must scan $image by its digest"
  [[ "$call" == "image "* && "${call##* }" == "$image" ]] || fail "Trivy must run 'trivy image … $image', got: $call"
  for flag in '--image-src remote' '--scanners vuln' '--ignore-unfixed' '--exit-code 1' '--severity HIGH,CRITICAL'; do
    grep -qF -- " $flag " <<< " $call " || fail "the Trivy gate must pass $flag, got: $call"
  done
  grep -qF -- '--ignorefile' <<< "$call" && fail 'without .trivyignore.yaml Trivy must get no --ignorefile'
done

printf 'vulnerabilities: []\n' > "$tmp/checkout/.trivyignore.yaml"
trivy_scan || fail 'the trivy-scan block must pass with a .trivyignore.yaml'
[[ $(grep -cF -- '--ignorefile .trivyignore.yaml' "$tmp/calls") -eq 2 ]] \
  || fail 'with .trivyignore.yaml in the repository root Trivy must read it for every image'
rm "$tmp/checkout/.trivyignore.yaml"

severity_of() { trivy_scan SCAN_SEVERITY="$1" || return 1; head -1 "$tmp/calls" | grep -oE -- '--severity [A-Z,]+' | cut -d' ' -f2; }
[[ "$(severity_of critical)" == 'CRITICAL' ]] || fail 'scan-severity critical must fail Trivy on CRITICAL only'
[[ "$(severity_of medium)" == 'MEDIUM,HIGH,CRITICAL' ]] || fail 'scan-severity medium must fail Trivy on MEDIUM and above'
[[ "$(severity_of low)" == 'LOW,MEDIUM,HIGH,CRITICAL' ]] || fail 'scan-severity low must fail Trivy on LOW and above'
[[ "$(severity_of negligible)" == 'UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL' ]] || fail 'scan-severity negligible must fail Trivy on every severity'
trivy_scan SCAN_SEVERITY=severe && fail 'an unknown scan-severity must fail the Trivy gate'
grep -qF 'scan-severity' "$tmp/out" || fail 'the refusal of an unknown threshold must name scan-severity'

trivy_scan FAIL_ON=app-backend && fail 'a finding in the backend must fail the Trivy gate'
[[ $(grep -c . "$tmp/calls") -eq 2 ]] || fail 'a finding in one image must not stop the scan of the others'

# --- sign: podpis po obu bramkach, w jobie bez kodu repozytorium ---
grep -qFx '      images: ${{ steps.digests.outputs.images }}' <<< "$build_push" \
  || fail 'build-push must expose the scanned digests as its output images'
grep -qF 'id-token' <<< "$build_push" && fail 'build-push runs dependency code, so it must never get id-token: write'
sign=$(job sign)
[[ -n "$sign" ]] || fail 'deploy.yml must have a sign job'
grep -qFx '    needs: [versions, build-push]' <<< "$sign" || fail 'sign must wait for versions and for build-push with its gates'
grep -qFx '    if: ${{ inputs.scan-images }}' <<< "$sign" \
  || fail 'sign must run exactly when the images were scanned, and only after build-push succeeded'
grep -qE '^    timeout-minutes: [0-9]+$' <<< "$sign" || fail 'the sign job needs a time limit'
permissions=$(awk '/^    permissions:$/ { p = 1; next } p && /^      / { print; next } p { exit }' <<< "$sign")
[[ "$permissions" == $'      id-token: write\n      packages: write' ]] \
  || fail "sign needs exactly id-token: write and packages: write, got: $(paste -sd'|' - <<< "$permissions")"
grep -qE 'actions/checkout|gradlew|npm ' <<< "$sign" && fail 'sign must not check out or run the code of the repository'
grep -qFx '      IMAGES: ${{ needs.build-push.outputs.images }}' <<< "$sign" \
  || fail 'sign must sign exactly the digests that build-push scanned'
grep -qFx '      IMAGE_PREFIX: ghcr.io/${{ needs.versions.outputs.owner }}/${{ inputs.app-name }}' <<< "$sign" \
  || fail 'sign must know the image prefix of the application'
pinned sigstore/cosign-installer "$(step sign 'Install cosign')" \
  || fail "sign must install cosign in the step 'Install cosign' with sigstore/cosign-installer pinned to a commit SHA"

block sign-images > "$tmp/sign.sh"
[[ -s "$tmp/sign.sh" ]] || fail 'deploy.yml has no sign-images block between its markers'
sign_images() {
  : > "$tmp/calls"
  (env PATH="$tmp/bin:$PATH" CALLS="$tmp/calls" IMAGE_PREFIX=ghcr.io/owner/app "$@" bash "$tmp/sign.sh") > "$tmp/out" 2>&1
}
sign_images IMAGES="$backend $frontend" || fail 'the sign-images block must sign two scanned images'
[[ "$(paste -sd'|' - < "$tmp/calls")" == "sign --yes $backend|sign --yes $frontend" ]] \
  || fail "each digest must be signed keyless, by digest, without a prompt, got: $(paste -sd'|' - < "$tmp/calls")"
for bad in 'ghcr.io/owner/app-backend:2.0.0' "ghcr.io/owner/other-backend@$backend_digest" "ghcr.io/owner/app-migrate@$backend_digest" \
  "ghcr.io/owner/app-backend@sha256:abc" ''; do
  sign_images IMAGES="$bad" && fail "sign must refuse '$bad': only digests of the scanned images of this application are signed"
  [[ ! -s "$tmp/calls" ]] || fail "sign must not call cosign at all for '$bad'"
done
sign_images IMAGES="$backend ghcr.io/owner/app-frontend:3.0.0" && fail 'one reference by tag must refuse the whole set'
[[ ! -s "$tmp/calls" ]] || fail 'sign checks every reference before it signs any'

# --- kontrakt dla platform-workflows-check: wywołujący nadaje id-token: write ---
for contract in "$root/frontend/packages/versions/workflow-contract.txt" "$root/templates/tests/fixtures/workflow-contract.txt"; do
  for permission in 'id-token: write' 'packages: write'; do
    grep -qFx "deploy.yml job sign permissions $permission" "$contract" \
      || fail "${contract#"$root"/} must list the permission $permission of the sign job of deploy.yml"
  done
done

echo 'OK: deploy.yml scans each image by digest with Grype and Trivy and signs those digests keyless only after both gates'
