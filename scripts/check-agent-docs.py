#!/usr/bin/env python3
"""check-agent-docs.py [root]: every command, task, bin and path the agent guidance names exists (N-SHOW-1).

Reads the code spans of templates/agents/platform-block.md, AGENTS.md, docs/consumer-agents.md and docs/runbooks/*.md:
- a path under a Platform root (scripts/, templates/, docs/, gradle/, frontend/packages/, .github/workflows/) or a
  root script (./release.sh) exists in the tree; a consumer path scripts/<x> may be the template templates/<x>;
- `./gradlew <task>` names a task the build-logic sources register, or a task of Gradle or of an applied plugin;
- a platform-<name> word is a bin of frontend/packages/versions/package.json.
Paths with placeholders (<…>, {…}, *) and consumer paths (backend/, frontend/package.json) are not checked.
"""
import glob
import json
import os
import re
import sys

root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
DOCS = ["templates/agents/platform-block.md", "AGENTS.md", "docs/consumer-agents.md"] + sorted(
    os.path.relpath(path, root) for path in glob.glob(os.path.join(root, "docs/runbooks/*.md"))
)
PLATFORM_ROOTS = ("scripts/", "templates/", "docs/", "gradle/", "frontend/packages/", ".github/workflows/")
ROOT_SCRIPTS = re.compile(r"^\./([A-Za-z0-9_-]+\.sh)$")
PATH = re.compile(r"(?<![\w/.-])((?:\./)?[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+)")
GRADLE = re.compile(r"\./gradlew\s+([:A-Za-z0-9_-]+)")
BIN = re.compile(r"(?<![\w/.:-])(platform-[a-z]+(?:-[a-z]+)*)(?![\w.-]*\.[a-z]+)(?![\w/-])")
STANDARD_TASKS = {"build", "check", "test", "assemble", "dependencies", "bootJar", "bootRun", "jar", "spotlessApply",
                  "spotlessCheck", "jacocoTestReport", "pitest", "sonar", "cyclonedxBom", "help", "tasks", "clean"}
WORKFLOW_NAMES = {"platform-bump", "platform-agents"}
# Ignorowany katalog lokalny i pliki, które żyją u konsumenta (w Platform leżą per moduł).
NOT_IN_TREE = {"docs/concepts", "docs/concepts/", "gradle/verification-metadata.xml", "gradle/wrapper/gradle-wrapper.properties"}


def tasks():
    names = set()
    for path in glob.glob(os.path.join(root, "gradle/build-logic/src/main/kotlin/**/*.kt*"), recursive=True):
        names.update(re.findall(r'register(?:<[^>]+>)?\("([A-Za-z0-9]+)"', open(path, encoding="utf-8").read()))
    return names


def bins():
    manifest = os.path.join(root, "frontend/packages/versions/package.json")
    return set(json.load(open(manifest, encoding="utf-8")).get("bin", {})) if os.path.isfile(manifest) else set()


def path_exists(path):
    path = path[2:] if path.startswith("./") else path
    if os.path.exists(os.path.join(root, path)):
        return True
    return path.startswith("scripts/") and os.path.exists(os.path.join(root, "templates", path[len("scripts/"):]))


def main():
    known_tasks, known_bins, problems = tasks(), bins(), []
    for doc in DOCS:
        full = os.path.join(root, doc)
        if not os.path.isfile(full):
            problems.append(f"{doc}: missing")
            continue
        for number, line in enumerate(open(full, encoding="utf-8"), 1):
            for span in re.findall(r"`([^`]+)`", line):
                if any(mark in span for mark in "<>{}*"):
                    candidates = []
                else:
                    candidates = [span]
                for task in GRADLE.findall(span):
                    name = task.split(":")[-1]
                    if name not in known_tasks and name not in STANDARD_TASKS:
                        problems.append(f"{doc}:{number}: `./gradlew {task}` names no registered task")
                for word in BIN.findall(span):
                    if word not in known_bins and word not in WORKFLOW_NAMES and "/" not in span.split(word)[0][-1:]:
                        problems.append(f"{doc}:{number}: `{word}` is not a bin of @dominiksienkiewicz/versions")
                for candidate in candidates:
                    match = ROOT_SCRIPTS.match(candidate.split()[0]) if candidate.split() else None
                    if match and not os.path.exists(os.path.join(root, match.group(1))):
                        problems.append(f"{doc}:{number}: `{candidate}` names a root script that does not exist")
                    for path in PATH.findall(candidate):
                        bare = path[2:] if path.startswith("./") else path
                        if bare.startswith(PLATFORM_ROOTS) and bare not in NOT_IN_TREE and not path_exists(path):
                            problems.append(f"{doc}:{number}: `{path}` does not exist")
    if problems:
        print("Agent guidance names things that do not exist:\n  " + "\n  ".join(problems))
        sys.exit(1)
    print(f"OK: every command, task, bin and path in {len(DOCS)} agent documents exists")


main()
