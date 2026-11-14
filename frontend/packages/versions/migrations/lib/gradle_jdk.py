"""Move the JDK that runs Gradle to the Java of Platform's build-logic (ADR-0034).

Rewritten automatically: a literal `java-version` below the target in a job that calls one of Platform's
reusable workflows, and a `java=` below the target in `.sdkmanrc` or `backend/.sdkmanrc`. Reported for a
manual fix: a literal `java-version` below the target anywhere else (the migration cannot tell whether that
JDK runs Gradle) and Gradle daemon criteria below the target (regenerating them needs Foojay, so the network).
Usage: gradle_jdk.py detect|apply <java> <sdkman java>. Exit status of detect: 0 fix needed, 1 nothing, 2 manual only.
"""
import glob
import os
import re
import sys

CALLER = re.compile(r"^\s+uses:\s*DominikSienkiewicz/Platform/\.github/workflows/[^@\s]+@")
JAVA_VERSION = re.compile(r"^(\s+java-version:\s*)([\"']?)(\d+)(\2)(\s*(?:#.*)?)$")
JOB = re.compile(r"^  [A-Za-z0-9_-]+:\s*$")
SDKMAN = re.compile(r"^java=(\d+)\S*\s*$")
DAEMON = re.compile(r"^toolchainVersion=(\d+)\s*$")


def workflow_fixes(path, lines, target):
    """Return ({line index: replacement}, [manual notes]) for one workflow."""
    fixes, manual = {}, []
    top_end = next((i for i, line in enumerate(lines) if re.match(r"^jobs:\s*$", line)), len(lines))
    jobs = [i for i in range(top_end + 1, len(lines)) if JOB.match(lines[i])]
    for number, start in enumerate(jobs):
        end = jobs[number + 1] if number + 1 < len(jobs) else next(
            (i for i in range(start + 1, len(lines)) if re.match(r"^\S", lines[i])), len(lines))
        caller = any(CALLER.match(line) for line in lines[start:end])
        for index in range(start, end):
            match = JAVA_VERSION.match(lines[index])
            if not match or int(match.group(3)) >= target:
                continue
            if caller:
                prefix, quote, _, _, rest = match.groups()
                fixes[index] = f"{prefix}{quote}{target}{quote}{rest}"
            else:
                manual.append(f"{path}:{index + 1}: java-version {match.group(3)} is set outside a Platform caller; "
                              f"raise it to {target} if this JDK runs Gradle")
    return fixes, manual


def sdkman_fixes(lines, target, sdkman_java):
    fixes = {}
    for index, line in enumerate(lines):
        match = SDKMAN.match(line)
        if match and int(match.group(1)) < target:
            fixes[index] = f"java={sdkman_java}"
    return fixes


def daemon_notes(target):
    notes = []
    for path in ("gradle/gradle-daemon-jvm.properties", "backend/gradle/gradle-daemon-jvm.properties"):
        if not os.path.isfile(path):
            continue
        for line in open(path, encoding="utf-8").read().split("\n"):
            match = DAEMON.match(line)
            if match and int(match.group(1)) < target:
                notes.append(f"{path}: toolchainVersion={match.group(1)}; "
                             f"run ./gradlew updateDaemonJvm --jvm-version={target}")
    return notes


def main():
    mode, target, sdkman_java = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    fixed, manual = False, []
    workflows = sorted(glob.glob(".github/workflows/*.yml") + glob.glob(".github/workflows/*.yaml"))
    sdkmanrcs = [path for path in (".sdkmanrc", "backend/.sdkmanrc") if os.path.isfile(path)]
    for path in workflows + sdkmanrcs:
        lines = open(path, encoding="utf-8").read().split("\n")
        if path in sdkmanrcs:
            fixes = sdkman_fixes(lines, target, sdkman_java)
        else:
            fixes, notes = workflow_fixes(path, lines, target)
            manual += notes
        if not fixes:
            continue
        fixed = True
        if mode == "apply":
            open(path, "w", encoding="utf-8").write("\n".join(fixes.get(i, line) for i, line in enumerate(lines)))
    manual += daemon_notes(target)
    for note in manual:
        print(note)
    if mode == "detect":
        sys.exit(0 if fixed else 2 if manual else 1)


main()
