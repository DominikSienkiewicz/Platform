# ADR-0001: Platform as the single source of shared artifacts, and the latest-in-portfolio rule

## Status

Accepted — 2026-07-05

## Context

Several product repositories consume this platform, which already publishes Gradle
convention plugins (`seniordev.*`), a version catalog (`pl.seniordeveloper:platform-catalog`),
test fixtures (`platform-test-fixtures`) and frontend npm packages (`@dominiksienkiewicz/*`).

An audit in July 2026 found that a number of elements were still being copied between
repositories rather than consumed, and that the copies had drifted. The same tool appeared
at up to four different versions across the portfolio at once — the platform pin, the
Gradle wrapper, the Sonar plugin and the frontend Node base image each had two or more
live variants, and in one case the platform itself trailed its own consumers.

Scripts had drifted the same way: consumers kept forked copies of automation the platform
already ships as a reusable workflow, and one repository had hand-rebuilt a test container
that the published test fixtures provide — pinning an older database image in the process.

Version drift between repositories is **cost without benefit**: a divergent dependency
graph, builds that cannot be reproduced, and the entire "works on my machine" class of
failure.

## Decision

1. **Anything duplicated across two or more repositories is moved into the platform and
   consumed** — as a catalog entry, convention plugin, test fixture, npm package or
   template — never copied. A fork of a script or config the platform already provides is
   debt to be removed.
2. **Latest-in-portfolio rule.** When the same tool or library exists at different versions
   across repositories, the newest one wins. It lands in the platform as the single source
   and every repository consumes it through the platform pin. Exceptions must be
   **documented** — for example, `build-logic` and Gradle stay on JDK 25 while consumers
   compile for JDK 27; see [ADR-0004](0004-consumer-toolchain-jdk-27.md).
3. **Version changes flow through a platform release plus a bump in the consumer**, never
   through a manual per-repository edit. A new library means a catalog entry and a release
   first, and only then a bump downstream.

## Consequences

- (+) One dependency graph, reproducible builds, and a smaller forked surface.
- (+) Governance is enforced by tooling rather than convention: `platformDependencyCheck`
  (Gradle) and `platform-versions-check` (npm) fail the build on a version outside the
  canonical set.
- (−) Changing a version costs a release-and-bump cycle. This is a deliberate trade for
  consistency.
- (−) A consumer's pin can sit briefly behind the platform's published HEAD. That is the
  normal flow, closed by the bump script (see the amendment below).

## What this decision does not cover

Two categories were deliberately excluded when the rule was adopted, and the reasoning is
worth keeping: a shared preset is **not** adopted where it is not drop-in compatible with a
consumer's existing design tokens, and a dependency is **not** bumped from a milestone to a
GA release blindly, because the API can change across that boundary. In both cases the
platform side is harmonised first, and the consumer migrates afterwards.

## Delivered with this decision (2026-07-05)

Version-catalog bundles for the dependency spine repeated across consumers; Sonar moved
into `seniordev.quality-conventions` so consumers stop declaring it inline; and shared
`@dominiksienkiewicz/api-client` and `@dominiksienkiewicz/query` packages to replace the
per-repository fetch wrappers and query clients that had drifted apart.

## Incubating artifacts (2026-10-18)

The consolidation this decision delivered stopped at the platform side: no consumer uses the catalog
bundles, the security starter, `api-client` or `query`. The consumer migration is deferred, not
forced: these artifacts stay *incubating*, still published, until a first consumer adopts one, and
that adoption pull request removes the label in README.md. `api-client` and `query` are additionally
marked private, so they are not published until then. `docs/consuming.md` shows the adoption path.

## Amended (2026-10-18)

Renovate never opened a pull request in Platform or in a consumer, and its pin manager could not have
produced a green one: it rewrote only `settings.gradle.kts`, not the lockfiles, the verification
metadata or the frontend canon. Pin lag is therefore closed by `platform-bump`, run by hand or on a
schedule through the reusable `platform-bump.yml`, which opens the bump pull request. The shared
Renovate preset now covers GitHub Actions and Docker images only; Platform's own `renovate.json`
manages its catalog and frontend canon ([ADR-0002](0002-release-and-versioning-contract.md), item 6).
