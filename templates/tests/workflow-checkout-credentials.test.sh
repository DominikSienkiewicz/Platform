#!/usr/bin/env bash
# Every actions/checkout step sets persist-credentials: false, so no later step that runs repository or
# dependency code finds the token in .git/config. A checkout handed an explicit token: exists to push
# with it (promote.yml writes the GitOps repository) and keeps it.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

missing=""
seen=0
expected=0
for workflow in "$root"/.github/workflows/*.yml; do
  result=$(awk '
    function finish() {
      if (in_step && checkout) { count++; if (!dropped && !token) print "missing " start }
      in_step = 0; checkout = 0; dropped = 0; token = 0
    }
    BEGIN { steps_indent = -1; dash = -1 }
    { match($0, /^ */); indent = RLENGTH }
    /^[[:space:]]*steps:[[:space:]]*$/ { finish(); steps_indent = indent; dash = -1; next }
    steps_indent >= 0 && /^[[:space:]]*- / && indent >= steps_indent && (dash < 0 || indent == dash) {
      if (dash < 0) dash = indent
      finish(); in_step = 1; start = NR
    }
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    steps_indent >= 0 && indent <= steps_indent && !/^[[:space:]]*- / { finish(); steps_indent = -1; dash = -1 }
    in_step && /uses:[[:space:]]*actions\/checkout@/ { checkout = 1 }
    in_step && /persist-credentials:[[:space:]]*false/ { dropped = 1 }
    in_step && /^[[:space:]]*token:/ { token = 1 }
    END { finish(); print "seen " count + 0 }
  ' "$workflow")
  while read -r kind value; do
    case "$kind" in
      missing) missing+="  ${workflow##*/}:$value"$'\n' ;;
      seen) seen=$((seen + value)) ;;
    esac
  done <<< "$result"
  expected=$((expected + $(grep -c 'uses:[[:space:]]*actions/checkout@' "$workflow" || true)))
done

[[ "$seen" -eq "$expected" && "$expected" -gt 0 ]] \
  || { echo "the guard parsed $seen of $expected actions/checkout steps" >&2; exit 1; }

if [[ -n "$missing" ]]; then
  printf 'actions/checkout steps without persist-credentials: false (and without an explicit token):\n%s' "$missing" >&2
  exit 1
fi
echo "OK: all $seen actions/checkout steps drop their credentials, except those handed a token to push with"
