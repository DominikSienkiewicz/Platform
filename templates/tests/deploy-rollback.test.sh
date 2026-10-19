#!/usr/bin/env bash
# Rollback dispatch of deploy.yml (N-REL-12): rollback-to-backend/rollback-to-frontend replace the versions of the
# checkout with tags already in GHCR, skip build-push and still deploy; without them nothing changes. The versions
# block is cut out between its markers and run against a fake checkout.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/deploy.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" 2>/dev/null >&2; exit 1; }
awk 'index($0, "# >>> versions") { inside = 1; next } index($0, "# <<< versions") { inside = 0 } inside { sub(/^          /, ""); print }' \
  "$workflow" > "$tmp/versions.sh"
[[ -s "$tmp/versions.sh" ]] || fail 'deploy.yml has no versions block between its markers'

for input in rollback-to-backend rollback-to-frontend; do
  grep -qE "^      $input:$" "$workflow" || fail "deploy.yml must declare the $input input"
done
grep -qF "if: needs.versions.outputs.rollback != 'true'" <(sed -n '/^  build-push:/,/^    runs-on:/p' "$workflow") \
  || fail 'a rollback must skip build-push'
grep -qF "needs.build-push.result == 'skipped'" <(sed -n '/^  deploy:/,/^    runs-on:/p' "$workflow") \
  || fail 'the deploy job must run after a skipped build-push'

mkdir -p "$tmp/checkout/backend" "$tmp/checkout/frontend"
printf 'version=2.0.0\n' > "$tmp/checkout/backend/gradle.properties"
printf '{ "version": "3.0.0" }\n' > "$tmp/checkout/frontend/package.json"
outputs() {
  : > "$tmp/github-output"
  (cd "$tmp/checkout" && GITHUB_OUTPUT="$tmp/github-output" GHCR_OWNER=Owner MIGRATE_TAG_SOURCE=backend \
    ROLLBACK_BACKEND="$1" ROLLBACK_FRONTEND="$2" bash "$tmp/versions.sh") > "$tmp/out" 2>&1 || fail 'the versions block must run'
  paste -sd' ' - < "$tmp/github-output"
}
[[ "$(outputs '' '')" == "owner=owner backend=2.0.0 frontend=3.0.0 migrate=2.0.0 rollback=false" ]] || fail 'without rollback the checkout versions deploy'
[[ "$(outputs 1.9.0 '')" == "owner=owner backend=1.9.0 frontend=3.0.0 migrate=1.9.0 rollback=true" ]] || fail 'a backend rollback replaces the backend tag, and the migrate tag follows it'
[[ "$(outputs '' 2.9.0)" == "owner=owner backend=2.0.0 frontend=2.9.0 migrate=2.0.0 rollback=true" ]] || fail 'a frontend rollback replaces only the frontend tag'
echo 'OK: a rollback dispatch deploys existing tags without building, and a normal deploy is unchanged'
