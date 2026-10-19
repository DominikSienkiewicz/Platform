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
#   --force-status       project the roadmap status even over a status the automation set (see below).
#
# Status ownership (Decision 12): once an issue exists, its Status belongs to the automation and the
# board. A re-sync does not move an issue back from ready (or a later status) to backlog/blocked while
# every dependency in its marker is closed: that is an auto-unblock the roadmap has not caught up with.
# --force-status restores the plain projection. ROADMAP_ISSUE_LIMIT (default 5000) bounds the issue
# snapshot; a snapshot that reaches it stops the run, as does a failed one, before anything is created.
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
DRY_RUN=0; PROJECT=""; ONLY=""; ASSIGNEE=""; NATIVE_DEPS=1; PREVIEW=""; FORCE_STATUS=0
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
    --force-status)   FORCE_STATUS=1 ;;
    --preview)        PREVIEW="${2:-}"; shift ;;   # read-only body preview for a single ID
    --preview=*)      PREVIEW="${1#*=}" ;;
    -h|--help)        sed -n '2,32p' "$0"; exit 0 ;;
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

  # By number only, as roadmap-unblock.sh does: the configured title may match another board.
  PROJECT_NODE_ID="$(gh project list --owner "$OWNER" --format json --limit 100 \
    | jq -r --arg n "$PROJECT" '.projects[] | select((.number|tostring)==$n) | .id' | head -1)"
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
opt_id() { local field="$1" option="$2"; printf '%s' "${FIELDS_JSON:-}" | jq -r --arg f "$field" --arg n "$option" '.fields[]|select(.name==$f).options[]?|select(.name==$n).id' | head -1; }

# ---- working data ---------------------------------------------------------------
TMP="$(mktemp -d "${TMPDIR:-/tmp}/roadmap-issues.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TSV="$TMP/tsv"; TSVU="$TMP/tsvu"; MAP_NUM="$TMP/map_num"; MAP_ITEM="$TMP/map_item"
: > "$MAP_NUM"; : > "$MAP_ITEM"
roadmap_tsv > "$TSV"
# TAB is IFS-whitespace → `read` collapses adjacent tabs and drops empty middle fields (shifts columns).
# Rewrite to US (0x1F, NOT whitespace) so `read` keeps empty fields (e.g. missing depends_on).
tr $'\t' $'\037' < "$TSV" > "$TSVU"

in_only() { local id="$1"; [[ -z "$ONLY" ]] && return 0; roadmap_depends_contains "$ONLY" "$id"; }
# An ID outside --only is not in MAP_NUM, but its issue may exist: fall back to the snapshot.
num_of()  {
  local id="$1" n
  n="$(awk -F'\t' -v id="$id" '$1==id{print $2; exit}' "$MAP_NUM")"
  [[ -n "$n" ]] || n="$(find_issue_by_id "$id")"
  printf '%s' "$n"
}
FAILED=0
failed() { note "FAILED: $*"; FAILED=$((FAILED+1)); }
item_of() { local id="$1"; awk -F'\t' -v id="$id" '$1==id{print $2; exit}' "$MAP_ITEM"; }
emit_split() { local sep="$1" prefix="$2" text="$3"; awk -v sep="$sep" -v p="$prefix" -v t="$text" 'BEGIN{n=split(t,a,sep); for(i=1;i<=n;i++){gsub(/^[ \t]+|[ \t]+$/,"",a[i]); if(length(a[i])) print p a[i]}}'; }

# ---- labels (idempotent; skipped in --preview) ----------------------------------
if [[ -z "$PREVIEW" ]]; then
  say "== Labels =="
  while IFS= read -r lbl; do
    color="$(roadmap_label_color "$lbl")"; desc="$(roadmap_label_desc "$lbl")"
    if [[ "$DRY_RUN" = 1 ]]; then note "DRY  label $lbl (#$color)"
    elif err="$(gh label create "$lbl" --color "$color" --description "$desc" --force 2>&1 >/dev/null)"; then note "✓ $lbl"
    else
      # PASS 2 would die later at --add-label of this label, with half of the issues rewritten.
      echo "Could not create label $lbl: $err" >&2
      exit 1
    fi
  done < <(roadmap_all_labels)
  say ""
fi

