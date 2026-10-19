#!/usr/bin/env bash
# roadmap-to-issues.sh and roadmap-project-setup.sh against the gh stub (E2-22): a failed or truncated
# issue snapshot stops the run before anything is created (E2-18), write errors are not swallowed
# (E2-20), a re-sync keeps an auto-unblocked status (E2-21) and ticked criteria (E2-25), --only keeps
# dependency links and --project selects by number (E2-24), native links are reconciled (E2-23), and
# titles and the document path come from the roadmap and the config (E2-16, E2-26).
# shellcheck disable=SC2034 # rc and out are read inside the expect conditions (eval)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=fixtures/roadmap-repo.sh
source "$DIR/fixtures/roadmap-repo.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/roadmap-issues-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; fails=$((fails+1)); }
expect() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

repo="$TMP/repo"
roadmap_repo "$repo"
sed -i.bak 's#^ROADMAP_DOC_PATH=.*#ROADMAP_DOC_PATH="docs/plan/roadmap.md"#' "$repo/scripts/lib/roadmap-config.sh"
mkdir -p "$repo/docs/plan"
cat > "$repo/docs/plan/roadmap.md" <<'MD'
# Roadmap: Generator

## Streams

| Stream | Theme  | Chain                    |
| ------ | ------ | ------------------------ |
| A      | Anchor | `F-01` → `S-01` → `S-02` |

## Foundations

### F-01: Baseline

- **Outcome:** the baseline exists.
- **Change ID:** baseline
- **Prerequisites:** —
- **Status:** ready

## Slices

### S-01: Sign in

- **Outcome:** a user signs in; a user signs out
- **Change ID:** account-and-signin
- **Prerequisites:** F-01
- **Status:** ready

### S-02: Follow-up

- **Outcome:** a follow-up works.
- **Change ID:** follow-up
- **Prerequisites:** S-01
- **Blockers:** waiting for S-01.
- **Status:** blocked

## Backlog Handoff

| Roadmap ID | Change ID          | Suggested issue title         | Ready for `/10x-plan` | Notes |
| ---------- | ------------------ | ----------------------------- | --------------------- | ----- |
| S-01       | account-and-signin | Sign-in with GitHub and email | yes                   |       |
MD

marker() { printf '<!-- roadmap-id: %s | change-id: c | stream: A | depends-on: %s | status: %s -->' "$1" "$2" "$3"; }
state() {
  local dir="$1"
  mkdir -p "$dir"
  jq -n --arg f01 "$(marker F-01 "" ready)" --arg s01 "$(marker S-01 F-01 ready)" \
        --arg s02 "$(marker S-02 S-01 blocked)" --arg f99 "$(marker F-99 "" "done")" '[
    {number:10, title:"F-01: baseline", state:"CLOSED", labels:[{name:"status:done"}], body:$f01},
    {number:11, title:"S-01: old title", state:"CLOSED", labels:[{name:"status:done"}],
     body:("## Acceptance criteria\n- [x] a user signs in\n- [ ] a user signs out\n" + $s01)},
    {number:12, title:"S-02: follow-up", state:"OPEN", labels:[{name:"status:ready"},{name:"type:slice"},{name:"stream:A"}], body:$s02},
    {number:13, title:"F-99: elsewhere", state:"OPEN", labels:[], body:$f99}
  ]' > "$dir/issues.json"
  echo '{"projects":[{"number":13,"id":"PVT_13","title":"SkillSprintPlus Roadmap","closed":false},{"number":12,"id":"PVT_12","title":"Other","closed":false}]}' > "$dir/projects.json"
  echo '{"fields":[{"name":"Status","id":"FS","options":[{"name":"backlog","id":"O_BACKLOG"},{"name":"ready","id":"O_READY"},{"name":"blocked","id":"O_BLOCKED"}]},{"name":"Stream","id":"FT","options":[{"name":"A","id":"O_A"}]},{"name":"Roadmap ID","id":"FR"}]}' > "$dir/fields.json"
  echo '[{"id":1011,"number":11},{"id":1013,"number":13},{"id":1099,"number":99}]' > "$dir/blocked_by.12.json"
}
generate() {
  set +e
  (cd "$repo" && bash scripts/roadmap-to-issues.sh --project 12 "$@") > "$GH_STATE/out.txt" 2>&1
  rc=$?
  set -e
  out="$(cat "$GH_STATE/out.txt")"
}

