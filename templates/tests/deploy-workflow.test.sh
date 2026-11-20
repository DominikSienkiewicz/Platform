#!/usr/bin/env bash
# deploy.yml, przypadek po przypadku: cache warstw budowania obrazów, podpisany łańcuch dostaw (digesty, bramki Grype
# i Trivy, podpis cosign keyless), tryb jednego obrazu i miejsce zwalniane na bazy Trivy. Bloki wycięte z workflowu
# biegną na atrapach docker, trivy, cosign i gh, więc testy uruchamiają dostarczany kod.
# Wspólne helpery (fail, block, job, step, line_of, pinned) są w lib/workflow.sh.
# shellcheck disable=SC2016 # dosłowne wyrażenia GitHuba
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/workflow.sh
source "$(dirname "$0")/lib/workflow.sh"
# shellcheck disable=SC2034 # workflow czyta lib/workflow.sh
workflow="$root/.github/workflows/deploy.yml"

# --- cache ---
# Nagłówek deploy.yml obiecuje cache: każdy build-push-action ma cache-from i cache-to w GHA z własnym scope,
# a bootJar biegnie po setup-gradle w tym samym jobie.
(
job=$(awk '/^  build-push:$/{p=1;next} /^  [a-z-]+:$/{p=0} p' "$workflow")
builds=$(grep -c 'uses: docker/build-push-action@' <<<"$job")
[[ $builds -ge 4 ]] || fail "expected the four image builds, found $builds"
[[ $(grep -c 'cache-from: type=gha,scope=' <<<"$job") -eq $builds ]] || fail 'every image build reads the GHA layer cache'
[[ $(grep -c 'cache-to: type=gha,mode=max,scope=' <<<"$job") -eq $builds ]] || fail 'every image build writes the GHA layer cache'
scopes=$(grep -oE 'cache-to: type=gha,mode=max,scope=.*$' <<<"$job" | sort | uniq -d)
[[ -z "$scopes" ]] || fail "two images share a cache scope: $scopes"
gradle=$(grep -n 'uses: gradle/actions/setup-gradle@' <<<"$job" | cut -d: -f1)
bootjar=$(grep -n 'name: Build bootJar' <<<"$job" | cut -d: -f1)
[[ -n "$gradle" && -n "$bootjar" && "$gradle" -lt "$bootjar" ]] || fail 'setup-gradle must run before the bootJar build'

echo 'OK: deploy.yml caches every image build per image and builds bootJar with the Gradle cache'
)

# --- signed-images ---
# Łańcuch dostaw w deploy.yml (etap 5.2): build-push ustala digest każdego skanowanego obrazu, Grype i Trivy skanują ten
# digest jako bramka, a osobny job sign podpisuje cosign keyless dokładnie te digesty, dopiero gdy obie bramki przeszły.
# sign nie uruchamia kodu repozytorium i tylko on ma id-token: write, więc kod zależności w buildzie nie dostaje
# tożsamości podpisu. Bloki digestów, Trivy i podpisu są wycinane między znacznikami i uruchamiane z atrapami docker,
# trivy i cosign.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

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
[[ "$outputs" == "backend=$backend|frontend=$frontend|images=$backend $frontend|backend-digest=$backend_digest|frontend-digest=$frontend_digest" ]] \
  || fail "two images must resolve to the digest references and the digests of the backend and the frontend, got: $outputs"
outputs=$(digests SINGLE_IMAGE=true FRONTEND_VER='') || fail 'the image-digests block must run for a single image'
[[ "$outputs" == "backend=$backend|frontend=|images=$backend|backend-digest=$backend_digest|frontend-digest=" ]] \
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
# GitHub pomija wyjście joba, w którym jest wartość sekretu, a właściciel w referencji obrazu bywa wartością sekretu
# (GPR_USER konsumenta), więc build-push wystawia same digesty, a sign składa z nich referencje.
job_outputs=$(awk '/^    outputs:$/ { p = 1; next } p && /^      / { print; next } p { exit }' <<< "$build_push")
[[ "$job_outputs" == $'      backend-digest: ${{ steps.digests.outputs.backend-digest }}\n      frontend-digest: ${{ steps.digests.outputs.frontend-digest }}' ]] \
  || fail "build-push must expose only the scanned digests, never a reference with the owner, which GitHub drops when a secret holds that value; got: $(paste -sd'|' - <<< "$job_outputs")"
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
grep -qFx '      BACKEND_DIGEST: ${{ needs.build-push.outputs.backend-digest }}' <<< "$sign" \
  || fail 'sign must sign exactly the backend digest that build-push scanned'
