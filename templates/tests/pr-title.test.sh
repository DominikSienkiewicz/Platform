#!/usr/bin/env bash
# Job pr-title w ci.yml: tytuł PR-a sprawdzany wzorcem CONVENTIONAL z release.sh (jedno źródło), tylko na pull_request.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

awk '
  $0 == "      - name: Check the title" { selected = 1; next }
  selected && /^        run: \|$/ { body = 1; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$root/.github/workflows/ci.yml" > "$tmp/title.sh"
[[ -s "$tmp/title.sh" ]] || fail 'ci.yml has no "Check the title" step'
# shellcheck disable=SC2016 # literal GitHub expression
grep -qF "if: \${{ github.event_name == 'pull_request' }}" "$root/.github/workflows/ci.yml" || fail 'pr-title must run only on pull requests'

cp "$root/release.sh" "$tmp/release.sh"
check() { (cd "$tmp" && TITLE="$1" bash "$tmp/title.sh") > "$tmp/out" 2>&1; }
for title in 'feat(versions): add upgrade migrations' 'fix: keep the lockfile' 'ci!: require packages: read'; do
  check "$title" || { cat "$tmp/out"; fail "\"$title\" is a Conventional Commit"; }
done
for title in 'ci fix' 'Update scripts' 'feat:missing space' 'Feat: capital type'; do
  if check "$title"; then fail "\"$title\" is not a Conventional Commit"; fi
  grep -qF 'must be a Conventional Commit' "$tmp/out" || { cat "$tmp/out"; fail 'the failure must explain the rule'; }
done

sed -i.bak '/^CONVENTIONAL=/d' "$tmp/release.sh"
if check 'fix: anything'; then fail 'without the pattern in release.sh the check must fail, not pass everything'; fi

# Ruleset main wymaga checka pr-title po nazwie joba (kontekst statusu); zmiana nazwy joba bez rulesetu po cichu
# zdjęłaby wymóg.
job_name=$(awk '$0 == "  pr-title:" { job = 1; next } job && /^    name: / { sub(/^    name: /, ""); print; exit }' "$root/.github/workflows/ci.yml")
[[ -n "$job_name" ]] || fail 'the pr-title job of ci.yml must have a name'
jq -e --arg context "$job_name" \
  'any(.rules[]; .type == "required_status_checks" and any(.parameters.required_status_checks[]; .context == $context and .integration_id == 15368))' \
  "$root/.github/rulesets/main.json" > /dev/null \
  || fail "the main ruleset must require the GitHub Actions check \"$job_name\""

echo 'OK: pr-title checks pull request titles with the Conventional Commit pattern of release.sh, and main requires it'
