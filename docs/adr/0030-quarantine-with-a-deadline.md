# ADR-0030: Flaky tests: quarantine with a deadline, and retries that keep the build red

## Status

Accepted — 2026-10-19

## Context

Flaky tests either blocked CI or were disabled and forgotten.

## Decision

- `@Tag("quarantine")` moves a test to `quarantineTest`, outside `check`, with `ignoreFailures`; each needs
  `// quarantine: <issue-url> until <date>` above the tag (PLAT-QUA-001), and an expired date fails on CI only
  (PLAT-QUA-002, N-REL-13).
- `backend-ci.yml` retries a failed test once with `org.gradle.test-retry` and `failOnPassedAfterRetry`: the build
  stays red, and the job summary separates flaky from broken tests.

## Consequences

- A quarantine cannot outlive its issue unnoticed, and a retry never hides a failure.

## Revisit when

None.
