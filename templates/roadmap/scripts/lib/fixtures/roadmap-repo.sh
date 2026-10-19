#!/usr/bin/env bash
# Shared setup of the roadmap toolkit tests (sourced): a throwaway consumer repository with the
# canonical scripts, the SkillSprintPlus example config and the gh stub on PATH.
#   roadmap_repo DIR      → DIR/scripts/** and DIR/scripts/lib/roadmap-config.sh
#   roadmap_gh STATE_DIR  → exports GH_STATE, GH_LOG, GH_REPO, GH_OWNER and puts the stub first on PATH

ROADMAP_KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"   # templates/roadmap

roadmap_repo() {
  local dir="$1"
  mkdir -p "$dir/scripts" "$dir/context/foundation"
  cp -R "$ROADMAP_KIT/scripts/." "$dir/scripts/"
  cp "$ROADMAP_KIT/examples/roadmap-config.skillsprintplus.sh" "$dir/scripts/lib/roadmap-config.sh"
}

roadmap_gh() {
  local state="$1"
  mkdir -p "$state/bin"
  cp "$ROADMAP_KIT/scripts/lib/fixtures/gh-stub" "$state/bin/gh"
  chmod +x "$state/bin/gh"
  export GH_STATE="$state" GH_LOG="$state/gh.log" GH_REPO="o/r" GH_OWNER="o"
  : > "$GH_LOG"
  PATH="$state/bin:$PATH"
  export PATH
}