grep -qFx '      FRONTEND_DIGEST: ${{ needs.build-push.outputs.frontend-digest }}' <<< "$sign" \
  || fail 'sign must sign exactly the frontend digest that build-push scanned'
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
sign_images BACKEND_DIGEST="$backend_digest" FRONTEND_DIGEST="$frontend_digest" \
  || fail 'the sign-images block must sign two scanned images'
[[ "$(paste -sd'|' - < "$tmp/calls")" == "sign --yes $backend|sign --yes $frontend" ]] \
  || fail "each digest must be signed keyless, by digest, without a prompt, got: $(paste -sd'|' - < "$tmp/calls")"
sign_images BACKEND_DIGEST="$backend_digest" FRONTEND_DIGEST='' || fail 'the sign-images block must sign a single scanned image'
[[ "$(paste -sd'|' - < "$tmp/calls")" == "sign --yes $backend" ]] \
  || fail "a single image must sign only the backend, got: $(paste -sd'|' - < "$tmp/calls")"
for bad in '' '2.0.0' 'sha256:abc' "sha256:$(printf 'B%.0s' {1..64})" "$backend_digest ghcr.io/owner/other-backend@$backend_digest"; do
  sign_images BACKEND_DIGEST="$bad" FRONTEND_DIGEST="$frontend_digest" \
    && fail "sign must refuse the backend digest '$bad': only sha256 digests of the scanned images are signed"
  [[ ! -s "$tmp/calls" ]] || fail "sign must not call cosign at all for the backend digest '$bad'"
done
grep -qF 'build-push resolved no backend digest' <<< "$(sign_images BACKEND_DIGEST='' FRONTEND_DIGEST=''; cat "$tmp/out")" \
  || fail 'a missing backend digest must name build-push as the job that resolved none'
sign_images BACKEND_DIGEST="$backend_digest" FRONTEND_DIGEST='sha256:abc' && fail 'one bad digest must refuse the whole set'
[[ ! -s "$tmp/calls" ]] || fail 'sign checks every digest before it signs any'

# --- kontrakt dla platform-workflows-check: wywołujący nadaje id-token: write ---
for contract in "$root/frontend/packages/versions/workflow-contract.txt" "$root/templates/tests/fixtures/workflow-contract.txt"; do
  for permission in 'id-token: write' 'packages: write'; do
    grep -qFx "deploy.yml job sign permissions $permission" "$contract" \
      || fail "${contract#"$root"/} must list the permission $permission of the sign job of deploy.yml"
  done
done

echo 'OK: deploy.yml scans each image by digest with Grype and Trivy and signs those digests keyless only after both gates'
)

# --- single-image ---
# Tryb jednego obrazu w deploy.yml (single-image): eksport frontendu trafia do jara przed bootJar, a budowany, skanowany
# i wypychany jest tylko obraz backendu, z pustym tagiem frontendu. Bez wejścia deploy.yml działa jak dotąd. Bloki
# preflightu, wersji i skanu Snyka są wycinane między znacznikami i uruchamiane; docker w skanie to atrapa.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- wejście ---
input=$(sed -n '/^      single-image:$/,/^      [a-z-]*:$/p' "$workflow")
[[ -n "$input" ]] || fail 'deploy.yml must declare the single-image input'
grep -qFx '        type: boolean' <<< "$input" || fail 'single-image must be a boolean'
grep -qFx '        default: false' <<< "$input" || fail 'single-image must default to false, so a consumer of two images behaves as before'

# --- preflight: jeden obraz wymaga tych samych sekretów co dwa ---
block preflight > "$tmp/preflight.sh"
[[ -s "$tmp/preflight.sh" ]] || fail 'deploy.yml has no preflight block between its markers'
(env GPR_USER=u GPR_KEY=k NPM_GH_TOKEN=n GHCR_OWNER=o bash "$tmp/preflight.sh") > "$tmp/out" 2>&1 \
  || fail 'a single image must pass the preflight when every secret and variable is set'
