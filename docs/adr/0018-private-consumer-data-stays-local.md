# ADR-0018: Nothing about the private consumers runs in Platform's public CI

## Status

Accepted — 2026-10-19

## Context

Platform is public (Decision 1), its consumers are private. Adoption reports, canaries and rollouts read the
consumers' code, pins and CI results; in a public workflow their logs would publish that information.

## Decision

- The adoption and lag report runs locally: `scripts/consumer-audit.sh --lag` and `--adoption` (Decision 32).
- The pre-release canary runs locally: `scripts/canary.sh` records the result for `HEAD` under
  `.git/platform-canary/`, and `release.sh` requires it or `--skip-canary "<reason>"` (Decision 35).
- The ring rollout runs locally: `scripts/ring-rollout.sh` bumps Touchstone first and the rest after its pull
  request is green (N-REL-1).

## Consequences

- These steps need the maintainer's machine and token; a release cannot be fully automated.
- Public CI tests the scripts with stubs, never with the consumers.

## Revisit when

The consumers become public, or Platform moves to a private CI runner.
