#!/usr/bin/env bash
# render-example.sh <version> <out-dir> — publiczne repozytorium przykładowe platform-example (N-DX-3), wyrenderowane
# z kanonu wydania <version> zamiast pisane ręcznie: spring-app z frontendem Next.js przez scripts/new-consumer.sh,
# package-lock.json frontendu (frontend-ci instaluje przez npm ci) i README, które mówi, skąd przykład pochodzi.
# npm potrzebuje odczytu @dominiksienkiewicz/* z GitHub Packages: biegnie w frontend/, którego .npmrc (templates/npmrc)
# czyta GITHUB_TOKEN. Woła go job example w release.yml; testy: templates/tests/render-example.test.sh (npm podmieniony
# atrapą) i templates/tests/release-example-npm-auth.test.sh (token kroku joba example).
set -euo pipefail
usage='Usage: scripts/render-example.sh <X.Y.Z> <out-dir>'
version=${1:?$usage}
out=${2:?$usage}
root=$(cd "$(dirname "$0")/.." && pwd)

bash "$root/scripts/new-consumer.sh" --name platform-example --package pl.seniordeveloper.example --kind spring-app \
  --frontend next --platform-version "$version" --out "$out"
(cd "$out/frontend" && npm install --package-lock-only --ignore-scripts --no-audit --no-fund)
[[ -f "$out/frontend/package-lock.json" ]] || { echo "npm did not write frontend/package-lock.json" >&2; exit 1; }

cat > "$out/README.md" <<README
# platform-example

A product repository as [DominikSienkiewicz/Platform](https://github.com/DominikSienkiewicz/Platform) renders
it: \`scripts/new-consumer.sh --kind spring-app --frontend next\` at Platform v$version. The backend applies the
published convention plugins and catalog, the frontend pins every dependency at the Platform canon, and CI
calls Platform's reusable workflows at the exact tag.

Do not edit it by hand: each Platform release regenerates the whole repository. Start your own the same way:

\`\`\`bash
scripts/new-consumer.sh --name order-service --package pl.example.orders --kind spring-app --frontend next --out ../order-service
\`\`\`
README
echo "Rendered platform-example for Platform $version in $out."
