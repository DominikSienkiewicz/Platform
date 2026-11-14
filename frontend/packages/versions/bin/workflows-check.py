#!/usr/bin/env python3
"""platform-workflows-check: hold every caller of a Platform reusable workflow to the callee's contract.

A caller that grants too few permissions, passes an input or secret the workflow does not declare, or
omits a required input fails with startup_failure and no step log. This check finds that statically, from
the caller contract snapshot of a Platform release (workflow-contract.txt, shipped in this package):

- the job's effective permissions (its own block, else the workflow's) cover every permission the callee
  requests in any of its jobs; without either block the repository's default token permissions apply,
  which this check cannot see, so it warns;
- every `with:` key is an input of the callee, and every required input is passed;
- every explicitly passed secret is a secret of the callee (`secrets: inherit` hides that, so it warns);
- the ref is the exact release tag the contract describes (Decision 3).

Usage: platform-workflows-check [--ref vX.Y.Z] [--contract <file>] [--root <dir>]
Exit 0 without errors (warnings allowed), 1 with errors. The YAML is read line by line in the shape
GitHub workflows use; a shape it does not recognise is reported as a warning, never guessed.
"""
import argparse
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
USES = re.compile(r"^    uses:\s*DominikSienkiewicz/Platform/\.github/workflows/([A-Za-z0-9_.-]+\.ya?ml)@(\S+)")
LEVEL = {"none": 0, "read": 1, "write": 2}


def indent(line):
    return len(line) - len(line.lstrip(" "))


def meaningful(line):
    stripped = line.strip()
    return bool(stripped) and not stripped.startswith("#")


def value_of(line):
    return re.sub(r"\s+#.*$", "", line.split(":", 1)[1]).strip() if ":" in line else ""


def children(lines, index):
    """Lines one level below lines[index], as (line index, key, value)."""
    level, child_level, found = indent(lines[index]), None, []
    for child in range(index + 1, len(lines)):
        if not meaningful(lines[child]):
            continue
        if indent(lines[child]) <= level:
            break
        if child_level is None:
            child_level = indent(lines[child])
        if indent(lines[child]) == child_level:
            key = lines[child].strip().split(":", 1)[0].strip("\"'")
            found.append((child, key, value_of(lines[child])))
    return found


def permissions(lines, index):
    """Permissions declared at lines[index] as {scope: level}, "read-all"/"write-all", or None for an unknown shape."""
    value = value_of(lines[index])
    if value in ("read-all", "write-all"):
        return value
    if value.startswith("{") and value.endswith("}"):
        pairs = [part.split(":", 1) for part in value[1:-1].split(",") if part.strip()]
        if any(len(pair) != 2 for pair in pairs):
            return None
        return {scope.strip(): level.strip() for scope, level in pairs}
    if value:
        return None
    return {key: level for _, key, level in children(lines, index)}


def grants(declared, scope):
    if declared == "write-all":
        return LEVEL["write"]
    if declared == "read-all":
        return LEVEL["read"]
    return LEVEL.get(declared.get(scope, "none"), 0)


def read_contract(path):
    contract = {}
    for line in open(path, encoding="utf-8"):
        parts = line.rstrip("\n").split(" ")
        if len(parts) < 3:
            continue
        workflow = contract.setdefault(parts[0], {"inputs": {}, "secrets": set(), "permissions": {}})
        kind = parts[1]
        if kind == "input":
            workflow["inputs"][parts[2]] = "required=true" in parts[3:]
        elif kind == "secret":
            workflow["secrets"].add(parts[2])
        elif kind in ("permissions", "job"):
            rest = " ".join(parts[2:] if kind == "permissions" else parts[4:])
            if ":" in rest:
                scope, level = (part.strip() for part in rest.split(":", 1))
                workflow["permissions"][scope] = max(workflow["permissions"].get(scope, 0), LEVEL.get(level, 0))
    return contract


