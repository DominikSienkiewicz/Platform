#!/usr/bin/env bash
# Auto-unblock: after a prerequisite is closed, find dependent issues (via the depends-on MARKER)
# and, if ALL their prerequisites are closed as completed (not planned or a duplicate does not count),
# move them to `ready` (Projects Status + label) and append a comment listing the changes actually made
# (audit trail). The automation reads the MARKER, so it works regardless of native dependency-API
# availability; the current status comes from the status:* label. A write that fails makes the run fail.
#
#   ./scripts/roadmap-unblock.sh --closed 42 --dry-run       # preview: what closing #42 unblocks
#   ./scripts/roadmap-unblock.sh --closed 42                 # actually unblock
#   ROADMAP_PROJECT_NUMBER=12 ./scripts/roadmap-unblock.sh --closed 42
#
# Flags: --closed N (number of the closed issue; in an Action = github.event.issue.number)
#        --project N (default: $ROADMAP_PROJECT_NUMBER or detect by title)
#        --dry-run   (mutates nothing — proposes)
#
# Requires: gh (scope `project`), jq. In GitHub Actions for a user-owned repo use a PAT (scope project)
# as GH_TOKEN — the default GITHUB_TOKEN cannot write Projects v2.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Source order (required): config VALUES → canonical helpers → parser.
# shellcheck source=lib/roadmap-config.sh
source "$ROOT/scripts/lib/roadmap-config.sh"
# shellcheck source=lib/roadmap-lib.sh
source "$ROOT/scripts/lib/roadmap-lib.sh"
# roadmap_depends_contains (anchored membership) lives in the parser — without it the unblock loop dies.
# shellcheck source=lib/roadmap-parse.sh
source "$ROOT/scripts/lib/roadmap-parse.sh"

DRY_RUN=0; CLOSED=""; PROJECT="${ROADMAP_PROJECT_NUMBER:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --closed)    CLOSED="${2:-}"; shift ;;
    --closed=*)  CLOSED="${1#*=}" ;;
    --project)   PROJECT="${2:-}"; shift ;;
    --project=*) PROJECT="${1#*=}" ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done
[[ -n "$CLOSED" ]] || { echo "Pass --closed <number of the closed issue>." >&2; exit 1; }

command -v gh >/dev/null || { echo "gh CLI missing." >&2; exit 1; }
command -v jq >/dev/null || { echo "jq missing." >&2; exit 1; }

REPO="${GH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
OWNER="${GH_OWNER:-$(gh repo view --json owner -q .owner.login)}"
TITLE="$ROADMAP_PROJECT_TITLE"
say()  { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }

# ---- map of all issues with a marker: number, state, reason, rid, deps, status ----
# Separated by US (0x1F), not TAB: TAB is IFS whitespace, so `read` would collapse an empty field
# (an open issue has no close reason, a foundation no deps) and shift the columns after it.
# Fields are read independently of their order (a missing one is "": `capture` yields nothing, not an
# error), so the older layout without `status` (SkillSprintPlus)
# works too. The status comes from the status:* label, which the automation and the board own once an
# issue exists (Decision 12); the marker's status is only the fallback for an issue without that label.
LIMIT="${ROADMAP_ISSUE_LIMIT:-5000}"
ISSUES_JSON="$(gh issue list --repo "$REPO" --state all --limit "$LIMIT" --json number,state,stateReason,labels,body)"
if [[ "$(jq 'length' <<< "$ISSUES_JSON")" -ge "$LIMIT" ]]; then
  echo "::error::The repository has $LIMIT issues or more; raise ROADMAP_ISSUE_LIMIT so no marker is missed." >&2
  exit 1
