#!/usr/bin/env bash
# Statyczne asercje templates/Dockerfile.frontend: npm ci z --ignore-scripts jak w frontend-ci, jeden id sekretu
# tylko na kroku npm ci, Node major każdego etapu = frontend/.nvmrc, nie-root w runnerze i układ standalone.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
dockerfile="$root/templates/Dockerfile.frontend"
fail() { echo "FAIL: $*" >&2; exit 1; }

node_major=$(tr -d '[:space:]v' < "$root/frontend/.nvmrc" | cut -d. -f1)
majors=$(sed -n -E 's/^FROM[[:space:]]+node:([0-9]+)[^[:space:]]*.*/\1/p' "$dockerfile" | sort -u)
[[ "$majors" == "$node_major" ]] || fail "every stage must run Node $node_major (frontend/.nvmrc), got: $majors"
[[ $(grep -c '^FROM ' "$dockerfile") -eq 3 ]] || fail 'expected the deps, builder and runner stages'

ci_line=$(grep -E '^RUN .*npm ci' "$dockerfile") || fail 'the deps stage must run npm ci'
grep -qF -- '--ignore-scripts' <<<"$ci_line" || fail 'npm ci must run with --ignore-scripts, as frontend-ci does'
ids=$(grep -oE 'type=secret,id=[a-z_]+' "$dockerfile" | sort -u)
[[ "$ids" == 'type=secret,id=github_token' ]] || fail "exactly one secret id, github_token, got: $ids"
if [[ $(grep -c 'type=secret' "$dockerfile") -ne 1 ]] || ! grep -qF 'type=secret' <<<"$ci_line"; then
  fail 'the secret may only reach the npm ci step'
fi
if grep -qE '^(ARG|ENV) .*(TOKEN|token)' "$dockerfile"; then fail 'the token must never be an ARG or ENV, which would bake it into a layer'; fi

runner=$(awk '/^FROM .* AS runner$/ { inside = 1 } inside' "$dockerfile")
grep -qE '^USER nextjs$' <<<"$runner" || fail 'the runner must drop to a non-root user'
for copy in '/app/.next/standalone ./' '/app/.next/static ./.next/static' '/app/public ./public'; do
  grep -qF -- "$copy" <<<"$runner" || fail "the runner must copy $copy"
done
grep -qxF 'CMD ["node", "server.js"]' "$dockerfile" || fail 'the runner starts the standalone server.js'
grep -qF 'output: "standalone"' "$root/templates/frontend/next.config.ts" || fail 'the canonical next.config.ts must emit standalone output'

echo 'OK: templates/Dockerfile.frontend installs like CI, keeps the token out of layers and runs standalone as non-root'
