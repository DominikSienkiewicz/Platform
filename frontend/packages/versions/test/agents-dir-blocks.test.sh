#!/usr/bin/env bash
# Bloki platform-agents-backend i -frontend (N-SHOW-1): stos z stack.json (= katalog) i versions.json wydania, brak
# wartości = exit 2 bez zapisu, bloki różnych nazw obok siebie w jednym AGENTS.md, a krok bumpa (wycięty markerami
# platform-bump:agents) kładzie blok backendu do backend/AGENTS.md albo do AGENTS.md przy Gradle w korzeniu, blok
# frontendu do frontend/AGENTS.md i stub CLAUDE.md tylko tam, gdzie go nie ma. Kopie w paczce = kanon z templates/.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
package="$here/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
sync() { python3 "$package/bin/sync-agents-block.py" "$@"; }

root="$here/../../../.."
if [[ -d "$root/templates/agents" ]]; then
  for block in backend-block.md frontend-block.md; do
    cmp -s "$root/templates/agents/$block" "$package/agents/$block" || fail "the packaged $block must equal templates/agents/$block"
  done
  python3 "$root/scripts/agents-stack.py" --check "$root" > /dev/null || fail 'agents/stack.json must match the catalog'
fi

java=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["java"])' "$package/agents/stack.json")
next=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["versions"]["next"])' "$package/versions.json")

[[ "$(sync "$package/agents/backend-block.md" 1.6.0 "$tmp/backend.md" "$package/agents/stack.json")" == added ]] \
  || fail 'the backend block is written'
grep -qF "Java $java toolchain" "$tmp/backend.md" || fail 'the backend block names the Java of stack.json'
[[ "$(sync "$package/agents/frontend-block.md" 1.6.0 "$tmp/frontend.md" "$package/versions.json")" == added ]] \
  || fail 'the frontend block is written'
grep -qF "Next.js $next," "$tmp/frontend.md" || fail 'the frontend block names the Next.js of versions.json'
if grep -qF '{{' "$tmp/backend.md" "$tmp/frontend.md"; then fail 'no placeholder may survive'; fi

printf 'Own text.\n' > "$tmp/unfilled.md"
if sync "$package/agents/backend-block.md" 1.6.0 "$tmp/unfilled.md" 2> "$tmp/err"; then fail 'a block without its values must not be written'; fi
grep -qF 'no value for' "$tmp/err" || fail 'the error must name the missing values'
[[ "$(cat "$tmp/unfilled.md")" == 'Own text.' ]] || fail 'a failed run must leave the file untouched'

printf '# Consumer\n\nOwn rules.\n' > "$tmp/AGENTS.md"
sync "$package/agents/platform-block.md" 1.6.0 "$tmp/AGENTS.md" > /dev/null
root_block() { awk '/<!-- BEGIN platform-agents /,/<!-- END platform-agents -->/' "$tmp/AGENTS.md"; }
before=$(root_block)
[[ "$(sync "$package/agents/backend-block.md" 1.6.0 "$tmp/AGENTS.md" "$package/agents/stack.json")" == added ]] \
  || fail 'a backend block is added next to the root block'
[[ "$(root_block)" == "$before" ]] || fail 'the backend block must leave the root block byte-identical'
[[ "$(sync "$package/agents/platform-block.md" 1.7.0 "$tmp/AGENTS.md")" == replaced ]] || fail 'the root block is replaced'
[[ $(grep -c '<!-- BEGIN platform-agents-backend v1.6.0' "$tmp/AGENTS.md") -eq 1 ]] || fail 'the root sync must keep the backend block'
[[ "$(sync "$package/agents/backend-block.md" 1.6.0 "$tmp/AGENTS.md" "$package/agents/stack.json")" == unchanged ]] \
  || fail 'a second backend run is a no-op'

