#!/usr/bin/env bash
# upsert-issue.sh <title> <body-file> — jedno otwarte issue na tytuł: tworzy je, a kolejny raz dopisuje komentarz,
# zamiast mnożyć duplikaty. Woła go upstream-canary.yml (gh z GH_TOKEN i GH_REPO); test: templates/tests/upsert-issue.test.sh.
set -euo pipefail
title=${1:?Usage: upsert-issue.sh <title> <body-file>}
body=${2:?Usage: upsert-issue.sh <title> <body-file>}
number=$(gh issue list --state open --search "$title in:title" --limit 50 --json number,title \
  | jq -r --arg title "$title" 'map(select(.title == $title)) | .[0].number // empty')
if [[ -n "$number" ]]; then
  gh issue comment "$number" --body-file "$body"
  echo "Updated issue #$number: $title"
else
  gh issue create --title "$title" --body-file "$body"
  echo "Opened an issue: $title"
fi
