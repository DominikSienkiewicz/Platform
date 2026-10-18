#!/usr/bin/env bash
# repo-settings.sh na atrapie `gh`, która serwuje stan repo z plików JSON i loguje każde wywołanie:
# --check wysyła tylko GET i zgłasza dryf, --apply naprawia go bez żadnego DELETE, a scalona gałąź
# kończy się podpowiedzią, nie usunięciem.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; echo "--- output ---" >&2; cat "$work/out.txt" >&2; exit 1; }

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
method=GET path="" jq_expr="" input=""
[[ "$1" == api ]] && shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method) method="$2"; shift 2 ;;
    --jq) jq_expr="$2"; shift 2 ;;
    --input) input="$2"; shift 2 ;;
    --paginate) shift ;;
    *) path="$1"; shift ;;
  esac
done
if [[ "$method" != GET ]]; then
  if [[ "$input" == - ]]; then body=$(cat); elif [[ -n "$input" ]]; then body=$(jq -c . "$input"); else body=""; fi
  printf '%s %s %s\n' "$method" "$path" "$body" >> "$GH_LOG"
  exit 0
fi
printf 'GET %s\n' "$path" >> "$GH_LOG"
file="$GH_STATE/${path//\//__}.json"
[[ -f "$file" ]] || exit 1
if [[ -n "$jq_expr" ]]; then jq -r "$jq_expr" "$file"; else cat "$file"; fi
STUB
chmod +x "$work/bin/gh"

# state <dir> <name> <json>: jeden endpoint atrapy (ścieżka API z / zamienionym na __).
state() { mkdir -p "$1"; printf '%s\n' "$3" > "$1/${2//\//__}.json"; }
R=repos/acme/platform

drifted="$work/drifted"
state "$drifted" "$R" '{"default_branch":"main","delete_branch_on_merge":false,"security_and_analysis":{"secret_scanning":{"status":"disabled"},"secret_scanning_push_protection":{"status":"disabled"},"dependabot_security_updates":{"status":"enabled"}}}'
state "$drifted" "$R/private-vulnerability-reporting" '{"enabled":false}'
state "$drifted" "$R/actions/permissions" '{"enabled":true,"allowed_actions":"selected","sha_pinning_required":false}'
state "$drifted" "$R/rulesets" '[{"id":7,"name":"main"}]'
state "$drifted" "$R/rulesets/7" '{"name":"main","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"}],"bypass_actors":[]}'
state "$drifted" "$R/branches" '[{"name":"main"},{"name":"old-work"},{"name":"open-work"}]'
state "$drifted" "$R/compare/main...old-work" '{"ahead_by":0}'
state "$drifted" "$R/compare/main...open-work" '{"ahead_by":2}'
state "$drifted" repos/acme/consumer/actions/permissions/workflow '{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}'
printf '# consumers\nacme/consumer\n' > "$work/consumers.txt"

run() {
  : > "$work/gh.log"
  set +e
  PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GH_STATE="$1" PLATFORM_REPO=acme/platform CONSUMERS_FILE="$work/consumers.txt" \
    bash "$here/repo-settings.sh" "${@:2}" > "$work/out.txt" 2>&1
  rc=$?
  set -e
}

run "$drifted" --check --consumers
[[ $rc -eq 1 ]] || fail "--check must exit 1 on drift (got $rc)"
if grep -v '^GET ' "$work/gh.log"; then fail '--check may only send GET requests'; fi
for setting in "delete head branches on merge" "secret scanning" "secret scanning push protection" \
  "Dependabot security update pull requests" "Dependabot alerts" "private vulnerability reporting" \
  "actions pinned by commit SHA" "ruleset main" "ruleset release-tags" "ruleset v1-pointer" \
  "GitHub Actions may create pull requests"; do
  grep -q "^DRIFT   $setting" "$work/out.txt" || fail "--check must report drift of: $setting"
done
grep -qF 'branch old-work is merged into main — delete it yourself: gh api --method DELETE repos/acme/platform/git/refs/heads/old-work' "$work/out.txt" \
  || fail 'a merged branch must be named with the command that deletes it'
if grep -q 'open-work' "$work/out.txt"; then fail 'a branch with unmerged commits must not be suggested for deletion'; fi
grep -q '^NOTE    no PLATFORM_BUMP_TOKEN secret' "$work/out.txt" || fail 'a consumer without PLATFORM_BUMP_TOKEN must be noted'

run "$drifted" --apply --consumers
[[ $rc -eq 0 ]] || fail "--apply must succeed (got $rc)"
if grep -q '^DELETE ' "$work/gh.log"; then fail '--apply must never delete anything'; fi
expect_call() { grep -qxF -- "$1" "$work/gh.log" || fail "missing call: $1"; }
expect_call 'PATCH repos/acme/platform {"delete_branch_on_merge": true}'
expect_call 'PATCH repos/acme/platform {"security_and_analysis": {"secret_scanning": {"status": "enabled"}}}'
expect_call 'PATCH repos/acme/platform {"security_and_analysis": {"secret_scanning_push_protection": {"status": "enabled"}}}'
expect_call 'PATCH repos/acme/platform {"security_and_analysis": {"dependabot_security_updates": {"status": "disabled"}}}'
expect_call 'PUT repos/acme/platform/vulnerability-alerts '
expect_call 'PUT repos/acme/platform/private-vulnerability-reporting '
expect_call 'PUT repos/acme/platform/actions/permissions {"enabled":true,"allowed_actions":"selected","sha_pinning_required":true}'
expect_call "PUT repos/acme/platform/rulesets/7 $(jq -c . "$here/../.github/rulesets/main.json")"
expect_call "POST repos/acme/platform/rulesets $(jq -c . "$here/../.github/rulesets/release-tags.json")"
expect_call "POST repos/acme/platform/rulesets $(jq -c . "$here/../.github/rulesets/v1-pointer.json")"
expect_call 'PUT repos/acme/consumer/actions/permissions/workflow {"default_workflow_permissions":"read","can_approve_pull_request_reviews":true}'
grep -q '^FIXED   ruleset release-tags' "$work/out.txt" || fail '--apply must report what it fixed'

clean="$work/clean"
state "$clean" "$R" '{"default_branch":"main","delete_branch_on_merge":true,"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"},"dependabot_security_updates":{"status":"disabled"}}}'
state "$clean" "$R/vulnerability-alerts" '{}'
state "$clean" "$R/private-vulnerability-reporting" '{"enabled":true}'
state "$clean" "$R/actions/permissions" '{"enabled":true,"allowed_actions":"all","sha_pinning_required":true}'
state "$clean" "$R/rulesets" '[{"id":1,"name":"main"},{"id":2,"name":"release-tags"},{"id":3,"name":"v1-pointer"}]'
# GitHub zwraca rulesety z dodatkowymi polami (id, source, parametry reguł); porównanie ich nie widzi.
for pair in 1:main 2:release-tags 3:v1-pointer; do
  state "$clean" "$R/rulesets/${pair%%:*}" "$(jq -c '. + {id: 1, source: "acme/platform", rules: [.rules[] | . + {parameters: {}}] | reverse}' "$here/../.github/rulesets/${pair#*:}.json")"
done
state "$clean" "$R/branches" '[{"name":"main"}]'
run "$clean" --check
[[ $rc -eq 0 ]] || fail "a repository in the wanted state must pass --check (got $rc)"
if grep -q '^DRIFT' "$work/out.txt"; then fail 'no drift may be reported for the wanted state'; fi

echo 'OK: repo-settings checks with GET only, applies drift without deleting, and only suggests deleting merged branches'
