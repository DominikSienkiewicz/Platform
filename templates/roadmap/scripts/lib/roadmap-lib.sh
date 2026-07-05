#!/usr/bin/env bash
# CANONICAL helpers over roadmap-config.sh values — synced from Platform, do not edit per-repo.
#
# The single source of truth for the 6 statuses, 5 streams and the label set lives in
# roadmap-config.sh (per-repo VALUES). These helpers derive labels/colors/descriptions
# from those arrays so the scripts never drift apart.
#
# Source order (required): roadmap-config.sh → roadmap-lib.sh → roadmap-parse.sh.
# bash 3.2 safe (macOS): indexed arrays + a plain for loop, NO `declare -A`.

# Roadmap status → board Status option (mirrored in the status:* label).
roadmap_board_status() {
  case "$1" in
    proposed) echo backlog ;;
    ready)    echo ready ;;
    blocked)  echo blocked ;;
    *)        echo "$1" ;;   # in-progress/in-review/done — passthrough (work in flight)
  esac
}

# Full label set (idempotently created by the generator).
roadmap_all_labels() {
  printf '%s\n' type:foundation type:slice
  local s
  for s in "${ROADMAP_STREAMS[@]}";  do printf 'stream:%s\n' "$s"; done
  for s in "${ROADMAP_STATUSES[@]}"; do printf 'status:%s\n' "$s"; done
}

# Index of $1 in the array whose remaining args are its elements; empty if absent.
# Usage: _roadmap_index_of NEEDLE "${ARRAY[@]}"  → echoes 0-based index or "".
_roadmap_index_of() {
  local needle="$1"; shift
  local i=0
  for e in "$@"; do
    if [ "$e" = "$needle" ]; then printf '%s' "$i"; return 0; fi
    i=$((i+1))
  done
  return 1
}

# Label color (hex, no #) — derived from the per-repo palette arrays in roadmap-config.sh.
#   type:foundation → ROADMAP_TYPE_LABEL_COLORS[0]; type:slice → [1]
#   stream:X        → index of X in ROADMAP_STREAMS  → ROADMAP_STREAM_LABEL_COLORS[idx]
#   status:X        → index of X in ROADMAP_STATUSES → ROADMAP_STATUS_LABEL_COLORS[idx]
#   default         → EDEDED
roadmap_label_color() {
  local key="$1" name idx
  case "$key" in
    type:foundation) printf '%s' "${ROADMAP_TYPE_LABEL_COLORS[0]}"; return 0 ;;
    type:slice)      printf '%s' "${ROADMAP_TYPE_LABEL_COLORS[1]}"; return 0 ;;
    stream:*)
      name="${key#stream:}"
      if idx="$(_roadmap_index_of "$name" "${ROADMAP_STREAMS[@]}")"; then
        printf '%s' "${ROADMAP_STREAM_LABEL_COLORS[$idx]}"; return 0
      fi ;;
    status:*)
      name="${key#status:}"
      if idx="$(_roadmap_index_of "$name" "${ROADMAP_STATUSES[@]}")"; then
        printf '%s' "${ROADMAP_STATUS_LABEL_COLORS[$idx]}"; return 0
      fi ;;
  esac
  printf '%s' EDEDED
}

# Label description.
roadmap_label_desc() {
  case "$1" in
    type:foundation)    echo "Roadmap foundation (bounded enabler)" ;;
    type:slice)         echo "Roadmap vertical slice (user-visible outcome)" ;;
    stream:*)           echo "Roadmap stream ${1#stream:} (shared prerequisite chain)" ;;
    status:*)           echo "Mirror of Projects v2 Status = ${1#status:}" ;;
    *)                  echo "" ;;
  esac
}
