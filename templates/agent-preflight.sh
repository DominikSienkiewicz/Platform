#!/usr/bin/env bash
# agent-preflight.sh [-q] — how many agents may run JVM integration tests on this machine right now.
# CANON: Platform/templates/agent-preflight.sh, copied to <repo>/scripts/agent-preflight.sh.
#
# Exit 0: go. Exit 1: reduce concurrency to the number printed. Exit 2: do not start agents at all.
# Reads macOS (vm_stat, sysctl) or Linux (/proc/meminfo). Swap occupancy matters more than free RAM: once a
# machine pages, another agent deepens it, so a swap above AGENT_SWAP_STOP_PERCENT stops everything.
# The defaults were measured on one host (a Spring integration-test agent ~4.3 GB); re-derive them for yours:
#   AGENT_COST_GB (4.3)  AGENT_RESERVE_GB (6)  AGENT_MAX (3)
#   AGENT_SWAP_STOP_PERCENT (70)  AGENT_SWAP_SLOW_PERCENT (40)
# Pair it with agent-gradle.sh, whose AI_AGENT_TEST_SLOTS caps the test runs once agents are started.
set -euo pipefail

quiet=0
[[ "${1:-}" == "-q" ]] && quiet=1
cost=${AGENT_COST_GB:-4.3}
reserve=${AGENT_RESERVE_GB:-6}
max=${AGENT_MAX:-3}
swap_stop=${AGENT_SWAP_STOP_PERCENT:-70}
swap_slow=${AGENT_SWAP_SLOW_PERCENT:-40}
# Test seams: fixture outputs instead of the commands of the running system.
os=${PREFLIGHT_OS:-$(uname -s)}

case "$os" in
  Darwin)
    vm=${PREFLIGHT_VM_STAT:-$(vm_stat)}
    swap=${PREFLIGHT_SWAPUSAGE:-$(sysctl -n vm.swapusage)}
    page=${PREFLIGHT_PAGESIZE:-$(sysctl -n hw.pagesize)}
    read -r free_gb swap_pct < <(awk -v page="$page" -v swap="$swap" '
      /Pages (free|inactive|speculative):/ { gsub(/\./, "", $NF); pages += $NF }
      END {
        n = split(swap, part, " ")
        for (i = 1; i <= n; i++) {
          if (part[i] == "total") { total = part[i + 2]; sub(/M/, "", total) }
          if (part[i] == "used") { used = part[i + 2]; sub(/M/, "", used) }
        }
        printf "%.1f %.0f\n", pages * page / 1073741824, (total > 0 ? 100 * used / total : 0)
      }' <<<"$vm")
    ;;
  Linux)
    meminfo=${PREFLIGHT_MEMINFO:-/proc/meminfo}
    read -r free_gb swap_pct < <(awk '
      $1 == "MemAvailable:" { available = $2 }
      $1 == "SwapTotal:" { total = $2 }
      $1 == "SwapFree:" { free = $2 }
      END { printf "%.1f %.0f\n", available / 1048576, (total > 0 ? 100 * (total - free) / total : 0) }' "$meminfo")
    ;;
  *) echo "agent-preflight.sh supports macOS and Linux, not $os." >&2; exit 2 ;;
esac

slots=$(awk -v free="$free_gb" -v reserve="$reserve" -v cost="$cost" -v max="$max" \
  'BEGIN { n = int((free - reserve) / cost); if (n < 0) n = 0; if (n > max) n = max; print n }')
status=0
verdict="GO: room for $slots agents on integration tests"
if awk -v s="$swap_pct" -v f="$free_gb" -v stop="$swap_stop" -v r="$reserve" 'BEGIN { exit !(s >= stop || f < r) }'; then
  status=2
  verdict="STOP: swap ${swap_pct}% and ${free_gb} GB free; the machine is paging, restart it before starting agents"
elif awk -v s="$swap_pct" -v slow="$swap_slow" -v n="$slots" 'BEGIN { exit !(s >= slow || n < 2) }'; then
  status=1
  verdict="REDUCE: run at most $slots agents on integration tests (swap ${swap_pct}%)"
fi
if [[ "$quiet" -eq 0 ]]; then
  echo "free memory  ${free_gb} GB (reserve ${reserve} GB)"
  echo "swap         ${swap_pct}%"
  echo "agent cost   ${cost} GB each, at most ${max}"
  echo "$verdict"
fi
exit "$status"
