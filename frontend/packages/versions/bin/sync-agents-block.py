#!/usr/bin/env python3
"""sync-agents-block.py <block-template> <version> <AGENTS.md> [values.json ...]: a managed Platform block in AGENTS.md.

N-SHOW-1: the text between `<!-- BEGIN <name>` and `<!-- END <name> -->` is replaced by the block of the release
platform-bump goes to; without markers the block is appended, and a missing AGENTS.md is created. The marker name
(`platform-agents`, `platform-agents-backend`, `platform-agents-frontend`) comes from the template's first line, so
blocks of different names live side by side. `{{VERSION}}` is the version argument; every other `{{key}}` comes from
the values files (a flat JSON map, or versions.json, whose `versions` map is used). A placeholder no file fills ends
the run with exit 2 and leaves AGENTS.md untouched. Text outside the markers stays byte-identical, and a second run
changes nothing. Prints `unchanged`, `replaced` or `added`.
"""

import json
import os
import re
import sys

MARKER = re.compile(r"^<!-- BEGIN (platform-agents(?:-[a-z]+)?) ")
PLACEHOLDER = re.compile(r"\{\{([A-Za-z0-9_.@/-]+)\}\}")


def load_values(paths):
    values = {}
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        versions = data.get("versions")
        values.update(versions if isinstance(versions, dict) else data)
    return values


def main():
    template_path, version, agents_path = sys.argv[1:4]
    values = load_values(sys.argv[4:])
    values["VERSION"] = version
    with open(template_path, encoding="utf-8") as handle:
        template = handle.read()
    marker = MARKER.match(template)
    if not marker:
        sys.exit(f"sync-agents-block: {template_path} does not start with a platform-agents BEGIN marker")
    name = re.escape(marker.group(1))
    missing = sorted({key for key in PLACEHOLDER.findall(template) if key not in values})
    if missing:
        print(f"sync-agents-block: no value for {', '.join(missing)} in {template_path}", file=sys.stderr)
        sys.exit(2)
    block = PLACEHOLDER.sub(lambda found: str(values[found.group(1)]), template).rstrip("\n")
    current = ""
    if os.path.exists(agents_path):
        with open(agents_path, encoding="utf-8") as handle:
            current = handle.read()
    match = re.search(rf"<!-- BEGIN {name}\s.*?<!-- END {name} -->", current, re.S)
    if match:
        updated = current[: match.start()] + block + current[match.end() :]
        outcome = "replaced"
    else:
        # Pusta linia przed blokiem, chyba że plik jest pusty.
        separator = "" if not current else ("\n" if current.endswith("\n") else "\n\n")
        updated = current + separator + block + "\n"
        outcome = "added"
    if updated == current:
        print("unchanged")
        return
    directory = os.path.dirname(agents_path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(agents_path, "w", encoding="utf-8") as handle:
        handle.write(updated)
    print(outcome)


main()
