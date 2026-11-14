#!/usr/bin/env bash
# Job example w release.yml: npm, którego woła scripts/render-example.sh w wygenerowanym frontend/, musi dostać
# token GitHub Packages pod nazwą, którą czyta frontend/.npmrc (kopia templates/npmrc: ${GITHUB_TOKEN}), a PAT
# PLATFORM_EXAMPLE_TOKEN widzą tylko kroki, które go potrzebują.
#
# Dlaczego sam NODE_AUTH_TOKEN nie wystarcza: actions/setup-node z registry-url pisze plik użytkownika
# z `_authToken=${NODE_AUTH_TOKEN}`, ale plik projektu ma ten sam klucz i npm bierze go pierwszego. Bez
# GITHUB_TOKEN w środowisku npm zostawia `${GITHUB_TOKEN}` dosłownie jako token i GitHub Packages odpowiada 401.
#
# Zachowanie: render-example.sh biegnie z atrapą npm, która zapisuje katalog, w którym npm by ruszył; w tym
# katalogu prawdziwy npm (offline, `npm config list`, atrapy wartości) pokazuje, który plik wygrywa. Krok, który
# sprawdza obecność PAT, biegnie wycięty z release.yml z atrapą i pisze do GITHUB_OUTPUT tylko present=true|false.
# Struktura: każdy krok joba example, który odpala npm, dostaje zmienną z wygrywającego pliku z tokenu workflowu,
# job ma packages: read; PAT stoi tylko w env: kroku sprawdzającego (pierwszego) i kroków z git clone/push —
# nigdy w env: joba ani w kroku z npm — a żaden if: nie czyta sekretu wprost, tylko wynik tego kroku.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
release="$root/.github/workflows/release.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  local message="$1"
  echo "FAIL: $message" >&2
  exit 1
}

