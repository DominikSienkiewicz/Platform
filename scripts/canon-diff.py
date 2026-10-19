#!/usr/bin/env python3
"""canon-diff.py <base> <head>: what a Platform change does to consumers, compared as parsed values.

Reads, at both git revisions: the catalog (gradle/catalog/libs.versions.toml), the frontend canon
(frontend/packages/versions/versions.json), the reusable workflow caller contract
(templates/tests/fixtures/workflow-contract.txt) and the copied canon under templates/. Comment-only edits
change nothing here. Prints a Markdown report and, with --github-output <file>, writes
consumer_action=true|false for the job that labels the pull request.

Consumer action (ADR-0002, a MINOR in the 1.x line) is: a removed catalog alias (version, library, bundle,
plugin), a package removed from the frontend canon, and in the workflow contract a removed input or secret,
a new required input, a new or raised permission, or a changed default. A changed version is not, because
platform-bump moves it and regenerates the lockfiles; a changed template is reported for re-copying.
"""
import json
import subprocess
import sys
import tomllib

CATALOG = "gradle/catalog/libs.versions.toml"
CANON = "frontend/packages/versions/versions.json"
CONTRACT = "templates/tests/fixtures/workflow-contract.txt"
SECTIONS = ("versions", "libraries", "bundles", "plugins")
LEVEL = {"none": 0, "read": 1, "write": 2}


