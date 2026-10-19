# ADR-0008: Overrides above the Boot BOM and npm overrides are a last resort, each with a removal condition

## Status

Accepted — 2026-10-19

## Context

Platform imports the Spring Boot, Spring Modulith and Spring AI BOMs and lets them choose the version
of every library they manage. Twice the BOM chose a version Platform could not ship:

- for compatibility: Boot 4.1.1 pins Lombok 1.18.46, which fails on javac 27, and
  `spring-modulith-core` 2.1.1 pulls ArchUnit 1.4.2, which cannot read Java 27 class files;
- for security: Boot 4.1.1, the newest Boot, manages Tomcat 11.0.24 and Jackson 3.1.5 and 2.21.5,
  each with HIGH or CRITICAL advisories fixed in a later patch of the same line.

The frontend has the same pressure from transitive npm packages. An override fixes the version
today and then outlives its reason: the CVE pins of Netty and PostgreSQL would have forced versions
older than the BOM once Boot moved past them, and the `postcss` and `sharp` npm pins lived in four
consumers for a release longer than they were needed. The rationale was spread over
`docs/versions.md`, comments in `seniordev.spring-modulith-conventions` and CLAUDE.md, in two
languages.

## Decision

- **An override is a last resort.** Platform overrides a BOM version only when the BOM's version
  breaks the toolchain or carries a HIGH or CRITICAL advisory with a fix, and no newer release of the
  BOM's owner manages a good version. A newer Boot, Modulith or Spring AI release is always preferred
  to an override.
- **The smallest step.** An override takes the newest patch of the line the BOM manages, never a newer
  minor, so the BOM's compatibility testing still applies.
- **Every override carries its removal condition** next to it in the source, as `USUŃ, gdy …` (remove
  when …), and in the table of `docs/versions.md`. The release that meets the condition removes the
  override; `canon-cve-scan.yml` shows whether a BOM release is clean.
- **Overrides live in Platform only.** Consumers do not set BOM version properties: they reach every
  consumer, and nothing else sees them. `platformBomOverrideCheck` warns about a property a consumer
  sets, and `platform-bump` lists `useVersion`, `force`, `strictly` and `extra["….version"]`
  overrides after every bump (Decision 18).
- **Each override has one source.** The version stands in the catalog, and the convention reads it
  from the `PlatformVersions` that `build-logic` generates from the catalog; `PlatformVersionsTest` fails
  on a literal in the convention source. (Until 1.6.0 the version was mirrored in the source and two
  mirror tests compared the copies.)
- **npm follows the same rule.** The default fix for a vulnerable transitive package is
  `npm update <package> --package-lock-only` and a committed lockfile. An entry in `overrides` is
  only for a parent that pins the exact vulnerable version, it is part of the canon, and it is
  removed in every consumer in the release that removes it from the canon, because `platform-bump`
  does not delete an override the canon dropped.

## Consequences

- A reader finds the reason and the exit for every override in one table, and a reviewer can reject
  one without a removal condition.
- An override that outlives its reason still costs a release to remove, but it no longer goes
  unnoticed: the next BOM bump meets the stated condition.
- Consumers lose the option to fix a version locally without a warning. A real local need goes into
  Platform and a release.
