#!/usr/bin/env bash
# Wtyczka Claude Code z korzenia repo (N-SHOW-1): marketplace `.claude-plugin/marketplace.json` wskazuje wtyczkę
# `platform`, a ta ma dokładnie siedem cienkich skilli, z których każdy odsyła do swojego runbooka (albo do docs/gates.md)
# na tagu wydania przypiętego w repo konsumenta i nie niesie własnej procedury. Pole `version` jest pominięte w obu
# manifestach, żeby wersję wtyczki wyznaczał commit (docs: "omit version"), a nie ręczny numer poza release.sh.
# Na atrapie skill z nieistniejącą ścieżką musi oblać scripts/check-agent-docs.py.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "${OUT:-}" >&2; exit 1; }

# Skrypt trafia do pliku, nie do $(...): bash 3.2 z macOS gubi się na backtickach w heredocu wewnątrz podstawienia.
cat > "$tmp/contract.py" <<'PY'
import json
import os
import re
import sys

root = sys.argv[1]
problems = []
KEBAB = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
TAG_LINK = re.compile(r"/blob/v<version>/(docs/[A-Za-z0-9_./-]+?)(?:#<code>)?`")
# skill -> cele, które wolno mu wskazać (runbook albo sekcja bramki), nic poza nimi
TARGETS = {
    "bump-consumer": {"docs/runbooks/bump-consumer.md"},
    "fix-gate-failure": {"docs/gates.md"},
    "add-library": {"docs/runbooks/add-jvm-library.md", "docs/runbooks/add-frontend-dependency.md"},
    "test-unreleased-change": {"docs/runbooks/test-unreleased-change.md"},
    "tdd-feature": {"docs/runbooks/tdd-feature.md"},
    "tdd-bugfix": {"docs/runbooks/tdd-bugfix.md"},
    "ddd-modeling": {"docs/runbooks/ddd-modeling.md"},
}


def need(condition, message):
    if not condition:
        problems.append(message)


market = json.load(open(os.path.join(root, ".claude-plugin/marketplace.json"), encoding="utf-8"))
need(KEBAB.match(market.get("name", "")), "the marketplace name must be kebab-case")
need(market.get("description"), "the marketplace needs a description")
need(market.get("owner", {}).get("name"), "the marketplace needs owner.name")
entries = market.get("plugins", [])
need([entry.get("name") for entry in entries] == ["platform"], "the marketplace must list exactly the plugin platform")

for entry in entries:
    source = entry.get("source")
    need(isinstance(source, str) and source.startswith("./") and ".." not in source,
         "the plugin source must be a relative path inside the repository")
    plugin_root = os.path.join(root, source)
    manifest = json.load(open(os.path.join(plugin_root, ".claude-plugin/plugin.json"), encoding="utf-8"))
    need(manifest.get("name") == entry.get("name"), "the entry name and the plugin.json name must be equal")
    need("version" not in manifest and "version" not in entry, "plugin.json and the entry carry no version field")
    skills = sorted(os.listdir(os.path.join(plugin_root, "skills")))
    need(skills == sorted(TARGETS), f"the plugin must have exactly the skills {sorted(TARGETS)}, found {skills}")
    for skill in skills:
        path = os.path.join(plugin_root, "skills", skill, "SKILL.md")
        label = f"skills/{skill}/SKILL.md"
        text = open(path, encoding="utf-8").read()
        front = re.match(r"---\n(.*?)\n---\n", text, re.S)
        need(front, f"{label} needs a frontmatter")
        if not front:
            continue
        fields = dict(re.findall(r"^([a-z-]+):\s*(.*)$", front.group(1), re.M))
        need(fields.get("name") == skill, f"{label}: name must equal the directory")
        description = fields.get("description", "").strip('"')
        need(description and len(description) <= 1536, f"{label}: a description of at most 1536 characters")
        need(skill != "fix-gate-failure" or "PLAT-" in description, f"{label}: the description must name the PLAT code")
        need("platformVersion" in text and "platform-agents" in text, f"{label}: must say where the pin is read")
        need(text.count("\n") <= 30, f"{label}: a skill only points at the runbook and holds no procedure")
        found = set(TAG_LINK.findall(text))
        need(found == TARGETS.get(skill, set()), f"{label}: must link exactly {sorted(TARGETS.get(skill, []))} at the tag, found {sorted(found)}")

if problems:
    print("\n".join(problems))
    sys.exit(1)
PY
OUT=$(python3 -I "$tmp/contract.py" "$root") || fail 'the marketplace, the plugin and its seven skills must follow the contract'

fixture="$tmp/platform"
mkdir -p "$fixture/templates/agents" "$fixture/docs/runbooks" "$fixture/frontend/packages/versions" \
  "$fixture/plugins/platform/skills/demo"
printf '{ "bin": { "platform-bump": "bin/platform-bump.sh" } }\n' > "$fixture/frontend/packages/versions/package.json"
printf -- '- Bump with `platform-bump`.\n' > "$fixture/templates/agents/platform-block.md"
cp "$fixture/templates/agents/platform-block.md" "$fixture/AGENTS.md"
printf -- '- See `docs/runbooks/cut-release.md`.\n' > "$fixture/docs/consumer-agents.md"
: > "$fixture/docs/runbooks/cut-release.md"
printf -- 'Read https://github.com/DominikSienkiewicz/Platform/blob/v<version>/docs/runbooks/cut-release.md first.\n' \
  > "$fixture/plugins/platform/skills/demo/SKILL.md"
python3 -I "$root/scripts/check-agent-docs.py" "$fixture" > /dev/null || fail 'the fixture skill must pass while its runbook exists'
rm "$fixture/docs/runbooks/cut-release.md"
if OUT=$(python3 -I "$root/scripts/check-agent-docs.py" "$fixture"); then fail 'a skill naming a missing runbook must fail the check'; fi
grep -qF 'plugins/platform/skills/demo/SKILL.md:1: `docs/runbooks/cut-release.md` (named by a link at a release tag) does not exist' <<<"$OUT" \
  || fail 'the failure must name the skill file, the line and the missing path'
echo 'OK: the marketplace lists the platform plugin, its seven skills only point at runbooks at the pinned tag, and the checker covers them'
