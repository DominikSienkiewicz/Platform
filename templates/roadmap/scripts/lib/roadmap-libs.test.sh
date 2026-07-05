#!/usr/bin/env bash
# Regression: every script calling a roadmap_* helper MUST source the file that defines it,
# and in the canonical order (config → lib → parse). Catches "command not found: roadmap_…".
# Additionally: the parallel VALUES arrays must be equal length (using the bookofstyling example
# config), so a mis-sized palette never silently indexes past the end. Purely static — no GitHub.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$DIR/.." && pwd)"
TEMPLATE_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"        # templates/roadmap
fails=0

# ---- 1. helper definitions: each script sources config + lib + parse -------------
for s in roadmap-project-setup.sh roadmap-to-issues.sh roadmap-unblock.sh; do
  path="$SCRIPTS_DIR/$s"
  # lib files sourced by the script
  libs="$(grep -oE 'lib/[a-z.-]+\.sh' "$path" | sed 's#^lib/#scripts/lib/#' | sort -u)"
  # required source set: config + lib + parse must all be present
  for req in scripts/lib/roadmap-config.sh scripts/lib/roadmap-lib.sh scripts/lib/roadmap-parse.sh; do
    if printf '%s\n' "$libs" | grep -qxF "$req"; then :; else
      printf '  ✗ %-26s does not source %s\n' "$s" "$req"; fails=$((fails+1))
    fi
  done

  # called roadmap_* helpers (underscore — not the roadmap-*.sh filenames)
  refs="$(grep -oE 'roadmap_[a-z_]+' "$path" | sort -u)"
  # For sourcing we need a config VALUES file present as scripts/lib/roadmap-config.sh;
  # the shipped file is roadmap-config.sh.example — use the bookofstyling example as the values.
  missing="$(
    source "$TEMPLATE_ROOT/examples/roadmap-config.bookofstyling.sh" 2>/dev/null || true
    # shellcheck disable=SC1091
    source "$SCRIPTS_DIR/lib/roadmap-lib.sh" 2>/dev/null || true
    # shellcheck disable=SC1091
    source "$SCRIPTS_DIR/lib/roadmap-parse.sh" 2>/dev/null || true
    for f in $refs; do
      if ! declare -F "$f" >/dev/null 2>&1; then printf '%s ' "$f"; fi
    done
  )"
  if [ -n "${missing// /}" ]; then
    printf '  ✗ %-26s undefined helpers: %s\n' "$s" "$missing"; fails=$((fails+1))
  else
    printf '  ✓ %-26s all roadmap_* helpers defined, config+lib+parse sourced\n' "$s"
  fi
done

echo

# ---- 2. parallel array lengths (bookofstyling example config) --------------------
(
  # shellcheck disable=SC1091
  source "$TEMPLATE_ROOT/examples/roadmap-config.bookofstyling.sh"
  arr_fail=0
  eq() { # eq NAME_A LEN_A NAME_B LEN_B
    if [ "$2" = "$4" ]; then
      printf '  ✓ %s (%s) == %s (%s)\n' "$1" "$2" "$3" "$4"
    else
      printf '  ✗ %s (%s) != %s (%s)\n' "$1" "$2" "$3" "$4"; arr_fail=1
    fi
  }
  ns="${#ROADMAP_STATUSES[@]}"
  eq "#STATUSES" "$ns" "#STATUS_COLORS"       "${#ROADMAP_STATUS_COLORS[@]}"
  eq "#STATUSES" "$ns" "#STATUS_DESCS"        "${#ROADMAP_STATUS_DESCS[@]}"
  eq "#STATUSES" "$ns" "#STATUS_LABEL_COLORS" "${#ROADMAP_STATUS_LABEL_COLORS[@]}"
  nr="${#ROADMAP_STREAMS[@]}"
  eq "#STREAMS"  "$nr" "#STREAM_LABEL_COLORS" "${#ROADMAP_STREAM_LABEL_COLORS[@]}"
  exit "$arr_fail"
) || fails=$((fails+1))

echo
if [ "$fails" -eq 0 ]; then echo "OK: PASS"; else echo "FAIL ($fails checks)"; exit 1; fi
