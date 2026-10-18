# ADR-0005: SpotBugs stays report-only until a measurable exit criterion is met

## Status

Accepted — 2026-10-18

## Context

`seniordev.quality-conventions` runs SpotBugs with `ignoreFailures = true`. The reason was that
static analysers lagged behind new bytecode: with each toolchain move a SpotBugs release could
fail to read the class files, and a failing analyser in `check` would block every consumer at
once. The original condition ("until JDK 25 bytecode support is green") could not be measured
and went stale when the toolchain moved to JDK 27.

Since 2026-10-18 the TestKit consumer build in `build-logic` runs `spotbugsMain` and
`spotbugsTest` on the toolchain's class files (class-file 71) in both templates, and fails on
"Unsupported class file major version". SpotBugs 4.10.3 passes it.

## Decision

SpotBugs stays report-only until both criteria hold:

1. **Bytecode.** The TestKit consumer build runs SpotBugs on the toolchain's class files
   without "Unsupported class file major version". `PlatformConsumerFunctionalTest` measures
   this on every Platform build. Met on 2026-10-18 for JDK 27.
2. **Findings.** Every consumer's `spotbugsMain` passes with `ignoreFailures = false`, after its
   real findings are fixed or excluded in the shared `spotbugs-exclude.xml` with a reason.

When both hold, the default switches to failing in a MINOR release with a consumer action
entry, per [ADR-0002](0002-release-and-versioning-contract.md). A consumer may opt in earlier
with `spotbugs { ignoreFailures.set(false) }`.

## Consequences

- (+) The exit is measurable, and its first half is checked automatically.
- (+) A future toolchain move that breaks SpotBugs shows up in Platform's build, before any
  consumer bumps.
- (−) Until criterion 2 holds, SpotBugs findings are advisory and can accumulate.

## Revisit when

- Criterion 2 has been measured in every consumer.
- The toolchain moves again: criterion 1 must hold for the new class-file version before the
  release.
