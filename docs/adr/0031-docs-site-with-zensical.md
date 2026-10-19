# ADR-0031: A documentation site built with Zensical, deployed when the owner enables Pages

## Status

Accepted — 2026-10-19

## Context

The docs live in the repository and render on GitHub, but a showcase without a site is harder to read, and the
docs on `main` run ahead of the releases consumers pin. The owner chose Zensical as the generator (2026-10-19).

## Decision

- `zensical.toml` builds the site from `docs/`; `scripts/docs-site.py` points every link that leaves `docs/` at
  GitHub at the built ref, and `docs-site.yml` builds in strict mode, so a broken link or anchor fails (N-SHOW-16).
- Zensical and its dependencies are pinned with hashes in `docs/requirements-site.txt`.
- The deploy to GitHub Pages runs from `main` only after the owner enables Pages and sets `PAGES_ENABLED=true`.

## Consequences

- The repository stays the source of truth; the site is a rendering of it.

## Revisit when

Zensical reaches 1.0 and ships native versioning, which would replace the generated `versions.json`.

## Amended (2026-10-20)

The owner asked for versioned docs (N-SHOW-16), which the revisit condition above had deferred. Consumers pin a
release, while the site showed `main`, which runs ahead of every pin; a reader on 1.6 needs the 1.6 pages.

- **One version per released MINOR line, plus `unreleased (main)`.** `/<X.Y>/` holds the docs of the newest patch tag
  `vX.Y.Z` of that line that carries the site tooling (`zensical.toml` and `scripts/docs-site.py`, so 1.6.0 and
  later; older tags have no version), and `/unreleased/` the docs of `main`. The root redirects to the newest
  released MINOR, or to `unreleased` while no release carries the tooling. A later patch of a line replaces its
  version, because the newest patch is what consumers should pin.
- **Every run assembles every version.** `actions/deploy-pages` replaces the whole site, so
  `scripts/docs-versions.py` rebuilds all of them: each version from its own tag's tree with that tag's
  `docs-site.py`, in strict mode, with `site_url` at its own subpath. That keeps the call
  `docs-site.py <ref> <out-dir>` a contract between releases. A version that fails stops the deploy, and the
  previous site stays live.
- **The version selector is the theme's own.** Zensical keeps Material for MkDocs' selector: with
  `extra.version.provider = "mike"` it reads `versions.json` from the site root. Its versioning support is a
  transitional fork of the `mike` tool ([Zensical's mike page](https://zensical.org/docs/compatibility/mkdocs/mike/))
  that deploys to a `gh-pages` branch, which this Pages deploy from Actions does not use. The assembly writes
  `versions.json` in mike's format itself, so no further tool is installed.
- **Triggers.** A pull request still builds only its own commit in strict mode. A push to `main` and every release tag
  `vX.Y.Z` rebuild the assembled site, and deploy it once the owner has set `PAGES_ENABLED=true` and allowed the
  release tags to deploy to the `github-pages` environment.

Every version is built with the Zensical that the running commit pins, not the one of its tag. A Zensical bump that
fails an older version's strict build blocks the deploy until the bump is reverted or the assembly learns to build
that version with its own pin.
