#!/usr/bin/env bash
# Copy to scripts/agent-gradle.sh in a consumer. Explicitly opt in with AI_AGENT=1 or true.
set -euo pipefail
cd "$(dirname "$0")/.."
case "${AI_AGENT:-}" in
  1|true) exec ./gradlew "$@" --max-workers=2 --no-parallel ;;
  *) exec ./gradlew "$@" ;;
esac
