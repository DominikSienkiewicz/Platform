# ADR-0029: Support window: the latest MINOR, at most 3 releases or 60 days behind

## Status

Accepted — 2026-10-19

## Context

Fixes go forward only, but nothing said how far behind a consumer may stay, and an old pin gave no signal.

## Decision

- Only the latest MINOR receives fixes; a pin stays at most 3 releases or 60 days behind, whichever comes first;
  a release that fixes a vulnerability is adopted within 14 days (N-REL-6, `RELEASING.md`).
- The settings plugin and `platform-versions-check` print one line for a release older than 60 days, from the
  commit date of its tag; the notice never fails a build.

## Consequences

- Consumers see the lag without a network call.

## Revisit when

The release cadence changes enough to make 60 days wrong.
