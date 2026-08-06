#!/usr/bin/env bash
# Auto-unblock: after a prerequisite is closed, find dependent issues (via the depends-on MARKER)
# and, if ALL their prerequisites are closed, move them to `ready` (Projects Status + label) and
# append a rationale comment (audit trail). The automation reads the MARKER, so it works regardless
# of native dependency-API availability.
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

# ---- map of all issues with a marker: rid \t number \t state \t deps \t status ----
RAW="$(gh issue list --repo "$REPO" --state all --limit 200 --json number,state,body \
  | jq -r '
      .[]
      | select((.body // "") | test("roadmap-id:"))
      | (.body) as $b
      | ($b | capture("roadmap-id: (?<rid>[^ |]+)[^\n]*?depends-on: (?<dep>[^|]*)\\|[^\n]*?status: (?<sta>[^ ]+) -->")) as $m
      | [ (.number|tostring), .state, $m.rid, ($m.dep | gsub("[[:space:]]";"")), $m.sta ] | @tsv
  ')"
[[ -n "$RAW" ]] || { say "No issues with a roadmap marker — nothing to do."; exit 0; }

# lookup helpers over RAW (columns: 1=number 2=state 3=rid 4=deps 5=status)
by_rid()    { awk -F'\t' -v r="$1" '$3==r{print; exit}' <<< "$RAW"; }
by_number() { awk -F'\t' -v n="$1" '$1==n{print; exit}' <<< "$RAW"; }
col()       { cut -f"$2" <<< "$1"; }

closed_row="$(by_number "$CLOSED")"
[[ -n "$closed_row" ]] || { say "Issue #$CLOSED has no roadmap marker — skipping."; exit 0; }
CLOSED_RID="$(col "$closed_row" 3)"
say "Closed prerequisite: #$CLOSED ($CLOSED_RID)"
say ""

# ---- project (to move Status on the board) ----
if [[ -z "$PROJECT" ]]; then
  PROJECT="$(gh project list --owner "$OWNER" --format json --limit 100 \
    | jq -r --arg t "$TITLE" '.projects[] | select(.title==$t) | .number' | head -1 || true)"
fi
PROJECT_NODE_ID=""; FID_STATUS=""; READY_OPT=""; ITEMS_JSON="[]"
if [[ -n "$PROJECT" ]]; then
  PROJECT_NODE_ID="$(gh project list --owner "$OWNER" --format json --limit 100 \
    | jq -r --arg n "$PROJECT" '.projects[] | select((.number|tostring)==$n) | .id' | head -1)"
  FJSON="$(gh project field-list "$PROJECT" --owner "$OWNER" --format json --limit 100)"
  FID_STATUS="$(printf '%s' "$FJSON" | jq -r '.fields[]|select(.name=="Status").id')"
  READY_OPT="$(printf '%s' "$FJSON" | jq -r '.fields[]|select(.name=="Status").options[]|select(.name=="ready").id')"
  ITEMS_JSON="$(gh project item-list "$PROJECT" --owner "$OWNER" --format json --limit 200 2>/dev/null || echo '{"items":[]}')"
fi
item_id_for() { printf '%s' "$ITEMS_JSON" | jq -r --argjson n "$1" '.items[]? | select(.content.number==$n) | .id' | head -1; }

# ---- find dependents and check whether ALL of their prereqs are closed ----
unblocked=0
while IFS=$'\t' read -r num state rid deps status; do
  roadmap_depends_contains "$deps" "$CLOSED_RID" || continue        # depends on the closed one?
  [[ "$state" = "OPEN" ]] || { note "→ $rid (#$num): skip (issue $state)"; continue; }
  case "$status" in backlog|blocked) : ;; *) note "→ $rid (#$num): skip (status '$status' outside backlog/blocked)"; continue ;; esac

  # all prerequisites closed?
  all_closed=1; pending=""; done_list=""
  for dep in ${deps//,/ }; do
    drow="$(by_rid "$dep")"
    if [[ -z "$drow" ]]; then all_closed=0; pending="$pending $dep(no-issue)"; continue; fi
    dstate="$(col "$drow" 2)"; dnum="$(col "$drow" 1)"
    if [[ "$dstate" = "CLOSED" ]]; then done_list="$done_list #$dnum($dep)"; else all_closed=0; pending="$pending #$dnum($dep)"; fi
  done

  if [[ "$all_closed" != 1 ]]; then
    note "→ $rid (#$num): still blocked — waiting on:$pending"
    continue
  fi

  unblocked=$((unblocked+1))
  comment="🔓 **Auto-unblock** — all prerequisites closed, moving status → \`ready\`.
- Triggered by closing #$CLOSED ($CLOSED_RID).
- Closed prerequisites:$done_list
- Change: Projects Status → \`ready\`, label \`status:ready\` (was \`$status\`)."

  if [[ "$DRY_RUN" = 1 ]]; then
    note "→ $rid (#$num): UNBLOCK ✅  (closed prereqs:$done_list)"
    note "    [dry-run] label status:$status → status:ready; Projects Status → ready; audit comment"
  else
    note "→ $rid (#$num): UNBLOCK ✅"
    gh issue edit "$num" --repo "$REPO" --remove-label "status:$status" --add-label "status:ready" >/dev/null 2>&1 || true
    if [[ -n "$PROJECT_NODE_ID" ]] && [[ -n "$FID_STATUS" ]] && [[ -n "$READY_OPT" ]]; then
      item="$(item_id_for "$num")"
      [[ -n "$item" ]] && gh project item-edit --id "$item" --project-id "$PROJECT_NODE_ID" \
        --field-id "$FID_STATUS" --single-select-option-id "$READY_OPT" >/dev/null 2>&1 \
        || note "    (could not set Projects Status — check token scope project)"
    else
      note "    (skipped Projects Status — no project number/field; label and comment suffice as the signal)"
    fi
    gh issue comment "$num" --repo "$REPO" --body "$comment" >/dev/null
  fi
done <<< "$RAW"

say ""
say "Done. Unblocked (or to-unblock in dry-run): $unblocked"
