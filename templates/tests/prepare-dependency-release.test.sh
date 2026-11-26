#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git init -q -b fixture "$fixture"
cd "$fixture"
git config user.name 'Dependency test'
git config user.email test@example.invalid
mkdir -p scripts gradle/{build-logic,catalog} templates/jvm/app frontend/packages/lint
cp "$root"/scripts/{release-notes,changelog-section}.sh scripts/
if [[ -f "$root/scripts/prepare-dependency-release.sh" ]]; then
  cp "$root/scripts/prepare-dependency-release.sh" scripts/
fi
printf '# Changelog\n\n## [Unreleased]\n\n## [2.1.3] - 2026-11-01\n\n### Consumer action required\n\nNone.\n' > CHANGELOG.md
for f in gradle/{build-logic,catalog}/gradle.properties templates/jvm/app/gradle.properties; do
  printf 'platformVersion=2.1.3\n' > "$f"
done
printf '{\n  "name": "fixture",\n  "version": "2.1.3",\n  "dependencies": {"x": "1.0.0"}\n}\n' > frontend/packages/lint/package.json
git add .
git commit -qm 'chore: seed the fixture'
git tag -a v2.1.3 -m 'Platform 2.1.3'
git commit --allow-empty -qm 'fix: preserve an unreleased fix'
base=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$base"
git switch -qc renovate/example
sed -i.bak 's/"x": "1.0.0"/"x": "1.0.1"/' frontend/packages/lint/package.json
rm frontend/packages/lint/package.json.bak
git commit -qam 'fix(deps): update the example package'
head=$(git rev-parse HEAD)
fail() { echo "FAIL: $*" >&2; exit 1; }

if [[ -f scripts/prepare-dependency-release.sh ]]; then
  bash scripts/prepare-dependency-release.sh "$base"
fi
grep -qx 'platformVersion=2.1.4' gradle/build-logic/gradle.properties ||
  fail 'a compatible dependency update must prepare the next Platform patch'
for f in gradle/catalog/gradle.properties templates/jvm/app/gradle.properties; do
  grep -qx 'platformVersion=2.1.4' "$f" || fail "wrong version in $f"
done
grep -q '"version": "2.1.4"' frontend/packages/lint/package.json
grep -q '"x": "1.0.1"' frontend/packages/lint/package.json
grep -q 'preserve an unreleased fix' CHANGELOG.md
grep -q 'update the example package' CHANGELOG.md
[[ $(bash scripts/changelog-section.sh --consumer-action 2.1.4) == None. ]]
[[ $(git rev-parse HEAD) == "$head" && $(git tag -l) == v2.1.3 ]]
git diff --cached --quiet
diff_before=$(git diff)
[[ $(bash scripts/prepare-dependency-release.sh "$base") == 2.1.4 ]]
[[ $(git diff) == "$diff_before" ]] || fail 'retry must reproduce the same preparation'

git add -A
git commit -qm 'chore(deps): refresh generated dependency files'
bash scripts/prepare-dependency-release.sh "$base" >/dev/null
git diff --exit-code

git switch -qc manual-review "$base"
git commit --allow-empty -qm 'feat!: raise the minimum JDK' -m 'Consumer-Action: Install a newer runtime.'
breaking=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$breaking"
git commit --allow-empty -qm 'fix(deps): update the example package'
[[ $(bash scripts/prepare-dependency-release.sh "$breaking") == 2.2.0 ]] || fail 'consumer action requires the next minor'
grep -q 'Install a newer runtime' CHANGELOG.md
git restore .
if bash scripts/prepare-dependency-release.sh "$base"; then fail 'a stale base must be refused'; fi
git diff --exit-code

git switch -qc pending-notes "$base"
sed -i.bak '/^## \[Unreleased\]/a\
Manually drafted notes.
' CHANGELOG.md
rm CHANGELOG.md.bak
git commit -qam 'docs: draft the next release'
pending=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$pending"
git commit --allow-empty -qm 'fix(deps): update the example package'
if bash scripts/prepare-dependency-release.sh "$pending"; then fail 'pending notes must be preserved for review'; fi
git diff --exit-code

git switch -qc upstream-major "$head"
git update-ref refs/remotes/origin/main "$base"
[[ $(bash scripts/prepare-dependency-release.sh "$base" --review-major) == 2.2.0 ]] || fail 'an upstream major needs migration review'
bash scripts/changelog-section.sh --consumer-action 2.2.0 | grep -q 'update the example package'
git restore .
git switch -q renovate/example
git update-ref refs/remotes/origin/main "$base"
git tag v2.1.4
if bash scripts/prepare-dependency-release.sh "$base"; then fail 'an existing tag must be refused'; fi
git diff --exit-code
echo 'OK: a dependency patch is reproducible, includes all unreleased changes and respects the release contract'
