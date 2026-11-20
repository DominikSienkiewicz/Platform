# ADR-0018: Nothing about the private consumers runs in Platform's public CI

## Status

Accepted — 2026-10-19

## Context

Platform is public (Decision 1), its consumers are private. Adoption reports, canaries and rollouts read the
consumers' code, pins and CI results; in a public workflow their logs would publish that information.

## Decision

- The adoption report runs locally: `scripts/consumer-audit.sh` (Decision 32); its `--lag` and `--adoption` modes were
  removed on 2026-11-20.
- The pre-release canary runs locally: `scripts/canary.sh` records the result for `HEAD` under
  `.git/platform-canary/`, and `release.sh` requires it or `--skip-canary "<reason>"` (Decision 35).
- The ring rollout runs locally: `scripts/ring-rollout.sh` bumps Touchstone first and the rest after its pull
  request is green (N-REL-1).

## Consequences

- These steps need the maintainer's machine and token; a release cannot be fully automated.
- Public CI tests the scripts with stubs, never with the consumers.

## Revisit when

The consumers become public, or Platform moves to a private CI runner.

## Update — no canary and no ring rollout (2026-11-20)

`scripts/canary.sh`, `scripts/preview-on-consumer.sh`, `scripts/ring-rollout.sh` and the canary gate of `release.sh`
(with `--skip-canary` and the `Canary-Skipped:` trailer) are removed: a release no longer waits for a local preview on
every consumer, and consumers take a release through their own `platform-bump.yml` caller. The adoption report stays
local as decided above. An unreleased change is still tried on a consumer with `-PplatformRepository`
([test an unreleased change](../runbooks/test-unreleased-change.md)).
