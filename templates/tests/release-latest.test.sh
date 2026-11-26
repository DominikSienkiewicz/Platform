#!/usr/bin/env bash
# Wydanie bez argumentów z pełnej historii, wyłącznie do lokalnego bare origin.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset ASSUME_YES
fail() { echo "FAIL: $*" >&2; exit 1; }

git init -q --bare -b main "$tmp/origin.git"
git init -q -b main "$tmp/work"
cd "$tmp/work"
git config user.name 'Release Test'
git config user.email 'release-test@example.invalid'
git remote add origin "$tmp/origin.git"
mkdir -p gradle/build-logic frontend/packages/example scripts docs
cp "$root/release.sh" .
cp "$root/scripts/"{changelog-section,release-notes}.sh scripts/
printf 'platformVersion=2.0.1\n' > gradle/build-logic/gradle.properties
printf '{\n  "version": "2.0.1"\n}\n' > frontend/packages/example/package.json
printf '## [Unreleased]\n\n## [2.0.1] - 2026-11-01\n\n### Consumer action required\n\nNone.\n' > CHANGELOG.md
cat > docs/compatibility.md <<'MATRIX'
<!-- compatibility-matrix -->
| Platform | Released | Java |
|---|---|---|
| Unreleased | Pending | 27 |
| 2.0.1 | 2026-11-01 | 26 |
MATRIX
git add .
git commit -qm 'chore: initialize release fixture'
git tag -a v2.0.1 -m 'Platform 2.0.1'
git switch -qc update
git commit --allow-empty -qm 'fix: upgrade the test runner' -m 'Consumer-Action: Review the test configuration.'
git switch -q main
git merge -q --no-ff update -m 'Merge pull request #15 from example/update' -m 'fix(deps): update dependencies'
git push -qu origin main v2.0.1

before=$(git rev-parse HEAD)
if ! bash release.sh <<< n > "$tmp/plan" 2>&1; then
  cat "$tmp/plan" >&2
  fail 'the zero-argument release should present a plan'
fi
grep -Fq 'Plan: 2.0.1 -> 2.1.0' "$tmp/plan" || fail 'the merged action requires a minor'
grep -Fq -- '- update dependencies (' "$tmp/plan" || fail 'use the conventional title from the GitHub merge'
grep -Fq 'Review the test configuration.' "$tmp/plan" || fail 'the plan must show the action'
[[ $(git rev-parse HEAD) == "$before" && -z $(git status --porcelain) ]] || fail 'declining must preserve the checkout'

# Zmiana indeksu w drugim terminalu, gdy skrypt czeka na odpowiedź.
python3 - <<'PROMPT'
from pathlib import Path
import subprocess

with subprocess.Popen(["bash", "release.sh"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                      stderr=subprocess.STDOUT, text=True) as release:
    for line in release.stdout:
        if line.startswith("Plan:"):
            break
    else:
        raise SystemExit("release did not show its plan")
    Path("other-work").write_text("in progress\n")
    subprocess.run(["git", "add", "other-work"], check=True)
    release.communicate("y\n", timeout=10)
    if release.returncode == 0:
        raise SystemExit("release must reject a change staged during confirmation")
PROMPT
[[ $(git rev-parse HEAD) == "$before" && $(git diff --cached --name-only) == other-work ]] || fail 'preserve the staged edit'
git restore --staged -- other-work
rm other-work

release() { ASSUME_YES=1 bash release.sh > "$tmp/run" 2>&1 || { cat "$tmp/run" >&2; return 1; }; }
remote_commit() { git --git-dir="$tmp/origin.git" rev-parse "$1^{commit}"; }
release
released=$(git rev-parse HEAD)
[[ $(remote_commit main) == "$released" && $(remote_commit refs/tags/v2.1.0) == "$released" ]] || fail 'both remote refs must identify the release'
[[ $(git cat-file -t refs/tags/v2.1.0) == tag ]] || fail 'the version tag must be annotated'
grep -qx 'platformVersion=2.1.0' gradle/build-logic/gradle.properties
grep -Fq '"version": "2.1.0"' frontend/packages/example/package.json
grep -Fq 'Review the test configuration.' CHANGELOG.md
grep -Eq '^\| 2\.1\.0 \| [0-9]{4}-[0-9]{2}-[0-9]{2} \| 27 \|$' docs/compatibility.md || fail 'the pending matrix row must identify the release'
release
[[ $(git rev-parse HEAD) == "$released" && $(git tag -l | wc -l) -eq 2 ]] || fail 'rerunning must keep the same release'

git commit --allow-empty -qm 'feat: add an optional report'
git push -q origin main
release
[[ $(remote_commit refs/tags/v2.1.1) == "$(git rev-parse HEAD)" ]] || fail 'an optional feature must produce a patch'
git diff --exit-code v2.1.0 HEAD -- docs/compatibility.md || fail 'published matrix rows must stay unchanged'

sed -i.bak '/^## \[Unreleased\]/a\
\
## [2.2.0] - 2026-11-26\
\
### Consumer action required\
\
- Set the region in the workflow.
' CHANGELOG.md
rm CHANGELOG.md.bak
git add CHANGELOG.md
git commit -qm 'docs: prepare manual release notes'
git push -q origin main
release
[[ $(remote_commit refs/tags/v2.2.0) == "$(git rev-parse HEAD)" ]] || fail 'honor the prepared minor with its own notes'
git diff --exit-code HEAD^ HEAD -- CHANGELOG.md || fail 'hand-written release notes must stay unchanged'
git commit --allow-empty -qm 'fix: prepare another release'
git push -q origin main
before=$(remote_commit main)
cat > "$tmp/origin.git/hooks/update" <<'HOOK'
#!/usr/bin/env bash
[[ $1 != refs/tags/v2.2.1 ]]
HOOK
chmod +x "$tmp/origin.git/hooks/update"
if ASSUME_YES=1 bash release.sh > "$tmp/rejected" 2>&1; then fail 'a rejected tag must fail publication'; fi
[[ $(remote_commit main) == "$before" ]] || fail 'a rejected tag must leave remote main unchanged'
if git --git-dir="$tmp/origin.git" show-ref --verify --quiet refs/tags/v2.2.1; then fail 'the rejected release must have no remote tag'; fi
release_commit=$(git rev-parse 'v2.2.1^{commit}')
grep -Fq "git push --atomic origin $release_commit:refs/heads/main refs/tags/v2.2.1" "$tmp/rejected" || fail 'show how to retry the prepared release'
rm "$tmp/origin.git/hooks/update"
git push -q --atomic origin "$release_commit:refs/heads/main" refs/tags/v2.2.1
release
[[ $(remote_commit refs/tags/v2.2.1) == "$(git rev-parse HEAD)" ]] || fail 'retry must publish the same release'
git switch -qc region
git commit --allow-empty -qm 'feat: add deployment regions'
git switch -q main
git merge -q --no-ff region -m 'Merge pull request #16 from example/region' -m 'feat(ci)!: require the region input'
git push -q origin main
release
[[ $(remote_commit refs/tags/v2.3.0) == "$(git rev-parse HEAD)" ]] || fail 'a breaking PR title must select a minor'
grep -Fq -- '- Breaking change: require the region input' CHANGELOG.md || fail 'the PR title must explain consumer action'
echo 'OK: latest release, confirmation, notes, version files, matrix and idempotent rerun'
