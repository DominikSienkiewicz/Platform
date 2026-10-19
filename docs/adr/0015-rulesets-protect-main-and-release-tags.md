# ADR-0015: Rulesets protect main and the release tags without a required pull request

## Status

Accepted — 2026-10-19

## Context

A single maintainer integrates through `merge.sh`, so a required pull request would only add ceremony. What must
not happen is a deleted or force-pushed `main`, or a moved release tag: consumers pin tags, and GitHub Packages
keeps the artifact of the original tag.

## Decision

Rulesets in `.github/rulesets/`, applied by `scripts/repo-settings.sh --apply` (Decision 9): `main` cannot be
deleted or force-pushed, release tags `v*.*.*` cannot be moved or deleted, and `v1` cannot be deleted. No pull
request and no review are required.

## Consequences

- A bad release is fixed forward with a new tag and the yank list, never by moving the tag.
- `scripts/repo-settings.sh --check` reports drift between the files and GitHub; only the owner applies them.

## Revisit when

A second maintainer joins: then a required review on `main` becomes worth its cost.