(env -u NPM_GH_TOKEN GPR_USER=u GPR_KEY=k GHCR_OWNER=o bash "$tmp/preflight.sh") > "$tmp/out" 2>&1 \
  && fail 'a single image must still require NPM_GH_TOKEN: npm ci of the export reads it'

# --- wersje: bez wersji frontendu, więc frontend/package.json nie jest potrzebny ---
block versions > "$tmp/versions.sh"
[[ -s "$tmp/versions.sh" ]] || fail 'deploy.yml has no versions block between its markers'
grep -qFx '          SINGLE_IMAGE: ${{ inputs.single-image }}' <<< "$(job versions)" \
  || fail 'the versions step must pass inputs.single-image as SINGLE_IMAGE in its env:'
mkdir -p "$tmp/checkout/backend"
printf 'version=2.0.0\n' > "$tmp/checkout/backend/gradle.properties"
versions() {
  : > "$tmp/github-output"
  (cd "$tmp/checkout" && env GITHUB_OUTPUT="$tmp/github-output" GHCR_OWNER=Owner MIGRATE_TAG_SOURCE=backend \
    "$@" bash "$tmp/versions.sh") > "$tmp/out" 2>&1 || return 1
  paste -sd' ' - < "$tmp/github-output"
}
outputs=$(versions SINGLE_IMAGE=true) || fail 'with a single image the versions block must run without frontend/package.json'
[[ "$outputs" == 'owner=owner backend=2.0.0 frontend= migrate=2.0.0' ]] \
  || fail "a single image takes the backend version and leaves the frontend tag empty, got: $outputs"
mkdir -p "$tmp/checkout/frontend"
printf '{ "version": "3.0.0" }\n' > "$tmp/checkout/frontend/package.json"
outputs=$(versions SINGLE_IMAGE=false) || fail 'with two images the versions block must run'
[[ "$outputs" == 'owner=owner backend=2.0.0 frontend=3.0.0 migrate=2.0.0' ]] \
  || fail "two images take the versions of the checkout, got: $outputs"

# --- build-push: eksport przed bootJar, bez obrazu frontendu ---
single_backend_if="        if: \${{ inputs.single-image && steps.exists.outputs.backend == 'false' }}"
for name in 'Set up Node for the frontend export' 'Install the frontend for the export' 'Build the frontend export'; do
  body=$(step build-push "$name")
  [[ -n "$body" ]] || fail "build-push must have the step '$name'"
  grep -qFx -- "$single_backend_if" <<< "$body" \
    || fail "'$name' must run exactly when single-image is set and the backend image is not in GHCR yet"
done
node_step=$(step build-push 'Set up Node for the frontend export')
grep -qFx '        uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0' <<< "$node_step" \
  || fail 'the Node setup must use the setup-node pin of the other workflows'
grep -qFx '          node-version: "24"' <<< "$node_step" || fail 'the export must build on Node 24, as the other workflows do'
install_step=$(step build-push 'Install the frontend for the export')
grep -qFx '        working-directory: frontend' <<< "$install_step" || fail 'npm ci must run in frontend/'
grep -qFx '        run: npm ci --ignore-scripts' <<< "$install_step" || fail 'npm ci must skip lifecycle scripts, as in frontend-ci'
grep -qFx '          GITHUB_TOKEN: ${{ secrets.NPM_GH_TOKEN }}' <<< "$install_step" \
  || fail 'npm ci must get NPM_GH_TOKEN as GITHUB_TOKEN, which the .npmrc template reads'
build_step=$(step build-push 'Build the frontend export')
grep -qFx '        working-directory: frontend' <<< "$build_step" || fail 'the export must build in frontend/'
grep -qFx '        run: npm run build' <<< "$build_step" || fail 'the export must be npm run build'
grep -qF 'secrets.' <<< "$build_step" && fail 'npm run build runs dependency code and must get no credential'
node_line=$(line_of build-push '- name: Set up Node for the frontend export')
install_line=$(line_of build-push '- name: Install the frontend for the export')
export_line=$(line_of build-push '- name: Build the frontend export')
bootjar_line=$(line_of build-push '- name: Build bootJar')
[[ "$node_line" -lt "$install_line" && "$install_line" -lt "$export_line" && "$export_line" -lt "$bootjar_line" ]] \
  || fail 'Node, npm ci and npm run build must run in that order before bootJar, which packs the export'
