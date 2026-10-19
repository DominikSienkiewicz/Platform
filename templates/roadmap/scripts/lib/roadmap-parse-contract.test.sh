#!/usr/bin/env bash
# Parser contract beyond the basic fixture: duplicate IDs stop the run (E2-18), the Backlog Handoff
# table and the Risk field reach the TSV (E2-16), the title falls back to the suggested title, and
# the streams come from ROADMAP_STREAMS instead of a hard-coded A–E (E2-26). Hermetic, bash 3.2 safe.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/roadmap-parse.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fails=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" = "$actual" ]]; then printf '  ✓ %s\n' "$desc"
  else printf '  ✗ %s — expected [%s], got [%s]\n' "$desc" "$expected" "$actual"; fails=$((fails+1)); fi
}

cat > "$TMP/roadmap.md" <<'MD'
# Roadmap: Contract

## Streams

| Stream | Theme  | Chain             |
| ------ | ------ | ----------------- |
| A      | Anchor | `F-01` → `S-01`   |
| F      | Extra  | `S-02`            |

## Foundations

### F-01: Baseline

- **Outcome:** the baseline exists.
- **Change ID:** baseline
- **Prerequisites:** —
- **Risk:** minimal enabler only.
- **Status:** ready

## Slices

### S-01: Sign in

- **Outcome:** a user signs in.
- **Change ID:** account-and-signin
- **Prerequisites:** F-01
- **Status:** proposed

### S-02: Extra stream item

- **Outcome:** something in stream F.
- **Change ID:** extra-item
- **Prerequisites:** S-01
- **Status:** proposed

## Backlog Handoff

| Roadmap ID | Change ID          | Suggested issue title                | Ready for `/10x-plan` | Notes            |
| ---------- | ------------------ | ------------------------------------ | --------------------- | ---------------- |
| F-01       | baseline           | Wire the baseline for domain code    | yes                   | Unblocks S-01    |
| S-01       | account-and-signin | Sign-in with GitHub and email        | no                    | Run after F-01   |
MD

# shellcheck disable=SC2034 # read by roadmap-parse.sh when sourced
ROADMAP_STREAMS=(A B C D E F)
# shellcheck disable=SC2034 # read by roadmap-parse.sh when sourced
ROADMAP_TITLES_TSV=""
# shellcheck source=roadmap-parse.sh
source "$DIR/roadmap-parse.sh"
TSV="$(roadmap_tsv "$TMP/roadmap.md")"
cell() { printf '%s\n' "$TSV" | awk -F'\t' -v id="$1" -v c="$2" '$1==id{print $c; exit}'; }

echo "== roadmap-parse contract =="
check "header names the new columns" "suggested_title risk notes ready_for_plan" \
  "$(printf '%s\n' "$TSV" | head -1 | cut -f12-15 | tr '\t' ' ')"
check "F-01 suggested_title from Backlog Handoff" "Wire the baseline for domain code" "$(cell F-01 12)"
check "F-01 risk" "minimal enabler only." "$(cell F-01 13)"
check "F-01 notes" "Unblocks S-01" "$(cell F-01 14)"
check "F-01 ready_for_plan" "yes" "$(cell F-01 15)"
check "S-01 ready_for_plan" "no" "$(cell S-01 15)"
check "S-02 without a handoff row has no suggested title" "" "$(cell S-02 12)"
check "S-02 stream F from ROADMAP_STREAMS" "F" "$(cell S-02 4)"
check "title falls back to the suggested title without a sidecar" "Sign-in with GitHub and email" \
  "$(roadmap_title_en S-01 "$(cell S-01 12)")"

sed 's/^### S-02: Extra stream item$/### S-01: Duplicate heading/' "$TMP/roadmap.md" > "$TMP/duplicate.md"
set +e
roadmap_tsv "$TMP/duplicate.md" > /dev/null 2> "$TMP/err"
rc=$?
set -e
check "a duplicate ID exits 2" "2" "$rc"
check "the duplicate is named" "roadmap-parse: duplicate id S-01" "$(cat "$TMP/err")"

echo
if [[ "$fails" -eq 0 ]]; then echo "OK: PASS (all assertions green)"; else echo "FAIL ($fails assertions failed)"; exit 1; fi
