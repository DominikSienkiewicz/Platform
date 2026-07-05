#!/usr/bin/env bash
# CANON of the LOGIC is Platform; THIS file is per-repo values — copy to
# scripts/lib/roadmap-config.sh in SkillSprintPlus and edit. Never re-synced from Platform.
#
# VALUES file sourced by roadmap-lib.sh + the three roadmap scripts. Variables are consumed
# ACROSS files, so SC2034 is intentionally silenced (shellcheck sees this file in isolation).
# shellcheck disable=SC2034

# --- Project + document paths (per-repo) -----------------------------------------
ROADMAP_PROJECT_TITLE="SkillSprintPlus Roadmap"
ROADMAP_DOC_PATH="context/foundation/roadmap.md"
ROADMAP_TITLES_TSV=""                                   # no EN titles sidecar
ROADMAP_DEFAULT_ASSIGNEE="DominikSienkiewicz"

# --- Canonical Status field (shared across all repos) ----------------------------
ROADMAP_STATUSES=(backlog ready in-progress blocked in-review "done")
ROADMAP_STATUS_COLORS=(GRAY BLUE YELLOW RED PURPLE GREEN)
ROADMAP_STATUS_DESCS=(
  "Proposed roadmap item; not yet started"
  "Prerequisites met; ready to pick up"
  "Actively being worked on"
  "Blocked by an open prerequisite or decision"
  "Implementation complete; under review"
  "Delivered / archived"
)

# --- Canonical Streams (shared across all repos) ---------------------------------
ROADMAP_STREAMS=(A B C D E)

# --- Label colors (hex, no #) — SkillSprintPlus palette --------------------------
ROADMAP_TYPE_LABEL_COLORS=(1D76DB 0E8A16)                  # foundation, slice
ROADMAP_STREAM_LABEL_COLORS=(FBCA04 FBCA04 FBCA04 FBCA04 FBCA04)  # parallel to ROADMAP_STREAMS
ROADMAP_STATUS_LABEL_COLORS=(EDEDED 0E8A16 FBCA04 D73A4A 5319E7 6F42C1)  # parallel to ROADMAP_STATUSES
