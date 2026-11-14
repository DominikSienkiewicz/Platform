"""Remove frontend overrides of packages the target canon no longer lists.

The walk matches platform-bump's: "." names the parent package, a "$name" value is an npm reference and stays,
and @dominiksienkiewicz/* pins stay. Emptied override objects are removed with their entries.
Usage: stale_overrides.py detect|apply <versions.json>. Exit status of detect: 0 fix needed, 1 nothing.
"""
import json
import sys

PACKAGE = "frontend/package.json"


def prune(node, parent, canon, removed, path):
    for key, value in list(node.items()):
        name = parent if key == "." else key
        at = path if key == "." else f"{path}.{key}"
        if isinstance(value, dict):
            prune(value, name, canon, removed, at)
            if not value:
                del node[key]
        elif (isinstance(value, str) and name and not value.startswith("$")
              and not name.startswith("@dominiksienkiewicz/") and name not in canon):
            removed.append(f"{at}: {value}")
            del node[key]


def main():
    mode, canon_path = sys.argv[1], sys.argv[2]
    canon = json.load(open(canon_path))["versions"]
    manifest = json.load(open(PACKAGE))
    removed = []
    prune(manifest.get("overrides", {}), None, canon, removed, "overrides")
    if mode == "detect":
        sys.exit(0 if removed else 1)
    if "overrides" in manifest and not manifest["overrides"]:
        del manifest["overrides"]
    with open(PACKAGE, "w") as out:
        json.dump(manifest, out, indent=2, ensure_ascii=False)
        out.write("\n")
    for entry in removed:
        print(f"           removed {entry}")


main()