echo "== roadmap-to-issues =="
state "$TMP/sync"; roadmap_gh "$TMP/sync"
generate
expect "a re-sync of existing issues succeeds" '[[ $rc -eq 0 ]]'
expect "nothing is created when every item has an issue" '! grep -q "^issue create" "$GH_LOG"'
expect "(9) an auto-unblocked status:ready is not reverted to blocked" '! grep -q "^issue edit 12 .*--remove-label status:ready" "$GH_LOG"'
expect "(9) nor is its board Status" '! grep -q "item-edit --id ITEM-12 .*O_BLOCKED" "$GH_LOG" && grep -q "item-edit --id ITEM-12 .*O_READY" "$GH_LOG"'
expect "(9) the marker records the kept status" 'grep -qF "| status: ready -->" "$GH_STATE/body.12"'
expect "(10) a ticked criterion survives the re-sync" 'grep -qxF -- "- [x] a user signs in" "$GH_STATE/body.11" && grep -qxF -- "- [ ] a user signs out" "$GH_STATE/body.11"'
expect "(7) the title comes from the Backlog Handoff table" 'grep -qF -- "issue edit 11 --repo o/r --title S-01: Sign-in with GitHub and email" "$GH_LOG"'
expect "(E2-26) the body header names ROADMAP_DOC_PATH" 'grep -qF "docs/plan/roadmap.md" "$GH_STATE/body.12"'
expect "--project selects the board by number, not by a title of another board" \
  'grep -q "item-edit .*--project-id PVT_12" "$GH_LOG" && ! grep -q "PVT_13" "$GH_LOG"'
expect "(E2-23) an existing matching native link is not posted again" '! grep -q "^api --method POST repos/o/r/issues/12/dependencies/blocked_by" "$GH_LOG"'
expect "(E2-23) a native link to a roadmap issue outside the deps is removed" 'grep -qxF "api --method DELETE repos/o/r/issues/12/dependencies/blocked_by/1013" "$GH_LOG"'
expect "(E2-23) a link to an issue without a marker is left alone" '! grep -q "blocked_by/1099" "$GH_LOG"'

: > "$GH_LOG"
generate --force-status
expect "--force-status restores the roadmap status" 'grep -q "^issue edit 12 .*--add-label status:blocked.*--remove-label status:ready" "$GH_LOG"'

: > "$GH_LOG"; rm -f "$GH_STATE/body.12"
generate --only S-02
expect "(8) --only keeps the link to a dependency outside the filter" 'grep -qF "Blocked by #11 (S-01)" "$GH_STATE/body.12"'

generate --dry-run
expect "a dry run shows the title change" 'grep -qF "title: S-01: old title → S-01: Sign-in with GitHub and email" <<<"$out"'

state "$TMP/listfails"; roadmap_gh "$TMP/listfails"; echo 1 > "$GH_STATE/issue-list.rc"
generate
expect "(1) a failed issue list stops the run" '[[ $rc -ne 0 ]] && ! grep -q "^issue create" "$GH_LOG"'

state "$TMP/limit"; roadmap_gh "$TMP/limit"
export ROADMAP_ISSUE_LIMIT=4
generate
expect "a snapshot that reaches the limit stops the run" '[[ $rc -ne 0 ]] && grep -qF "ROADMAP_ISSUE_LIMIT" <<<"$out" && ! grep -q "^issue create" "$GH_LOG"'
unset ROADMAP_ISSUE_LIMIT

state "$TMP/labels"; roadmap_gh "$TMP/labels"; echo 1 > "$GH_STATE/label-create.rc"
generate
expect "a failed label create stops the run before any issue changes" \
  '[[ $rc -ne 0 ]] && grep -qF "HTTP 403" <<<"$out" && ! grep -q "^issue \(create\|edit\)" "$GH_LOG"'

state "$TMP/assignee"; roadmap_gh "$TMP/assignee"; echo 1 > "$GH_STATE/assignee.rc"
generate
expect "a failed assignment is counted and fails the run at the end" \
  '[[ $rc -ne 0 ]] && grep -qF "FAILED=" <<<"$out" && grep -q "could not assign" <<<"$out"'

echo "== roadmap-project-setup =="
state "$TMP/setup"; roadmap_gh "$TMP/setup"
echo '{"projects":[{"number":13,"id":"PVT_13","title":"SkillSprintPlus Roadmap","closed":true}]}' > "$GH_STATE/projects.json"
set +e
(cd "$repo" && bash scripts/roadmap-project-setup.sh) > "$GH_STATE/out.txt" 2>&1
rc=$?
set -e
expect "a closed board with the title is not duplicated" '[[ $rc -ne 0 ]] && ! grep -q "^project create" "$GH_LOG"'
expect "and the error says to reopen it" 'grep -qF "closed" "$GH_STATE/out.txt" && grep -q "^project list .*--closed" "$GH_LOG"'

echo
if [[ "$fails" -eq 0 ]]; then echo "OK: PASS (all assertions green)"; else echo "FAIL ($fails assertions failed)"; exit 1; fi
