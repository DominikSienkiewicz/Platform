# ADR-0012: Platform's own Java modules are analysed in SonarQube Cloud like a consumer

## Status

Accepted — 2026-10-19

## Context

`seniordev.quality-conventions` configures SonarQube Cloud for every consumer, but Platform's own
published Java modules, `platform-test-fixtures` and `platform-security-starter`, were not analysed. The
code with the widest reach ran under weaker hygiene than the code it checks. Once both modules applied
`seniordev.java-conventions` from `gradle/build-logic` through `includeBuild`, nothing technical stood in
the way of the quality conventions as well.

## Decision

Both modules apply `seniordev.quality-conventions` exactly as a consumer does, with the PIT target set
to their own packages. A `sonar` job in `ci.yml` runs `build sonar` in each module. It skips with a
notice until the `SONAR_TOKEN` secret exists, so the job lands before the projects are set up.

The projects `DominikSienkiewicz_platform-test-fixtures` and `DominikSienkiewicz_platform-security-starter`
in the `dominiksienkiewicz` organisation, with Automatic Analysis off, are created once by hand
([RELEASING.md](../../RELEASING.md), Repository settings).

## Consequences

- Platform dogfoods its quality gate: a change to `quality-conventions` that breaks the Sonar task fails
  Platform's CI before it reaches a consumer.
- The analysis needs one secret and two projects owned outside the repository; without them the job is
  a no-op, not a failure.
- `build-logic` itself (Kotlin) is not analysed; ktlint through Spotless is its hygiene gate.

## Revisit when

`build-logic` grows code that SonarQube Cloud would analyse better than ktlint, or the analysis moves to
the reusable `sonar.yml` that no consumer calls today.

## Update — multi-module consumers (2026-10-19)

A multi-module consumer applies `seniordev.sonar-conventions` in its root project (Decision 24, F-13): one analysis
under one project key, waiting for the JaCoCo report of every module. `seniordev.quality-conventions` applies the
Sonar plugin only in the root project, so a module never runs a partial analysis of its own.

## Update — the job waits for the analysis (2026-10-20)

The scanner only uploads the report; SonarQube Cloud processes it afterwards. The first analyses after the
projects were created landed nowhere: CI analyses `main`, the projects' main branch was still `master`, and no
`main` branch appeared, since the Free plan analyses only the main branch and pull requests of a private project,
yet the `sonar` job stayed green. The job now runs with
`sonar.qualitygate.wait=true`, so a rejected analysis or a red quality gate fails Platform's CI, and the one-time
setup renames each project's main branch to `main`. Consumers keep the scanner's default; the wait is Platform's
own job only.

Waiting surfaced two more setup gaps, now part of the one-time setup in [RELEASING.md](../../RELEASING.md): the
projects are public, because the organisation's Free plan caps private code at 50k lines and Azimuth already fills
it, and each has a New code definition, without which the quality gate is not computed and the scanner reports
`NONE` as failed. The job also analyses every module before it fails, so a red `platform-test-fixtures` no longer
hides the state of `platform-security-starter`.
