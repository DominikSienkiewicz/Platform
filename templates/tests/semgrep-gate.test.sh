#!/usr/bin/env bash
# Bramka PLAT-SAST-001 w reusable semgrep.yml. Semgrep ma dwie skale severity: dawną ERROR/WARNING/INFO i nową
# CRITICAL/HIGH/MEDIUM/LOW (np. reguły package_managers). Bramka liczyła tylko dawną, więc znalezisko HIGH albo
# CRITICAL przechodziło, a MEDIUM nie trafiało nawet do podsumowania. Test wycina prawdziwy blok `run:` kroku skanu
# z YAML-a i uruchamia go z atrapą `semgrep`, która zapisuje przygotowany wynik JSON.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/semgrep.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" >&2 2>/dev/null; exit 1; }

awk '
  index($0, "      - name: Semgrep — SAST") == 1 { selected = 1; next }
  selected && /^        run: \|$/ { body = 1; next }
  body && /^$/ { print ""; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$workflow" > "$tmp/gate.sh"
[[ -s "$tmp/gate.sh" ]] || fail 'semgrep.yml has no "Semgrep — SAST" step with a run block'

mkdir "$tmp/bin"
cat > "$tmp/bin/semgrep" <<'STUB'
#!/usr/bin/env bash
# Atrapa: zapisuje $FAKE_RESULT pod ścieżką z --output i kończy się kodem $FAKE_RC.
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then output=$2; fi
  shift
done
if [ -n "${FAKE_RESULT:-}" ]; then cp "$FAKE_RESULT" "$output"; fi
exit "${FAKE_RC:-0}"
STUB
chmod +x "$tmp/bin/semgrep"

# result <plik> <severity>...: wynik Semgrepa z jednym znaleziskiem na każdą podaną severity.
result() {
  local file=$1
  shift
  jq -n '{results: [$ARGS.positional | to_entries[]
    | {check_id: "rule.\(.value | ascii_downcase)", path: "src/file\(.key).py", start: {line: (.key + 1)},
       extra: {severity: .value}}]}' --args "$@" > "$file"
}

# gate <wynik> [kod semgrep]: uruchamia blok bramki, zapisuje wyjście w $tmp/out i zwraca jej kod wyjścia.
gate() {
  local work
  work=$(mktemp -d "$tmp/run.XXXXXX")
  (cd "$work" && PATH="$tmp/bin:$PATH" SEMGREP_CONFIGS='p/default p/secrets' FAKE_RESULT=$1 FAKE_RC=${2:-0} \
    bash "$tmp/gate.sh") > "$tmp/out" 2>&1
}

for blocking in ERROR HIGH CRITICAL; do
  result "$tmp/$blocking.json" "$blocking"
  if gate "$tmp/$blocking.json" 1; then fail "a $blocking finding must fail the gate"; fi
  grep -qF '::error title=PLAT-SAST-001::[PLAT-SAST-001] Semgrep found 1 blocking finding' "$tmp/out" \
    || fail "a $blocking finding must be reported as PLAT-SAST-001"
  grep -qF "rule.$(tr '[:upper:]' '[:lower:]' <<< "$blocking")" "$tmp/out" || fail "the $blocking finding must be listed"
done

result "$tmp/mixed.json" HIGH ERROR CRITICAL MEDIUM WARNING
if gate "$tmp/mixed.json" 1; then fail 'blocking findings among advisory ones must fail the gate'; fi
grep -qF 'Semgrep found 3 blocking findings' "$tmp/out" || fail 'the gate must count CRITICAL, HIGH and ERROR together'

result "$tmp/advisory.json" MEDIUM WARNING LOW INFO MEDIUM
gate "$tmp/advisory.json" 1 || fail 'MEDIUM, WARNING, LOW and INFO findings are log-only'
grep -qF 'Semgrep: 2 MEDIUM, 1 WARNING, 1 LOW, 1 INFO; 0 blocking (CRITICAL, HIGH, ERROR)' "$tmp/out" \
  || fail 'the summary must count every severity, MEDIUM and LOW included'
if grep -q '^::error' "$tmp/out"; then fail 'advisory findings must not be annotated as errors'; fi

result "$tmp/unknown.json" INVENTORY
gate "$tmp/unknown.json" 1 || fail 'a severity outside both scales is log-only'
grep -qF 'Semgrep: 1 INVENTORY; 0 blocking' "$tmp/out" || fail 'the summary must also count a severity it does not know'

result "$tmp/clean.json"
gate "$tmp/clean.json" || fail 'a clean scan must pass'
grep -qF 'Semgrep: no findings; 0 blocking' "$tmp/out" || fail 'a clean scan must say so'

if gate '' 2; then fail 'a scan without a result must fail'; fi
grep -qF 'Semgrep produced no result (rc=2)' "$tmp/out" || fail 'a scan without a result must say why it failed'

echo 'OK: semgrep.yml blocks CRITICAL, HIGH and ERROR findings and counts every severity'
