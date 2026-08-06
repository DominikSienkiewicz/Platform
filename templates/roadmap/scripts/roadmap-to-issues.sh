#!/usr/bin/env bash
# Idempotent generator: roadmap → GitHub Issues + Projects v2 items (re-syncable projection).
# Idempotency key = marker in the issue body (roadmap-id: <ID>). Re-run = upsert, no duplicates.
#
# Two passes:
#   PASS 1 — create/find every issue (by marker), add to the board, build ID→number/itemid maps.
#   PASS 2 — now that numbers are known: full body with "Blocked by #N (ID)", labels, assignee,
#            board fields (Status/Stream/Roadmap ID), best-effort native blocked_by.
#
#   ./scripts/roadmap-to-issues.sh --project 12 --dry-run
#   ./scripts/roadmap-to-issues.sh --project 12                 # real run
#   ./scripts/roadmap-to-issues.sh --only F-01,S-02 --project 12
#   ./scripts/roadmap-to-issues.sh --assignee someuser --project 12
#   ./scripts/roadmap-to-issues.sh --no-native-deps --project 12
#
# Flags:
#   --dry-run            mutates nothing; prints the plan (CREATE/UPDATE) and field intents.
#   --project N          project number (default: detect by title "$ROADMAP_PROJECT_TITLE").
#   --only "A,B"         restrict to the given roadmap IDs.
#   --assignee LOGIN     issue assignee (default: ROADMAP_DEFAULT_ASSIGNEE or repo owner).
#   --no-native-deps     skip best-effort native blocked_by (marker stays canonical anyway).
#   --preview ID         print the issue body for one roadmap ID and exit (read-only, no project).
#
# Requires: gh (scope `project`), jq. Labels are created idempotently (gh label create --force).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Source order (required): config VALUES → canonical helpers → parser.
# shellcheck source=lib/roadmap-config.sh
source "$ROOT/scripts/lib/roadmap-config.sh"
# shellcheck source=lib/roadmap-lib.sh
source "$ROOT/scripts/lib/roadmap-lib.sh"
# shellcheck source=lib/roadmap-parse.sh
source "$ROOT/scripts/lib/roadmap-parse.sh"

# ---- flags ----------------------------------------------------------------------
DRY_RUN=0; PROJECT=""; ONLY=""; ASSIGNEE=""; NATIVE_DEPS=1; PREVIEW=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=1 ;;
    --project)        PROJECT="${2:-}"; shift ;;
    --project=*)      PROJECT="${1#*=}" ;;
    --only)           ONLY="${2:-}"; shift ;;
    --only=*)         ONLY="${1#*=}" ;;
    --assignee)       ASSIGNEE="${2:-}"; shift ;;
    --assignee=*)     ASSIGNEE="${1#*=}" ;;
    --no-native-deps) NATIVE_DEPS=0 ;;
    --preview)        PREVIEW="${2:-}"; shift ;;   # read-only body preview for a single ID
    --preview=*)      PREVIEW="${1#*=}" ;;
    -h|--help)        sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

