#!/usr/bin/env python3
"""docs-versions.py [--repo <dir>] [--unreleased <ref>] <out-dir>: the whole versioned documentation site (N-SHOW-16).

Builds one version per released MINOR line at /<X.Y>/, from the newest patch tag vX.Y.Z of that line that carries
the docs tooling (zensical.toml and scripts/docs-site.py, so 1.6.0 and later), and the unreleased channel at
/unreleased/ from <ref> (default: main). Each version is staged by the scripts/docs-site.py of its own ref and built
with `zensical build --strict`, its site_url pointing at its own subpath. The root gets versions.json in the format
of mike, which the version selector of the theme reads (extra.version.provider = "mike"), and an index.html that
redirects to the newest released MINOR, or to unreleased while no release carries the tooling.
"""
import argparse
import html
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import tomllib

TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
TOOLING = ("zensical.toml", "scripts/docs-site.py")
UNRELEASED = "unreleased"
UNRELEASED_TITLE = "unreleased (main)"
SITE_URL = re.compile(r'^site_url[ \t]*=[ \t]*"[^"\n]*"[ \t]*$', re.MULTILINE)
REDIRECT = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Redirecting to the documentation</title>
<link rel="canonical" href="{canonical}">
<meta http-equiv="refresh" content="0; url={target}">
<script>location.replace({target_js} + location.hash)</script>
</head>
<body>
<p>Redirecting to <a href="{target}">the {title} documentation</a>.</p>
</body>
</html>
"""


def fail(message):
    sys.exit(f"docs-versions: {message}")


def run(command, failure, **options):
    if subprocess.run(command, **options).returncode != 0:
        fail(failure)


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True).stdout


def has_tooling(repo, ref):
    return all(
        subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{ref}:{path}"], capture_output=True).returncode == 0
        for path in TOOLING
    )


def released_lines(repo):
    """[(X.Y, tag)] od najnowszej linii MINOR: dla każdej najnowszy patch, który ma już narzędzie strony."""
    lines = {}
    for tag in git(repo, "tag", "--list", "v*").decode().split():
        match = TAG.match(tag)
        if match:
            major, minor, patch = (int(part) for part in match.groups())
            lines.setdefault((major, minor), []).append((patch, tag))
    chosen = []
    for (major, minor), patches in sorted(lines.items(), reverse=True):
        # Tagi sprzed 1.6.0 nie mają zensical.toml ani docs-site.py, więc ich linia po prostu nie powstaje.
        tag = next((tag for _, tag in sorted(patches, reverse=True) if has_tooling(repo, f"refs/tags/{tag}")), None)
        if tag:
            chosen.append((f"{major}.{minor}", tag))
    return chosen


def site_url_of(repo, ref):
    config = tomllib.loads(git(repo, "show", f"{ref}:zensical.toml").decode())
    url = config.get("project", {}).get("site_url")
    if not url:
        fail(f"zensical.toml at {ref} has no project.site_url to build the versions under.")
    return url if url.endswith("/") else url + "/"


def configure(path, site_url, label):
    """site_url wersji na jej podścieżkę i przełącznik wersji motywu (mike), dopisany, gdy wydanie go nie ma."""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    text, count = SITE_URL.subn(lambda _: f'site_url = "{site_url}"', text)
    if count != 1:
        fail(f"zensical.toml of {label} must hold exactly one site_url line, found {count}.")
    version = tomllib.loads(text)["project"].get("extra", {}).get("version")
    if version is None:
        text += '\n[project.extra.version]\nprovider = "mike"\n'
    elif version.get("provider") != "mike":
        fail(f'zensical.toml of {label} sets extra.version without provider = "mike", which versions.json needs.')
    project = tomllib.loads(text)["project"]
    if project["site_url"] != site_url or project["extra"]["version"]["provider"] != "mike":
        fail(f"could not set site_url and the version selector in zensical.toml of {label}.")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    return project.get("site_dir", "site")


def build(repo, ref, link_ref, name, site_url, work, zensical):
    """Jedna wersja: drzewo refu z git archive, jego własny docs-site.py, build strict; zwraca katalog strony."""
    tree = os.path.join(work, "tree", name)
    stage = os.path.join(work, "stage", name)
    os.makedirs(tree)
    with tarfile.open(fileobj=io.BytesIO(git(repo, "archive", "--format=tar", ref))) as archive:
        archive.extractall(tree, filter="data")
    run([sys.executable, "-I", os.path.join(tree, "scripts", "docs-site.py"), link_ref, stage],
        f"scripts/docs-site.py of {link_ref} failed to stage /{name}/.")
    site_dir = configure(os.path.join(stage, "zensical.toml"), site_url, link_ref)
    run([zensical, "build", "--strict"],
        f"the strict build of /{name}/ from {link_ref} failed; the output above names the page.", cwd=stage)
    built = os.path.join(stage, site_dir)
    if not os.path.isfile(os.path.join(built, "index.html")):
        fail(f"zensical built no index.html for {name} from {link_ref}.")
    return built


def main():
    root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("out", help="a new or empty directory for the assembled site")
    parser.add_argument("--repo", default=root, help="the git repository whose tags and refs are built")
    parser.add_argument("--unreleased", default="main", help="the ref built as the unreleased channel")
    args = parser.parse_args()
    repo, out = os.path.abspath(args.repo), os.path.abspath(args.out)
    if os.path.exists(out) and (not os.path.isdir(out) or os.listdir(out)):
        fail(f"{out} exists and is not an empty directory.")
    zensical = shutil.which("zensical")
    if not zensical:
        fail("zensical is not on PATH; install docs/requirements-site.txt with pip --require-hashes.")
    try:
        unreleased = git(repo, "rev-parse", "--verify", f"{args.unreleased}^{{commit}}").decode().strip()
    except subprocess.CalledProcessError:
        fail(f"{args.unreleased} is not a commit of {repo}.")
    if not has_tooling(repo, unreleased):
        fail(f"{args.unreleased} has no {' and no '.join(TOOLING)} to build the unreleased channel from.")

    base = site_url_of(repo, unreleased)
    releases = released_lines(repo)
    # Kanał unreleased linkuje do GitHuba po SHA (jak dotychczasowy deploy z main), wydanie po swoim tagu.
    versions = [(UNRELEASED, unreleased, unreleased, UNRELEASED_TITLE)]
    versions += [(name, f"refs/tags/{tag}", tag, f"{name} (latest)" if not index else name)
                 for index, (name, tag) in enumerate(releases)]
    default = releases[0][0] if releases else UNRELEASED

    with tempfile.TemporaryDirectory() as work:
        site = os.path.join(work, "site")
        os.makedirs(site)
        for name, ref, link_ref, _ in versions:
            print(f"Building /{name}/ from {link_ref}", flush=True)
            shutil.move(build(repo, ref, link_ref, name, f"{base}{name}/", work, zensical), os.path.join(site, name))
        entries = [{"version": name, "title": title, "aliases": []} for name, _, _, title in versions]
        with open(os.path.join(site, "versions.json"), "w", encoding="utf-8") as handle:
            json.dump(entries, handle, indent=2)
            handle.write("\n")
        target = f"{default}/"
        title = next(title for name, _, _, title in versions if name == default)
        with open(os.path.join(site, "index.html"), "w", encoding="utf-8") as handle:
            handle.write(REDIRECT.format(canonical=html.escape(base + target), target=html.escape(target),
                                         target_js=html.escape(json.dumps(target), quote=False),
                                         title=html.escape(title)))
        # Wynik trafia do <out> dopiero po zbudowaniu wszystkich wersji: nieudany build nie zostawia połowy strony.
        if os.path.isdir(out):
            os.rmdir(out)
        shutil.move(site, out)
    print(f"Docs site in {out}: {', '.join(name for name, *_ in versions)}; / redirects to /{default}/")


if __name__ == "__main__":
    main()
