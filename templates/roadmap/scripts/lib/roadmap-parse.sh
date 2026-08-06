#!/usr/bin/env bash
# Roadmap parser (`/10x-roadmap` doc → TSV, one item = one row) + marker helpers.
# The roadmap doc stays the source of truth; issues are its idempotent projection
# (see scripts/roadmap-to-issues.sh).
#
# Two modes:
#   • execute:  ./scripts/lib/roadmap-parse.sh [ROADMAP_PATH]   → prints TSV to stdout
#   • source:   source scripts/lib/roadmap-parse.sh             → exposes:
#                 roadmap_tsv [PATH]              – TSV (with header row)
#                 roadmap_marker ID CID STREAM DEPS STATUS  – HTML-comment footer (idempotency key)
#                 roadmap_depends_contains "A,B" ID          – exit 0 when ID is in the list (anchored)
#                 roadmap_title_en ID FALLBACK               – EN title from sidecar or fallback
#
# TSV columns: id  change_id  type  stream  status_roadmap  status_board  depends_on  prd_refs  outcome  unknowns  blockers
#   • type:           F-* → foundation, S-* → slice
#   • stream:         derived from the "## Streams" table (first stream A→E mentioning the ID wins)
#   • status_board:   proposed→backlog, ready→ready, blocked→blocked (rest passthrough)
#   • depends_on:     IDs pulled from the **Prerequisites** field (e.g. "F-01,F-02"); empty = none
#   • unknowns/blockers: sub-bullets joined by the sentinel " ¶ " (the generator splits them back)
#
# Doc path + titles sidecar come from ROADMAP_DOC_PATH / ROADMAP_TITLES_TSV (set by
# roadmap-config.sh when sourced) with env override (ROADMAP / ROADMAP_TITLES_EN) still allowed.
#
# bash 3.2 safe (macOS): no `declare -A`. Associative arrays live only in awk (standard POSIX
# awk, not a bashism) and need no gawk (no 3-arg match/capture — we use RSTART/RLENGTH).
set -euo pipefail

# ROOT works both when executed and when sourced.
_RP_SELF="${BASH_SOURCE[0]}"
ROADMAP_PARSE_ROOT="$(cd "$(dirname "$_RP_SELF")/../.." && pwd)"

# Resolve the roadmap doc path: env ROADMAP wins, then config ROADMAP_DOC_PATH
# (relative to repo root), then the historical default.
if [[ -n "${ROADMAP:-}" ]]; then
  ROADMAP_DEFAULT="$ROADMAP"
