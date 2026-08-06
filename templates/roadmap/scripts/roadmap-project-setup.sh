#!/usr/bin/env bash
# One-time Projects v2 bootstrap for the roadmap board (idempotent — safe to re-run).
#   • find or create the project titled "$ROADMAP_PROJECT_TITLE"
#   • rewrite the built-in Status field to the 6 canonical options (backlog/ready/in-progress/blocked/in-review/done)
#     — via GraphQL updateProjectV2Field; ALWAYS sends the full six and PRESERVES the id of existing
#       options with the same name (otherwise orphaned items). `gh project` cannot edit Status options.
#   • add Stream (single-select A–E) and Roadmap ID (text) fields if missing.
#
#   ./scripts/roadmap-project-setup.sh [--dry-run]
#   ROADMAP_PROJECT_TITLE="Other title" ./scripts/roadmap-project-setup.sh
#   GH_OWNER=login GH_REPO=owner/repo ./scripts/roadmap-project-setup.sh
#
# Requires: gh CLI logged in with token-scope `project` (Projects v2 read/write), jq.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Source order (required): config VALUES → canonical helpers → parser.
# shellcheck source=lib/roadmap-config.sh
source "$ROOT/scripts/lib/roadmap-config.sh"
# shellcheck source=lib/roadmap-lib.sh
source "$ROOT/scripts/lib/roadmap-lib.sh"
# shellcheck source=lib/roadmap-parse.sh
source "$ROOT/scripts/lib/roadmap-parse.sh"

DRY_RUN=0
[[ "${1:-}" = "--dry-run" ]] && DRY_RUN=1

command -v gh >/dev/null || { echo "gh CLI missing. https://cli.github.com/" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq missing." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not logged in — run: gh auth login" >&2; exit 1; }

OWNER="${GH_OWNER:-$(gh repo view --json owner -q .owner.login 2>/dev/null || true)}"
[[ -n "$OWNER" ]] || { echo "Owner not detected. Set GH_OWNER=login." >&2; exit 1; }
TITLE="$ROADMAP_PROJECT_TITLE"
say() { printf '%s\n' "$*"; }
run() { if [[ "$DRY_RUN" = 1 ]]; then say "DRY  $*"; else say "RUN  $*"; "$@"; fi; }

say "Owner:   $OWNER"
say "Project: $TITLE"
say "Mode:    $([[ "$DRY_RUN" = 1 ]] && echo DRY-RUN || echo APPLY)"
say ""

# --- 1. Find or create the project -----------------------------------------------
existing="$(gh project list --owner "$OWNER" --format json --limit 100 \
  | jq -r --arg t "$TITLE" '.projects[] | select(.title==$t) | "\(.number)\t\(.id)"' | head -1)"

if [[ -n "$existing" ]]; then
  NUMBER="$(printf '%s' "$existing" | cut -f1)"
  NODE_ID="$(printf '%s' "$existing" | cut -f2)"
  say "✓ Project exists: #$NUMBER ($NODE_ID)"
else
  if [[ "$DRY_RUN" = 1 ]]; then
    say "DRY  gh project create --owner $OWNER --title \"$TITLE\"  (skipped the rest — project does not exist yet)"
    say ""
    say "After really creating it, re-run without --dry-run to configure the fields."
    exit 0
  fi
  created="$(gh project create --owner "$OWNER" --title "$TITLE" --format json)"
  NUMBER="$(printf '%s' "$created" | jq -r '.number')"
  NODE_ID="$(printf '%s' "$created" | jq -r '.id')"
  say "✓ Created project: #$NUMBER ($NODE_ID)"
fi

# --- 2. Fetch fields once ---------------------------------------------------------
FIELDS_JSON="$(gh project field-list "$NUMBER" --owner "$OWNER" --format json --limit 100)"
STATUS_FID="$(printf '%s' "$FIELDS_JSON" | jq -r '.fields[] | select(.name=="Status") | .id')"
[[ -n "$STATUS_FID" ]] && [[ "$STATUS_FID" != "null" ]] || { echo "Status field not found in the project." >&2; exit 1; }

# --- 3. Rewrite Status options (preserve id by name) ------------------------------
literal=""
i=0
while [[ "$i" -lt "${#ROADMAP_STATUSES[@]}" ]]; do
  name="${ROADMAP_STATUSES[$i]}"
  color="${ROADMAP_STATUS_COLORS[$i]}"
  desc="${ROADMAP_STATUS_DESCS[$i]}"
  oid="$(printf '%s' "$FIELDS_JSON" \
    | jq -r --arg n "$name" '.fields[] | select(.name=="Status") | .options[]? | select(.name==$n) | .id' | head -1)"
  if [[ -n "$oid" ]] && [[ "$oid" != "null" ]]; then
    opt="{id: \"$oid\", name: \"$name\", color: $color, description: \"$desc\"}"
  else
    opt="{name: \"$name\", color: $color, description: \"$desc\"}"
  fi
  literal="${literal:+$literal, }$opt"
  i=$((i+1))
done

MUTATION="mutation { updateProjectV2Field(input: { fieldId: \"$STATUS_FID\", singleSelectOptions: [ $literal ] }) { projectV2Field { __typename ... on ProjectV2SingleSelectField { id options { id name } } } } }"

if [[ "$DRY_RUN" = 1 ]]; then
  say "DRY  updateProjectV2Field Status → [$(printf '%s ' "${ROADMAP_STATUSES[@]}")]"
  say "     (preserved ids: $(printf '%s' "$FIELDS_JSON" | jq -r '.fields[]|select(.name=="Status").options[]?.name' | tr '\n' ' '))"
else
  say "RUN  updateProjectV2Field Status (6 options, ids preserved by name)"
  gh api graphql -f query="$MUTATION" \
    --jq '.data.updateProjectV2Field.projectV2Field.options | map(.name) | join(", ")' \
    | sed 's/^/     Status = /'
fi

# --- 4. Add Stream + Roadmap ID fields if missing ---------------------------------
ensure_field() { # ensure_field NAME DATA_TYPE [single-select-options]
  local fname="$1" dtype="$2" opts="${3:-}"
  if printf '%s' "$FIELDS_JSON" | jq -e --arg n "$fname" '.fields[] | select(.name==$n)' >/dev/null; then
    say "✓ Field '$fname' already exists"
    return 0
  fi
  if [[ "$dtype" = "SINGLE_SELECT" ]]; then
    run gh project field-create "$NUMBER" --owner "$OWNER" --name "$fname" --data-type "$dtype" --single-select-options "$opts"
  else
    run gh project field-create "$NUMBER" --owner "$OWNER" --name "$fname" --data-type "$dtype"
  fi
}
ensure_field "Stream" SINGLE_SELECT "$(IFS=,; echo "${ROADMAP_STREAMS[*]}")"
ensure_field "Roadmap ID" TEXT

say ""
say "================================================================"
say " Done. Project number: $NUMBER"
say " Use it in the generator: ./scripts/roadmap-to-issues.sh --project $NUMBER --dry-run"
say " For the auto-unblock Action set repo variable: ROADMAP_PROJECT_NUMBER=$NUMBER"
say "================================================================"
