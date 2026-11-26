#!/usr/bin/env bash
# refresh-catalog-update.sh <base-commit>: odtwarza pliki po zmianie katalogu w gałęzi aktualizacji.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: refresh-catalog-update.sh <base-commit>' >&2; exit 2; }
cd "$(dirname "$0")/.."
catalog=gradle/catalog/libs.versions.toml
previous=$(mktemp)
trap 'rm -f "$previous"' EXIT
base=$(git rev-parse --verify --end-of-options "$1^{commit}")
git show "$base:$catalog" > "$previous"
if cmp -s "$previous" "$catalog"; then exit 0; fi

python3 - "$previous" "$catalog" <<'PY'
import re
import subprocess
import sys
import tomllib
import xml.etree.ElementTree as ET
from pathlib import Path

previous_path, catalog_path = map(Path, sys.argv[1:])
previous = tomllib.loads(previous_path.read_text())["versions"]
catalog = catalog_path.read_text()
current = tomllib.loads(catalog)["versions"]
boot_version = current["springBoot"]
if boot_version == previous["springBoot"]:
    if current["jooq"] != previous["jooq"]:
        sys.exit("jOOQ must follow the version managed by Spring Boot.")
    sys.exit(0)

stable = r"[0-9]+\.[0-9]+\.[0-9]+"
if not re.fullmatch(stable, boot_version):
    sys.exit(f"Expected a stable Spring Boot version, got {boot_version!r}.")
artifact = "spring-boot-dependencies"
url = f"https://repo.maven.apache.org/maven2/org/springframework/boot/{artifact}/{boot_version}/{artifact}-{boot_version}.pom"
pom = ET.fromstring(subprocess.check_output([
    "curl", "--fail", "--silent", "--show-error", "--retry", "3", "--max-time", "90", "--proto", "=https", url,
]))
ns = {"": "http://maven.apache.org/POM/4.0.0"}
coordinates = [pom.findtext(key, namespaces=ns) for key in ("groupId", "artifactId", "version")]
if coordinates != ["org.springframework.boot", artifact, boot_version]:
    sys.exit(f"The Maven POM does not identify Spring Boot {boot_version}.")
jooq = pom.findtext("properties/jooq.version", default="", namespaces=ns).strip()
if not re.fullmatch(stable, jooq):
    sys.exit(f"Spring Boot {boot_version} does not declare a stable jooq.version.")
updated, count = re.subn(r'(?m)^(jooq\s*=\s*")[^"]+(")', rf'\g<1>{jooq}\2', catalog)
if count != 1 or tomllib.loads(updated)["versions"]["jooq"] != jooq:
    sys.exit("Cannot update the jOOQ pin in gradle/catalog/libs.versions.toml.")
catalog_path.write_text(updated)
PY
python3 scripts/agents-stack.py
bash scripts/write-verification-metadata.sh --write-locks
