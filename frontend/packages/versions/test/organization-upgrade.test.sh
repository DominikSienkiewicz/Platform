#!/usr/bin/env bash
# Migracja współrzędnych istniejącego konsumenta i wykonanie narzędzi z nowego scope.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=bump-fixture.sh
source "$(dirname "$0")/bump-fixture.sh"
here=$(cd "$(dirname "$0")/.." && pwd)
org=SeniorDeveloper-pl-Dominik-Sienkiewicz
scope=@seniordeveloper-pl-dominik-sienkiewicz
old=@dominiksienkiewicz
extra_files() {
  printf 'platformVersion=1.13.1\n' > "$1/gradle.properties"
  printf 'maven { url = uri("https://maven.pkg.github.com/DominikSienkiewicz/Platform") }\n' > "$1/settings.gradle.kts"
  printf '%s\n' "@dominiksienkiewicz:registry=https://npm.pkg.github.com" '//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}' > "$1/frontend/.npmrc"
  printf '%s\n' "import base from '@dominiksienkiewicz/eslint-config/next'" "import app from '@dominiksienkiewicz/app-only'" > "$1/frontend/eslint.config.mjs"
  printf 'extends: github>DominikSienkiewicz/Platform\n' > "$1/renovate.json5"
  cat >> "$1/.github/workflows/ci.yml" <<'YAML'
  deploy:
    uses: DominikSienkiewicz/Platform/.github/workflows/promote.yml@v1.13.1
    with:
      infra-repository: 'DominikSienkiewicz/example-gitops' # transferred with the application
  custom:
    uses: example/local-ci/.github/workflows/deploy.yml@v1
    with:
      infra-repository: DominikSienkiewicz/example-gitops
YAML
  printf '%s\n' '# local-config-preview-marker' >> "$1/frontend/eslint.config.mjs"
}
# Nowy stub zachowuje odwołanie do starego node_modules po to, by rozpoznać instalację 1.x.
with_stub() {
  extra_files "$1"
  python3 - "$1/frontend/package.json" <<'PYTHON'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
manifest = json.loads(p.read_text())
manifest["optionalDependencies"] = {"@dominiksienkiewicz/tsconfig": "1.13.1"}
manifest["dependencies"] = {"@seniordeveloper-pl-dominik-sienkiewicz/example-app": "3.1.0"}
p.write_text(json.dumps(manifest, indent=2) + "\n")
PYTHON
  mkdir -p "$1/scripts"
  cp "$here/../../../templates/platform-bump.sh" "$1/scripts/platform-bump.sh"
}
FIXTURE_EXTRA=with_stub
dir=$(consumer transferred 1.13.1)
test_upgrade() {
  grep -qF '"@seniordeveloper-pl-dominik-sienkiewicz/versions": "2.0.0"' "$dir/frontend/package.json" || fail 'the old versions dependency must move to the organization at 2.0.0'
  grep -qF '"@seniordeveloper-pl-dominik-sienkiewicz/tsconfig": "2.0.0"' "$dir/frontend/package.json" || fail 'optional Platform dependencies must move to the same release'
  grep -qF '"@seniordeveloper-pl-dominik-sienkiewicz/example-app": "3.1.0"' "$dir/frontend/package.json" || fail 'other organization packages must retain their own versions'
  grep -qF "$org/Platform/.github/workflows/frontend-ci.yml@v2.0.0" "$dir/.github/workflows/ci.yml" || fail 'the consumer workflow must resolve through the organization'
  grep -qF "infra-repository: '$org/example-gitops' # transferred with the application" "$dir/.github/workflows/ci.yml" || fail 'the explicit promotion override must move with the GitOps repository'
  grep -qF 'infra-repository: DominikSienkiewicz/example-gitops' "$dir/.github/workflows/ci.yml" || fail 'application-owned workflow inputs must keep their values'
  grep -qF "maven.pkg.github.com/${scope#@}/Platform" "$dir/settings.gradle.kts" || fail 'a standalone Gradle settings file must use the transferred repository'
  grep -qF "$scope:registry=https://npm.pkg.github.com" "$dir/frontend/.npmrc" || fail 'npm must resolve the new scope'
  grep -qF "$scope/eslint-config/next" "$dir/frontend/eslint.config.mjs" || fail 'scoped subpath imports must follow the package'
  grep -qF "$old/app-only" "$dir/frontend/eslint.config.mjs" || fail 'application-owned dependencies must keep their identities'
  grep -qF "github>$org/Platform" "$dir/renovate.json5" || fail 'the shared preset must move with its repo'
}
bump "$dir" --dry-run 2.0.0
[[ $rc -eq 0 && -z "$(git -C "$dir" status --porcelain)" ]] || fail 'the preview must restore all candidate files'
grep -qF 'frontend/eslint.config.mjs' "$dir.log" || fail 'the preview must identify changed consumer files'
if grep -qF 'local-config-preview-marker' "$dir.log"; then fail 'the migration preview must not print adjacent configuration lines'; fi
bump "$dir" 2.0.0
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail 'the migration must complete'; }
test_upgrade
cmp "$here/../../../templates/platform-bump.sh" "$dir/scripts/platform-bump.sh" || fail 'the verified canonical bootstrap must remain byte-identical'
git -C "$dir" add -A
git -C "$dir" -c user.name=t -c user.email=t@example.test commit -qm upgrade
bump "$dir" 2.0.0
[[ $rc -eq 0 && -z "$(git -C "$dir" status --porcelain)" ]] || fail 'a second bump must leave an organization-scoped consumer unchanged'
grep -qF "npm pack $scope/versions@2.0.0" "$FAKE_NPM_LOG" || fail 'the v2 canon must come from the organization'
grep -qF -- "--signer-workflow $org/Platform/.github/workflows/release.yml" "$FAKE_GH_LOG" || fail 'the v2 signer must be the release workflow in the organization'
FIXTURE_EXTRA=''
packed=$(consumer compact-pins 1.13.1)
printf '{"dependencies":{"%s/example-app":"3.1.0","%s/versions":"1.13.1"}}\n' "$old" "$old" > "$packed/frontend/package.json"
git -C "$packed" commit -qam compact
FAKE_VERSIONS='[{"name":"1.13.1"},{"name":"2.0.0"},{"name":"3.1.0"}]' bump "$packed" --print-target
[[ $rc -eq 0 && "$(tail -1 "$packed.log")" == 1.13.1 ]] || fail 'compact JSON and unrelated scoped packages must not cause an automatic major upgrade'
FAKE_VERSIONS='[{"name":"2.0.0"}]' FAKE_VERSIONS_NEXT='[{"name":"1.13.1"}]' bump "$packed" --print-target
[[ $rc -eq 0 && "$(tail -1 "$packed.log")" == 1.13.1 ]] || fail 'the old line must remain discoverable on subsequent Packages pages'
conflict=$(consumer conflicting 1.13.1)
printf '{"dependencies":{"%s/versions":"1.13.1","%s/versions":"2.0.0"}}\n' "$old" "$scope" > "$conflict/frontend/package.json"
git -C "$conflict" add frontend/package.json
git -C "$conflict" -c user.name=t -c user.email=t@example.test commit -qm partial
bump "$conflict" 2.0.0
[[ $rc -ne 0 && -z "$(git -C "$conflict" status --porcelain)" ]] || fail 'colliding package coordinates must fail without changing the partial migration'
# Kontrakt zagnieżdżonego reusable workflow sprawdzamy pod adresem organizacji.
printf 'jobs:\n  build:\n    uses: %s/Platform/.github/workflows/backend-ci.yml@v2.0.0\n    permissions: {}\n' "$org" > "$dir/.github/workflows/ci.yml"
if python3 "$here/bin/workflows-check.py" --ref v2.0.0 --root "$dir" > "$fixture_work/check"; then fail 'the new workflow owner must go through permission validation'; fi
grep -q 'needs packages: read' "$fixture_work/check" || fail 'the missing workflow permission must be reported'
echo 'OK: Platform 2.0.0 migrates the old coordinates and recognizes the new coordinates'
