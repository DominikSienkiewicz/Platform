#!/usr/bin/env bash
# Oznaczenie dokładnego scalenia i pojedyncze zdarzenie wydania na atrapach API.
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

cd "$fixture"
git init -q -b fixture
git config user.email fixture@example.invalid
git config user.name fixture
git config commit.gpgsign false
git config core.hooksPath /dev/null
mkdir -p gradle/build-logic bin state
printf 'platformVersion=2.0.1\n' > gradle/build-logic/gradle.properties
printf '# Changelog\n' > CHANGELOG.md
git add gradle CHANGELOG.md
git commit -qm 'fix: previous release'
base=$(git rev-parse HEAD)
git tag v2.0.1
git switch -qc updates
write_release() {
  printf 'platformVersion=%s\n' "$1" > gradle/build-logic/gradle.properties
  printf '# Changelog\n\n## [%s] - 2026-11-26\n\n### Consumer action required\n\n%s\n\n### Fixed\n\n- Updated Tomcat.\n' "$1" "$2" > CHANGELOG.md
  git add gradle CHANGELOG.md
  git commit -qm 'fix(deps): update Tomcat'
}
write_release 2.0.2 None.
approved=$(git rev-parse HEAD)
git switch -q fixture
git merge -q --no-ff -m 'fix(deps): update Tomcat' updates
merged=$(git rev-parse HEAD)
export STATE="$fixture/state" PATH="$fixture/bin:$PATH"
cat > bin/gh <<'GH'
#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
state = pathlib.Path(os.environ['STATE'])
tag = os.environ.get('TAG', 'v2.0.2')
if args[:2] == ['workflow', 'run']:
    assert args[2:] == ['release.yml', '--ref', tag]
    with (state/'events').open('a') as output: output.write('workflow_dispatch ' + tag + '\n')
elif args[:2] == ['run', 'list']:
    assert args[args.index('--commit') + 1] == os.environ['MERGED']
    print('[]')  # Zdarzenie push może dotrzeć do Actions po odpowiedzi API.
elif args[0] == 'api':
    endpoint = next(a for a in args if a.startswith('repos/')).split('/git/')[1]
    fields = dict(a.split('=', 1) for a in args if '=' in a)
    if endpoint.startswith('matching-refs/'):
        print((state/'refs').read_text() if (state/'refs').exists() else '[]')
    elif endpoint == 'tags':
        assert fields['object'] == os.environ['MERGED'] and fields['type'] == 'commit'
        with (state/'creates').open('a') as output: output.write('tag\n')
        (state/'tag').write_text(json.dumps({'tag': fields['tag'], 'message': fields['message'],
                                             'object': {'type':'commit', 'sha':fields['object']}}))
        print(json.dumps({'sha':'a'*40}))
    elif endpoint == 'refs':
        assert fields == {'ref':'refs/tags/' + tag, 'sha':'a'*40}
        if (state/'ref-fails').exists() or (state/'refs').exists(): sys.exit(1)
        (state/'refs').write_text(json.dumps([{'ref':fields['ref'], 'object':{'type':'tag','sha':fields['sha']}}]))
        with (state/'events').open('a') as output: output.write('push ' + tag + '\n')
        if (state/'response-lost').exists(): sys.exit(1)
        print('{}')
    elif endpoint == 'tags/' + 'a'*40:
        print((state/'tag').read_text())
    else:
        sys.exit('unexpected API path ' + endpoint)
else:
    sys.exit('unexpected command ' + str(args))
GH
chmod +x bin/gh
export MERGED="$merged"
finalize() { bash "$scripts/tag-dependency-release.sh" "$1" "$2"; }
finalize "$merged" "$approved"
[[ $(cat state/events) == 'push v2.0.2' ]] || fail 'the tag push must be the only release trigger, even before its run is visible'
jq -e --arg sha "$merged" '.object.sha == $sha and .tag == "v2.0.2" and (.message | contains("### Consumer action required\n\nNone."))' state/tag >/dev/null || fail 'the tag must identify the merge and include the reviewed notes'
finalize "$merged" "$approved"
[[ $(cat state/creates) == tag && $(cat state/events) == 'push v2.0.2' ]] || fail 'retry must verify the existing tag without another release'

workflow="$scripts/../.github/workflows/dependency-release.yml"
grep -Fq 'permission-contents: write' "$workflow" || fail 'the installation token must be allowed to create the tag'
grep -Fq "GH_TOKEN: \${{ steps.app.outputs.token }}" "$workflow" || fail 'the tag push must authenticate as the dependency App'
grep -Fq 'tags: ["v*.*.*"]' "$scripts/../.github/workflows/release.yml" || fail 'version tag pushes must trigger release.yml'

mkdir recovery
touch recovery/ref-fails
if STATE="$fixture/recovery" finalize "$merged" "$approved"; then fail 'a failed tag creation without a matching ref must fail'; fi
[[ ! -e recovery/events ]] || fail 'a failed ref creation started a release'
rm recovery/ref-fails
touch recovery/response-lost
STATE="$fixture/recovery" finalize "$merged" "$approved" || fail 'verify the matching tag if its creation response was lost'
STATE="$fixture/recovery" finalize "$merged" "$approved"
[[ $(cat recovery/events) == 'push v2.0.2' ]] || fail 'recovering a ref creation must emit exactly one tag push'

reject() {
  if finalize "$1" "$2" > state/error 2>&1; then fail "expected refusal: $3"; fi
  grep -Fq -- "$3" state/error || fail "unexpected reason: $(cat state/error)"
  [[ $(cat state/creates) == tag && $(cat state/events) == 'push v2.0.2' ]] || fail 'an invalid candidate mutated the release'
}
reject "$approved" "$approved" 'checkout does not match'
reject "$merged" "$base" 'merged tree differs'
jq '.object.sha = "deadbeef"' state/tag > state/conflict && mv state/conflict state/tag
reject "$merged" "$approved" 'differs from the reviewed commit or release notes'
jq '.[0].object.type = "commit"' state/refs > state/light && mv state/light state/refs
reject "$merged" "$approved" 'is not an annotated tag'

git switch -q --detach "$base"
write_release 2.0.4 None.
invalid=$(git rev-parse HEAD)
reject "$invalid" "$invalid" 'Expected the next patch'
git switch -q --detach "$base"
write_release 2.0.2 'Reconfigure the servlet.'
invalid=$(git rev-parse HEAD)
reject "$invalid" "$invalid" 'with consumer action must be a minor'
git switch -q --detach "$merged"
git tag -f v2.0.1 "$approved" >/dev/null
reject "$merged" "$approved" 'must precede the update on main'
git tag -f v2.0.1 "$base" >/dev/null
git switch -q --detach "$base"
write_release 2.1.0 'Reconfigure the servlet.'
minor=$(git rev-parse HEAD)
mkdir minor-state
STATE="$fixture/minor-state" TAG=v2.1.0 MERGED="$minor" finalize "$minor" "$minor"
[[ $(cat minor-state/events) == 'push v2.1.0' ]] || fail 'a reviewed minor release with consumer action must trigger one run'
echo 'OK: one tag push releases the reviewed merge, including after a retry; conflicting tags are rejected'
