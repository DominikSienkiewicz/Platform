#!/usr/bin/env python3
"""agents-stack.py [--check] [root]: the backend stack the platform-agents-backend block names, from the catalog.

Writes frontend/packages/versions/agents/stack.json, a flat map of the `[versions]` entries listed in KEYS, read from
gradle/catalog/libs.versions.toml. The file ships in @dominiksienkiewicz/versions, so platform-bump fills the block of
the release it goes to without the catalog or the network. With --check nothing is written: the script exits 1 when
the file differs from the catalog.
"""
import json
import os
import re
import sys

KEYS = ("java", "gradle", "springBoot", "springModulith", "springAi", "junit")
ENTRY = re.compile(r'^([A-Za-z0-9_-]+)\s*=\s*"([^"]+)"')

args = [arg for arg in sys.argv[1:] if arg != "--check"]
check = "--check" in sys.argv[1:]
root = os.path.abspath(args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
catalog = os.path.join(root, "gradle/catalog/libs.versions.toml")
target = os.path.join(root, "frontend/packages/versions/agents/stack.json")


def catalog_versions():
    versions, section = {}, None
    with open(catalog, encoding="utf-8") as handle:
        for line in handle:
            header = re.match(r"^\[([A-Za-z0-9_-]+)\]", line)
            if header:
                section = header.group(1)
                continue
            entry = ENTRY.match(line)
            if section == "versions" and entry:
                versions[entry.group(1)] = entry.group(2)
    return versions


def main():
    versions = catalog_versions()
    missing = [key for key in KEYS if key not in versions]
    if missing:
        sys.exit(f"agents-stack: {catalog} has no [versions] entry for {', '.join(missing)}")
    expected = json.dumps({key: versions[key] for key in KEYS}, indent=2) + "\n"
    current = open(target, encoding="utf-8").read() if os.path.exists(target) else ""
    if check:
        if current != expected:
            print(f"{os.path.relpath(target, root)} differs from the catalog; run scripts/agents-stack.py and commit.")
            sys.exit(1)
        print("The agents stack matches the catalog.")
        return
    if current != expected:
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(expected)
    print(f"Wrote {os.path.relpath(target, root)}")


main()
