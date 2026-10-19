#!/usr/bin/env bash
# repo-settings.sh — ustawienia GitHuba Platform jako kod, a z --consumers także kanał platform-bump.yml
# w repozytoriach z scripts/consumers.txt.
#
#   scripts/repo-settings.sh --check                # wyłącznie GET: raport dryfu, exit 1 przy dryfie
#   scripts/repo-settings.sh --apply                # ustawia to, co się rozjechało (PATCH/PUT/POST, nigdy DELETE)
#   scripts/repo-settings.sh --check --consumers    # dodatkowo ustawienia konsumentów potrzebne platform-bump.yml
#
# Platform: auto-delete head branches, secret scanning i push protection, alerty Dependabota (bez jego PR-ów
# bezpieczeństwa: wersje przesuwa platform-bump), Private Vulnerability Reporting, wymóg przypinania akcji
# po SHA i rulesety z .github/rulesets/*.json (main, tagi wydań, wskaźnik v1).
# Gałęzi nie usuwa nigdy: zdalne gałęzie scalone do domyślnej wypisuje z komendą do ręcznego uruchomienia.
# Uruchamia je właściciel repo (`gh auth login` z admin), nie CI. Test: scripts/repo-settings.test.sh.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
repo="${PLATFORM_REPO:-DominikSienkiewicz/Platform}"
rulesets_dir="${RULESETS_DIR:-$root/.github/rulesets}"
consumers_file="${CONSUMERS_FILE:-$root/scripts/consumers.txt}"

usage() { echo "Usage: $0 --check|--apply [--consumers]" >&2; exit 2; }
mode=""
with_consumers=0
for arg in "$@"; do
  case "$arg" in
    --check) mode=check ;;
    --apply) mode=apply ;;
    --consumers) with_consumers=1 ;;
    *) usage ;;
  esac
done
[[ -n "$mode" ]] || usage

drift=0
failures=0

report() { printf '%-7s %s%s\n' "$1" "$2" "${3:+ — $3}"; }

# expect <name> <have> <want> <apply command…>: OK, DRIFT (--check) albo próba naprawy (--apply).
expect() {
  local name="$1" have="$2" wanted="$3"
  shift 3
  if [[ "$have" == "$wanted" ]]; then
    report OK "$name"
  elif [[ "$mode" == check ]]; then
    report DRIFT "$name" "is $have, should be $wanted"
    drift=$((drift + 1))
  elif "$@" > /dev/null; then
    report FIXED "$name" "$have -> $wanted"
  else
    report ERROR "$name" "could not set it to $wanted"
    failures=$((failures + 1))
  fi
}

get() { gh api --method GET "$@"; }
patch_repo() { gh api --method PATCH "repos/$repo" --input - <<<"$1"; }
security_status() { jq -r --arg key "$1" '.security_and_analysis[$key].status // "disabled"' <<<"$repo_json"; }

echo "== $repo"
repo_json=$(get "repos/$repo")
default_branch=$(jq -r '.default_branch' <<<"$repo_json")

expect "delete head branches on merge" "$(jq -r '.delete_branch_on_merge' <<<"$repo_json")" true \
  patch_repo '{"delete_branch_on_merge": true}'
expect "secret scanning" "$(security_status secret_scanning)" enabled \
  patch_repo '{"security_and_analysis": {"secret_scanning": {"status": "enabled"}}}'
expect "secret scanning push protection" "$(security_status secret_scanning_push_protection)" enabled \
  patch_repo '{"security_and_analysis": {"secret_scanning_push_protection": {"status": "enabled"}}}'
expect "Dependabot security update pull requests (platform-bump moves versions)" "$(security_status dependabot_security_updates)" disabled \
  patch_repo '{"security_and_analysis": {"dependabot_security_updates": {"status": "disabled"}}}'

