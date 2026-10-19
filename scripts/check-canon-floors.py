#!/usr/bin/env python3
"""check-canon-floors.py <bom.json> <libs.versions.toml>: the canon SBOM honours the catalog's CVE floors.

platform-bom raises Jackson and Tomcat above the versions Spring Boot manages (CVE floors, `because("CVE…")` in
gradle/bom/build.gradle.kts). canon-cve-scan.yml scans the SBOM of gradle/canon-probe, so a component below its
floor means the probe lost platform-bom and Grype reports versions no consumer gets. A floor whose catalog key is
missing (an older tag) is skipped. `--keys` prints the catalog keys this script enforces; its test compares them
with the CVE floors of gradle/bom.
"""
import json
import re
import sys
import tomllib

FLOORS = {
    "jacksonBom": ["tools.jackson.core:jackson-core", "tools.jackson.core:jackson-databind"],
    "jackson2Bom": ["com.fasterxml.jackson.core:jackson-core", "com.fasterxml.jackson.core:jackson-databind"],
    "tomcat": [
        "org.apache.tomcat.embed:tomcat-embed-core",
        "org.apache.tomcat.embed:tomcat-embed-el",
        "org.apache.tomcat.embed:tomcat-embed-websocket",
    ],
}


def numeric(version):
    return tuple(int(part) for part in re.findall(r"\d+", version.split("-")[0]))


def main():
    if sys.argv[1:] == ["--keys"]:
        print("\n".join(FLOORS))
        return 0
    bom_path, catalog_path = sys.argv[1:3]
    with open(catalog_path, "rb") as catalog_file:
        versions = tomllib.load(catalog_file).get("versions", {})
    with open(bom_path) as bom_file:
        components = json.load(bom_file).get("components", [])
    floor_of = {
        coordinate: (key, versions[key])
        for key, coordinates in FLOORS.items()
        if key in versions
        for coordinate in coordinates
    }
    checked = 0
    below = []
    for component in components:
        coordinate = f"{component.get('group', '')}:{component.get('name', '')}"
        if coordinate not in floor_of:
            continue
        key, floor = floor_of[coordinate]
        checked += 1
        if numeric(component.get("version", "0")) < numeric(floor):
            below.append(f"{coordinate} {component.get('version')} is below the floor {floor} ({key})")
    if below:
        for line in below:
            print(f"::error title=Canon CVE floors::{line}")
        print(
            "The canon SBOM misses platform-bom's CVE floors, so the scan would report versions no consumer gets. "
            "Check that gradle/canon-probe resolves pl.seniordeveloper:platform-bom.",
            file=sys.stderr,
        )
        return 1
    print(f"OK: {checked} components meet the CVE floors of the catalog")
    return 0


if __name__ == "__main__":
    sys.exit(main())
