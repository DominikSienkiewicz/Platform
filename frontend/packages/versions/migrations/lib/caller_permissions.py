"""Grant packages: read to every job that calls Platform's backend-ci.yml or frontend-ci.yml.

The effective permissions of a calling job are its own permissions block, else the workflow's. Without
either, GitHub's default token permissions apply, and both defaults grant packages: read. A shape the
migration does not recognise (a flow mapping, an unknown scalar) is reported for a manual fix.
Usage: caller_permissions.py detect|apply. Exit status of detect: 0 fix needed, 1 nothing, 2 manual only.
"""
import glob
import re
import sys

CALLEE = re.compile(r"^\s+uses:\s*DominikSienkiewicz/Platform/\.github/workflows/(?:backend|frontend)-ci\.ya?ml@")
GRANTS = re.compile(r"\bpackages:\s*(?:read|write)\b")


def indent(line):
    return len(line) - len(line.lstrip(" "))


def meaningful(line):
    stripped = line.strip()
    return stripped and not stripped.startswith("#")


def permissions_at(lines, start, end, level):
    for index in range(start, end):
        match = re.match(r"^( *)permissions:\s*(.*?)\s*(?:#.*)?$", lines[index])
        if match and len(match.group(1)) == level:
            return index, match.group(2)
    return None, None


def plan(path, lines):
    """Return ({line index: replacement lines}, [manual notes]) for one workflow."""
    fixes, manual = {}, []
    top_end = next((i for i, line in enumerate(lines) if re.match(r"^jobs:\s*$", line)), len(lines))
    top_index, top_value = permissions_at(lines, 0, len(lines), 0)
    jobs = [i for i in range(top_end + 1, len(lines)) if re.match(r"^  [A-Za-z0-9_-]+:\s*$", lines[i])]
    for number, start in enumerate(jobs):
        end = jobs[number + 1] if number + 1 < len(jobs) else next(
            (i for i in range(start + 1, len(lines)) if re.match(r"^\S", lines[i])), len(lines))
        if not any(CALLEE.match(line) for line in lines[start:end]):
            continue
        index, value = permissions_at(lines, start + 1, end, 4)
        if index is None:
            index, value = top_index, top_value
        if index is None or index in fixes:
            continue
        level = indent(lines[index])
        if value in ("read-all", "write-all"):
            continue
        if value:
            if not GRANTS.search(value):
                manual.append(f"{path}:{index + 1}: add packages: read to `permissions: {value}`")
            continue
        children = []
        for child in range(index + 1, len(lines)):
            if not meaningful(lines[child]):
                continue
            if indent(lines[child]) <= level:
                break
            children.append(child)
        if any(GRANTS.search(lines[child]) for child in children):
            continue
        none = next((child for child in children if re.match(r"^\s*packages:\s*none\b", lines[child])), None)
        if none is not None:
            fixes[none] = [re.sub(r"none\b", "read", lines[none], count=1)]
        else:
            child_indent = indent(lines[children[0]]) if children else level + 2
            fixes[index] = [lines[index], " " * child_indent + "packages: read"]
    return fixes, manual


def main():
    mode = sys.argv[1]
    fixed, manual = False, []
    for path in sorted(glob.glob(".github/workflows/*.yml") + glob.glob(".github/workflows/*.yaml")):
        text = open(path, encoding="utf-8").read()
        lines = text.split("\n")
        fixes, notes = plan(path, lines)
        manual += notes
        if not fixes:
            continue
        fixed = True
        if mode == "apply":
            rewritten = []
            for index, line in enumerate(lines):
                rewritten += fixes.get(index, [line])
            open(path, "w", encoding="utf-8").write("\n".join(rewritten))
    for note in manual:
        print(note)
    if mode == "detect":
        sys.exit(0 if fixed else 2 if manual else 1)


main()
