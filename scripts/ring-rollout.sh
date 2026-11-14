#!/usr/bin/env bash
# ring-rollout.sh <X.Y.Z> [--workflow <file>] [--dry-run] — bump Platform u konsumentów pierścieniami (N-REL-1,
# Decyzja 35: lokalnie, uruchamia właściciel). Pierścień 1 (domyślnie Touchstone) dostaje bump pierwszy; reszta
# z scripts/consumers.txt dopiero, gdy CI każdego PR-a bumpu z pierścienia 1 jest zielone.
#   - bump: `gh workflow run <file> -R <repo> -f version=<X.Y.Z>`, czyli caller reusable platform-bump.yml w repo
#     konsumenta (domyślnie .github/workflows/platform-bump.yml);
#   - zielone CI: PR z gałęzi platform-bump/v<X.Y.Z> i `gh pr checks --watch` na nim; brak PR-a po
#     RING_ROLLOUT_TIMEOUT sekundach (domyślnie 900) albo czerwone checki zatrzymują rollout przed pierścieniem 2.
#   RING_ROLLOUT_FIRST — pierścień 1, owner/name po przecinku; RING_ROLLOUT_POLL — odstęp sprawdzania PR-a.
# Test: scripts/ring-rollout.test.sh (gh podmieniony).
set -euo pipefail
usage='Usage: scripts/ring-rollout.sh <X.Y.Z> [--workflow <file>] [--dry-run]'
root=$(cd "$(dirname "$0")/.." && pwd)
version="" workflow="platform-bump.yml" dry_run=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workflow) workflow=${2:?"--workflow needs a file name. $usage"}; shift ;;
    --dry-run) dry_run=true ;;
    [0-9]*.[0-9]*.[0-9]*) version=$1 ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
  shift
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "$usage" >&2; exit 2; }
first=${RING_ROLLOUT_FIRST:-DominikSienkiewicz/Touchstone}
poll=${RING_ROLLOUT_POLL:-20}
timeout=${RING_ROLLOUT_TIMEOUT:-900}

ring1=() ring2=()
IFS=',' read -r -a ring1 <<<"$first"
while IFS= read -r repo; do
  [[ -z "$repo" || "$repo" == \#* ]] && continue
  [[ ",$first," == *",$repo,"* ]] || ring2+=("$repo")
done < "$root/scripts/consumers.txt"

dispatch() {
  local repo=$1
  if [[ "$dry_run" == true ]]; then
    echo "would run $workflow in $repo for $version"
    return 0
  fi
  echo "==> $repo: $workflow for Platform $version"
  gh workflow run "$workflow" -R "$repo" -f version="$version"
}

# green <repo>: czeka na PR bumpu i jego checki; 0 = zielone.
green() {
  local repo=$1 waited=0 number=""
  [[ "$dry_run" == true ]] && { echo "would wait for the checks of platform-bump/v$version in $repo"; return 0; }
  until number=$(gh pr list -R "$repo" --head "platform-bump/v$version" --state open --json number --jq '.[0].number // empty') \
    && [[ -n "$number" ]]; do
    if [[ $waited -ge $timeout ]]; then
      echo "$repo: no pull request from platform-bump/v$version after ${timeout}s." >&2
      return 1
    fi
    sleep "$poll"
    waited=$((waited + poll))
  done
  echo "==> $repo: waiting for the checks of pull request #$number"
  gh pr checks "$number" -R "$repo" --watch --fail-fast
}

for repo in "${ring1[@]}"; do dispatch "$repo"; done
for repo in "${ring1[@]}"; do
  if ! green "$repo"; then
    echo "Ring 1 is not green in $repo, so Platform $version stops there; the other consumers were not bumped." >&2
    exit 1
  fi
done
echo "==> Ring 1 is green; bumping the other consumers."
for repo in "${ring2[@]}"; do dispatch "$repo"; done
echo "Platform $version: ring 1 green, ring 2 dispatched (${#ring2[@]} repositories); review their pull requests."
