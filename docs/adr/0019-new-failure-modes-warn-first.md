# ADR-0019: A new failure mode warns first and fails in a later MINOR

## Status

Accepted — 2026-10-19

## Context

Every gate Platform adds fails builds that passed the day before. Consumers bump on their own schedule, so a
gate that fails at once turns a routine bump into an unplanned fix.

## Decision

- A new failure mode ships as a warning in one MINOR and becomes a failure no earlier than the next, with both
  steps in the CHANGELOG: the container guard of the test fixtures (Decision 33) and the deprecation channel
  (`PLAT-DEPR-001`, `-Pplatform.deprecations.mode=fail` to opt in early) follow this.
- A check that depends on the date never fails an old commit locally: an expired quarantine fails only on CI
  ([ADR-0030](0030-quarantine-with-a-deadline.md)), and the support window only prints a notice
  ([ADR-0029](0029-support-window.md)).

## Consequences

- A consumer always gets one release of notice, and old commits stay buildable.
- Platform's own TestKit runs every warning as a failure, so the conventions never trigger their own warnings.

## Revisit when

None: this is how Platform introduces gates.
