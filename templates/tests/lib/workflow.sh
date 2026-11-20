#!/usr/bin/env bash
# Wspólne helpery testów workflowów, źródłowane przez templates/tests/*.test.sh, które wycinają joby, kroki
# i bloki między znacznikami z .github/workflows/*.yml. Źródłujący ustawia `workflow` na testowany plik YAML.
# Wszystkie testy workflowów mają ten sam układ: `# >>> nazwa` / `# <<< nazwa` w kroku `run: |` (wcięcie 10 spacji).

# shellcheck disable=SC2034,SC2154 # root i workflow należą do źródłującego testu
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

# fail <komunikat>: kończy test; jeśli test zapisał wyjście badanego bloku do "$tmp/out", pokazuje je.
fail() {
  echo "FAIL: $*" >&2
  cat "${tmp:-/dev/null}/out" 2>/dev/null >&2 || true
  exit 1
}

# block <nazwa>: treść bloku między znacznikami, bez wcięcia YAML.
block() {
  awk -v from="# >>> $1" -v to="# <<< $1" \
    'index($0, from) { inside = 1; next } index($0, to) { inside = 0 } inside { sub(/^          /, ""); print }' "$workflow"
}

# job <nazwa>: treść joba (wszystko pod `  <nazwa>:` do następnego joba).
job() { awk -v start="  $1:" '$0 == start { p = 1; next } /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { p = 0 } p' "$workflow"; }

# step <job> <nazwa>: krok joba od wiersza `- name: <nazwa>…` do następnego kroku.
step() { awk -v name="      - name: $2" 'index($0, name) == 1 { p = 1; print; next } p && /^      - / { p = 0 } p' <<< "$(job "$1")"; }

# line_of <job> <tekst>: numer pierwszego wiersza joba z tym tekstem.
line_of() { grep -nF -- "$2" <<< "$(job "$1")" | head -1 | cut -d: -f1; }

# pinned <akcja> <tekst>: tekst ma `uses: <akcja>@<40 hex> # vX.Y.Z`.
pinned() { grep -qE "^        uses: $1@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$" <<< "$2"; }

# extract_step <plik> <krok>: skrypt z `run: |` kroku o dokładnie tej nazwie, bez wcięcia YAML.
extract_step() {
  awk -v step="$2" '
    $0 == "      - name: " step { selected = 1; next }
    selected && /^        run: \|$/ { body = 1; next }
    body && /^          / { sub(/^          /, ""); print; next }
    body { exit }
  ' "$1"
}

# step_condition <plik> <krok>: wiersz `if:` kroku o dokładnie tej nazwie.
step_condition() {
  awk -v step="$2" '
    $0 == "      - name: " step { selected = 1; next }
    selected && /^        if: / { print; exit }
    selected && /^      - / { exit }
  ' "$1"
}
