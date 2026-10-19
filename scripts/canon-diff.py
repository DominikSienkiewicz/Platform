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
import os
import subprocess
import sys

# Silnik porównania żyje w paczce versions (bin/canon_diff.py), bo tę samą logikę konsument dostaje w bumpie
# (bump-report.py, N-REL-8); ten skrypt tylko czyta obie rewizje gita Platform.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "frontend", "packages", "versions", "bin"))
import canon_diff  # noqa: E402

CATALOG = "gradle/catalog/libs.versions.toml"
CANON = "frontend/packages/versions/versions.json"
CONTRACT = "templates/tests/fixtures/workflow-contract.txt"


def show(revision, path):
    result = subprocess.run(["git", "show", f"{revision}:{path}"], capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def templates(base, head):
    result = subprocess.run(["git", "diff", "--name-only", base, head, "--", "templates/", ":!templates/tests/",
                             ":!templates/README.md"],
                            capture_output=True, text=True, check=True)
    return [path for path in result.stdout.splitlines() if path]


def main():
    arguments = sys.argv[1:]
    output = None
    if "--github-output" in arguments:
        index = arguments.index("--github-output")
        output = arguments[index + 1]
        del arguments[index:index + 2]
    base, head = arguments
    changes = canon_diff.catalog_changes(canon_diff.catalog_from_text(show(base, CATALOG)),
                                         canon_diff.catalog_from_text(show(head, CATALOG)))
    changes += canon_diff.canon_changes(canon_diff.canon_from_text(show(base, CANON)),
                                        canon_diff.canon_from_text(show(head, CANON)))
    old_contract = canon_diff.contract_from_text(show(base, CONTRACT))
    new_contract = canon_diff.contract_from_text(show(head, CONTRACT))
    lines = [f"- {change.line}" for change in changes]
    if not old_contract and new_contract:
        lines.append("- the base has no workflow contract snapshot yet, so workflow changes are not compared")
        new_contract = {}
    workflow_changes = canon_diff.contract_changes(old_contract, new_contract)
    lines += [f"- {change.line}" for change in workflow_changes]
    actions = [change.action for change in changes + workflow_changes if change.action]

    for path in templates(base, head):
        lines.append(f"- template `{path}` changed: repositories that keep a copy re-copy it")

    print(f"## Consumer impact of {base[:12]}..{head[:12]}\n")
    print("\n".join(lines) if lines else "Nothing a consumer pins or calls changes.")
    print("\n### Consumer action required\n")
    print("\n".join(f"- {action}" for action in actions) if actions else "None.")
    if output:
        with open(output, "a") as out:
            out.write(f"consumer_action={'true' if actions else 'false'}\n")


main()
