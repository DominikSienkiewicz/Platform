#!/usr/bin/env python3
"""docs-gen.py [--check] [root]: regenerate the marked regions of the Markdown from their sources (N-SHOW-15).

Regions:
- `<!-- include: <path>[#L<a>-L<b>] -->` followed by a fenced code block: the block holds exactly those lines of the
  file, so a snippet cannot drift from the template it shows;
- `<!-- docs-gen:inputs <workflow>.yml -->` … `<!-- /docs-gen -->`: the inputs table of a reusable workflow, from
  `on.workflow_call.inputs` of .github/workflows/<workflow>.yml;
- `<!-- docs-gen:npm-packages -->` … `<!-- /docs-gen -->`: every package under frontend/packages, from its package.json.
With --check nothing is written: the script lists the files whose regions are stale and exits 1.
"""
import glob
import json
import os
import re
import sys

args = [arg for arg in sys.argv[1:] if arg != "--check"]
check = "--check" in sys.argv[1:]
root = os.path.abspath(args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

INCLUDE = re.compile(r"(<!-- include: ([^#\s]+)(?:#L(\d+)-L(\d+))? -->\n)(```[^\n]*\n)(.*?)(```)", re.S)
REGION = re.compile(r"(<!-- docs-gen:([a-z-]+)(?: ([^\s]+))? -->\n)(.*?)(<!-- /docs-gen -->)", re.S)


def read(path):
    with open(os.path.join(root, path), encoding="utf-8") as handle:
        return handle.read()


def include(match):
    path, first, last = match.group(2), match.group(3), match.group(4)
    lines = read(path).splitlines(keepends=True)
    if first:
        lines = lines[int(first) - 1 : int(last)]
    body = "".join(lines)
    if not body.endswith("\n"):
        body += "\n"
    return match.group(1) + match.group(5) + body + match.group(7)


def workflow_inputs(name):
    """Name, type, default, required and description of each input, read by indentation from the workflow file."""
    inputs, current, section = [], None, None
    for line in read(f".github/workflows/{name}").splitlines():
        if re.match(r"^  workflow_call:\s*$", line):
            section = "call"
            continue
        if section == "call" and re.match(r"^    inputs:\s*$", line):
            section = "inputs"
            continue
        if section == "inputs":
            if re.match(r"^    \S", line) or re.match(r"^  \S", line) or re.match(r"^\S", line):
                break
            item = re.match(r"^      ([A-Za-z0-9_-]+):\s*$", line)
            if item:
                current = {"name": item.group(1), "type": "", "default": "", "required": "false", "description": ""}
                inputs.append(current)
                continue
            attribute = re.match(r"^        (type|default|required|description):\s*(.*)$", line)
            if attribute and current is not None:
                value = attribute.group(2).strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                    value = value[1:-1].replace('\\"', '"')
                current[attribute.group(1)] = value
    return inputs


def cell(text):
    return text.replace("|", "\\|")


def inputs_table(name):
    rows = ["| Input | Type | Default | Description |", "|---|---|---|---|"]
    for entry in workflow_inputs(name):
        default = "required" if entry["required"] == "true" else (f"`{entry['default']}`" if entry["default"] else "empty")
        rows.append(f"| `{entry['name']}` | {entry['type']} | {default} | {cell(entry['description'])} |")
    return "\n".join(rows) + "\n"


def npm_packages():
    rows = ["| Package | Directory | Published | Bins | Description |", "|---|---|---|---|---|"]
    for manifest in sorted(glob.glob(os.path.join(root, "frontend/packages/*/package.json"))):
        package = json.load(open(manifest, encoding="utf-8"))
        directory = os.path.relpath(os.path.dirname(manifest), root)
        bins = ", ".join(f"`{name}`" for name in sorted(package.get("bin", {}))) or "—"
        published = "no (private)" if package.get("private") else "yes"
        rows.append(f"| `{package['name']}` | `{directory}/` | {published} | {bins} | {cell(package.get('description', ''))} |")
    return "\n".join(rows) + "\n"


def region(match):
    kind, argument = match.group(2), match.group(3)
    if kind == "inputs":
        body = inputs_table(argument)
    elif kind == "npm-packages":
        body = npm_packages()
    else:
        raise SystemExit(f"unknown docs-gen region {kind}")
    return match.group(1) + body + match.group(5)


def main():
    stale = []
    documents = sorted(set(glob.glob(os.path.join(root, "*.md")) + glob.glob(os.path.join(root, "docs/**/*.md"), recursive=True)))
    for path in documents:
        if "/docs/concepts/" in path:
            continue
        text = open(path, encoding="utf-8").read()
        generated = REGION.sub(region, INCLUDE.sub(include, text))
        if generated != text:
            stale.append(os.path.relpath(path, root))
            if not check:
                with open(path, "w", encoding="utf-8") as handle:
                    handle.write(generated)
    if check and stale:
        print("Generated regions are stale; run scripts/docs-gen.sh and commit:\n  " + "\n  ".join(stale))
        sys.exit(1)
    print(("Regenerated: " + ", ".join(stale)) if stale and not check else "Every generated region is current.")


main()