fi
RAW="$(jq -r '
    .[]
    | select((.body // "") | test("roadmap-id:"))
    | (.body) as $b
    | (($b | capture("roadmap-id: (?<v>[^ |]+)").v) // "") as $rid
    | select($rid != "" and ($rid | test("^[FS]-[0-9]+$")))
    | (($b | capture("depends-on: (?<v>[^|]*)").v) // "") as $dep
    | (($b | capture("status: (?<v>[^ |]+) *-->").v) // "") as $marker_status
    | ([.labels[]?.name | select(startswith("status:")) | ltrimstr("status:")] | first // $marker_status) as $sta
    | [ (.number|tostring), .state, (.stateReason // ""), $rid, ($dep | gsub("[[:space:]]";"")), $sta ] | join("\u001f")
  ' <<< "$ISSUES_JSON")"
UNREADABLE="$(jq -r '
    [ .[] | select((.body // "") | test("roadmap-id:"))
      | select((((.body | capture("roadmap-id: (?<v>[^ |]+)").v) // "") | test("^[FS]-[0-9]+$")) | not)
      | "#\(.number)" ] | join(" ")' <<< "$ISSUES_JSON")"
if [[ -n "$UNREADABLE" ]]; then
  echo "::warning::Issues with an unreadable roadmap marker: $UNREADABLE. Run ./scripts/roadmap-to-issues.sh to rewrite their markers."
fi
[[ -n "$RAW" ]] || { say "No issues with a readable roadmap marker — nothing to do."; exit 0; }

# lookup helpers over RAW (columns: 1=number 2=state 3=reason 4=rid 5=deps 6=status)
by_rid()    { local rid="$1"; awk -F'\037' -v r="$rid" '$4==r{print; exit}' <<< "$RAW"; }
by_number() { local number="$1"; awk -F'\037' -v n="$number" '$1==n{print; exit}' <<< "$RAW"; }
col()       { local row="$1" index="$2"; cut -d $'\037' -f"$index" <<< "$row"; }

closed_row="$(by_number "$CLOSED")"
[[ -n "$closed_row" ]] || { say "Issue #$CLOSED has no roadmap marker — skipping."; exit 0; }
CLOSED_RID="$(col "$closed_row" 4)"
say "Closed prerequisite: #$CLOSED ($CLOSED_RID)"
say ""

# ---- project (to move Status on the board) ----
if [[ -z "$PROJECT" ]]; then
  PROJECT="$(gh project list --owner "$OWNER" --format json --limit 100 \
    | jq -r --arg t "$TITLE" '.projects[] | select(.title==$t) | .number' | head -1 || true)"
fi
PROJECT_NODE_ID=""; FID_STATUS=""; READY_OPT=""; ITEMS_JSON='{"items":[]}'
if [[ -n "$PROJECT" ]]; then
  PROJECT_NODE_ID="$(gh project list --owner "$OWNER" --format json --limit 100 \
    | jq -r --arg n "$PROJECT" '.projects[] | select((.number|tostring)==$n) | .id' | head -1)"
  FJSON="$(gh project field-list "$PROJECT" --owner "$OWNER" --format json --limit 100)"
  FID_STATUS="$(printf '%s' "$FJSON" | jq -r '.fields[]|select(.name=="Status").id')"
  READY_OPT="$(printf '%s' "$FJSON" | jq -r '.fields[]|select(.name=="Status").options[]|select(.name=="ready").id')"
  # A failed item list must stop the run: an empty board would read as "no board item" for every issue.
  ITEMS_JSON="$(gh project item-list "$PROJECT" --owner "$OWNER" --format json --limit "$LIMIT")"
fi
item_id_for() { local number="$1"; printf '%s' "$ITEMS_JSON" | jq -r --argjson n "$number" '.items[]? | select(.content.number==$n) | .id' | head -1; }

# ---- find dependents and check whether ALL of their prereqs are closed as completed ----
unblocked=0; failed=()
while IFS=$'\037' read -r num state _reason rid deps status; do
  roadmap_depends_contains "$deps" "$CLOSED_RID" || continue        # depends on the closed one?
  [[ "$state" = "OPEN" ]] || { note "→ $rid (#$num): skip (issue $state)"; continue; }
  case "$status" in backlog|blocked) : ;; *) note "→ $rid (#$num): skip (status '$status' outside backlog/blocked)"; continue ;; esac

  # all prerequisites closed as completed? Not planned or a duplicate is no readiness.
  all_closed=1; pending=""; done_list=""
  for dep in ${deps//,/ }; do
    drow="$(by_rid "$dep")"
    if [[ -z "$drow" ]]; then all_closed=0; pending="$pending $dep(no-issue)"; continue; fi
    dstate="$(col "$drow" 2)"; dreason="$(col "$drow" 3)"; dnum="$(col "$drow" 1)"
    if [[ "$dstate" = "CLOSED" ]] && [[ "$dreason" = "COMPLETED" ]]; then
      done_list="$done_list #$dnum($dep)"
    elif [[ "$dstate" = "CLOSED" ]]; then
      all_closed=0; pending="$pending #$dnum($dep, $(tr '[:upper:]_' '[:lower:] ' <<< "$dreason"))"
    else
      all_closed=0; pending="$pending #$dnum($dep)"
    fi
  done

  if [[ "$all_closed" != 1 ]]; then
    note "→ $rid (#$num): still blocked — waiting on:$pending"
    continue
  fi

  unblocked=$((unblocked+1))
  if [[ "$DRY_RUN" = 1 ]]; then
    note "→ $rid (#$num): UNBLOCK ✅  (closed prereqs:$done_list)"
    note "    [dry-run] label status:$status → status:ready; Projects Status → ready; audit comment"
    continue
  fi

  note "→ $rid (#$num): UNBLOCK ✅"
  applied=()
  if err="$(gh issue edit "$num" --repo "$REPO" --remove-label "status:$status" --add-label "status:ready" 2>&1 >/dev/null)"; then
    applied+=("label \`status:ready\` (was \`status:$status\`)")
  else
    note "    could not change the label: $err"; failed+=("#$num label")
  fi
  if [[ -n "$PROJECT_NODE_ID" ]] && [[ -n "$FID_STATUS" ]] && [[ -n "$READY_OPT" ]]; then
    item="$(item_id_for "$num")"
    if [[ -z "$item" ]]; then
      note "    no board item for #$num — add the issue to project #$PROJECT to track its Status"
    elif err="$(gh project item-edit --id "$item" --project-id "$PROJECT_NODE_ID" \
        --field-id "$FID_STATUS" --single-select-option-id "$READY_OPT" 2>&1 >/dev/null)"; then
      applied+=("Projects Status → \`ready\`")
    else
      note "    could not set Projects Status: $err"; failed+=("#$num board")
    fi
  else
    note "    (skipped Projects Status — no project number/field; label and comment suffice as the signal)"
  fi
  if [[ ${#applied[@]} -gt 0 ]]; then
    comment="🔓 **Auto-unblock** — all prerequisites closed as completed, moving status → \`ready\`.
- Triggered by closing #$CLOSED ($CLOSED_RID).
- Closed prerequisites:$done_list
- Changed: $(printf '%s; ' "${applied[@]}" | sed 's/; $//')."
    if ! err="$(gh issue comment "$num" --repo "$REPO" --body "$comment" 2>&1 >/dev/null)"; then
      note "    could not post the audit comment: $err"; failed+=("#$num comment")
    fi
  fi
done <<< "$RAW"

say ""
say "Done. Unblocked (or to-unblock in dry-run): $unblocked"
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "::error::Auto-unblock could not apply: ${failed[*]}. The audit comments list only the changes that were made." >&2
  exit 1
fi
