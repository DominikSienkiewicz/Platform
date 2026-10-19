#!/usr/bin/env bash
# Runner migracji wydania: platform-bump woła KOPIĘ z rozpakowanego tarballa wydania docelowego, więc zawsze
# biegnie logika celu, nie zainstalowana. Migracja = migrations/<SINCE>-<slug>.sh (albo every-<slug>.sh: każdy
# bump) z funkcjami describe, touches, detect (0 = do zrobienia, 1 = nic, 2 = ręcznie) i apply. Działa na
# drzewie roboczym w CWD (root repo), bez sieci, commitów i pushy; musi być idempotentna.
#
#   run.sh files <current> <target>   # pliki, które pasujące migracje mogą zmienić (migawka do rollbacku)
#   run.sh apply <current> <target>   # uruchamia pasujące migracje w kolejności SINCE
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mode=${1:?files or apply}
current=${2:-0.0.0}
target=${3:?target version}
[[ -n "$current" ]] || current=0.0.0
export MIGRATION_LIB="$here/lib"

# call <migration> <function>: każda funkcja w osobnym podpowłoce, żeby migracje się nie przenikały.
call() {
  # shellcheck source=/dev/null
  ( source "$1" && "$2" )
}

key() { local IFS=.; read -r -a part <<<"$1"; printf '%05d%05d%05d' "${part[0]}" "${part[1]}" "${part[2]}"; }

# Pasujące migracje w kolejności: wersje SINCE rosnąco (CUR < SINCE <= TARGET), potem every-*.
selected() {
  local file name since
  for file in "$here"/*.sh; do
    name=${file##*/}
    [[ "$name" == run.sh ]] && continue
    since=${name%%-*}
    if [[ "$since" == every ]]; then
      printf '99999999999999999 %s\n' "$file"
    elif [[ "$since" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$(key "$current")" < "$(key "$since")" ]] \
      && ! [[ "$(key "$target")" < "$(key "$since")" ]]; then
      printf '%s %s\n' "$(key "$since")" "$file"
    fi
  done | LC_ALL=C sort | cut -d' ' -f2-
}

case "$mode" in
  files)
    while IFS= read -r migration; do
      call "$migration" touches
    done < <(selected) | LC_ALL=C sort -u
    ;;
  apply)
    while IFS= read -r migration; do
      slug=${migration##*/}
      slug=${slug%.sh}
      set +e
      notes=$(call "$migration" detect)
      status=$?
      set -e
      case "$status" in
        0)
          call "$migration" apply
          echo "  applied  $slug: $(call "$migration" describe)"
          ;;
        1) echo "  skipped  $slug (not needed here)" ;;
        2)
          echo "  manual   $slug: $(call "$migration" describe)"
          [[ -z "$notes" ]] || printf '%s\n' "$notes" | sed 's/^/           /'
          ;;
        *) echo "Migration $slug failed in detect (exit $status)." >&2; exit 1 ;;
      esac
    done < <(selected)
    ;;
  *) echo "Usage: run.sh files|apply <current> <target>" >&2; exit 2 ;;
esac
