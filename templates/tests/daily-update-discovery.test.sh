#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

python3 - <<'PY'
import fnmatch
import json
import re
import tomllib
from pathlib import Path

config = json.loads(Path("renovate.json").read_text())
catalog_path = Path("gradle/catalog/libs.versions.toml")
content = catalog_path.read_text()
catalog = tomllib.loads(content)
assert config.get("schedule") == ["at any time"], "a daily run must be able to open upgrades on any weekday"

# Każda zewnętrzna wersja biblioteki lub narzędzia ma źródło: natywny alias Gradle albo współrzędną Maven.
# Wersje JDK i wrappera mają osobny proces migracji, a jOOQ i Lombok odczytujemy z BOM-u Boota.
referenced = {
    entry["version"]["ref"]
    for section in ("libraries", "plugins")
    for entry in catalog[section].values() if "version" in entry
}
manager = next(m for m in config["customManagers"] if m.get("datasourceTemplate") == "maven")
pattern = re.compile(manager["matchStrings"][0].replace("(?<", "(?P<"))
managed = {}
for hit in pattern.finditer(content):
    key = re.search(r'^([A-Za-z][A-Za-z0-9]*) *= *"', hit[0], re.MULTILINE)[1]
    assert key not in managed and hit["currentValue"] == catalog["versions"][key], key
    managed[key] = hit["depName"]
assert set(managed) == catalog["versions"].keys() - referenced - {"java", "gradle", "lombok"}, managed
assert managed["tomcat"] == "org.apache.tomcat.embed:tomcat-embed-core"
assert managed["jackson2Bom"] == managed["jackson2Tooling"] == "com.fasterxml.jackson:jackson-bom"
assert managed["jacksonBom"] == "tools.jackson:jackson-bom"

# Ignorowana w repozytoriach konsumentów paczka musi zostać włączona przed odczytem wersji z npm.
# Na tym etapie Renovate nie zna jeszcze typu aktualizacji (major/minor/patch).
for path, manager_name in (("frontend/packages/eslint-config/package.json", "npm"),
                           ("frontend/packages/versions/versions.json", "custom.regex")):
    assert any(
        r.get("enabled") is True and "matchUpdateTypes" not in r and manager_name in r.get("matchManagers", [])
        and any(fnmatch.fnmatchcase(path, pattern) for pattern in r.get("matchFileNames", []))
        for r in config["packageRules"]
    ), f"the {manager_name} lookup must run for {path} before Renovate determines the update type"

def allowed(key, candidate):
    current = catalog["versions"][key]
    major, minor, _ = current.split(".", 2)
    rules = [r for r in config["packageRules"] if managed[key] in r.get("matchPackageNames", []) and "allowedVersions" in r]
    expression = rules[-1]["allowedVersions"].replace("{{major}}", major).replace("{{minor}}", minor)
    return bool(re.search(expression.strip("/"), candidate))

for key in ("tomcat", "jacksonBom", "jackson2Bom", "jackson2Tooling", "guava", "postgresqlJdbc", "openTelemetry", "logback"):
    major, minor, _ = catalog["versions"][key].split(".", 2)
    suffix = "-jre" if key == "guava" else ""
    assert allowed(key, f"{major}.{minor}.999{suffix}")
    assert not allowed(key, f"{major}.{int(minor) + 1}.0{suffix}")
    assert not allowed(key, f"{major}.{minor}.999-rc1")
    assert not allowed(key, f"{major}.{minor}.999-android")
    if key == "guava":
        assert not allowed(key, f"{major}.{minor}.999")

plugin_id = catalog["plugins"]["jooq-codegen"]["id"]
for dependency in (plugin_id, "org.projectlombok:lombok"):
    assert any(r.get("enabled") is False and dependency in r.get("matchDepNames", []) for r in config["packageRules"]), \
        f"{dependency} must follow the version managed by Spring Boot"
print("OK: daily discovery covers the canonical JVM dependencies and keeps overrides on their stable patch lines")
PY