if get "repos/$repo/vulnerability-alerts" > /dev/null 2>&1; then alerts=enabled; else alerts=disabled; fi
expect "Dependabot alerts" "$alerts" enabled gh api --method PUT "repos/$repo/vulnerability-alerts"

expect "private vulnerability reporting" "$(get "repos/$repo/private-vulnerability-reporting" --jq '.enabled')" true \
  gh api --method PUT "repos/$repo/private-vulnerability-reporting"

actions_json=$(get "repos/$repo/actions/permissions")
set_sha_pinning() {
  gh api --method PUT "repos/$repo/actions/permissions" --input - <<<"$(jq -c '{enabled, allowed_actions, sha_pinning_required: true}' <<<"$actions_json")"
}
expect "actions pinned by commit SHA" "$(jq -r '.sha_pinning_required // false' <<<"$actions_json")" true set_sha_pinning

# Ruleset porównujemy po nazwie, celu, egzekwowaniu, warunkach, typach reguł i bypassach.
ruleset_shape() { jq -cS '{name, target, enforcement, conditions, rules: ([.rules[].type] | sort), bypass_actors: (.bypass_actors // [])}'; }
existing_rulesets=$(get "repos/$repo/rulesets" --jq '.[] | [.name, (.id | tostring)] | @tsv')
for file in "$rulesets_dir"/*.json; do
  name=$(jq -r '.name' "$file")
  id=$(awk -F '\t' -v name="$name" '$1 == name { print $2; exit }' <<<"$existing_rulesets")
  wanted=$(ruleset_shape < "$file")
  if [[ -z "$id" ]]; then
    expect "ruleset $name" absent present gh api --method POST "repos/$repo/rulesets" --input "$file"
  else
    have=$(get "repos/$repo/rulesets/$id" | ruleset_shape)
    if [[ "$have" == "$wanted" ]]; then shape=matches; else shape=differs; fi
    expect "ruleset $name" "$shape" matches gh api --method PUT "repos/$repo/rulesets/$id" --input "$file"
  fi
done

while IFS= read -r branch; do
  [[ -n "$branch" && "$branch" != "$default_branch" ]] || continue
  ahead=$(get "repos/$repo/compare/$default_branch...$branch" --jq '.ahead_by')
  if [[ "$ahead" == 0 ]]; then
    report NOTE "branch $branch is merged into $default_branch" "delete it yourself: gh api --method DELETE repos/$repo/git/refs/heads/$branch"
  fi
done < <(get --paginate "repos/$repo/branches" --jq '.[].name')

if [[ "$with_consumers" -eq 1 ]]; then
  while IFS= read -r consumer; do
    echo "== $consumer"
    workflow_json=$(get "repos/$consumer/actions/permissions/workflow")
    allow_pull_requests() {
      gh api --method PUT "repos/$consumer/actions/permissions/workflow" --input - <<<"$(jq -c '{default_workflow_permissions, can_approve_pull_request_reviews: true}' <<<"$workflow_json")"
    }
    expect "GitHub Actions may create pull requests (platform-bump.yml)" \
      "$(jq -r '.can_approve_pull_request_reviews' <<<"$workflow_json")" true allow_pull_requests
    if ! get "repos/$consumer/actions/secrets/PLATFORM_BUMP_TOKEN" > /dev/null 2>&1; then
      report NOTE "no PLATFORM_BUMP_TOKEN secret" "platform-bump.yml then leaves workflow references alone and its pull request runs no CI; add a classic PAT with the repo and workflow scopes"
    fi
  done < <(grep -vE '^[[:space:]]*(#|$)' "$consumers_file")
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$failures setting(s) could not be applied; check that gh is logged in with admin on the repository." >&2
  exit 1
fi
if [[ "$drift" -gt 0 ]]; then
  echo "$drift setting(s) drifted; apply them with: scripts/repo-settings.sh --apply$([[ $with_consumers -eq 1 ]] && echo ' --consumers')" >&2
  exit 1
fi
