#!/usr/bin/env bash
# Bramka produkcyjna (G-6): setup-gh-deploy.sh tworzy environment `production` z polityką gałęzi `release`
# i trzyma w nim SSH_*, zanim cokolwiek tam zapisze; deploy.yml sprawdza SSH_* w jobie z environmentem,
# a preflight (bez environmentu, więc bez dostępu do nich) już ich nie wymaga.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; [[ -f "$work/out.txt" ]] && cat "$work/out.txt" >&2; exit 1; }

bin="$work/bin"; mkdir -p "$bin"
log="$work/gh.log"
cat > "$bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$log"
case "\$*" in
  "repo view"*) echo owner/fake-repo ;;
  "api -X PUT repos/owner/fake-repo/environments/production --input -") cat > "$work/environment.json"; exit "\${GH_ENV_STATUS:-0}" ;;
  "api repos/owner/fake-repo/environments/production/deployment-branch-policies"*) printf '%s' "\${GH_POLICIES:-}" ;;
  "api -X PUT repos/owner/fake-repo/branches/release/protection"*) cat > "$work/protection.json" ;;
  "secret list"*) printf '%s' "\${GH_REPO_SECRETS:-}" ;;
  "secret set"*) cat > /dev/null ;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\necho "fakehost ssh-ed25519 AAAAC3NzaFAKEKEY"\n' > "$bin/ssh-keyscan"
# --with-release tworzy gałąź przez git; atrapa zachowuje się jak istniejąca gałąź na origin.
# shellcheck disable=SC2016 # $1 i $@ należą do generowanej atrapy, nie do tego skryptu
printf '#!/usr/bin/env bash\n[ "$1" = ls-remote ] && exit 0\nexec %q "$@"\n' "$(command -v git)" > "$bin/git"
chmod +x "$bin/gh" "$bin/ssh-keyscan" "$bin/git"

repo="$work/repo"; mkdir -p "$repo/scripts"
cp "$root/templates/setup-gh-deploy.sh" "$repo/scripts/"
echo "SENTINEL_key" > "$work/id_deploy"
cat > "$repo/.secrets.local" <<EOF
GPR_USER=u
GPR_KEY=k
NPM_GH_TOKEN=n
SSH_HOST=1.2.3.4
SSH_USER=deploy
SSH_KEY_FILE=$work/id_deploy
GHCR_OWNER=o
DEPLOY_PATH=/opt/app
EOF
run() {
  : > "$log"
  set +e
  PATH="$bin:$PATH" GH_REPO=owner/fake-repo bash "$repo/scripts/setup-gh-deploy.sh" "$@" > "$work/out.txt" 2>&1
  rc=$?
  set -e
}

run
[[ $rc -eq 0 ]] || fail "the bootstrap must succeed (exit $rc)"
grep -q '"custom_branch_policies": true' "$work/environment.json" || fail 'the environment must allow custom branch policies only'
grep -q '"protected_branches": false' "$work/environment.json" || fail 'the environment must not open to every protected branch'
grep -qx 'api -X POST repos/owner/fake-repo/environments/production/deployment-branch-policies -f name=release -f type=branch' "$log" \
  || fail 'the release branch policy must be created'
env_line=$(grep -n -F 'environments/production --input -' "$log" | cut -d: -f1)
for n in SSH_HOST SSH_USER SSH_KEY SSH_KNOWN_HOSTS; do
  line=$(grep -n -E "^secret set $n -R owner/fake-repo --env production$" "$log" | cut -d: -f1)
  [[ -n "$line" ]] || fail "$n must be a secret of the production environment"
  [[ "$line" -gt "$env_line" ]] || fail "$n must be stored after the environment exists"
done
for n in GPR_USER GPR_KEY NPM_GH_TOKEN; do
  grep -qE "^secret set $n -R owner/fake-repo$" "$log" || fail "$n must stay a repository secret"
done
if grep -q 'gh secret delete' "$work/out.txt"; then fail 'no leftover warning without repository-level SSH secrets'; fi

GH_POLICIES=release run
[[ $rc -eq 0 ]] || fail "an existing release policy must not fail the bootstrap"
if grep -q 'deployment-branch-policies -f' "$log"; then fail 'an existing release policy must not be created twice'; fi

GH_REPO_SECRETS=$'GPR_KEY\nSSH_KEY\nSSH_HOST' run
[[ $rc -eq 0 ]] || fail "leftover repository secrets only warn"
grep -qF 'gh secret delete SSH_KEY -R owner/fake-repo' "$work/out.txt" || fail 'the warning must give the delete command for SSH_KEY'
grep -qF 'gh secret delete SSH_HOST -R owner/fake-repo' "$work/out.txt" || fail 'the warning must give the delete command for SSH_HOST'
if grep -qF 'gh secret delete GPR_KEY' "$work/out.txt"; then fail 'GPR_KEY is a repository secret by design'; fi

GH_ENV_STATUS=1 run
[[ $rc -ne 0 ]] || fail 'a missing environment must fail the bootstrap'
if grep -q -- '--env production' "$log"; then fail 'no SSH secret may be written without the environment'; fi
grep -q 'GitHub Pro, Team or Enterprise' "$work/out.txt" || fail 'the failure must name the plan requirement'

run --with-release
grep -q '"required_approving_review_count": 0' "$work/protection.json" || fail 'release protection must not require an approval a single maintainer cannot give'

# deploy.yml: preflight bez SSH_*, pierwszy krok joba deploy (environment production) je sprawdza.
workflow="$root/.github/workflows/deploy.yml"
if grep -qi 'required reviewer' "$workflow"; then fail 'deploy.yml must not promise a required reviewer'; fi
awk '/^  preflight:$/{p=1;next} /^  [a-z-]+:$/{p=0} p' "$workflow" | grep -qE 'secrets\.SSH_|[ "]SSH_(HOST|USER|KEY|KNOWN_HOSTS)( |$)' && fail 'preflight cannot see environment secrets and must not require SSH_*'
first_step=$(awk '/^  deploy:$/{d=1} d && /^    steps:$/{s=1;next} s && /^      - /{print;exit}' "$workflow")
[[ "$first_step" == "      - name: Check the SSH secrets of the production environment" ]] || fail "the deploy job must check SSH_* first, got: $first_step"
awk '/^  deploy:$/{d=1} d && /^    environment: production/{found=1} END{exit !found}' "$workflow" || fail 'the deploy job must run in the production environment'
awk '/# >>> ssh-secrets/{p=1} /# <<< ssh-secrets/{p=0} p && /^        run: \|$/{r=1;next} p && r && /^          /{sub(/^          /,"");print}' "$workflow" > "$work/check.sh"
[[ -s "$work/check.sh" ]] || fail 'the ssh-secrets block is missing'
if SSH_HOST=h SSH_USER=u SSH_KEY='' SSH_KNOWN_HOSTS=k bash "$work/check.sh" > "$work/out.txt" 2>&1; then fail 'a missing SSH_KEY must fail the deploy job'; fi
grep -q 'Missing secrets of the production environment: SSH_KEY' "$work/out.txt" || fail 'the error must name SSH_KEY'
SSH_HOST=h SSH_USER=u SSH_KEY=k SSH_KNOWN_HOSTS=k bash "$work/check.sh" > "$work/out.txt" 2>&1 || fail 'complete SSH secrets must pass'

echo 'OK: SSH secrets live in the production environment limited to release, and deploy.yml checks them there'
