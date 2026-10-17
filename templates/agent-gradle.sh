#!/usr/bin/env bash
# Copy to scripts/agent-gradle.sh in a consumer. Explicitly opt in with AI_AGENT=1 or true.
# Runs ./gradlew from the repository root, or backend/gradlew from backend/ when the root has none.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f gradlew && -f backend/gradlew ]]; then cd backend; fi
case "${AI_AGENT:-}" in
  1|true) exec ./gradlew "$@" --max-workers=2 --no-parallel ;;
  *) exec ./gradlew "$@" ;;
esac
