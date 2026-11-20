# ADR-0024: The roadmap toolkit is experimental; only its marker contract is stable

## Status

Superseded — 2026-11-20: Platform no longer ships the roadmap toolkit. Platform 1.13.0 removes `templates/roadmap/`
and the reusable `roadmap-unblock.yml`, because no consumer copies the toolkit or calls the workflow. Accepted
2026-10-19.

## Context

`templates/roadmap/` turns a roadmap Markdown file into GitHub Issues and a Projects v2 board. It is useful to the
product repositories but younger than the rest of Platform, and its GitHub API usage changes with GitHub.

## Decision

- The toolkit is part of Platform and marked *experimental*; only the marker contract of the roadmap file is
  stable (Decision 11).
- After an automatic unblock, the status belongs to the automation and the board; `--force-status` projects the
  roadmap again (Decision 12).
- Auto-unblock takes a classic token with `project` and `repo`, passed explicitly and valid for 90 days at most
  (Decision 13).

## Consequences

- Consumers may rely on the markers, not on the scripts' flags or output.

## Revisit when

Two consumers have run it for a release cycle without changes to its interface.
