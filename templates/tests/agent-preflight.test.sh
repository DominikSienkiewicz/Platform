#!/usr/bin/env bash
# templates/agent-preflight.sh na wyjściach-atrapach vm_stat/sysctl (macOS) i /proc/meminfo (Linux): kody 0, 1 i 2.
# shellcheck disable=SC2015 # `rc check && output check || fail` fails when either check fails, as intended
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" >&2; exit 1; }
: > "$tmp/out"

# vm_stat <free GB>: strony 16 KB, wolne + nieaktywne + spekulatywne
vm_stat_with() {
  local pages=$(( $1 * 65536 ))
  printf 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free:                             %d.\nPages inactive:                         0.\nPages speculative:                      0.\nPages occupied by compressor:           10.\n' "$pages"
}
mac() {
  set +e
  PREFLIGHT_OS=Darwin PREFLIGHT_PAGESIZE=16384 PREFLIGHT_VM_STAT="$(vm_stat_with "$1")" \
    PREFLIGHT_SWAPUSAGE="total = 9216.00M  used = $2M  free = 0.00M  (encrypted)" bash "$root/templates/agent-preflight.sh" > "$tmp/out"
  rc=$?
  set -e
}
linux() {
  printf 'MemTotal:       50331648 kB\nMemAvailable:   %d kB\nSwapTotal:      %d kB\nSwapFree:       %d kB\n' \
    $(( $1 * 1048576 )) 8388608 $(( 8388608 - $2 * 1024 )) > "$tmp/meminfo"
  set +e
  PREFLIGHT_OS=Linux PREFLIGHT_MEMINFO="$tmp/meminfo" bash "$root/templates/agent-preflight.sh" > "$tmp/out"
  rc=$?
  set -e
}

mac 24 0;      [[ $rc -eq 0 ]] && grep -qF 'GO: room for 3 agents' "$tmp/out" || fail "macOS with 24 GB free must go (rc $rc)"
mac 12 0;      [[ $rc -eq 1 ]] && grep -qF 'REDUCE: run at most 1 agents' "$tmp/out" || fail "macOS with 12 GB free must reduce (rc $rc)"
mac 24 4608;   [[ $rc -eq 1 ]] || fail "macOS with 50% swap must reduce (rc $rc)"
mac 24 8800;   [[ $rc -eq 2 ]] && grep -qF 'STOP: swap 95%' "$tmp/out" || fail "macOS with 95% swap must stop (rc $rc)"
linux 30 0;    [[ $rc -eq 0 ]] || fail "Linux with 30 GB available must go (rc $rc)"
linux 4 0;     [[ $rc -eq 2 ]] || fail "Linux below the reserve must stop (rc $rc)"
linux 30 7000; [[ $rc -eq 2 ]] || fail "Linux with 83% swap must stop (rc $rc)"
AGENT_COST_GB=2 AGENT_MAX=6 PREFLIGHT_OS=Linux PREFLIGHT_MEMINFO="$tmp/meminfo" bash "$root/templates/agent-preflight.sh" -q && fail 'a swap above the stop threshold must stop even with a lower agent cost'
linux 30 0
AGENT_COST_GB=2 AGENT_MAX=6 PREFLIGHT_OS=Linux PREFLIGHT_MEMINFO="$tmp/meminfo" bash "$root/templates/agent-preflight.sh" > "$tmp/out"
grep -qF 'GO: room for 6 agents' "$tmp/out" || fail 'the cost and the ceiling must be overridable'

echo 'OK: agent-preflight.sh turns free memory and swap into go, reduce or stop on macOS and Linux'