elif [[ -n "${ROADMAP_DOC_PATH:-}" ]]; then
  case "$ROADMAP_DOC_PATH" in
    /*) ROADMAP_DEFAULT="$ROADMAP_DOC_PATH" ;;
    *)  ROADMAP_DEFAULT="$ROADMAP_PARSE_ROOT/$ROADMAP_DOC_PATH" ;;
  esac
else
  ROADMAP_DEFAULT="$ROADMAP_PARSE_ROOT/context/foundation/roadmap.md"
fi

# Resolve the EN titles sidecar: env ROADMAP_TITLES_EN wins, then config ROADMAP_TITLES_TSV
# (relative to repo root; "" disables), then the historical default.
if [[ -n "${ROADMAP_TITLES_EN:-}" ]]; then
  : # explicit env override kept as-is
elif [[ -n "${ROADMAP_TITLES_TSV+x}" ]]; then
  # config var is defined (possibly empty → sidecar disabled)
  if [[ -n "$ROADMAP_TITLES_TSV" ]]; then
    case "$ROADMAP_TITLES_TSV" in
      /*) ROADMAP_TITLES_EN="$ROADMAP_TITLES_TSV" ;;
      *)  ROADMAP_TITLES_EN="$ROADMAP_PARSE_ROOT/$ROADMAP_TITLES_TSV" ;;
    esac
  else
    ROADMAP_TITLES_EN=""
  fi
else
  ROADMAP_TITLES_EN="$ROADMAP_PARSE_ROOT/scripts/lib/roadmap-titles.en.tsv"
fi

roadmap_tsv() {
  local file="${1:-$ROADMAP_DEFAULT}"
  [[ -f "$file" ]] || { echo "roadmap-parse: roadmap file not found: $file" >&2; return 1; }
  # Two passes over the same file: (1) FNR==NR builds stream[ID]; (2) parses item blocks.
  awk '
    function boardstatus(s) {
      if (s=="proposed") return "backlog"
      if (s=="ready")    return "ready"
      if (s=="blocked")  return "blocked"
      return s
    }
    function extract_ids(s,   t, out, tok) {
      t=s; out=""
      while (match(t, /[FS]-[0-9]+/)) {
        tok=substr(t, RSTART, RLENGTH)
        out=(out=="" ? tok : out "," tok)
        t=substr(t, RSTART+RLENGTH)
      }
      return out
    }
    function flush(   bs, st) {
      if (cur=="") return
      st=stream[cur]
      bs=boardstatus(status)
      if (unknowns=="—") unknowns=""
      if (blockers=="—") blockers=""
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", \
        cur, change, type, st, status, bs, deps, prd, outcome, unknowns, blockers
      cur=""
    }
    BEGIN {
      print "id\tchange_id\ttype\tstream\tstatus_roadmap\tstatus_board\tdepends_on\tprd_refs\toutcome\tunknowns\tblockers"
    }

    # ---------- Pass 1: "## Streams" table → stream[ID] ----------
    FNR==NR {
      if ($0 ~ /^## Streams[ \t]*$/) { in_streams=1; next }
      if (in_streams && $0 ~ /^## /)  { in_streams=0 }
      if (in_streams && $0 ~ /^\|/) {
        n=split($0, c, "|")
        cell=c[2]; gsub(/^[ \t]+|[ \t]+$/, "", cell)   # first column = stream letter
        if (cell ~ /^[A-E]$/) {
          letter=cell; tmp=$0
          while (match(tmp, /[FS]-[0-9]+/)) {           # first stream mentioning an ID wins
            tok=substr(tmp, RSTART, RLENGTH)
            if (!(tok in stream)) stream[tok]=letter
            tmp=substr(tmp, RSTART+RLENGTH)
          }
        }
      }
      next
    }

    # ---------- Pass 2: "### F-NN:/### S-NN:" blocks ----------
    /^### [FS]-[0-9]+:/ {
      flush()
      line=$0; sub(/^### /,"",line); ci=index(line,":"); id=substr(line,1,ci-1)
      if (id ~ /^[FS]-[0-9]+$/) {
        cur=id; type=(substr(id,1,1)=="F" ? "foundation" : "slice")
        change=""; prd=""; status=""; outcome=""; deps=""; unknowns=""; blockers=""; lastlabel=""
      } else cur=""
      next
    }
    /^## / { flush(); cur=""; next }   # section boundary (Backlog Handoff etc.) closes the current item

    cur!="" && /^- \*\*/ {
      l=$0; sub(/^- \*\*/,"",l); p=index(l,":**")
      if (p>0) {
        label=substr(l,1,p-1); val=substr(l,p+3); sub(/^[ ]+/,"",val); lastlabel=label
        if      (label=="Change ID")     change=val
        else if (label=="PRD refs")      prd=val
        else if (label=="Status")        status=val
        else if (label=="Outcome")       outcome=val
        else if (label=="Prerequisites") deps=extract_ids(val)
        else if (label=="Unknowns")      unknowns=val
        else if (label=="Blockers")      blockers=val
      }
      next
    }
    cur!="" && /^[ ]+- / {              # sub-bullet continuing the last field (Unknowns/Blockers)
      sb=$0; sub(/^[ ]+- /,"",sb)
      if      (lastlabel=="Unknowns") unknowns=(unknowns=="" ? sb : unknowns " ¶ " sb)
      else if (lastlabel=="Blockers") blockers=(blockers=="" ? sb : blockers " ¶ " sb)
      next
    }

    END { flush() }
  ' "$file" "$file"
}

# Footer marker: CANONICAL idempotency key and dependency source for automation
# (it reads the marker, not the API). Usage: roadmap_marker ID CHANGE_ID STREAM DEPENDS_ON STATUS_BOARD
roadmap_marker() {
  printf '<!-- roadmap-id: %s | change-id: %s | stream: %s | depends-on: %s | status: %s -->' \
    "$1" "${2:-}" "${3:-}" "${4:-}" "${5:-}"
}

# Anchored membership: is ID in the list "A,B,C" (S-1 != S-12, F-0 != F-01).
roadmap_depends_contains() {
  case ",${1}," in
    *,"$2",*) return 0 ;;
    *)        return 1 ;;
  esac
}

# EN title from the sidecar (ID<TAB>title); no entry → fallback (e.g. the roadmap's own title).
roadmap_title_en() {
  local id="$1" fallback="${2:-}"
  if [[ -n "$ROADMAP_TITLES_EN" ]] && [[ -f "$ROADMAP_TITLES_EN" ]]; then
    local hit
    hit="$(awk -F '\t' -v id="$id" '$1==id {sub(/^[^\t]*\t/,""); print; exit}' "$ROADMAP_TITLES_EN")"
    [[ -n "$hit" ]] && { printf '%s' "$hit"; return 0; }
  fi
  printf '%s' "$fallback"
}

# Direct execution → TSV to stdout.
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
  roadmap_tsv "${1:-}"
fi
