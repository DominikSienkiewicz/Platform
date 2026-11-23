"""Migrate Platform coordinates in consumer-owned build files before resolving the v2 packages."""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

OWNER = "SeniorDeveloper-pl-Dominik-Sienkiewicz"
SCOPE = "@" + OWNER.lower()
PACKAGES = "|".join(re.escape(name) for name in sys.argv[2].split())
PACKAGE = re.compile(r"@dominiksienkiewicz/(?=(" + PACKAGES + r")(?![\w.-]))", re.I)
REPOSITORY = re.compile(r"(?<![\w-])DominikSienkiewicz/Platform(?![\w-])", re.I)
MAVEN = re.compile(r"maven\.pkg\.github\.com/DominikSienkiewicz/Platform(?![\w-])", re.I)
REGISTRY = f"{SCOPE}:registry=https://npm.pkg.github.com"
LEGACY_REGISTRY = re.compile(r"^@dominiksienkiewicz:registry\s*=\s*https://npm\.pkg\.github\.com/?\s*$", re.I)
PROMOTE_CALL = re.compile(rf"^    uses:[ \t]*[\"']?{OWNER}/Platform/\.github/workflows/promote\.yml@", re.I | re.M)
INFRA_INPUT = re.compile(r"""^(      infra-repository:[ \t]*["']?)DominikSienkiewicz/(?=[\w.-]+["']?[ \t]*(?:#.*)?$)""", re.I | re.M)
FRONTEND_SUFFIXES = {
    ".cjs", ".css", ".cts", ".js", ".json", ".json5", ".jsonc", ".jsx", ".less",
    ".mjs", ".mts", ".sass", ".scss", ".ts", ".tsx", ".yaml", ".yml",
}
CONFIG_FILES = {
    "settings.gradle.kts", "backend/settings.gradle.kts", "renovate.json", "renovate.json5",
    ".github/renovate.json", ".github/renovate.json5", ".github/dependabot.yml",
    "compose.yml", "compose.yaml", "docker-compose.yml", "docker-compose.yaml",
}
LOCKFILES = {"package-lock.json", "pnpm-lock.yaml", "npm-shrinkwrap.json"}


def files():
    listed = subprocess.check_output(["git", "ls-files", "--cached", "-z"])
    candidates = {Path(os.fsdecode(p)) for p in listed.split(b"\0") if p}
    candidates.update(Path(p) for p in ("frontend/package.json", "settings.gradle.kts", "backend/settings.gradle.kts"))
    if Path(".npmrc").is_file():
        candidates.add(Path(".npmrc"))
    if Path("frontend/package.json").is_file():
        candidates.add(Path("frontend/.npmrc"))
    for path in sorted(candidates):
        if path.is_symlink() or path.name in LOCKFILES or path == Path("scripts/platform-bump.sh"):
            continue
        if path in (Path(".npmrc"), Path("frontend/.npmrc")):
            yield path
        elif path.is_file() and (
            path.as_posix() in CONFIG_FILES
            or path.parts[0] == "frontend" and (path.suffix in FRONTEND_SUFFIXES or path.name.startswith("Dockerfile"))
            or path.parts[:2] == (".github", "workflows") and path.suffix in {".yml", ".yaml"}
            or path.parts[0] == "scripts" and path.suffix == ".sh"
        ):
            yield path


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate key")
        result[key] = value
    return result


def migrated(path, data):
    if path.name == ".npmrc":
        mappings = [line.partition("=")[2].strip().rstrip("/") for line in data.splitlines()
                    if line.partition("=")[0].strip().lower() == SCOPE + ":registry"]
        if mappings:
            if any(url != "https://npm.pkg.github.com" for url in mappings):
                raise SystemExit(f"{path} already maps the organization to a different registry. Resolve it before the bump.")
            return data
        if path == Path(".npmrc") and not any(LEGACY_REGISTRY.fullmatch(line) for line in data.splitlines()):
            return data
        if not data:
            return f"{REGISTRY}\n//npm.pkg.github.com/:_authToken=${{GITHUB_TOKEN}}\n"
        lines = data.splitlines(keepends=True)
        for index, line in enumerate(lines):
            if LEGACY_REGISTRY.fullmatch(line):
                lines.insert(index, REGISTRY + "\n")
                return "".join(lines)
        return data.rstrip("\n") + "\n" + REGISTRY + "\n"
    data = MAVEN.sub(f"maven.pkg.github.com/{OWNER.lower()}/Platform", data)
    data = REPOSITORY.sub(f"{OWNER}/Platform", data)
    if path.parts[:2] == (".github", "workflows"):
        jobs = re.split(r"(?=^  [\w-]+:)", data, flags=re.M)
        data = "".join(INFRA_INPUT.sub(rf"\g<1>{OWNER}/", job) if PROMOTE_CALL.search(job) else job for job in jobs)
    updated = PACKAGE.sub(SCOPE + "/", data)
    if path.name == "package.json" and updated != data:
        try:
            json.loads(updated, object_pairs_hook=unique_keys)
        except ValueError:
            raise SystemExit(f"{path} contains conflicting package coordinates or invalid JSON. Resolve it before the bump.") from None
    return updated


def changed(path):
    before = path.read_bytes() if path.exists() else b""
    try:
        return migrated(path, before.decode("utf-8")).encode("utf-8") != before
    except UnicodeDecodeError:
        return False


def main():
    command = sys.argv[1]
    if command == "files":
        for path in files():
            if changed(path):
                sys.stdout.buffer.write(os.fsencode(path) + b"\0")
    elif command == "apply":
        for entry in sys.stdin.buffer.read().split(b"\0"):
            if entry:
                path = Path(os.fsdecode(entry))
                before = path.read_bytes() if path.exists() else b""
                path.write_bytes(migrated(path, before.decode("utf-8")).encode("utf-8"))
    else:
        raise SystemExit("Usage: organization.py files|apply PACKAGE_NAMES")


if __name__ == "__main__":
    main()
