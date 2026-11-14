#!/usr/bin/env python3
"""docs-site.py <ref> <out-dir>: the source of the documentation site, ready for `zensical build --strict` (N-SHOW-16).

Copies docs/ (without the local docs/concepts/) and zensical.toml into <out-dir>. A Markdown link that leaves docs/ (to
RELEASING.md, a template, a workflow) becomes a link to that file on GitHub at <ref>, so the site never links to a
page it does not have, and the strict build checks every link and anchor that stays inside docs/.
"""
import os
import re
import shutil
import sys

# Wywołanie `docs-site.py <ref> <out-dir>` to kontrakt: scripts/docs-versions.py uruchamia kopię tego skryptu z tagu
# każdego wydania od 1.6.0, więc nowa wersja może dokładać zachowanie, ale nie zmieniać argumentów ani układu <out-dir>.
ref, out =sys.argv[1], os.path.abspath(sys.argv[2])
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
docs = os.path.join(root, "docs")
repository = "https://github.com/DominikSienkiewicz/Platform"
LINK = re.compile(r"(\]\()([^)\s]+)(\))")


def rewrite(source, text):
    directory = os.path.dirname(source)

    def replace(match):
        target = match.group(2)
        if re.match(r"^[a-z]+:", target) or target.startswith("#") or target.startswith("/"):
            return match.group(0)
        path, _, anchor = target.partition("#")
        resolved = os.path.normpath(os.path.join(directory, path))
        if resolved == docs or resolved.startswith(docs + os.sep):
            return match.group(0)
        relative = os.path.relpath(resolved, root).replace(os.sep, "/")
        kind = "tree" if os.path.isdir(resolved) else "blob"
        return f"{match.group(1)}{repository}/{kind}/{ref}/{relative}{'#' + anchor if anchor else ''}{match.group(3)}"

    return LINK.sub(replace, text)


shutil.rmtree(out, ignore_errors=True)
for folder, subfolders, files in os.walk(docs):
    subfolders[:] = [name for name in subfolders if os.path.join(folder, name) != os.path.join(docs, "concepts")]
    for name in files:
        source = os.path.join(folder, name)
        target = os.path.join(out, "docs", os.path.relpath(source, docs))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if name.endswith(".md"):
            with open(source, encoding="utf-8") as handle:
                text = rewrite(source, handle.read())
            with open(target, "w", encoding="utf-8") as handle:
                handle.write(text)
        else:
            shutil.copy2(source, target)
shutil.copy2(os.path.join(root, "zensical.toml"), os.path.join(out, "zensical.toml"))
print(f"Site source for {ref} in {out}")