command -v gh >/dev/null || { echo "gh CLI missing." >&2; exit 1; }
command -v jq >/dev/null || { echo "jq missing." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not logged in." >&2; exit 1; }

REPO="${GH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
OWNER="${GH_OWNER:-$(gh repo view --json owner -q .owner.login)}"
[[ -n "$ASSIGNEE" ]] || ASSIGNEE="${ROADMAP_DEFAULT_ASSIGNEE:-}"
[[ -n "$ASSIGNEE" ]] || ASSIGNEE="$OWNER"
TITLE="$ROADMAP_PROJECT_TITLE"

say()  { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }

# ---- project + fields (skipped in --preview mode) -------------------------------
if [[ -z "$PREVIEW" ]]; then
  if [[ -z "$PROJECT" ]]; then
    PROJECT="$(gh project list --owner "$OWNER" --format json --limit 100 \
      | jq -r --arg t "$TITLE" '.projects[] | select(.title==$t) | .number' | head -1)"
  fi
  [[ -n "$PROJECT" ]] || { echo "Project '$TITLE' not found. Run roadmap-project-setup.sh first or pass --project N." >&2; exit 1; }

  PROJECT_NODE_ID="$(gh project list --owner "$OWNER" --format json --limit 100 \
    | jq -r --arg t "$TITLE" --arg n "$PROJECT" '.projects[] | select((.number|tostring)==$n or .title==$t) | .id' | head -1)"
  FIELDS_JSON="$(gh project field-list "$PROJECT" --owner "$OWNER" --format json --limit 100)"
  FID_STATUS="$(printf '%s' "$FIELDS_JSON" | jq -r '.fields[]|select(.name=="Status").id')"
  FID_STREAM="$(printf '%s' "$FIELDS_JSON" | jq -r '.fields[]|select(.name=="Stream").id')"
  FID_ROADMAP="$(printf '%s' "$FIELDS_JSON" | jq -r '.fields[]|select(.name=="Roadmap ID").id')"

  say "Repo:     $REPO"
  say "Owner:    $OWNER"
  say "Project:  #$PROJECT ($PROJECT_NODE_ID)"
  say "Assignee: $ASSIGNEE"
  say "Mode:     $([[ "$DRY_RUN" = 1 ]] && echo DRY-RUN || echo APPLY)"
  [[ -n "$ONLY" ]] && say "Filter:   --only $ONLY"
  say ""
fi
opt_id() { printf '%s' "${FIELDS_JSON:-}" | jq -r --arg f "$1" --arg n "$2" '.fields[]|select(.name==$f).options[]?|select(.name==$n).id' | head -1; }

# ---- working data ---------------------------------------------------------------
TMP="$(mktemp -d "${TMPDIR:-/tmp}/roadmap-issues.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TSV="$TMP/tsv"; TSVU="$TMP/tsvu"; MAP_NUM="$TMP/map_num"; MAP_ITEM="$TMP/map_item"
: > "$MAP_NUM"; : > "$MAP_ITEM"
roadmap_tsv > "$TSV"
# TAB is IFS-whitespace → `read` collapses adjacent tabs and drops empty middle fields (shifts columns).
# Rewrite to US (0x1F, NOT whitespace) so `read` keeps empty fields (e.g. missing depends_on).
tr $'\t' $'\037' < "$TSV" > "$TSVU"

in_only() { [[ -z "$ONLY" ]] && return 0; roadmap_depends_contains "$ONLY" "$1"; }
num_of()  { awk -F'\t' -v id="$1" '$1==id{print $2; exit}' "$MAP_NUM"; }
item_of() { awk -F'\t' -v id="$1" '$1==id{print $2; exit}' "$MAP_ITEM"; }
emit_split() { awk -v sep="$1" -v p="$2" -v t="$3" 'BEGIN{n=split(t,a,sep); for(i=1;i<=n;i++){gsub(/^[ \t]+|[ \t]+$/,"",a[i]); if(length(a[i])) print p a[i]}}'; }

# ---- labels (idempotent; skipped in --preview) ----------------------------------
if [[ -z "$PREVIEW" ]]; then
  say "== Labels =="
  while IFS= read -r lbl; do
    color="$(roadmap_label_color "$lbl")"; desc="$(roadmap_label_desc "$lbl")"
    if [[ "$DRY_RUN" = 1 ]]; then note "DRY  label $lbl (#$color)"
    else gh label create "$lbl" --color "$color" --description "$desc" --force >/dev/null 2>&1 && note "✓ $lbl"; fi
  done < <(roadmap_all_labels)
  say ""
fi

# ---- snapshot of existing issues (marker lookup) --------------------------------
if [[ -z "$PREVIEW" ]]; then
  ALL_ISSUES_JSON="$(gh issue list --state all --limit 200 --json number,body 2>/dev/null || echo '[]')"
else
  ALL_ISSUES_JSON='[]'
fi
find_issue_by_id() {
  printf '%s' "$ALL_ISSUES_JSON" \
    | jq -r --arg m "roadmap-id: $1 |" '.[] | select((.body // "") | contains($m)) | .number' | head -1
}

# ---- issue body -----------------------------------------------------------------
build_body() { # uses loop variables: id change type stream sr sb deps prd outcome unknowns blockers
  local marker; marker="$(roadmap_marker "$id" "$change" "$stream" "$deps" "$sb")"
  echo "> **Roadmap projection** — source of truth: \`context/foundation/roadmap.md\` (change: \`$change\`)."
  echo "> Re-sync: \`./scripts/roadmap-to-issues.sh\`. Do not edit the marker at the bottom by hand."
  echo ""
  echo "## Outcome"
  echo "$outcome"
  echo ""
  echo "## Acceptance criteria"
  emit_split "; " "- [ ] " "$outcome"
  [[ -n "$prd" ]] && echo "- [ ] Meets PRD requirements: $prd"
  echo ""
  echo "## Dependencies"
  if [[ -n "$deps" ]]; then
    local d n
    for d in ${deps//,/ }; do
      n="$(num_of "$d")"
      if [[ -n "$n" ]]; then echo "- ⛓️ Blocked by #$n ($d)"; else echo "- ⛓️ Blocked by $d (issue TBD)"; fi
    done
  else
    echo "- None — ready to start (foundation / no prerequisites)."
  fi
  echo ""
  if [[ "$sb" = "blocked" ]]; then
    echo "## ⛔ Blocked (why)"
    [[ -n "$blockers" ]] && emit_split " ¶ " "- " "$blockers"
    [[ -n "$unknowns" ]] && emit_split " ¶ " "- Open question: " "$unknowns"
    echo ""
  elif [[ -n "$unknowns" ]]; then
    echo "## Open questions / unknowns"
    emit_split " ¶ " "- " "$unknowns"
    echo ""
  fi
  echo "## Roadmap context"
  echo "- **Stream:** ${stream:-—} · **Type:** $type · **Roadmap status:** $sr → board \`$sb\`"
  echo "- **Change ID:** \`$change\`"
  echo ""
  echo "$marker"
}

# ---- preview one ID (read-only, no project/mutation) ----------------------------
if [[ -n "$PREVIEW" ]]; then
  found=0
  while IFS=$'\037' read -r id change type stream sr sb deps prd outcome unknowns blockers; do
    [[ "$id" = "$PREVIEW" ]] || continue
    found=1
    echo "===== PREVIEW issue: $id ====="
    echo "TITLE: $id: $(roadmap_title_en "$id" "$change")"
    echo "LABELS: type:$type, stream:$stream, status:$sb"
    echo "-------------------- BODY --------------------"
    build_body
    break
  done < "$TSVU"
  [[ "$found" = 1 ]] || { echo "Roadmap item '$PREVIEW' not found." >&2; exit 1; }
  exit 0
fi

# =================================================================================
# PASS 1 — create/find issues, add to board, build maps
# =================================================================================
say "== PASS 1: upsert issues + ID→number map =="
CREATED=0; UPDATED=0
while IFS=$'\037' read -r id change type stream sr sb deps prd outcome unknowns blockers; do
  [[ "$id" = "id" ]] && continue
  in_only "$id" || continue
  title="$id: $(roadmap_title_en "$id" "$change")"
  existing="$(find_issue_by_id "$id")"
  if [[ -n "$existing" ]]; then
    UPDATED=$((UPDATED+1)); num="$existing"
    note "UPDATE #$num  $id"
  else
    CREATED=$((CREATED+1))
    if [[ "$DRY_RUN" = 1 ]]; then
      num="TBD"; note "CREATE       $id   \"$title\""
    else
      # minimal body with marker (PASS 2 overwrites with the full one); marker makes the issue findable
      url="$(gh issue create --repo "$REPO" --title "$title" \
              --body "$(roadmap_marker "$id" "$change" "$stream" "$deps" "$sb")" \
              ${ASSIGNEE:+--assignee "$ASSIGNEE"})"
      num="${url##*/}"; note "CREATE #$num  $id"
    fi
  fi
  printf '%s\t%s\n' "$id" "$num" >> "$MAP_NUM"

  # add to board (idempotent — one item per content)
  if [[ "$DRY_RUN" = 1 ]] || [[ "$num" = "TBD" ]]; then
    printf '%s\t%s\n' "$id" "TBD" >> "$MAP_ITEM"
  else
    iurl="https://github.com/$REPO/issues/$num"
    item="$(gh project item-add "$PROJECT" --owner "$OWNER" --url "$iurl" --format json | jq -r '.id')"
    printf '%s\t%s\n' "$id" "$item" >> "$MAP_ITEM"
  fi
done < "$TSVU"
say ""

# =================================================================================
# PASS 2 — full body (deps→#N), labels, assignee, board fields, native deps
# =================================================================================
say "== PASS 2: body + labels + board fields + dependencies =="
while IFS=$'\037' read -r id change type stream sr sb deps prd outcome unknowns blockers; do
  [[ "$id" = "id" ]] && continue
  in_only "$id" || continue
  num="$(num_of "$id")"; item="$(item_of "$id")"
  title="$id: $(roadmap_title_en "$id" "$change")"

  if [[ "$DRY_RUN" = 1 ]]; then
    depline=""
    if [[ -n "$deps" ]]; then for d in ${deps//,/ }; do depline="$depline #$(num_of "$d"):$d"; done; fi
    note "$id → labels[type:$type, stream:$stream, status:$sb]  board[Status=$sb, Stream=$stream]  deps[${depline:- none}]"
    continue
  fi

  # body
  bodyfile="$TMP/body.$id"; build_body > "$bodyfile"
  gh issue edit "$num" --repo "$REPO" --title "$title" --body-file "$bodyfile" >/dev/null
  [[ -n "$ASSIGNEE" ]] && gh issue edit "$num" --repo "$REPO" --add-assignee "$ASSIGNEE" >/dev/null 2>&1 || true

  # labels — convergence (add missing, remove stale in managed namespaces)
  desired="type:$type stream:$stream status:$sb"
  cur="$(gh issue view "$num" --repo "$REPO" --json labels -q '.labels[].name' 2>/dev/null || true)"
  ladd=(); lrem=()
  for d in $desired; do printf '%s\n' "$cur" | grep -qxF "$d" || ladd+=(--add-label "$d"); done
  while IFS= read -r c; do
    case "$c" in
      type:*|stream:*|status:*)
        case " $desired " in *" $c "*) : ;; *) lrem+=(--remove-label "$c") ;; esac ;;
    esac
  done <<< "$cur"
  if [[ ${#ladd[@]} -gt 0 ]] || [[ ${#lrem[@]} -gt 0 ]]; then
    gh issue edit "$num" --repo "$REPO" ${ladd[@]+"${ladd[@]}"} ${lrem[@]+"${lrem[@]}"} >/dev/null
  fi

  # board fields
  if [[ -n "$item" ]] && [[ "$item" != "TBD" ]]; then
    soid="$(opt_id Status "$sb")"
    [[ -n "$soid" ]] && gh project item-edit --id "$item" --project-id "$PROJECT_NODE_ID" --field-id "$FID_STATUS" --single-select-option-id "$soid" >/dev/null
    if [[ -n "$stream" ]]; then
      stoid="$(opt_id Stream "$stream")"
      [[ -n "$stoid" ]] && gh project item-edit --id "$item" --project-id "$PROJECT_NODE_ID" --field-id "$FID_STREAM" --single-select-option-id "$stoid" >/dev/null
    fi
    gh project item-edit --id "$item" --project-id "$PROJECT_NODE_ID" --field-id "$FID_ROADMAP" --text "$id" >/dev/null
  fi

  # native blocked_by (best-effort; marker stays canonical)
  if [[ "$NATIVE_DEPS" = 1 ]] && [[ -n "$deps" ]]; then
    for d in ${deps//,/ }; do
      pnum="$(num_of "$d")"; [[ -n "$pnum" ]] && [[ "$pnum" != "TBD" ]] || continue
      pdb="$(gh api "repos/$REPO/issues/$pnum" --jq .id 2>/dev/null || true)"
      [[ -n "$pdb" ]] || continue
      if gh api --method POST "repos/$REPO/issues/$num/dependencies/blocked_by" -F issue_id="$pdb" >/dev/null 2>&1; then
        note "native: #$num blocked_by #$pnum ($d) ✓"
      else
        note "native: #$num blocked_by #$pnum ($d) — skipped (API unavailable; marker canonical)"
      fi
    done
  fi

  note "✓ #$num  $id  [type:$type stream:$stream status:$sb]"
done < "$TSVU"

say ""
say "================================================================"
say " Summary: CREATE=$CREATED  UPDATE=$UPDATED  (mode: $([[ "$DRY_RUN" = 1 ]] && echo DRY-RUN || echo APPLY))"
say " Verify:  gh issue list --state all --limit 100"
say "          gh project item-list $PROJECT --owner $OWNER --limit 100 --format json | jq '.items[]|{title,status:.status,stream:.stream}'"
say "================================================================"