def check_file(source, path, contract, ref, report):
    lines = open(source, encoding="utf-8").read().split("\n")
    jobs_line = next((i for i, line in enumerate(lines) if re.match(r"^jobs:\s*$", line)), None)
    if jobs_line is None:
        return
    top = next((i for i in range(0, len(lines)) if re.match(r"^permissions:", lines[i])), None)
    jobs = [i for i in range(jobs_line + 1, len(lines)) if re.match(r"^  [A-Za-z0-9_-]+:\s*$", lines[i])]
    for number, start in enumerate(jobs):
        end = jobs[number + 1] if number + 1 < len(jobs) else len(lines)
        body = range(start + 1, end)
        call = next(((i, USES.match(lines[i])) for i in body if USES.match(lines[i])), None)
        if call is None:
            continue
        line, match = call
        workflow, used_ref = match.group(1), match.group(2)
        job = lines[start].strip().rstrip(":")
        where = f"{path}:{line + 1} job {job} calls {workflow}@{used_ref}"
        callee = contract.get(workflow)
        if callee is None:
            report("ERROR", f"{where}: {ref} has no reusable workflow {workflow}")
            continue
        if used_ref != ref:
            report("WARN", f"{where}: checked against the contract of {ref}; reference that exact tag (Decision 3)")

        block = next((i for i in body if re.match(r"^    permissions:", lines[i])), top)
        declared = permissions(lines, block) if block is not None else None
        if block is None:
            report("WARN", f"{where}: no permissions block, so it depends on the repository's default token permissions")
        elif declared is None:
            report("WARN", f"{path}:{block + 1}: permissions in a shape this check does not read; check them by hand")
        else:
            for scope, needed in sorted(callee["permissions"].items()):
                if grants(declared, scope) < needed:
                    have = next(name for name, level in LEVEL.items() if level == grants(declared, scope))
                    want = next(name for name, level in LEVEL.items() if level == needed)
                    report("ERROR", f"{where}: grants {scope}: {have}, the workflow needs {scope}: {want}")

        with_line = next((i for i in body if re.match(r"^    with:\s*$", lines[i])), None)
        passed = {key for _, key, _ in children(lines, with_line)} if with_line is not None else set()
        for key in sorted(passed - set(callee["inputs"])):
            report("ERROR", f"{where}: input {key} is not declared by {workflow}")
        for key in sorted(name for name, required in callee["inputs"].items() if required and name not in passed):
            report("ERROR", f"{where}: required input {key} is missing")

        secrets_line = next((i for i in body if re.match(r"^    secrets:", lines[i])), None)
        if secrets_line is not None and value_of(lines[secrets_line]) == "inherit":
            report("WARN", f"{where}: secrets: inherit hands every secret over; pass the ones {workflow} declares")
        elif secrets_line is not None:
            for _, key, _ in children(lines, secrets_line):
                if key not in callee["secrets"]:
                    report("ERROR", f"{where}: secret {key} is not declared by {workflow}")


def main():
    parser = argparse.ArgumentParser(prog="platform-workflows-check")
    parser.add_argument("--ref", help="the Platform release tag the contract describes (default: this package's version)")
    parser.add_argument("--contract", default=os.path.join(HERE, "..", "workflow-contract.txt"))
    parser.add_argument("--root", default=".")
    args = parser.parse_args()
    ref = args.ref or "v" + json.load(open(os.path.join(HERE, "..", "package.json")))["version"]
    contract = read_contract(args.contract)
    errors = []

    def report(severity, message):
        print(f"{severity} {message}")
        if severity == "ERROR":
            errors.append(message)

    for path in sorted(glob.glob(os.path.join(args.root, ".github/workflows/*.yml"))
                       + glob.glob(os.path.join(args.root, ".github/workflows/*.yaml"))):
        check_file(path, os.path.relpath(path, args.root), contract, ref, report)
    if errors:
        print(f"{len(errors)} caller(s) break the reusable workflow contract of {ref}; their runs end in startup_failure.")
    sys.exit(1 if errors else 0)


main()
