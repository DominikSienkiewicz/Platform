#!/usr/bin/env bash
# roadmap-unblock.sh against the gh stub (E2-22): it reads markers in any field order and takes the
# status from the label (E2-17), counts only prerequisites closed as completed (E2-19), reports and
# fails on writes that did not happen (E2-20), and accepts the marker of the canonical issue form (J-12).
# shellcheck disable=SC2034 # rc, out and workflow are read inside the expect conditions (eval)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=fixtures/roadmap-repo.sh
source "$DIR/fixtures/roadmap-repo.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/roadmap-unblock.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; fails=$((fails+1)); }
expect() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

roadmap_repo "$TMP/repo"
marker() { printf '<!-- roadmap-id: %s | change-id: c | stream: A | depends-on: %s | status: %s -->' "$1" "$2" "$3"; }
form_marker="$(sed -n 's/^ *\(<!-- roadmap-id: .* -->\)$/\1/p' "$ROADMAP_KIT/.github/ISSUE_TEMPLATE/roadmap-item.yml" | head -1 \
  | sed 's/roadmap-id: [^ |]*/roadmap-id: S-05/; s/depends-on: [^|]*/depends-on: F-01 /')"

state() { # state DIR: the issues of the scenario, a board with items for #2 and #3 only
  local dir="$1" s01_label="$2"
  mkdir -p "$dir"
  jq -n --arg f01 "$(marker F-01 "" ready)" \
        --arg s01 '<!-- roadmap-id: S-01 | depends-on: F-01 | change-id: signin | stream: A -->' \
        --arg s02 "$(marker S-02 "F-01,F-02" blocked)" --arg f02 "$(marker F-02 "" ready)" \
        --arg s03 "$(marker S-03 F-01 blocked)" --arg s04 "$(marker S-04 F-01 backlog)" \
        --arg form "$form_marker" --arg s01label "$s01_label" '[
    {number:1, state:"CLOSED", stateReason:"COMPLETED", labels:[{name:"status:ready"}], body:("x\n"+$f01)},
    {number:2, state:"OPEN", stateReason:null, labels:[{name:$s01label}], body:("SSP layout\n"+$s01)},
    {number:3, state:"OPEN", stateReason:null, labels:[{name:"status:blocked"}], body:$s02},
    {number:4, state:"CLOSED", stateReason:"NOT_PLANNED", labels:[], body:$f02},
    {number:5, state:"OPEN", stateReason:null, labels:[{name:"status:ready"}], body:$s03},
    {number:6, state:"OPEN", stateReason:null, labels:[{name:"status:in-progress"}], body:$s04},
    {number:7, state:"OPEN", stateReason:null, labels:[], body:"roadmap-id: (marker lost)"},
    {number:8, state:"OPEN", stateReason:null, labels:[{name:"status:backlog"}], body:$form}
  ]' > "$dir/issues.json"
  echo '{"projects":[{"number":12,"id":"PVT_12","title":"SkillSprintPlus Roadmap","closed":false}]}' > "$dir/projects.json"
  echo '{"fields":[{"name":"Status","id":"FS","options":[{"name":"backlog","id":"O_B"},{"name":"ready","id":"O_R"}]}]}' > "$dir/fields.json"
  echo '{"items":[{"id":"ITEM-2","content":{"number":2}},{"id":"ITEM-3","content":{"number":3}}]}' > "$dir/items.json"
}
unblock() {
  set +e
  (cd "$TMP/repo" && ROADMAP_PROJECT_NUMBER=12 bash scripts/roadmap-unblock.sh --closed 1) > "$GH_STATE/out.txt" 2>&1
  rc=$?
  set -e
}

echo "== roadmap-unblock =="
state "$TMP/main" status:backlog
roadmap_gh "$TMP/main"
unblock
out="$(cat "$GH_STATE/out.txt")"
expect "a successful run exits 0" '[[ $rc -eq 0 ]]'
expect "(3) an SSP marker without status unblocks its dependent" \
  'grep -qxF "issue edit 2 --repo o/r --remove-label status:backlog --add-label status:ready" "$GH_LOG"'
expect "the comment lists the label and the board change it made" \
  'grep -qF "label \`status:ready\`" "$GH_STATE/comment.2" && grep -qF "Projects Status" "$GH_STATE/comment.2"'
expect "(5) a prerequisite closed as not planned keeps the dependent blocked" \
  'grep -qF "#4(F-02, not planned)" <<<"$out" && [[ ! -f "$GH_STATE/comment.3" ]]'
expect "(4) a dependent already labelled ready gets no second comment" '[[ ! -f "$GH_STATE/comment.5" ]]'
expect "a dependent in progress is left alone although its marker says backlog" \
  '[[ ! -f "$GH_STATE/comment.6" ]] && ! grep -q "^issue edit 6 " "$GH_LOG"'
expect "an unreadable marker is reported as a warning" 'grep -qF "::warning::" <<<"$out" && grep -qF "#7" <<<"$out"'
expect "(J-12) the issue form marker unblocks too" 'grep -q "^issue edit 8 .*--add-label status:ready" "$GH_LOG"'
expect "an issue without a board item is named, not blamed on the token" \
  'grep -qF "no board item for #8" <<<"$out" && ! grep -qF "token scope" <<<"$out"'
expect "the comment does not claim a board change that did not happen" '! grep -qF "Projects Status" "$GH_STATE/comment.8"'
expect "the issue list carries the close reason and labels" 'grep -q "^issue list .*stateReason" "$GH_LOG" && grep -q "^issue list .*labels" "$GH_LOG"'

state "$TMP/failing" status:backlog
roadmap_gh "$TMP/failing"
echo 1 > "$GH_STATE/issue-edit-labels.rc"
unblock
expect "(6) a failed label edit fails the run" '[[ $rc -ne 0 ]] && grep -qF "::error::" "$GH_STATE/out.txt"'
expect "(6) and the comment does not claim the label change" '! grep -qF "label \`status:ready\`" "$GH_STATE/comment.2" 2>/dev/null'

state "$TMP/listfails" status:backlog
roadmap_gh "$TMP/listfails"
echo 1 > "$GH_STATE/item-list.rc"
unblock
expect "a failed board item list fails instead of pretending the board is empty" '[[ $rc -ne 0 ]]'

workflow="$ROADMAP_KIT/../../.github/workflows/roadmap-unblock.yml"
expect "the workflow serialises runs per repository" 'grep -q "group: roadmap-unblock-\${{ github.repository }}" "$workflow"'
expect "the workflow runs only for issues closed as completed" 'grep -qF "github.event.issue.state_reason == '"'"'completed'"'"'" "$workflow"'

echo
if [[ "$fails" -eq 0 ]]; then echo "OK: PASS (all assertions green)"; else echo "FAIL ($fails assertions failed)"; exit 1; fi
