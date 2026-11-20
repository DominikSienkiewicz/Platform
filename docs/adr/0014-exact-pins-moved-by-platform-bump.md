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
  versions, and `uses: …@vX.Y.Z` for the reusable workflows (Decision 3). The moving `v1` tag was retired once
  every consumer pinned an exact tag (Update, 2026-11-20).
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

## Revisit when

Nothing: the condition was met and `v1`, `move-v1` and the `v1-pointer` ruleset are retired (see Update).

## Update — `v1` retired (2026-11-20)

Every consumer (Azimuth, Touchstone, Training) pinned `@v1.12.0`, so `move-v1` left `release.yml` and
`.github/rulesets/v1-pointer.json` left the repository. The `v1` tag is no longer moved; the maintainer deletes
the remote tag and the ruleset after the release. An external caller of `@v1` must pin an exact `vX.Y.Z`
(`platform-bump` rewrites it).
