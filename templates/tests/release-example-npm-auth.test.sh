#!/usr/bin/env bash
# Job example w release.yml: npm, którego woła scripts/render-example.sh w wygenerowanym frontend/, musi dostać
# token GitHub Packages pod nazwą, którą czyta frontend/.npmrc (kopia templates/npmrc: ${GITHUB_TOKEN}).
#
# Dlaczego sam NODE_AUTH_TOKEN nie wystarcza: actions/setup-node z registry-url pisze plik użytkownika
# z `_authToken=${NODE_AUTH_TOKEN}`, ale plik projektu ma ten sam klucz i npm bierze go pierwszego. Bez
# GITHUB_TOKEN w środowisku npm zostawia `${GITHUB_TOKEN}` dosłownie jako token i GitHub Packages odpowiada 401.
#
# Zachowanie: render-example.sh biegnie z atrapą npm, która zapisuje katalog, w którym npm by ruszył; w tym
# katalogu prawdziwy npm (offline, `npm config list`, atrapy wartości) pokazuje, który plik wygrywa. Struktura:
# każdy krok joba example, który odpala npm, dostaje zmienną z wygrywającego pliku z tokenu workflowu, job ma
# packages: read, a PLATFORM_EXAMPLE_TOKEN (tylko push do platform-example) nie jest tokenem npm.
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

# Zapisuje do katalogu $1 każdy krok joba (wejście: blok joba), który odpala npm wprost albo przez render-example.sh;
# komentarze YAML pomija, bo nie są częścią żadnego kroku.
write_npm_steps() {
  local dir="$1"
  awk -v dir="$dir" '
    function flush() {
      if (step != "" && (step ~ /render-example\.sh/ || step ~ /(^|[[:space:];&|(])npm[[:space:]]/)) {
        file = dir "/step-" ++n
        printf "%s", step > file
        close(file)
      }
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

# Wartość zmiennej $1 z bloku env: o wcięciu $2 i kluczach o wcięciu $3 (wejście: blok joba albo kroku).
env_value() {
  local name="$1" env_indent="$2" key_indent="$3"
  awk -v name="$name" -v env_indent="$env_indent" -v key_indent="$key_indent" '
    $0 == env_indent "env:" { in_env = 1; next }
    in_env && index($0, key_indent) != 1 { in_env = 0 }
    in_env && substr($0, length(key_indent) + 1, 1) != " " {
      line = substr($0, length(key_indent) + 1)
      if (index(line, name ": ") == 1) { value = substr(line, length(name) + 3); sub(/[[:space:]]+$/, "", value); print value; exit }
    }
  '
}

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

write_npm_steps "$tmp/steps" <<<"$job"
compgen -G "$tmp/steps/step-*" > /dev/null || fail 'the example job must have a step that runs scripts/render-example.sh'
job_value=$(env_value "$token_var" '    ' '      ' <<<"$job")
workflow_token='^\$[{][{] (secrets\.GITHUB_TOKEN|github\.token) [}][}]$'
for step in "$tmp/steps"/step-*; do
  name=$(sed -n 's/^      - name: //p' "$step")
  value=$(env_value "$token_var" '        ' '          ' < "$step")
  value=${value:-$job_value}
  [[ -n "$value" ]] || fail "step \"$name\" runs npm in frontend/, whose .npmrc reads \${$token_var}, but neither the step nor the job sets $token_var; NODE_AUTH_TOKEN only feeds setup-node's file, which the project file overrides, so npm would send the literal \${$token_var} and get a 401"
  grep -Eq "$workflow_token" <<<"$value" || fail "step \"$name\" must take $token_var from the workflow's GITHUB_TOKEN, not from $value"
  if awk '/^        run:/ { r = 1 } r' "$step" | grep -q '\$[{][{]'; then
    fail "step \"$name\" must pass values through env:, not interpolate them into run:"
  fi
done

echo "OK: release.yml gives npm in the rendered platform-example the $token_var its frontend/.npmrc reads"
