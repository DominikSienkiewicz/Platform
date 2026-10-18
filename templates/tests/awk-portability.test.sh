#!/usr/bin/env bash
# Shell scripts and workflows must not hand awk a `-v` variable named after a gawk builtin.
#
# The macOS awk (BWK) accepts such names, gawk on the Ubuntu runners aborts with
# "cannot use gawk builtin ... as variable name". The script then passes locally and fails only
# in CI, which is how templates/tests/release-gated-on-ci.test.sh broke the first push of the
# release gate. This guard is a static scan, so it fails on every platform.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  local message="$1"
  echo "FAIL: $message" >&2
  exit 1
}

# gawk builtin functions and keywords; none of them may be the target of `-v name=value`.
reserved='
  and asort asorti atan2 bindtextdomain close compl cos dcgettext dcngettext exp fflush gensub
  gsub index int isarray length log lshift match mkbool mktime or patsplit rand rshift sin split
  sprintf sqrt srand strftime strtonum sub substr system systime tolower toupper typeof xor
  BEGIN BEGINFILE END ENDFILE break case continue default delete do else exit for func function
  getline if in next nextfile print printf return switch while
'
names=$(echo "$reserved" | xargs | tr ' ' '|')
pattern="(^|[^[:alnum:]_])g?awk[[:space:]]([^|]*[[:space:]])?-v[[:space:]]*($names)="

reserved_assignments() {
  grep -nE "$pattern" "$@" || true
}

# --- The detector itself ---------------------------------------------------------------------
bad=close
fixture="$tmp/fixture.sh"
printf '%s\n' \
  "awk -v ${bad}=x '{ print }' file" \
  "awk -v start=a -v${bad}=b '{ print }' file" \
  "awk -v closed=x '{ print }' file" \
  "awk -v end_marker=x '{ print }' file" >"$fixture"
found=$(reserved_assignments "$fixture")
[[ "$(grep -c . <<<"$found")" == 2 ]] \
  || fail "detector must flag exactly the two reserved assignments in the fixture, got: $found"
grep -q '^1:' <<<"$found" || fail 'detector must flag a reserved name after a space'
grep -q '^2:' <<<"$found" || fail 'detector must flag a reserved name glued to -v'

# --- Every tracked script and workflow -------------------------------------------------------
files=()
while IFS= read -r file; do files+=("$root/$file"); done < <(
  git -C "$root" ls-files '*.sh' '*.yml' '*.yaml'
)
[[ "${#files[@]}" -gt 0 ]] || fail 'no tracked *.sh or workflow files found'
offenders=$(reserved_assignments "${files[@]}")
[[ -z "$offenders" ]] \
  || fail "awk -v must not assign a gawk builtin name (rename the variable):
${offenders//$root\//}"

echo 'OK: no awk -v assignment uses a gawk builtin name'