job_block() {
  local job="$1"
  awk -v job="$job" '
    /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
    in_jobs && /^[^[:space:]#]/ { exit }
    in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { selected = ($1 == job ":"); next }
    selected { print }
  '
}

# Zapisuje każdy krok joba (wejście: blok joba) do katalogu $1 jako step-NN, w kolejności; komentarze YAML pomija,
# bo nie są częścią żadnego kroku.
write_steps() {
  local dir="$1"
  awk -v dir="$dir" '
    function flush() {
      if (step != "") { file = sprintf("%s/step-%02d", dir, ++n); printf "%s", step > file; close(file) }
      step = ""
    }
    /^    steps:[[:space:]]*$/ { in_steps = 1; next }
    in_steps && /^[[:space:]]*#/ { next }
    in_steps && /^      - / { flush() }
    in_steps && /^  [^ ]/ { flush(); in_steps = 0 }
    in_steps { step = step $0 "\n" }
    END { flush() }
  '
}

# Blok env: o wcięciu $1 z kluczami o wcięciu $2 (wejście: blok joba albo kroku), linia po linii bez wcięcia.
env_block() {
  local env_indent="$1" key_indent="$2"
  awk -v env_indent="$env_indent" -v key_indent="$key_indent" '
    $0 == env_indent "env:" { in_env = 1; next }
    in_env && index($0, key_indent) != 1 { in_env = 0 }
    in_env && substr($0, length(key_indent) + 1, 1) != " " { line = substr($0, length(key_indent) + 1); sub(/[[:space:]]+$/, "", line); print line }
  '
}

# Wartość zmiennej $1 z bloku env: (wejście: wynik env_block).
env_value() {
  local name="$1"
  awk -v name="$name" 'index($0, name ": ") == 1 { print substr($0, length(name) + 3); exit }'
}

# Skrypt run: kroku (wejście: plik kroku), bez wcięcia — jednolinijkowy albo blok `run: |`.
run_body() {
  awk '
    /^        run: [|][-+]?[[:space:]]*$/ { block = 1; next }
    !block && /^        run: / { sub(/^        run: /, ""); print; exit }
    block && /^          / { sub(/^          /, ""); print; next }
    block && /^[[:space:]]*$/ { print ""; next }
    block { exit }
  '
}

step_name() { sed -n -e 's/^      - name: //p' -e 's/^      - uses: \([^ ]*\).*/\1/p' "$1" | head -n 1; }

# --- Zachowanie: który plik .npmrc czyta npm w katalogu, w którym render-example.sh go woła ---------------------
real_npm=$(command -v npm) || fail 'npm is required: the test asks npm itself which .npmrc wins'

mkdir -p "$tmp/stub" "$tmp/runner" "$tmp/home" "$tmp/steps"
cat > "$tmp/stub/npm" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$PWD" >> "$NPM_DIRS"
echo '{ "lockfileVersion": 3 }' > package-lock.json
STUB
chmod +x "$tmp/stub/npm"
PATH="$tmp/stub:$PATH" NPM_DIRS="$tmp/npm-dirs" bash "$root/scripts/render-example.sh" 9.9.9 "$tmp/example" > /dev/null
npm_dir=$(head -n 1 "$tmp/npm-dirs")
[[ -f "$npm_dir/.npmrc" ]] || fail "render-example.sh must run npm in the generated frontend, next to its .npmrc (ran in $npm_dir)"

# Plik użytkownika tak, jak pisze go actions/setup-node z registry-url i scope (NPM_CONFIG_USERCONFIG w $RUNNER_TEMP).
cat > "$tmp/runner/.npmrc" <<'NPMRC'
//npm.pkg.github.com/:_authToken=${NODE_AUTH_TOKEN}
@dominiksienkiewicz:registry=https://npm.pkg.github.com/
NPMRC
: > "$tmp/globalrc"
# Środowisko kroku przed poprawką: tylko NODE_AUTH_TOKEN (atrapa), bez GITHUB_TOKEN.
config=$(cd "$npm_dir" && env -i PATH="$PATH" HOME="$tmp/home" NPM_CONFIG_CACHE="$tmp/npm-cache" \
  NPM_CONFIG_USERCONFIG="$tmp/runner/.npmrc" NPM_CONFIG_GLOBALCONFIG="$tmp/globalrc" \
  NODE_AUTH_TOKEN=dummy-node-token "$real_npm" config list) || fail 'npm config list must run offline'
grep -qxF '; //npm.pkg.github.com/:_authToken = (protected) ; overridden by project' <<<"$config" \
  || { echo "$config" >&2; fail "npm must take the GitHub Packages token from the project's .npmrc over setup-node's file"; }

token_var=$(sed -n 's|^//npm\.pkg\.github\.com/:_authToken=\$[{]\([A-Za-z_][A-Za-z0-9_]*\)[}]$|\1|p' "$npm_dir/.npmrc")
[[ -n "$token_var" ]] || fail 'the generated frontend/.npmrc must read the GitHub Packages token from one variable'

# --- Struktura: job example daje tę zmienną każdemu krokowi, który odpala npm ----------------------------------
job=$(job_block example < "$release")
[[ -n "$job" ]] || fail 'release.yml must have an example job'
grep -qx '      packages: read' <<<"$job" || fail 'the example job must hold packages: read, so GITHUB_TOKEN can read GitHub Packages'

write_steps "$tmp/steps" <<<"$job"
job_env=$(env_block '    ' '      ' <<<"$job")
job_value=$(env_value "$token_var" <<<"$job_env")
pat_ref='secrets\.PLATFORM_EXAMPLE_TOKEN'
workflow_token='^\$[{][{] (secrets\.GITHUB_TOKEN|github\.token) [}][}]$'
npm_steps=0
for step in "$tmp/steps"/step-*; do
  grep -Eq 'render-example\.sh|(^|[[:space:];&|(])npm[[:space:]]' "$step" || continue
  npm_steps=$((npm_steps + 1))
  name=$(step_name "$step")
  value=$(env_block '        ' '          ' < "$step" | env_value "$token_var")
  value=${value:-$job_value}
  [[ -n "$value" ]] || fail "step \"$name\" runs npm in frontend/, whose .npmrc reads \${$token_var}, but neither the step nor the job sets $token_var; NODE_AUTH_TOKEN only feeds setup-node's file, which the project file overrides, so npm would send the literal \${$token_var} and get a 401"
  grep -Eq "$workflow_token" <<<"$value" || fail "step \"$name\" must take $token_var from the workflow's GITHUB_TOKEN, not from $value"
  if run_body < "$step" | grep -q '\$[{][{]'; then
    fail "step \"$name\" must pass values through env:, not interpolate them into run:"
  fi
  if grep -Eq "$pat_ref" "$step"; then
    fail "step \"$name\" runs npm and must not see PLATFORM_EXAMPLE_TOKEN: only the push to platform-example needs it"
  fi
done
[[ "$npm_steps" -gt 0 ]] || fail 'the example job must have a step that runs scripts/render-example.sh'

# --- Struktura: PAT widzą tylko krok sprawdzający jego obecność i kroki z git clone/push --------------------------
if grep -Eq "$pat_ref" <<<"$job_env"; then
  fail 'PLATFORM_EXAMPLE_TOKEN must not be in the env: of the example job, where every step, npm included, sees it; set it only on the presence check and on the steps that clone and push platform-example'
fi
pat_vars=()
presence_step=''
push_steps=0
for step in "$tmp/steps"/step-*; do
  grep -Eq "$pat_ref" "$step" || continue
  name=$(step_name "$step")
  step_env=$(env_block '        ' '          ' < "$step")
  [[ "$(grep -Ec "$pat_ref" "$step")" == "$(grep -Ec "$pat_ref" <<<"$step_env")" ]] \
    || fail "step \"$name\" must read PLATFORM_EXAMPLE_TOKEN only through its own env:"
  var=$(grep -E "^[A-Za-z_][A-Za-z0-9_]*: \\\$[{][{] $pat_ref [}][}]\$" <<<"$step_env" | cut -d: -f1)
  [[ -n "$var" ]] || fail "step \"$name\" must set one variable to exactly the PLATFORM_EXAMPLE_TOKEN secret"
  pat_vars+=("$var")
  body=$(run_body < "$step")
  if grep -Eq '(^|[[:space:];&|(])git (clone|push)([[:space:]]|$)' <<<"$body"; then
    push_steps=$((push_steps + 1))
  elif grep -q 'GITHUB_OUTPUT' <<<"$body" && [[ "$(basename "$step")" == step-01 && -z "$presence_step" ]]; then
    presence_step="$step"
    if grep 'GITHUB_OUTPUT' <<<"$body" | grep -q "$var"; then
      fail "step \"$name\" must write only whether $var is present to GITHUB_OUTPUT, never its value"
    fi
  else
    fail "step \"$name\" must not see PLATFORM_EXAMPLE_TOKEN: only the first step (presence check) and the steps that clone and push platform-example need it"
  fi
done
[[ -n "$presence_step" ]] || fail 'the first step of the example job must turn the presence of PLATFORM_EXAMPLE_TOKEN into a step output, reading the secret through its own env:'
[[ "$push_steps" -gt 0 ]] || fail 'the step that clones and pushes platform-example must take PLATFORM_EXAMPLE_TOKEN through its own env:'
presence_id=$(sed -n 's/^        id: //p' "$presence_step")
[[ -n "$presence_id" ]] || fail 'the presence check needs an id:, so the if: conditions can read its output'
if grep -q '^        if:' "$presence_step"; then fail 'the presence check must run unconditionally'; fi

# Żaden if: (joba ani kroku) nie czyta sekretu ani zmiennej z PAT; kroki z PAT i z npm czekają na present == 'true'.
while IFS= read -r condition; do
  if grep -q 'secrets\.' <<<"$condition"; then fail "no if: may read a secret directly: $condition"; fi
  for var in "${pat_vars[@]}"; do
    if grep -qF "env.$var" <<<"$condition"; then fail "no if: may read the PAT through env.$var: $condition"; fi
  done
done < <(grep -E '^ +if:' <<<"$job")
gate="^        if: \\\$[{][{] steps\\.$presence_id\\.outputs\\.present == 'true' [}][}]\$"
for step in "$tmp/steps"/step-*; do
  [[ "$step" != "$presence_step" ]] || continue
  if grep -Eq "$pat_ref" "$step" || grep -Eq 'render-example\.sh' "$step"; then
    grep -Eq "$gate" "$step" || fail "step \"$(step_name "$step")\" must run only when steps.$presence_id.outputs.present is 'true'"
  fi
done

# --- Zachowanie: krok sprawdzający, wycięty z release.yml, pisze do GITHUB_OUTPUT tylko present=true|false -------
run_body < "$presence_step" > "$tmp/presence.sh"
presence_var=${pat_vars[0]}
for scenario in 'dummy-example-pat true' ' false'; do
  value=${scenario% *}
  expected=${scenario##* }
  : > "$tmp/output"
  env -i PATH="$PATH" GITHUB_OUTPUT="$tmp/output" "$presence_var=$value" bash --noprofile --norc -eo pipefail "$tmp/presence.sh" > "$tmp/presence.log" 2>&1 \
    || fail "the presence check must succeed when the secret is ${value:-empty}: $(cat "$tmp/presence.log")"
  [[ "$(cat "$tmp/output")" == "present=$expected" ]] \
    || fail "the presence check must write only present=$expected to GITHUB_OUTPUT when the secret is ${value:-empty}, wrote: $(cat "$tmp/output")"
  if grep -qF 'dummy-example-pat' "$tmp/presence.log"; then fail 'the presence check must not print the secret'; fi
done

echo "OK: release.yml gives npm in the rendered platform-example the $token_var its frontend/.npmrc reads, and the PAT only to the push"
