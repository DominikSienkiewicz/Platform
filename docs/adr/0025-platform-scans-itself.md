# ADR-0025: Platform scans itself with the scanners it offers

## Status

Accepted — 2026-10-19

## Context

Platform offers Scorecard, Semgrep and SonarQube Cloud to its consumers; a showcase that does not run them on
itself shows less than it claims.

## Decision

- `self-scan.yml` runs Scorecard with `publish_results: true` (Decision 15) and Semgrep on Platform.
- Semgrep uses the registry rulesets, with the exception procedure of `docs/security-scanning.md` (Decision 26).
- `sonar.yml` has no callers; it is deprecated and kept so existing references resolve (Decision 14).
  Platform's own SonarQube Cloud analysis is [ADR-0012](0012-platform-scans-itself-in-sonarqube-cloud.md).

## Consequences

- The Scorecard badge reflects the repository as it is.

## Revisit when

`sonar.yml` gets a caller, or is removed in a MAJOR.
