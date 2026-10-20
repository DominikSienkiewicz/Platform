#!/usr/bin/env bash
# Job sonar w ci.yml analizuje każdy moduł także wtedy, gdy analiza wcześniejszego się nie powiedzie, i zwraca
# błąd dopiero po pętli: z `set -e` pierwszy czerwony moduł kończył krok, więc security-starter nie dostawał
# analizy. Blok między markerami sonar-modules biegnie naprawdę na atrapach ./gradlew (bez sieci i bez Gradle).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" >&2 2>/dev/null || true; exit 1; }

awk -v start='# >>> sonar-modules' -v end='# <<< sonar-modules' '
  index($0, start) { inside = 1; next }
  index($0, end) { inside = 0 }
  inside { sub(/^          /, ""); print }
' "$root/.github/workflows/ci.yml" > "$tmp/modules.sh"
[[ -s "$tmp/modules.sh" ]] || fail 'ci.yml has no sonar-modules block between its markers'

# Atrapa ./gradlew modułu: dopisuje jego nazwę do $CALLS i kończy się kodem z pliku exit-code.
stub() {
  mkdir -p "$tmp/repo/gradle/$1"
  printf '%s\n' "$2" > "$tmp/repo/gradle/$1/exit-code"
  cat > "$tmp/repo/gradle/$1/gradlew" <<'EOF'
#!/usr/bin/env bash
basename "$PWD" >> "$CALLS"
exit "$(cat exit-code)"
EOF
  chmod +x "$tmp/repo/gradle/$1/gradlew"
}
analyse() { (cd "$tmp/repo" && CALLS="$tmp/calls" bash -euo pipefail "$tmp/modules.sh") > "$tmp/out" 2>&1; }

stub test-fixtures 1
stub security-starter 0
: > "$tmp/calls"
if analyse; then fail 'a failing analysis of one module must fail the step'; fi
[[ "$(cat "$tmp/calls")" == $'test-fixtures\nsecurity-starter' ]] \
  || fail "every module must be analysed after one fails, got: $(tr '\n' ' ' < "$tmp/calls")"
grep -qF '::error::gradle/test-fixtures' "$tmp/out" || fail 'the step must name the module whose analysis failed'

stub test-fixtures 0
: > "$tmp/calls"
analyse || fail 'the step must pass when every analysis passes'

echo 'OK: the sonar job analyses every module and fails after the loop when one of them fails'
