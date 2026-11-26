#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/daily-dependencies.yml"
[[ -f "$workflow" ]] || { echo 'FAIL: no daily dependency workflow' >&2; exit 1; }
grep -Eq 'cron: "[0-9]+ [0-9]+ \* \* \*"' "$workflow"
grep -q 'bash scripts/refresh-catalog-update.sh' "$workflow"
grep -q 'bash scripts/prepare-dependency-release.sh' "$workflow"
grep -q 'expectedHeadOid' "$workflow"
[[ -f "$root/.github/renovate-version" ]] || { echo 'FAIL: use one Renovate version for discovery and validation' >&2; exit 1; }
grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' "$root/.github/renovate-version"
for caller in "$workflow" "$root/.github/workflows/ci.yml"; do
  grep -qF '.github/renovate-version' "$caller"
done
release="$root/.github/workflows/dependency-release.yml"
grep -q 'github.event.pull_request.merged == true' "$release"
grep -q 'github.event.pull_request.head.repo.full_name == github.repository' "$release"
grep -q 'bash scripts/tag-dependency-release.sh' "$release"
grep -Eq 'cron: "[0-9]+ [0-9]+ \* \* \*"' "$root/.github/workflows/canon-cve-scan.yml"
grep -q 'Check the proposed dependency release' "$root/.github/workflows/ci.yml"

# Pusta lista, kilka stron PR-ów, fork, obca gałąź oraz gałąź już przygotowana lub edytowana przez właściciela.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export PATH="$tmp:$PATH" FIXTURE="$tmp" GITHUB_REPOSITORY=org/platform BOT='bot[bot]'
cat > "$tmp/gh" <<'GH'
#!/usr/bin/env bash
set -eu
endpoint="${!#}"
case "$endpoint" in
  */pulls\?*) cat "$FIXTURE/pulls";;
  */commits/aa*) echo '{"author":{"login":"bot[bot]"},"commit":{"message":"fix(deps): update Tomcat"}}';;
  */commits/bb*) echo '{"author":{"login":"bot[bot]"},"commit":{"message":"chore(deps): refresh generated dependency files"}}';;
  */commits/cc*) echo '{"author":{"login":"maintainer"},"commit":{"message":"docs: refine the release notes"}}';;
  *) exit 88;;
esac
GH
chmod +x "$tmp/gh"
select_pending() { bash "$root/scripts/pending-dependency-updates.sh"; }
if [[ ! -f "$root/scripts/pending-dependency-updates.sh" ]]; then
  echo 'FAIL: the scan must skip proposals that are already prepared or edited by the maintainer' >&2
  exit 1
fi
echo '[[]]' > "$tmp/pulls"
[[ $(select_pending) == '[]' ]]
jq -n 'def pr($branch; $who; $repo; $sha):
  {number:1,user:{login:$who},base:{ref:"main",sha:("d"*40)},head:{ref:$branch,sha:($sha*40),repo:{full_name:$repo}}};
  [[(pr("renovate/catalog";"bot[bot]";"org/platform";"a") + {labels:[{name:"security"}],body:"Fixed in CVE-2026-12345 (GHSA-2345-cfgh-jmpq)."}),pr("renovate/fork";"bot[bot]";"other/platform";"x")],
   [pr("renovate/ready";"bot[bot]";"org/platform";"b"),pr("renovate/edited";"bot[bot]";"org/platform";"c"),
    pr("renovate/spoof";"human";"org/platform";"x"),pr("main";"bot[bot]";"org/platform";"x")]]' > "$tmp/pulls"
select_pending | jq -e 'length == 1 and .[0].branch == "renovate/catalog" and .[0].head == ("a"*40) and .[0].advisories == "CVE-2026-12345 GHSA-2345-cfgh-jmpq"' >/dev/null
echo 'OK: only pending same-repository update branches need a release candidate'

# Writer publikuje tylko bajty wygenerowanych plików, na sprawdzonej wersji gałęzi.
writer=$(sed -n '/# >>> attach-generated/,/# <<< attach-generated/p' "$workflow")
[[ -n "$writer" ]] || { echo 'FAIL: the writer must commit only reviewed release paths to the expected head' >&2; exit 1; }
mkdir -p "$tmp/candidate" "$tmp/result"
cd "$tmp/candidate"
git init -q
git config user.email fixture@example.invalid
git config user.name fixture
git config commit.gpgsign false
git config core.hooksPath /dev/null
echo '# Changelog' > CHANGELOG.md
mkdir -p gradle/build-logic
echo 'old' > gradle/build-logic/settings-gradle.lockfile
echo 'original' > unrelated
git add CHANGELOG.md gradle unrelated
git commit -qm 'chore: base'
export EXPECTED_HEAD BRANCH=renovate/catalog RUNNER_TEMP="$tmp"
EXPECTED_HEAD=$(git rev-parse HEAD)
printf '# Changelog\n\nDependency release\n' > CHANGELOG.md
echo 'new' > gradle/build-logic/settings-gradle.lockfile
echo 'unexpected' > unrelated
git diff > "$tmp/result/generated.patch"
git restore -- CHANGELOG.md gradle unrelated
cat > "$tmp/gh" <<'GH'
#!/usr/bin/env bash
set -eu
[[ "$*" == 'api graphql --input - --jq .data.createCommitOnBranch.commit.oid' ]]
jq -e --arg head "$EXPECTED_HEAD" '.variables.input | .expectedHeadOid == $head and
  .branch == {repositoryNameWithOwner:"org/platform",refName:"renovate/catalog"} and
  (.fileChanges.additions | length == 2 and .[1].path == "gradle/build-logic/settings-gradle.lockfile" and
  (.[1].contents | @base64d) == "new\n" and .[0].path == "CHANGELOG.md" and
  (.[0].contents | @base64d) == "# Changelog\n\nDependency release\n")' > /dev/null
GH
bash -euo pipefail -c "$writer"
echo 'OK: GitHub receives the expected head and the exact release file contents'
