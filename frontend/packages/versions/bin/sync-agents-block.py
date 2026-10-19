#!/usr/bin/env python3
"""sync-agents-block.py <block-template> <version> <AGENTS.md>: managed Platform block in a consumer's AGENTS.md.

N-SHOW-1: the text between `<!-- BEGIN platform-agents` and `<!-- END platform-agents -->` is replaced by the block of
the release platform-bump goes to (`{{VERSION}}` filled in); without markers the block is appended, and a missing
AGENTS.md is created. Text outside the markers stays byte-identical, and a second run changes nothing.
Prints `unchanged`, `replaced` or `added`.
"""

import os
import re
import sys

BLOCK = re.compile(r"<!-- BEGIN platform-agents\b.*?<!-- END platform-agents -->", re.S)


def main():
    template_path, version, agents_path = sys.argv[1:4]
    with open(template_path, encoding="utf-8") as handle:
        block = handle.read().replace("{{VERSION}}", version).rstrip("\n")
    current = ""
    if os.path.exists(agents_path):
        with open(agents_path, encoding="utf-8") as handle:
            current = handle.read()
    match = BLOCK.search(current)
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
    with open(agents_path, "w", encoding="utf-8") as handle:
        handle.write(updated)
    print(outcome)


main()
