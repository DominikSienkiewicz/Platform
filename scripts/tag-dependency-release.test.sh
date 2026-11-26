#!/usr/bin/env bash
# Oznaczenie dokładnego scalenia i ponowienie po awarii dispatchu na atrapach API.
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
    if (state/'dispatch-fails').exists(): sys.exit(1)
    with (state/'dispatches').open('a') as output: output.write(tag + '\n')
elif args[:2] == ['run', 'list']:
    assert args[args.index('--commit') + 1] == os.environ['MERGED']
    print((state/'runs').read_text() if (state/'runs').exists() else '[]')
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
        (state/'refs').write_text(json.dumps([{'ref':fields['ref'], 'object':{'type':'tag','sha':fields['sha']}}]))
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
touch state/dispatch-fails
if [[ -f "$scripts/tag-dependency-release.sh" ]] && finalize "$merged" "$approved"; then fail 'dispatch failure must fail the job'; fi
[[ -s state/tag ]] || fail 'the annotated tag must survive a failed dispatch'
jq -e --arg sha "$merged" '.object.sha == $sha and .tag == "v2.0.2" and (.message | contains("### Consumer action required\n\nNone."))' state/tag >/dev/null || fail 'the tag must identify the merge and include the reviewed notes'
rm state/dispatch-fails
finalize "$merged" "$approved"
[[ $(cat state/creates) == tag && $(cat state/dispatches) == v2.0.2 ]] || fail 'retry must reuse the tag and dispatch exactly once'
printf '[{"headBranch":"v2.0.2","status":"completed","conclusion":"success"}]\n' > state/runs
finalize "$merged" "$approved"
[[ $(cat state/dispatches) == v2.0.2 ]] || fail 'a successful release must skip another dispatch'

reject() {
  if finalize "$1" "$2" > state/error 2>&1; then fail "expected refusal: $3"; fi
  grep -Fq -- "$3" state/error || fail "unexpected reason: $(cat state/error)"
  [[ $(cat state/creates) == tag && $(cat state/dispatches) == v2.0.2 ]] || fail 'an invalid candidate mutated the release'
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
[[ $(cat minor-state/dispatches) == v2.1.0 ]] || fail 'a reviewed minor release with consumer action must dispatch'
echo 'OK: tags only the reviewed merge, recovers a failed dispatch and rejects conflicting releases'
