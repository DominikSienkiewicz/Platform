"""Move a consumer from the personal account DominikSienkiewicz to the organization that owns Platform since 2026-11-13.

Rewritten automatically, without the network:
- the npm scope @dominiksienkiewicz in frontend/package.json, the .npmrc files and every source or configuration
  file under frontend/ (imports, `extends`, CSS `@import` and `@source`, type declarations);
- `DominikSienkiewicz/Platform` in the workflows (callers of the reusable workflows) and in the settings scripts
  (the GitHub Packages URL and links);
- the owner, the scope and the asset name of the platform-bump stub in scripts/.
Lockfiles and node_modules stay: the bump regenerates the lockfile and npm replaces the installed packages. Any other
mention of the personal account (other repositories, GHCR images, documentation) is listed for a manual decision,
because some repositories and images stay with the personal account.
Usage: organization.py files|detect|apply. Exit status of detect: 0 fix needed, 1 nothing, 2 manual only.
"""
import os
import re
import sys

ORGANIZATION = "SeniorDeveloper-pl-Dominik-Sienkiewicz"
SCOPE = re.compile(r"@dominiksienkiewicz\b")
NEW_SCOPE = "@seniordeveloper-pl-dominik-sienkiewicz"
PLATFORM = re.compile(r"(?<![A-Za-z0-9-])DominikSienkiewicz/Platform\b")
STUB_OWNER = re.compile(r'^OWNER="DominikSienkiewicz"$', re.M)
STUB_ASSET = re.compile(r'^asset="dominiksienkiewicz-versions-\$version\.tgz"$', re.M)
PERSONAL = re.compile(r"@dominiksienkiewicz\b|DominikSienkiewicz/|ghcr\.io/dominiksienkiewicz/")

SKIPPED_DIRS = {".git", "node_modules", ".next", "dist", "build", "out", "coverage", ".turbo", ".gradle",
                "storybook-static"}
LOCKFILES = {"package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock"}
FRONTEND_SOURCES = (".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs", ".json", ".jsonc", ".css", ".scss",
                    ".sass", ".less")
NOTES_SHOWN = 20


def frontend_rewrite(text):
    return SCOPE.sub(NEW_SCOPE, text)


def workflow_rewrite(text):
    return PLATFORM.sub(f"{ORGANIZATION}/Platform", SCOPE.sub(NEW_SCOPE, text))


def settings_rewrite(text):
    return PLATFORM.sub(f"{ORGANIZATION}/Platform", text)


def stub_rewrite(text):
    text = STUB_OWNER.sub(f'OWNER="{ORGANIZATION}"', SCOPE.sub(NEW_SCOPE, text))
    return STUB_ASSET.sub('asset="seniordeveloper-pl-dominik-sienkiewicz-versions-$version.tgz"', text)


def walk(root):
    for directory, subdirectories, names in os.walk(root):
        subdirectories[:] = sorted(name for name in subdirectories if name not in SKIPPED_DIRS)
        for name in sorted(names):
            yield os.path.relpath(os.path.join(directory, name), ".")


def candidates():
    """Yield (path, rewrite) for every file the migration may rewrite."""
    for path in (".npmrc", "frontend/.npmrc"):
        if os.path.isfile(path):
            yield path, frontend_rewrite
    if os.path.isdir("frontend"):
        for path in walk("frontend"):
            name = os.path.basename(path)
            if name not in LOCKFILES and name != ".npmrc" and name.endswith(FRONTEND_SOURCES):
                yield path, frontend_rewrite
    if os.path.isdir(".github/workflows"):
        for path in walk(".github/workflows"):
            if path.endswith((".yml", ".yaml")):
                yield path, workflow_rewrite
    for path in ("settings.gradle.kts", "backend/settings.gradle.kts"):
        if os.path.isfile(path):
            yield path, settings_rewrite
    if os.path.isfile("scripts/platform-bump.sh"):
        yield "scripts/platform-bump.sh", stub_rewrite


def plan():
    """Return {path: new text} for every file whose text changes."""
    changes = {}
    for path, rewrite in candidates():
        try:
            text = open(path, encoding="utf-8").read()
        except UnicodeDecodeError:
            continue
        new = rewrite(text)
        if new != text:
            changes[path] = new
    return changes


def notes(changes):
    """Lines that still name the personal account once the rewrites are in, outside lockfiles and installed files."""
    found = []
    for path in walk("."):
        if os.path.basename(path) in LOCKFILES:
            continue
        try:
            text = changes.get(path) or open(path, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        for number, line in enumerate(text.split("\n"), start=1):
            if PERSONAL.search(line):
                found.append(f"{path}:{number}: still names the personal account: {line.strip()[:160]}")
    if len(found) > NOTES_SHOWN:
        found = found[:NOTES_SHOWN] + [f"... and {len(found) - NOTES_SHOWN} more lines; search for DominikSienkiewicz"]
    return found


def main():
    mode = sys.argv[1]
    changes = plan()
    if mode == "files":
        for path in sorted(changes):
            print(path)
        return
    manual = notes(changes)
    if mode == "detect":
        for note in manual:
            print(note)
        sys.exit(0 if changes else 2 if manual else 1)
    for path, text in changes.items():
        with open(path, "w", encoding="utf-8") as out:
            out.write(text)
    for note in manual:
        print(f"           {note}")


main()
