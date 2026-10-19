# ADR-0014: Consumers pin exact releases, and platform-bump moves every pin

## Status

Accepted — 2026-10-19

## Context

Consumers referenced Platform in four places with three forms: the settings plugin and the catalog by version,
the npm packages by version, and the reusable workflows by the moving `@v1`. A moving tag made a consumer's CI
change without a commit in the consumer, and `@v1` had already shipped a permission change that broke a caller
(v1.5.31). Bumps were done by hand or by Renovate rules that each repository configured differently.

## Decision

- Every reference is an exact release: `platformVersion` for the Gradle side, exact `@dominiksienkiewicz/*`
  versions, and `uses: …@vX.Y.Z` for the reusable workflows (Decision 3). The moving `v1` keeps moving only until
  the consumers have migrated.
- One channel moves them: `platform-bump`, run through `scripts/platform-bump.sh` or the reusable
  `platform-bump.yml` (Decision 5). The Renovate preset covers only GitHub Actions and Docker images.
- The bump runs the logic of the release it goes to: a copy that is not the target hands over to the target's bin
  from the release assets, checked against `SHA256SUMS` and the attestation (N-DX-4), and `--report` names what
  the crossed releases change for the repository (N-REL-8).
- Copied templates that drift are reported, never rewritten (Decision 27): `platform-templates-check` exits 0.

## Consequences

- A consumer's build changes only in a commit of that consumer, and the bump pull request shows every pin and
  lockfile that moves.
- A workflow change that needs new permissions reaches a caller only with its bump, where the contract snapshot
  and the report name it.
- `move-v1` retires once `scripts/consumer-audit.sh --adoption` shows no `@v1` left.

## Revisit when

Every consumer calls the workflows at an exact tag: then `v1` and `move-v1` go.
