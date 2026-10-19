#!/usr/bin/env python3
"""check-doc-links.py [<root>]: offline check of relative links and anchors in every tracked Markdown file.

A link to a file must point at an existing file or directory, and a `#fragment` (alone or after a path to a
Markdown file) at a heading of that file, slugged as GitHub does. External links (a scheme such as https:)
are not fetched. Links inside code fences and inline code are ignored. Exit 1 lists every broken link as
file:line.
"""
import os
import re
import subprocess
import sys

LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")


def slug(heading):
    text = re.sub(r"`([^`]*)`", r"\1", heading)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = text.strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors(path, cache={}):
    if path not in cache:
        found, counts, fenced = set(), {}, False
        for line in open(path, encoding="utf-8"):
            if line.lstrip().startswith("```"):
                fenced = not fenced
                continue
            match = None if fenced else HEADING.match(line)
            if match:
                base = slug(match.group(2))
                count = counts.get(base, 0)
                counts[base] = count + 1
                found.add(base if count == 0 else f"{base}-{count}")
        cache[path] = found
    return cache[path]


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    files = subprocess.run(["git", "-C", root, "ls-files", "*.md"], capture_output=True, text=True, check=True).stdout.split()
    broken = []
    for relative in files:
        path = os.path.join(root, relative)
        if not os.path.isfile(path):
            continue
        fenced = False
        for number, line in enumerate(open(path, encoding="utf-8"), start=1):
            if line.lstrip().startswith("```"):
                fenced = not fenced
                continue
            if fenced:
                continue
            for target in LINK.findall(re.sub(r"`[^`]*`", "", line)):
                if re.match(r"^[a-z][a-z0-9+.-]*:", target):
                    continue
                file_part, _, fragment = target.partition("#")
                destination = os.path.normpath(os.path.join(os.path.dirname(path), file_part)) if file_part else path
                if not os.path.exists(destination):
                    broken.append(f"{relative}:{number}: {target} (no such file)")
                elif fragment and destination.endswith(".md") and fragment.lower() not in anchors(destination):
                    broken.append(f"{relative}:{number}: {target} (no heading #{fragment})")
    for entry in broken:
        print(entry)
    if broken:
        print(f"{len(broken)} broken link(s) in the Markdown files.")
        sys.exit(1)
    print(f"Every relative link and anchor in {len(files)} Markdown files resolves.")


main()
