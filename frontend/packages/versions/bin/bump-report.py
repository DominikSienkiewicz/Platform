#!/usr/bin/env python3
"""bump-report.py: wpływ wydań (CUR, TARGET] Platform na to repo, dla `platform-bump --report` (N-REL-8).

Ten sam silnik co scripts/canon-diff.py (canon_diff.py), przecięty z tym, czego repo używa: aliasy `libs.…`
w skryptach Gradle, wersje narzucane przez convention pluginy, paczki frontendu, wołane reusable workflowy
i `FROM` Dockerfile'a przy zmianie toolchainu. Trzy sekcje: co dotyczy tego repo, czego tu nie ma i co wymaga akcji.

  bump-report.py --repo . --current 1.5.31 --target 1.6.0 \\
    --catalog-old a.toml --catalog-new b.toml [--canon-old a.json --canon-new b.json] \\
    [--contract-old a.txt --contract-new b.txt]
Brakujący plik (np. wydanie sprzed assetów) daje w raporcie notkę zamiast porównania tej części.
"""

import argparse
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import canon_diff  # noqa: E402

# Wersje katalogu, które convention pluginy narzucają każdemu buildowi z nimi (PlatformVersions + wrapper), więc
# dotyczą repo z backendem Platform bez względu na to, czy skrypt woła `libs.versions.<klucz>`.
CONVENTION_VERSIONS = {
    "java", "gradle", "googleJavaFormat", "checkstyle", "jacoco", "spotbugs", "pitestTool", "pitestJunit5",
    "springBoot", "springModulith", "springAi", "junit", "archunit", "lombok", "tomcat", "jacksonBom", "jackson2Bom",
    "errorprone", "nullaway",
}
ALIAS = re.compile(r"\blibs\.([A-Za-z0-9_.]+)")
USES = re.compile(r"uses:\s*[A-Za-z0-9_.-]+/Platform/\.github/workflows/([A-Za-z0-9_.-]+\.ya?ml)@")


def read(path):
    if not path or not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def gradle_scripts(repo):
    return [
        path
        for pattern in ("*.gradle.kts", "backend/**/*.gradle.kts", "*/**/*.gradle.kts")
        for path in glob.glob(os.path.join(repo, pattern), recursive=True)
        if "/build/" not in path and "/node_modules/" not in path and "/.gradle/" not in path
    ]


def used_aliases(repo):
    aliases = set()
    for path in sorted(set(gradle_scripts(repo))):
        for match in ALIAS.finditer(read(path) or ""):
            dotted = match.group(1).rstrip(".")
            # libs.boot.starter.webmvc.get() i libs.versions.x.get(): akcesor kończy się na pierwszym wywołaniu.
            dotted = re.split(r"\.(?:get|orNull|map)\b", dotted)[0]
            aliases.add("libs." + dotted)
    return aliases


def uses_platform_conventions(repo):
    return any("seniordev." in (read(path) or "") for path in gradle_scripts(repo))


def frontend_packages(repo):
    text = read(os.path.join(repo, "frontend", "package.json"))
    if not text:
        return set()
    manifest = json.loads(text)
    names = set()
    for section in ("dependencies", "devDependencies", "optionalDependencies"):
        names.update(manifest.get(section, {}))

    def walk(node):
        for key, value in node.items():
            if key != ".":
                names.add(key)
            if isinstance(value, dict):
                walk(value)

    walk(manifest.get("overrides", {}))
    return names


def called_workflows(repo):
    called = set()
    for path in glob.glob(os.path.join(repo, ".github", "workflows", "*.y*ml")):
        called.update(USES.findall(read(path) or ""))
    return called


def dockerfiles(repo):
    return [name for name in ("Dockerfile", "backend/Dockerfile") if os.path.isfile(os.path.join(repo, name))]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=".")
    parser.add_argument("--current", required=True)
    parser.add_argument("--target", required=True)
    for part in ("catalog", "canon", "contract"):
        parser.add_argument(f"--{part}-old")
        parser.add_argument(f"--{part}-new")
    args = parser.parse_args()
    repo = args.repo

    affects, unused, actions, notes = [], [], [], []
    aliases = used_aliases(repo)
    conventions = uses_platform_conventions(repo)

    old_catalog, new_catalog = read(args.catalog_old), read(args.catalog_new)
    if old_catalog is None or new_catalog is None:
        notes.append("the catalogs of both releases were not available, so the Gradle side is not compared")
    else:
        for change in canon_diff.catalog_changes(canon_diff.catalog_from_text(old_catalog), canon_diff.catalog_from_text(new_catalog)):
            used = sorted(set(change.aliases) & aliases)
            imposed = conventions and change.aliases[0].startswith("libs.versions.") and change.key in CONVENTION_VERSIONS
            if used or imposed:
                why = f"used as {', '.join(f'`{name}`' for name in used)}" if used else "imposed by the Platform conventions"
                affects.append(f"{change.line} ({why})")
                if change.action:
                    actions.append(change.action)
                if change.key == "java" and change.aliases[0] == "libs.versions.java":
                    for dockerfile in dockerfiles(repo):
                        affects.append(
                            f"`{dockerfile}`: its final `FROM` must run the new Java, or `platformRuntimeImageCheck` fails "
                            "(copy the final `FROM` of templates/Dockerfile.backend)"
                        )
            else:
                unused.append(change.line)

    old_canon, new_canon = read(args.canon_old), read(args.canon_new)
    packages = frontend_packages(repo)
    if packages:
        if old_canon is None or new_canon is None:
            notes.append("the frontend canons of both releases were not available, so the frontend is not compared")
        else:
            for change in canon_diff.canon_changes(canon_diff.canon_from_text(old_canon), canon_diff.canon_from_text(new_canon)):
                if change.key in packages:
                    affects.append(change.line)
                    if change.action:
                        actions.append(change.action)
                else:
                    unused.append(change.line)

    called = called_workflows(repo)
    if called:
        old_contract, new_contract = read(args.contract_old), read(args.contract_new)
        if old_contract is None or new_contract is None:
            notes.append("the workflow contracts of both releases were not available, so the workflow callers are not compared")
        else:
            for change in canon_diff.contract_changes(canon_diff.contract_from_text(old_contract), canon_diff.contract_from_text(new_contract)):
                if change.key in called:
                    affects.append(change.line)
                    if change.action:
                        actions.append(change.action)
                else:
                    unused.append(change.line)

    print(f"## Platform {args.current} → {args.target}: impact on this repository\n")
    print("### Affects this repo\n")
    print("\n".join(f"- {line}" for line in affects) if affects else "Nothing this repository uses changes.")
    print("\n### Not used here\n")
    print("\n".join(f"- {line}" for line in unused) if unused else "None.")
    print("\n### Consumer action required\n")
    lines = [f"- {action}" for action in dict.fromkeys(actions)]
    lines.append("- and every item of the release notes' Consumer action required sections, which the bump prints")
    print("\n".join(lines))
    if notes:
        print("\n" + "\n".join(f"> Note: {note}." for note in notes))


main()
