#!/usr/bin/env bash
# Parser self-check — "show evidence, not assurances". Hermetic: runs against the shipped
# fixture fixtures/roadmap.sample.md (2 foundations + 3 slices), so it never couples to a
# live roadmap's row count.
#
#   ./scripts/lib/roadmap-parse.test.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/roadmap-parse.sh"

FIXTURE="$DIR/fixtures/roadmap.sample.md"
[[ -f "$FIXTURE" ]] || { echo "fixture missing: $FIXTURE" >&2; exit 1; }

EXPECT_ROWS=5
fails=0
TSV="$(roadmap_tsv "$FIXTURE")"

# cell value: cell ID COLUMN_INDEX (1-based, per the TSV header)
cell() { printf '%s\n' "$TSV" | awk -F'\t' -v id="$1" -v c="$2" '$1==id{print $c; exit}'; }

check() { # check DESC EXPECTED ACTUAL
  if [[ "$2" = "$3" ]]; then
    printf '  ✓ %s\n' "$1"
  else
    printf '  ✗ %s — expected [%s], got [%s]\n' "$1" "$2" "$3"; fails=$((fails+1))
  fi
}

echo "== roadmap-parse self-check (fixture) =="
rows="$(printf '%s\n' "$TSV" | tail -n +2 | grep -c .)"
check "row count = $EXPECT_ROWS"                  "$EXPECT_ROWS" "$rows"

# type derivation (F-* → foundation, S-* → slice)
check "F-01 type=foundation"                      "foundation"   "$(cell F-01 3)"
check "S-01 type=slice"                           "slice"        "$(cell S-01 3)"

# board status mapping: proposed→backlog, ready→ready, blocked→blocked
check "F-01 status_board=ready (ready)"           "ready"        "$(cell F-01 6)"
check "S-01 status_board=backlog (proposed)"      "backlog"      "$(cell S-01 6)"
check "S-02 status_board=ready (ready)"           "ready"        "$(cell S-02 6)"
check "S-03 status_board=blocked (blocked)"       "blocked"      "$(cell S-03 6)"

# anchored depends_on (incl. an empty one on a foundation, and a dangling S-04 ref)
check "F-01 depends_on=(empty)"                   ""             "$(cell F-01 7)"
check "S-01 depends_on=F-01,F-02"                 "F-01,F-02"    "$(cell S-01 7)"
check "S-02 depends_on=S-01"                      "S-01"         "$(cell S-02 7)"
check "S-03 depends_on=S-01,S-04"                 "S-01,S-04"    "$(cell S-03 7)"

# stream assignment from the "## Streams" table (first stream mentioning the ID wins)
check "F-01 stream=A"                             "A"            "$(cell F-01 4)"
check "F-02 stream=B"                             "B"            "$(cell F-02 4)"
check "S-01 stream=A"                             "A"            "$(cell S-01 4)"
check "S-03 stream=D"                             "D"            "$(cell S-03 4)"

# multi-item Unknowns/Blockers on the blocked slice (joined by the " ¶ " sentinel)
if [[ -n "$(cell S-03 10)" ]]; then check "S-03 has unknowns" "ok" "ok"; else check "S-03 has unknowns" "ok" "EMPTY"; fi
if [[ -n "$(cell S-03 11)" ]]; then check "S-03 has blockers" "ok" "ok"; else check "S-03 has blockers" "ok" "EMPTY"; fi
case "$(cell S-03 10)" in
  *" ¶ "*) check "S-03 unknowns are multi-item (¶-joined)" "ok" "ok" ;;
  *)       check "S-03 unknowns are multi-item (¶-joined)" "ok" "SINGLE" ;;
esac

echo
if [[ "$fails" -eq 0 ]]; then
  echo "OK: PASS (all assertions green)"
else
  echo "FAIL ($fails assertions failed)"; exit 1
fi
