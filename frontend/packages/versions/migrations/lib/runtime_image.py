"""Move the final Dockerfile stage off a Java runtime older than the toolchain (27).

Only `eclipse-temurin:<N>-jre` and `-jdk` with N < 27 are rewritten; any other Temurin or SapMachine tag
below 27 (alpine, a digest, sapmachine:26) is reported for a manual fix.
Usage: runtime_image.py detect|apply <image>. Exit status of detect: 0 fix needed, 1 nothing, 2 manual only.
"""
import os
import re
import sys

FROM = re.compile(r"^(\s*FROM\s+(?:--platform=\S+\s+)?)(\S+)(.*)$", re.IGNORECASE)
AUTOMATIC = re.compile(r"^eclipse-temurin:(\d+)-(?:jre|jdk)$")
JAVA_TAG = re.compile(r"^(?:eclipse-temurin|sapmachine):(\d+)")
TOOLCHAIN = 27


def main():
    mode, image = sys.argv[1], sys.argv[2]
    fixed, manual = False, []
    for path in ("backend/Dockerfile", "Dockerfile"):
        if not os.path.isfile(path):
            continue
        lines = open(path, encoding="utf-8").read().split("\n")
        final = max((i for i, line in enumerate(lines) if FROM.match(line)), default=None)
        if final is None:
            continue
        prefix, current, rest = FROM.match(lines[final]).groups()
        automatic, java = AUTOMATIC.match(current), JAVA_TAG.match(current)
        if automatic and int(automatic.group(1)) < TOOLCHAIN:
            fixed = True
            if mode == "apply":
                lines[final] = prefix + image + rest
                open(path, "w", encoding="utf-8").write("\n".join(lines))
        elif java and int(java.group(1)) < TOOLCHAIN:
            manual.append(f"{path}:{final + 1}: move `{current}` to a Java {TOOLCHAIN} runtime such as {image}")
    for note in manual:
        print(note)
    if mode == "detect":
        sys.exit(0 if fixed else 2 if manual else 1)


main()
