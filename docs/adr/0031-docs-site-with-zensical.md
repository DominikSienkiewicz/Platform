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

Zensical reaches 1.0, or versioned docs per MINOR become necessary.
