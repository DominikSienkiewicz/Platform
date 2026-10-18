#!/usr/bin/env bash
# The "Check Grype exceptions" step of security-scan.yml, cut out between its markers and run as-is:
# an expired .grype.yaml entry fails, an undated one warns, a dated one passes, no file passes.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { local message="$1"; echo "FAIL: $message" >&2; echo "--- output ---" >&2; echo "$OUT" >&2; exit 1; }

step="$tmp/grype-exceptions.sh"
awk '
  index($0, "# >>> grype-exceptions") { inside = 1; next }
  index($0, "# <<< grype-exceptions") { inside = 0 }
  inside
' "$root/.github/workflows/security-scan.yml" > "$step"
OUT=""
[[ -s "$step" ]] || fail 'security-scan.yml has no grype-exceptions block between its markers'

# run_case <name> [<.grype.yaml content>]: runs the step in a directory with that config; sets RC and OUT.
run_case() {
  local dir="$tmp/$1"
  mkdir -p "$dir"
  if [[ $# -gt 1 ]]; then printf '%s\n' "$2" > "$dir/.grype.yaml"; fi
  RC=0
  OUT="$(cd "$dir" && bash "$step" 2>&1)" || RC=$?
}

run_case none
[[ $RC -eq 0 ]] || fail 'a repository without .grype.yaml must pass'

run_case expired 'ignore:
  # expires: 2000-01-01; tracking: https://example.test/1; reason: test
  - vulnerability: GHSA-aaaa-bbbb-cccc'
[[ $RC -ne 0 ]] || fail 'an expired exception must fail the scan'
grep -q '::error file=.grype.yaml,line=3::.*GHSA-aaaa-bbbb-cccc.*expired on 2000-01-01' <<<"$OUT" || fail 'the error must name the entry, its line and its date'

run_case undated 'ignore:
  # reason: nobody wrote a date
  - vulnerability: CVE-2026-0001'
[[ $RC -eq 0 ]] || fail 'an undated exception warns but does not fail'
grep -q '::warning file=.grype.yaml,line=3::.*CVE-2026-0001.*no # expires' <<<"$OUT" || fail 'an undated exception must warn'

run_case dated 'ignore:
  # expires: 2999-12-31; tracking: https://example.test/2; reason: test
  - vulnerability: CVE-2026-0002
    package:
      name: undici
  # expires: 2999-12-31; tracking: https://example.test/3; reason: test
  - package:
      name: left-pad'
[[ $RC -eq 0 ]] || fail 'dated exceptions in the future must pass'
if grep -q '::' <<<"$OUT"; then fail 'dated exceptions must not warn'; fi

# The date belongs to the entry right below it, not to every later one.
run_case one-date 'ignore:
  # expires: 2999-12-31; tracking: https://example.test/4; reason: test
  - vulnerability: CVE-2026-0003
  - vulnerability: CVE-2026-0004'
grep -q '::warning.*CVE-2026-0004' <<<"$OUT" || fail 'an expiry must not carry over to the next entry'

# The template carries a real date; a stub date keeps this case independent of the day CI runs.
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\necho 2026-01-01\n' > "$tmp/bin/date"
chmod +x "$tmp/bin/date"
PATH="$tmp/bin:$PATH" run_case template "$(cat "$root/templates/grype.yaml")"
[[ $RC -eq 0 ]] || fail 'templates/grype.yaml must be a valid, dated example'
if grep -q '::' <<<"$OUT"; then fail 'templates/grype.yaml must not warn'; fi

echo 'OK: expired Grype exceptions fail, undated ones warn, dated ones pass'