grep -qFx "        if: \${{ !inputs.single-image && steps.exists.outputs.frontend == 'false' }}" \
  <<< "$(step build-push 'Build & push — frontend')" || fail 'a single image must not build the frontend image'
grep -qFx '        if: ${{ inputs.scan-images && !inputs.single-image }}' <<< "$(step build-push 'Grype scan — frontend')" \
  || fail 'a single image must not scan a frontend image'

# --- Snyk: skanuje tylko obrazy, które powstały ---
grep -qFx '      SINGLE_IMAGE: ${{ inputs.single-image }}' <<< "$(job snyk-advisory)" \
  || fail 'the Snyk job must pass inputs.single-image as SINGLE_IMAGE in its env:'
block snyk-scan > "$tmp/snyk.sh"
[[ -s "$tmp/snyk.sh" ]] || fail 'deploy.yml has no snyk-scan block between its markers'
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\n[[ "$1" == pull ]] && echo "$2" >> "$PULLS"\nexit 0\n' > "$tmp/bin/docker"
chmod +x "$tmp/bin/docker"
snyk_pulls() {
  : > "$tmp/pulls"
  (env PATH="$tmp/bin:$PATH" PULLS="$tmp/pulls" IMAGE_PREFIX=ghcr.io/o/app BACKEND_VER=2.0.0 SNYK_IMAGE=snyk "$@" \
    bash "$tmp/snyk.sh") > "$tmp/out" 2>&1 || fail 'the snyk-scan block must run'
  paste -sd' ' - < "$tmp/pulls"
}
[[ "$(snyk_pulls SINGLE_IMAGE=true FRONTEND_VER='')" == 'ghcr.io/o/app-backend:2.0.0' ]] \
  || fail 'with a single image Snyk must scan only the backend image'
[[ "$(snyk_pulls SINGLE_IMAGE=false FRONTEND_VER=3.0.0)" == 'ghcr.io/o/app-backend:2.0.0 ghcr.io/o/app-frontend:3.0.0' ]] \
  || fail 'with two images Snyk must still scan the backend and the frontend'

echo 'OK: single-image builds the export into the jar and only the backend image; two images are unchanged'
)

# --- trivy-disk ---
# Miejsce na bazy Trivy w deploy.yml: build-push buduje i wypycha obrazy, a Grype pobiera swoją bazę, zanim Trivy
# pobierze bazę Java DB (blisko 1 GB spakowana). Release Azimuth 0.1.69 padł na "no space left on device" przy jej
# pobieraniu, więc przed instalacją Trivy krok zwalnia cache buildx i bazę Grype, a na runnerze GitHuba także
# narzędzia obrazu, których job nie używa. Blok jest wycinany między znacznikami i uruchamiany z atrapami docker,
# sudo i df; na runnerze self-hosted nie dotyka niczego poza cache joba.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

toolchains=(/usr/local/lib/android /usr/share/dotnet /opt/ghc /usr/local/.ghcup /opt/hostedtoolcache/CodeQL)

# --- krok: po bramkach Grype, przed instalacją Trivy, tylko gdy obrazy są skanowane ---
disk_step=$(step build-push 'Free the disk for the Trivy databases')
[[ -n "$disk_step" ]] || fail "build-push must have the step 'Free the disk for the Trivy databases'"
grep -qFx '        if: ${{ inputs.scan-images }}' <<< "$disk_step" || fail 'the disk is freed exactly when the images are scanned'
grep -qF 'continue-on-error' <<< "$disk_step" && fail 'a failure to free the disk must show, not be hidden by continue-on-error'
disk_line=$(line_of build-push '- name: Free the disk for the Trivy databases')
grype_line=$(line_of build-push '- name: Grype scan — frontend (gate)')
trivy_line=$(line_of build-push '- name: Set up Trivy')
[[ "$grype_line" -lt "$disk_line" && "$disk_line" -lt "$trivy_line" ]] \
  || fail 'the disk is freed after the last Grype gate, which needs its database, and before Trivy is set up'