def show(revision, path):
    result = subprocess.run(["git", "show", f"{revision}:{path}"], capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def catalog(revision):
    text = show(revision, CATALOG)
    parsed = tomllib.loads(text) if text else {}
    return {section: parsed.get(section, {}) for section in SECTIONS}


def canon(revision):
    text = show(revision, CANON)
    return json.loads(text).get("versions", {}) if text else {}


def contract(revision):
    """{workflow: {"input": {name: (required, default)}, "secret": {name: required}, "permission": {scope: level}}}"""
    workflows = {}
    for line in (show(revision, CONTRACT) or "").splitlines():
        parts = line.split(" ")
        if len(parts) < 3:
            continue
        workflow = workflows.setdefault(parts[0], {"input": {}, "secret": {}, "permission": {}})
        if parts[1] == "input":
            attributes = dict(part.split("=", 1) for part in parts[3:] if "=" in part)
            workflow["input"][parts[2]] = (attributes.get("required") == "true", attributes.get("default"))
        elif parts[1] == "secret":
            workflow["secret"][parts[2]] = "required=true" in parts[3:]
        elif parts[1] in ("permissions", "job"):
            rest = " ".join(parts[2:] if parts[1] == "permissions" else parts[4:])
            if ":" in rest:
                scope, level = (part.strip() for part in rest.split(":", 1))
                workflow["permission"][scope] = max(workflow["permission"].get(scope, 0), LEVEL.get(level, 0))
    return workflows


def templates(base, head):
    result = subprocess.run(["git", "diff", "--name-only", base, head, "--", "templates/", ":!templates/tests/",
                             ":!templates/README.md"],
                            capture_output=True, text=True, check=True)
    return [path for path in result.stdout.splitlines() if path]


def describe(value):
    if isinstance(value, dict):
        version = value.get("version")
        if isinstance(version, dict) and "ref" in version:
            return f"version.ref {version['ref']}"
        if version is not None:
            return str(version)
        return ", ".join(f"{key}={describe(item)}" for key, item in sorted(value.items()))
    return str(value)


def main():
    arguments = sys.argv[1:]
    output = None
    if "--github-output" in arguments:
        index = arguments.index("--github-output")
        output = arguments[index + 1]
        del arguments[index:index + 2]
    base, head = arguments
    actions, lines = [], []

    old, new = catalog(base), catalog(head)
    for section in SECTIONS:
        accessor = {"versions": "libs.versions.", "libraries": "libs.", "bundles": "libs.bundles.", "plugins": "libs.plugins."}[section]
        for key in sorted(set(old[section]) | set(new[section])):
            before, after = old[section].get(key), new[section].get(key)
            alias = accessor + key.replace("-", ".")
            if before is None:
                lines.append(f"- catalog `{alias}` added: {describe(after)}")
            elif after is None:
                lines.append(f"- catalog `{alias}` removed")
                actions.append(f"a build that uses `{alias}` no longer resolves it")
            elif before != after:
                lines.append(f"- catalog `{alias}`: {describe(before)} → {describe(after)}")

    old_canon, new_canon = canon(base), canon(head)
    for name in sorted(set(old_canon) | set(new_canon)):
        before, after = old_canon.get(name), new_canon.get(name)
        if before is None:
            lines.append(f"- frontend canon `{name}` added: {after}")
        elif after is None:
            lines.append(f"- frontend canon `{name}` removed")
            actions.append(f"`platform-versions-check` fails a frontend that still depends on `{name}`")
        elif before != after:
            lines.append(f"- frontend canon `{name}`: {before} → {after}")

    old_contract, new_contract = contract(base), contract(head)
    if not old_contract and new_contract:
        lines.append("- the base has no workflow contract snapshot yet, so workflow changes are not compared")
        new_contract = {}
    for workflow in sorted(set(old_contract) | set(new_contract)):
        before = old_contract.get(workflow, {"input": {}, "secret": {}, "permission": {}})
        after = new_contract.get(workflow)
        if after is None:
            lines.append(f"- `{workflow}` removed")
            actions.append(f"a caller of `{workflow}` fails")
            continue
        if workflow not in old_contract:
            lines.append(f"- `{workflow}` added")
            continue
        for name in sorted(set(before["input"]) | set(after["input"])):
            was, now = before["input"].get(name), after["input"].get(name)
            if was is None:
                lines.append(f"- `{workflow}` input `{name}` added" + (" (required)" if now[0] else ""))
                if now[0]:
                    actions.append(f"every caller of `{workflow}` must pass the new required input `{name}`")
            elif now is None:
                lines.append(f"- `{workflow}` input `{name}` removed")
                actions.append(f"a caller of `{workflow}` that passes `{name}` fails")
            elif was != now:
                lines.append(f"- `{workflow}` input `{name}`: required={was[0]} default={was[1]} → required={now[0]} default={now[1]}")
                actions.append(f"`{workflow}` input `{name}` changed its default or became required")
        for name in sorted(set(before["secret"]) - set(after["secret"])):
            lines.append(f"- `{workflow}` secret `{name}` removed")
            actions.append(f"a caller of `{workflow}` that passes the secret `{name}` fails")
        for name in sorted(set(after["secret"]) - set(before["secret"])):
            lines.append(f"- `{workflow}` secret `{name}` added")
        for scope in sorted(set(before["permission"]) | set(after["permission"])):
            was, now = before["permission"].get(scope, 0), after["permission"].get(scope, 0)
            if now > was:
                names = {level: name for name, level in LEVEL.items()}
                lines.append(f"- `{workflow}` needs `{scope}: {names[now]}` (was {names[was]})")
                actions.append(f"every caller of `{workflow}` must grant `{scope}: {names[now]}`")
            elif now < was:
                lines.append(f"- `{workflow}` no longer needs `{scope}` at its former level")

    changed_templates = templates(base, head)
    for path in changed_templates:
        lines.append(f"- template `{path}` changed: repositories that keep a copy re-copy it")

    print(f"## Consumer impact of {base[:12]}..{head[:12]}\n")
    print("\n".join(lines) if lines else "Nothing a consumer pins or calls changes.")
    print("\n### Consumer action required\n")
    print("\n".join(f"- {action}" for action in actions) if actions else "None.")
    if output:
        with open(output, "a") as out:
            out.write(f"consumer_action={'true' if actions else 'false'}\n")


main()
