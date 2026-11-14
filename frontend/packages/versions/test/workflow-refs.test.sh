#!/usr/bin/env bash
# The workflows block of bin/platform-bump.sh moves every reference to a Platform reusable workflow,
# and the platform-ref input of deploy.yml callers, to the bumped tag (Decision 3: exact vX.Y.Z,
# moved by platform-bump). The moving @v1 becomes exact too; a SHA reference and other repositories'
# workflows stay as they are. The block is cut out between its markers and run on fixture workflows.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/bin/platform-bump.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { local message="$1"; echo "FAIL: $message"; exit 1; }

awk '
  index($0, "# platform-bump:workflows-end") { exit }
  inside { print }
  index($0, "# platform-bump:workflows") { inside = 1 }
' "$SRC" > "$WORK/workflows.sh"
[[ -s "$WORK/workflows.sh" ]] || fail "no '# platform-bump:workflows' block in $SRC"

repo="$WORK/repo"
mkdir -p "$repo/.github/workflows"
cat > "$repo/.github/workflows/ci.yml" <<'YAML'
jobs:
  backend:
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.5.30
  frontend:
    uses: DominikSienkiewicz/Platform/.github/workflows/frontend-ci.yml@v1 # moving
  pinned:
    uses: DominikSienkiewicz/Platform/.github/workflows/semgrep.yml@0123456789abcdef0123456789abcdef01234567
  other:
    uses: someone/else/.github/workflows/build.yml@v1.5.30
YAML
cat > "$repo/.github/workflows/deploy.yaml" <<'YAML'
jobs:
  deploy:
    uses: DominikSienkiewicz/Platform/.github/workflows/deploy.yml@v1.5.30
    with:
      app-name: app
      platform-ref: "v1.5.30"
YAML
(cd "$repo" && OWNER=DominikSienkiewicz TARGET=1.6.0 bash "$WORK/workflows.sh")

ci="$repo/.github/workflows/ci.yml"
grep -qx '    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.6.0' "$ci" || fail 'an exact ref must move to the target'
grep -qx '    uses: DominikSienkiewicz/Platform/.github/workflows/frontend-ci.yml@v1.6.0 # moving' "$ci" || fail '@v1 must become the exact target'
grep -q 'semgrep.yml@0123456789abcdef0123456789abcdef01234567' "$ci" || fail 'a SHA reference must stay'
grep -q 'someone/else/.github/workflows/build.yml@v1.5.30' "$ci" || fail "another repository's workflow must stay"
grep -q 'deploy.yml@v1.6.0' "$repo/.github/workflows/deploy.yaml" || fail '.yaml workflows must move too'
grep -qx '      platform-ref: v1.6.0' "$repo/.github/workflows/deploy.yaml" || fail 'platform-ref must follow the target'

empty="$WORK/empty"
mkdir -p "$empty"
(cd "$empty" && OWNER=DominikSienkiewicz TARGET=1.6.0 bash "$WORK/workflows.sh") || fail 'a repository without workflows must pass'

echo 'OK: platform-bump moves Platform workflow refs and platform-ref to the exact target'
