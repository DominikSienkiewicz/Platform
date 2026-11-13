"""Move a consumer from the personal account DominikSienkiewicz to the organization that owns Platform since 2026-11-13.

Rewritten automatically, without the network:
- the npm scope @dominiksienkiewicz in frontend/package.json, the .npmrc files and every source or configuration
  file under frontend/ (imports, `extends`, CSS `@import` and `@source`, type declarations);
- `DominikSienkiewicz/Platform` in the workflows (callers of the reusable workflows), and outside comments in the
  settings scripts (the GitHub Packages URL and links in strings); a comment may say what the old owner did;
- the owner, the scope and the asset name of an old platform-bump stub in scripts/. The stub of 2.0.0 names the old
  scope on purpose, to recognise a bin npm installed from it, and stays as it is.
Lockfiles and node_modules stay: the bump regenerates the lockfile and npm replaces the installed packages. Any other
mention of the personal account (other repositories, GHCR images, documentation) is listed for a manual decision,
because some repositories and images stay with the personal account, and so is a repository of the organization's
GitHub Packages that dependencyResolutionManagement declares itself, which the settings plugin adds from 2.0.0 on.
Usage: organization.py files|detect|apply. Exit status of detect: 0 fix needed, 1 nothing, 2 manual only.
"""
import os
import re
import sys

ORGANIZATION = "SeniorDeveloper-pl-Dominik-Sienkiewicz"
SCOPE = re.compile(r"@dominiksienkiewicz\b")
NEW_SCOPE = "@seniordeveloper-pl-dominik-sienkiewicz"
PLATFORM = re.compile(r"(?<![A-Za-z0-9-])DominikSienkiewicz/Platform\b")
# Scope w stubie poza ścieżką node_modules/@dominiksienkiewicz/, którą stub 2.0.0 sprawdza celowo (stary bin).
STUB_SCOPE = re.compile(r"(?<!node_modules/)@dominiksienkiewicz/")
STUB_OWNER = re.compile(r'^OWNER="DominikSienkiewicz"$', re.M)
STUB_ASSET = re.compile(r'^asset="dominiksienkiewicz-versions-\$version\.tgz"$', re.M)
PERSONAL = re.compile(r"@dominiksienkiewicz\b|DominikSienkiewicz/|ghcr\.io/dominiksienkiewicz/")
STUB = "scripts/platform-bump.sh"
SETTINGS = ("settings.gradle.kts", "backend/settings.gradle.kts")
ORGANIZATION_PACKAGES = re.compile(r"maven\.pkg\.github\.com/SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform\b", re.I)

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


def comment_mask(text):
    """For each character of a Kotlin script, True when it belongs to a // or /* */ comment.

    Strings, raw strings and their ${...} templates count as code, so a `//` inside "https://..." opens no comment.
    """
    mask = [False] * len(text)
    state, frames, i = "code", [], 0
    while i < len(text):
        if state == "code":
            if text.startswith('"""', i):
                state, i = "raw", i + 3
                continue
            if text[i] == '"':
                state = "string"
            elif text.startswith("//", i) or text.startswith("/*", i):
                state = "line" if text[i + 1] == "/" else "block"
                mask[i] = mask[i + 1] = True
                i += 2
                continue
            elif text[i] == "{" and frames:
                frames[-1][1] += 1
            elif text[i] == "}" and frames:
                if frames[-1][1] == 0:
                    state = frames.pop()[0]
                else:
                    frames[-1][1] -= 1
            i += 1
        elif state in ("string", "raw"):
            if text.startswith("${", i):
                frames.append([state, 0])
                state, i = "code", i + 2
                continue
            if state == "string" and text[i] == "\\":
                i += 2
                continue
            if (state == "string" and text[i] in '"\n') or (state == "raw" and text.startswith('"""', i)):
                i += 3 if state == "raw" else 1
                state = "code"
                continue
            i += 1
        else:
            mask[i] = True
            if state == "line" and text[i] == "\n":
                mask[i] = False
                state = "code"
            elif state == "block" and text.startswith("*/", i):
                mask[i + 1] = True
                state, i = "code", i + 2
                continue
            i += 1
    return mask


def settings_rewrite(text):
    mask = comment_mask(text)
    return PLATFORM.sub(lambda match: match.group(0) if mask[match.start()] else f"{ORGANIZATION}/Platform", text)


def stub_rewrite(text):
    text = STUB_OWNER.sub(f'OWNER="{ORGANIZATION}"', STUB_SCOPE.sub(NEW_SCOPE + "/", text))
    return STUB_ASSET.sub('asset="seniordeveloper-pl-dominik-sienkiewicz-versions-$version.tgz"', text)


def duplicate_repositories(path, text):
    """Notes for the organization's GitHub Packages that dependencyResolutionManagement declares outside comments."""
    mask, found = comment_mask(text), []
    for block in re.finditer(r"\bdependencyResolutionManagement\b", text):
        start = text.find("{", block.end())
        if mask[block.start()] or start < 0:
            continue
        depth, end = 0, len(text)
        for index in range(start, len(text)):
            if mask[index] or text[index] not in "{}":
                continue
            depth += 1 if text[index] == "{" else -1
            if depth == 0:
                end = index
                break
        for url in ORGANIZATION_PACKAGES.finditer(text, start, end):
            if not mask[url.start()]:
                line = text.count("\n", 0, url.start()) + 1
                found.append(f"{path}:{line}: dependencyResolutionManagement declares the organization's GitHub Packages "
                             "repository, which the settings plugin adds itself from 2.0.0 on; delete this one")
    return found


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
    for path in SETTINGS:
        if os.path.isfile(path):
            yield path, settings_rewrite
    if os.path.isfile(STUB):
        yield STUB, stub_rewrite


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
    for path in SETTINGS:
        if os.path.isfile(path):
            found += duplicate_repositories(path, changes.get(path) or open(path, encoding="utf-8").read())
    for path in walk("."):
        if os.path.basename(path) in LOCKFILES or path == STUB:
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
