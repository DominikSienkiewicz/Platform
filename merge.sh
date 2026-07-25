#!/usr/bin/env bash
# Platform consumes its canonical template directly so its own helper cannot drift.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/templates/merge.sh" "$@"
