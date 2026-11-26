#!/usr/bin/env bash
set -euo pipefail
repo=${GITHUB_REPOSITORY:?}
bot=${BOT:?}

gh api --paginate --slurp "repos/$repo/pulls?state=open&base=main&per_page=100" |
  jq -c --arg repo "$repo" --arg bot "$bot" '.[][] | select(.user.login == $bot and .base.ref == "main"
      and .head.repo.full_name == $repo and (.head.ref | startswith("renovate/")))
    | {branch: .head.ref, head: .head.sha, base: .base.sha, number,
        advisories: (if any(.labels[]?; .name == "security") then
          [(.body // "") | scan("\\b(?:CVE-[0-9]{4}-[0-9]{4,}|GHSA-[23456789cfghjmpqrvwx]{4}(?:-[23456789cfghjmpqrvwx]{4}){2})\\b")]
          | unique | join(" ")
        else "" end)}' |
  while IFS= read -r proposal; do
    head=$(jq -r .head <<< "$proposal")
    commit=$(gh api "repos/$repo/commits/$head")
    if jq -e --arg bot "$bot" '.author.login == $bot and
      (.commit.message | split("\n")[0] != "chore(deps): refresh generated dependency files")' <<< "$commit" >/dev/null; then
      echo "$proposal"
    fi
  done | jq -cs '.'