# ---- snapshot of existing issues (marker lookup) --------------------------------
# Not fail-open: an empty snapshot after a failed query would make PASS 1 create a duplicate of every item.
LIMIT="${ROADMAP_ISSUE_LIMIT:-5000}"
if [[ -z "$PREVIEW" ]]; then
  ALL_ISSUES_JSON="$(gh issue list --repo "$REPO" --state all --limit "$LIMIT" --json number,title,state,labels,body)"
  if [[ "$(jq 'length' <<< "$ALL_ISSUES_JSON")" -ge "$LIMIT" ]]; then
    echo "The repository has $LIMIT issues or more; raise ROADMAP_ISSUE_LIMIT so no marker is missed." >&2
    exit 1
  fi
else
  ALL_ISSUES_JSON='[]'
fi
issue_field() { # issue_field NUMBER JQ: a field of an issue from the snapshot
  printf '%s' "$ALL_ISSUES_JSON" | jq -r --argjson n "$1" ".[] | select(.number == \$n) | $2"
}
deps_closed() { # deps_closed "A,B": every dependency has an issue and it is closed
  local d n
  for d in ${1//,/ }; do
    n="$(find_issue_by_id "$d")"
    [[ -n "$n" ]] && [[ "$(issue_field "$n" .state)" == CLOSED ]] || return 1
  done
  return 0
}
keep_ticks() { # keep_ticks CURRENT_BODY < NEW_BODY: "- [ ] text" becomes "- [x] text" when ticked in CURRENT_BODY
  awk 'FNR==NR { if ($0 ~ /^- \[[xX]\] /) ticked[substr($0, 7)]=1; next }
       /^- \[ \] / && (substr($0, 7) in ticked) { print "- [x] " substr($0, 7); next }
       { print }' "$1" -
}
find_issue_by_id() {
  local id="$1"
  printf '%s' "$ALL_ISSUES_JSON" \
    | jq -r --arg m "roadmap-id: $id |" '.[] | select((.body // "") | contains($m)) | .number' | head -1
}

# ---- issue body -----------------------------------------------------------------
build_body() { # uses loop variables: id change type stream sr sb deps prd outcome unknowns blockers suggested risk notes ready
  local marker; marker="$(roadmap_marker "$id" "$change" "$stream" "$deps" "$sb")"
  echo "> **Roadmap projection** — source of truth: \`${ROADMAP_DOC_PATH:-context/foundation/roadmap.md}\` (change: \`$change\`)."
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
  if [[ -n "$risk" ]]; then
    echo "## Risk"
    echo "$risk"
    echo ""
  fi
  if [[ -n "$notes" ]] || [[ -n "$ready" ]]; then
    echo "## Notes"
    if [[ -n "$notes" ]]; then echo "$notes"; fi
    if [[ -n "$ready" ]]; then echo "_Ready for /10x-plan: ${ready}_"; fi
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
  while IFS=$'\037' read -r id change type stream sr sb deps prd outcome unknowns blockers suggested risk notes ready; do
    [[ "$id" = "$PREVIEW" ]] || continue
    found=1
    echo "===== PREVIEW issue: $id ====="
    echo "TITLE: $id: $(roadmap_title_en "$id" "${suggested:-$change}")"
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
while IFS=$'\037' read -r id change type stream sr sb deps prd outcome unknowns blockers suggested risk notes ready; do
  [[ "$id" = "id" ]] && continue
  in_only "$id" || continue
  title="$id: $(roadmap_title_en "$id" "${suggested:-$change}")"
  existing="$(find_issue_by_id "$id")"
  if [[ -n "$existing" ]]; then
    UPDATED=$((UPDATED+1)); num="$existing"
    note "UPDATE #$num  $id"
    current_title="$(issue_field "$num" .title)"
    [[ "$current_title" == "$title" ]] || note "       title: $current_title → $title"
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
while IFS=$'\037' read -r id change type stream sr sb deps prd outcome unknowns blockers suggested risk notes ready; do
  [[ "$id" = "id" ]] && continue
  in_only "$id" || continue
  num="$(num_of "$id")"; item="$(item_of "$id")"
  title="$id: $(roadmap_title_en "$id" "${suggested:-$change}")"

  if [[ "$DRY_RUN" = 1 ]]; then
    depline=""
    if [[ -n "$deps" ]]; then for d in ${deps//,/ }; do depline="$depline #$(num_of "$d"):$d"; done; fi
    note "$id → labels[type:$type, stream:$stream, status:$sb]  board[Status=$sb, Stream=$stream]  deps[${depline:- none}]"
    continue
  fi

  # status ownership: keep a status the automation moved forward while every dependency is closed
  cur="$(gh issue view "$num" --repo "$REPO" --json labels -q '.labels[].name')"
  cur_status="$(printf '%s\n' "$cur" | sed -n 's/^status://p' | head -1)"
  if [[ "$FORCE_STATUS" != 1 ]] && [[ "$sb" =~ ^(backlog|blocked)$ ]] && [[ -n "$cur_status" ]] \
    && ! [[ "$cur_status" =~ ^(backlog|blocked)$ ]] && deps_closed "$deps"; then
    note "keeps status:$cur_status of #$num (dependencies closed; the roadmap still says $sb) — --force-status to override"
    sb="$cur_status"
  fi

  # body — a criterion ticked in the issue stays ticked when its text is unchanged
  bodyfile="$TMP/body.$id"; build_body > "$bodyfile.new"
  issue_field "$num" '.body // ""' > "$bodyfile.current"
  keep_ticks "$bodyfile.current" < "$bodyfile.new" > "$bodyfile"
  gh issue edit "$num" --repo "$REPO" --title "$title" --body-file "$bodyfile" >/dev/null
  if [[ -n "$ASSIGNEE" ]] && ! err="$(gh issue edit "$num" --repo "$REPO" --add-assignee "$ASSIGNEE" 2>&1 >/dev/null)"; then
    failed "#$num could not assign $ASSIGNEE: $err"
  fi

  # labels — convergence (add missing, remove stale in managed namespaces)
  desired="type:$type stream:$stream status:$sb"
  ladd=(); lrem=()
  for d in $desired; do printf '%s\n' "$cur" | grep -qxF "$d" || ladd+=(--add-label "$d"); done
  while IFS= read -r c; do
    case "$c" in
      type:*|stream:*|status:*)
        case " $desired " in *" $c "*) : ;; *) lrem+=(--remove-label "$c") ;; esac ;;
      # Etykiety spoza zarządzanych przestrzeni nazw należą do kogoś innego — nie ruszamy ich.
      *) : ;;
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

  # native blocked_by — reconciled with the marker: add the missing links, remove links to roadmap issues
  # that are no longer dependencies, leave links to issues without a marker (set by hand) alone.
  if [[ "$NATIVE_DEPS" = 1 ]]; then
    if ! links="$(gh api "repos/$REPO/issues/$num/dependencies/blocked_by" --jq '.[] | "\(.id)\t\(.number)"' 2>&1)"; then
      if grep -qiE '404|not found' <<< "$links"; then
        note "native: dependencies API unavailable for #$num — skipped (marker canonical)"
      else
        failed "#$num native dependencies: $links"
      fi
    else
      wanted=" "
      for d in ${deps//,/ }; do
        pnum="$(num_of "$d")"; [[ -n "$pnum" ]] && [[ "$pnum" != "TBD" ]] || continue
        wanted="$wanted$pnum "
        printf '%s\n' "$links" | cut -f2 | grep -qxF "$pnum" && continue
        pdb="$(gh api "repos/$REPO/issues/$pnum" --jq .id)"
        if err="$(gh api --method POST "repos/$REPO/issues/$num/dependencies/blocked_by" -F issue_id="$pdb" 2>&1 >/dev/null)"; then
          note "native: #$num blocked_by #$pnum ($d) ✓"
        elif grep -qi 'already' <<< "$err"; then
          note "native: #$num blocked_by #$pnum ($d) already linked"
        else
          failed "#$num blocked_by #$pnum ($d): $err"
        fi
      done
      while IFS=$'\t' read -r link_id link_num; do
        [[ -n "$link_id" ]] || continue
        case "$wanted" in *" $link_num "*) continue ;; esac
        [[ "$(issue_field "$link_num" '(.body // "") | test("roadmap-id:")')" == true ]] || continue
        if err="$(gh api --method DELETE "repos/$REPO/issues/$num/dependencies/blocked_by/$link_id" 2>&1 >/dev/null)"; then
          note "native: #$num no longer blocked_by #$link_num ✓"
        else
          failed "#$num remove blocked_by #$link_num: $err"
        fi
      done <<< "$links"
    fi
  fi

  note "✓ #$num  $id  [type:$type stream:$stream status:$sb]"
done < "$TSVU"

say ""
say "================================================================"
say " Summary: CREATE=$CREATED  UPDATE=$UPDATED  FAILED=$FAILED  (mode: $([[ "$DRY_RUN" = 1 ]] && echo DRY-RUN || echo APPLY))"
say " Verify:  gh issue list --state all --limit 100"
say "          gh project item-list $PROJECT --owner $OWNER --limit 100 --format json | jq '.items[]|{title,status:.status,stream:.stream}'"
say "================================================================"
[[ "$FAILED" -eq 0 ]] || exit 1
