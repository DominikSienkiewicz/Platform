#!/usr/bin/env bash
# Wskazówki dla agentów (N-SHOW-1): każda komenda, task, bin i ścieżka z bloku platform-agents, AGENTS.md, arkusza
# docs/consumer-agents.md i runbooków istnieje (scripts/check-agent-docs.py), a blok w AGENTS.md Platform jest
# bajt w bajt kanonem templates/agents/platform-block.md. Atrapa ze zmienioną nazwą skryptu musi failować.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "${OUT:-}" >&2; exit 1; }

OUT=$(python3 -I "$root/scripts/check-agent-docs.py" "$root") || fail 'the agent guidance must name only things that exist'
block=$(awk '/<!-- BEGIN platform-agents/,/<!-- END platform-agents -->/' "$root/AGENTS.md")
[[ "$block" == "$(cat "$root/templates/agents/platform-block.md")" ]] || fail 'the block in AGENTS.md must equal templates/agents/platform-block.md'
cmp -s "$root/templates/agents/platform-block.md" "$root/frontend/packages/versions/agents/platform-block.md" \
  || fail 'the versions package must ship the same block'

fixture="$tmp/platform"
mkdir -p "$fixture/templates/agents" "$fixture/docs/runbooks" "$fixture/scripts" "$fixture/frontend/packages/versions"
printf '{ "bin": { "platform-bump": "bin/platform-bump.sh" } }\n' > "$fixture/frontend/packages/versions/package.json"
printf -- '- Run `scripts/canary.sh` first.\n' > "$fixture/docs/runbooks/cut-release.md"
printf -- '- Bump with `platform-bump`.\n' > "$fixture/templates/agents/platform-block.md"
cp "$fixture/templates/agents/platform-block.md" "$fixture/AGENTS.md"
printf -- '- See `docs/runbooks/cut-release.md`.\n' > "$fixture/docs/consumer-agents.md"
: > "$fixture/scripts/canary.sh"
python3 -I "$root/scripts/check-agent-docs.py" "$fixture" > /dev/null || fail 'the fixture must pass before the rename'
mv "$fixture/scripts/canary.sh" "$fixture/scripts/preview.sh"
if OUT=$(python3 -I "$root/scripts/check-agent-docs.py" "$fixture"); then fail 'a renamed script must fail the check'; fi
grep -qF 'docs/runbooks/cut-release.md:1: `scripts/canary.sh` does not exist' <<<"$OUT" || fail 'the failure must name the file, line and path'
echo 'OK: the agent guidance names only commands, tasks, bins and paths that exist, and AGENTS.md carries the canon block'
