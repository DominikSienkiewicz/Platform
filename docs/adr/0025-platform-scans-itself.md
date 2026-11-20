# ADR-0025: Platform scans itself with the scanners it offers

## Status

Accepted — 2026-10-19

Partly superseded (2026-11-20): Platform no longer runs its own SonarQube Cloud analysis
([ADR-0012](0012-platform-scans-itself-in-sonarqube-cloud.md), superseded); `self-scan.yml` still runs Scorecard
and Semgrep on Platform.

## Context

Platform offers Scorecard, Semgrep and SonarQube Cloud to its consumers; a showcase that does not run them on
itself shows less than it claims.

## Decision

- `self-scan.yml` runs Scorecard with `publish_results: true` (Decision 15) and Semgrep on Platform.
- Semgrep uses the registry rulesets, with the exception procedure of `docs/security-scanning.md` (Decision 26).
- The reusable `sonar.yml`, which had no callers, was removed on 2026-11-20 (it was deprecated by Decision 14).
  Platform's own SonarQube Cloud analysis was [ADR-0012](0012-platform-scans-itself-in-sonarqube-cloud.md), removed
  in 1.13.0.

## Consequences

- The Scorecard badge reflects the repository as it is.

## Revisit when

a consumer needs a reusable SonarQube Cloud workflow again.