# Krok bumpa wycięty markerami; snapshot_file to atrapa, TARGET_LOGIC to ta paczka.
step=$(sed -n '/^# platform-bump:agents$/,/^# platform-bump:agents-end$/p' "$package/bin/platform-bump.sh")
[[ -n "$step" ]] || fail 'the bump must keep its platform-bump:agents markers'
run_step() {
  (cd "$1" && TARGET=1.6.0 TARGET_LOGIC="$2" bash -c 'set -euo pipefail; snapshot_file() { :; }; '"$step")
}

repo="$tmp/fullstack"
mkdir -p "$repo/backend" "$repo/frontend"
: > "$repo/backend/build.gradle.kts"
printf '{ "name": "web" }\n' > "$repo/frontend/package.json"
printf '# Our Claude notes\n' > "$repo/CLAUDE.md"
printf '@AGENTS.md\n# frontend notes\n' > "$repo/frontend/CLAUDE.md"
out=$(run_step "$repo" "$package")
grep -qF '<!-- BEGIN platform-agents v1.6.0' "$repo/AGENTS.md" || fail 'the root block goes to AGENTS.md'
grep -qF '<!-- BEGIN platform-agents-backend v1.6.0' "$repo/backend/AGENTS.md" || fail 'the backend block goes to backend/AGENTS.md'
grep -qF '<!-- BEGIN platform-agents-frontend v1.6.0' "$repo/frontend/AGENTS.md" || fail 'the frontend block goes to frontend/AGENTS.md'
if grep -qF 'platform-agents-backend' "$repo/AGENTS.md"; then fail 'with a backend/ build the root AGENTS.md gets no backend block'; fi
[[ "$(cat "$repo/backend/CLAUDE.md")" == '@AGENTS.md' ]] || fail 'a missing backend/CLAUDE.md becomes the @AGENTS.md stub'
[[ "$(cat "$repo/CLAUDE.md")" == '# Our Claude notes' ]] || fail 'an existing CLAUDE.md stays untouched'
[[ "$(cat "$repo/frontend/CLAUDE.md")" == $'@AGENTS.md\n# frontend notes' ]] || fail 'an existing frontend/CLAUDE.md stays untouched'
grep -qF 'CLAUDE.md does not import @AGENTS.md' <<<"$out" || fail 'a CLAUDE.md without the import gets a hint'
if grep -qF 'frontend/CLAUDE.md does not import' <<<"$out"; then fail 'a CLAUDE.md with the import gets no hint'; fi
snapshot=$(cd "$repo" && cat AGENTS.md backend/AGENTS.md frontend/AGENTS.md)
run_step "$repo" "$package" > /dev/null
[[ "$(cd "$repo" && cat AGENTS.md backend/AGENTS.md frontend/AGENTS.md)" == "$snapshot" ]] || fail 'a second bump changes nothing'

repo="$tmp/root-gradle"
mkdir -p "$repo"
: > "$repo/settings.gradle.kts"
run_step "$repo" "$package" > /dev/null
grep -qF '<!-- BEGIN platform-agents v1.6.0' "$repo/AGENTS.md" || fail 'a root Gradle build keeps the root block'
grep -qF '<!-- BEGIN platform-agents-backend v1.6.0' "$repo/AGENTS.md" || fail 'a root Gradle build gets the backend block in AGENTS.md'
[[ ! -e "$repo/frontend" ]] || fail 'a repository without frontend/ gets no frontend files'

old="$tmp/old-release"
mkdir -p "$old/agents" "$old/bin"
cp "$package/agents/platform-block.md" "$old/agents/"
cp "$package/bin/sync-agents-block.py" "$old/bin/"
repo="$tmp/older-target"
mkdir -p "$repo/backend"
: > "$repo/backend/build.gradle.kts"
run_step "$repo" "$old" > /dev/null
[[ ! -e "$repo/backend/AGENTS.md" ]] || fail 'a target release without backend-block.md writes no backend/AGENTS.md'
grep -qF '<!-- BEGIN platform-agents v1.6.0' "$repo/AGENTS.md" || fail 'an older target still writes the root block'
echo 'OK: the backend and frontend blocks carry the stack of their release and land where the code lives'
