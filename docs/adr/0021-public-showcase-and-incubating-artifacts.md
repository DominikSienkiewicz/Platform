# ADR-0021: A public showcase, with artifacts incubating until a consumer adopts them

## Status

Accepted — 2026-10-19

## Context

Platform publishes more than its consumers use: starters, private npm packages, catalog bundles, a ui registry.
An artifact nobody uses has no proof that its contract fits, and a public repository invites readers to rely on
what it shows.

## Decision

- The repository is public and run as a showcase (Decision 1).
- An artifact without a consumer is *incubating*, or private for npm, until a first consumer adopts it; that
  pull request removes the label (Decision 7, `docs/runbooks/promote-incubating-artifact.md`).
- Packages stay on GitHub Packages, which needs a classic token even for public packages (Decision 29); the GitHub
  Release assets give the credential-free path.

## Consequences

- The README and the reference say which artifacts are proven by a consumer.
- Readers need a token to resolve Platform, which `docs/consuming.md` states up front.

## Revisit when

GitHub Packages allows anonymous reads, or Platform moves to Maven Central and npmjs.
