#!/usr/bin/env bash
# canary.sh [--consumers-dir <dir>] [--gradle "<tasks>"] — niewydana Platform z HEAD na KAŻDYM konsumencie
# z scripts/consumers.txt, zanim niezmienny tag trafi do wszystkich (N-REL-1). Lokalnie, nie w publicznym CI:
# konsumenci są prywatni, a raport o nich nie wychodzi z maszyny właściciela.
#   - checkout konsumenta: <dir>/<nazwa> albo <dir>/<nazwa bez _com> (domyślnie katalog obok Platform,
#     PLATFORM_CONSUMERS_DIR nadpisuje);
#   - każdy przez scripts/preview-on-consumer.sh --frontend na jednym wspólnym repozytorium podglądu
#     (moduły publikowane raz): szybki pas backendu i platform-versions-check frontendu na kanonie z drzewa;
#   - wynik "PASS|FAIL|MISSING <owner/name>" dla pełnego SHA HEAD w <git-common-dir>/platform-canary/<sha>,
#     który czyta release.sh — wydanie bez zielonego wyniku wymaga --skip-canary "<powód>".
# Drzewo robocze musi być czyste: wynik należy do commita, który zostanie otagowany.
# Test: templates/tests/canary.test.sh (podgląd podmienia CANARY_PREVIEW).
set -euo pipefail
usage='Usage: scripts/canary.sh [--consumers-dir <dir>] [--gradle "<tasks>"]'
root=$(cd "$(dirname "$0")/.." && pwd)
preview=${CANARY_PREVIEW:-$root/scripts/preview-on-consumer.sh}
consumers_dir=${PLATFORM_CONSUMERS_DIR:-$(dirname "$root")}
gradle_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --consumers-dir) consumers_dir=${2:?"--consumers-dir needs a directory. $usage"}; shift ;;
    --gradle) gradle_args=(--gradle "${2:?"--gradle needs the tasks. $usage"}"); shift ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
  shift
done

if [[ -n "$(git -C "$root" status --porcelain --untracked-files=all)" ]]; then
  echo "Commit or set aside the changes first: the canary records its result for HEAD." >&2
  exit 2
fi
sha=$(git -C "$root" rev-parse HEAD)
record_dir="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)/platform-canary"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

results=()
while read -r repo; do
  name=${repo##*/}
  dir=""
  for candidate in "$consumers_dir/$name" "$consumers_dir/${name%_com}"; do
    if [[ -e "$candidate/.git" ]]; then dir=$candidate; break; fi
  done
  if [[ -z "$dir" ]]; then
    echo "==> $repo: no checkout under $consumers_dir" >&2
    results+=("MISSING $repo")
    continue
  fi
  if bash "$preview" "$dir" --frontend --staging "$staging" "${gradle_args[@]+"${gradle_args[@]}"}" < /dev/null; then
    results+=("PASS $repo")
  else
    results+=("FAIL $repo")
  fi
done < <(grep -Ev '^[[:space:]]*(#|$)' "$root/scripts/consumers.txt")

mkdir -p "$record_dir"
printf '%s\n' "${results[@]}" > "$record_dir/$sha"
echo ""
echo "Consumer canary for ${sha:0:7} (recorded for release.sh):"
printf '  %s\n' "${results[@]}"
if printf '%s\n' "${results[@]}" | grep -qv '^PASS '; then
  exit 1
fi