block trivy-disk > "$tmp/disk.sh"
[[ -s "$tmp/disk.sh" ]] || fail 'deploy.yml has no trivy-disk block between its markers'

mkdir -p "$tmp/bin"
for tool in docker sudo df; do
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %s "$*" >> "$CALLS"\n[[ "%s" == docker && -n "${DOCKER_FAILS:-}" ]] && exit 1\nexit 0\n' \
    "$tool" "$tool" > "$tmp/bin/$tool"
  chmod +x "$tmp/bin/$tool"
done
free_disk() {
  rm -rf "${tmp:?}/home"
  mkdir -p "$tmp/home/.cache/grype/db/6" "$tmp/home/.cache/trivy" "$tmp/home/.gradle/caches"
  : > "$tmp/calls"
  # Runner GitHuba, na którym biegnie ten test, sam ustawia RUNNER_ENVIRONMENT; ustawiają je tu tylko argumenty.
  (env -u RUNNER_ENVIRONMENT PATH="$tmp/bin:$PATH" CALLS="$tmp/calls" HOME="$tmp/home" "$@" bash "$tmp/disk.sh") \
    > "$tmp/out" 2>&1
}
calls_of() { grep "^$1 " "$tmp/calls" | cut -d' ' -f2- || true; }

# --- runner GitHuba: cache buildx, baza Grype i nieużywane narzędzia obrazu ---
free_disk RUNNER_ENVIRONMENT=github-hosted || fail 'the trivy-disk block must pass on a GitHub-hosted runner'
[[ "$(calls_of docker)" == 'buildx prune --all --force' ]] \
  || fail "the build cache of buildx must be pruned in full, got: $(calls_of docker | paste -sd'|' -)"
[[ ! -e "$tmp/home/.cache/grype" ]] || fail "Grype's database must be removed once the Grype gates have passed"
[[ -d "$tmp/home/.cache/trivy" && -d "$tmp/home/.gradle/caches" ]] || fail 'only the Grype cache is removed from the home directory'
[[ "$(calls_of sudo)" == "rm -rf ${toolchains[*]}" ]] \
  || fail "the unused toolchains of the runner image must be removed in one sudo rm -rf, got: $(calls_of sudo | paste -sd'|' -)"
[[ "$(calls_of df | paste -sd'|' -)" == '-h /|-h /' ]] || fail 'the free space must be logged before and after'
[[ "$(head -1 "$tmp/calls")" == 'df -h /' && "$(tail -1 "$tmp/calls")" == 'df -h /' ]] \
  || fail "the free space must be logged first and last, got: $(paste -sd'|' - < "$tmp/calls")"

# --- runner self-hosted: tylko cache joba, nic z systemu ---
free_disk RUNNER_ENVIRONMENT=self-hosted || fail 'the trivy-disk block must pass on a self-hosted runner'
[[ -z "$(calls_of sudo)" ]] || fail 'a self-hosted runner is not ours to strip: sudo must never run there'
[[ "$(calls_of docker)" == 'buildx prune --all --force' && ! -e "$tmp/home/.cache/grype" ]] \
  || fail 'a self-hosted runner still frees the buildx cache and the Grype database'
free_disk || fail 'the trivy-disk block must pass without RUNNER_ENVIRONMENT'
[[ -z "$(calls_of sudo)" ]] || fail 'without RUNNER_ENVIRONMENT the runner is not known to be GitHub-hosted, so sudo must not run'

# --- porażka prune nie zatrzymuje wydania, ale jest widoczna ---
free_disk RUNNER_ENVIRONMENT=github-hosted DOCKER_FAILS=1 || fail 'a failed buildx prune must not fail the release before Trivy runs'
grep -qF '::warning::' "$tmp/out" || fail 'a failed buildx prune must leave a warning in the log'
[[ -n "$(calls_of sudo)" && ! -e "$tmp/home/.cache/grype" ]] || fail 'a failed buildx prune must not stop the rest of the cleanup'

echo 'OK: deploy.yml frees the buildx cache, the Grype database and, on GitHub runners, unused toolchains before Trivy'
)
