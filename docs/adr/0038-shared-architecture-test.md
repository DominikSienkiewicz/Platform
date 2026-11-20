# ADR-0038: One shared architecture test with a hexagonal canon

## Status

Accepted — 2026-11-20.

## Context

Azimuth and Training each keep their own ArchUnit test of the hexagon inside their Spring Modulith modules.
Azimuth's `HexagonalArchitectureTest` imports its classes with a plain `ClassFileImporter` and checks three
rules, including "`adapter.out` does not depend on `adapter.in`". Training's `ArchitectureTest` runs
`PlatformArchRules` and `HexagonalRules.of(...)`. Both use the same package layout, both allow empty layers,
and neither checks what the other checks. Touchstone has flat modules without layers and no architecture test
at all. Copying the test into every repository brings back the drift that Platform exists to remove.

## Decision

- `platform-test-fixtures` ships `pl.seniordeveloper.platform.testing.arch.AbstractArchitectureTest`. A
  consumer subclasses it, names the classes to analyse with `@AnalyzeClasses`, and gets every
  `PlatformArchRules` rule, the three `HexagonalRules.of(...)` rules and the rule that an outbound adapter does
  not depend on an inbound adapter.
- The naming canon is the layout Azimuth and Training already share, as ArchUnit package patterns:

  | Layer | Default pattern | Overridable through |
  | --- | --- | --- |
  | Domain | `..domain..` | `domainPackages()` |
  | Application, with its ports under `application.port..` | `..application..` | `applicationPackages()` |
  | All adapters | `..adapter..` | `adapterPackages()` |
  | Inbound adapters | `..adapter.in..` | `inboundAdapterPackages()` |
  | Outbound adapters | `..adapter.out..` | `outboundAdapterPackages()` |

  The split of the ports into `port.in`, `port.out` and `port.query` is allowed and not checked. CQRS is a
  naming convention only: `port.query` holds the read side, and no rule enforces it.
- The rules, each a separate test in the report:

  | Test | Rule |
  | --- | --- |
  | `PlatformArchRules > …` | every rule of `PlatformArchRules`, one test each |
  | `domainIsFreeOfFrameworks` | the domain depends on no `org.springframework..`, `jakarta.persistence..` or `jakarta.servlet..` class |
  | `domainDependsOnNothingOutsideItself` | the domain depends on neither the application nor an adapter |
  | `applicationReachesAdaptersThroughPorts` | the application depends on no adapter |
  | `outboundAdaptersDoNotDependOnInboundAdapters` | an outbound adapter depends on no inbound adapter |

  The four hexagonal rules allow an empty layer (`allowEmptyShould(true)`), so a module that has no adapters
  yet passes and the rule starts to apply when the first adapter appears.
- The new rule is a separate public method, `HexagonalRules.outboundAdaptersDoNotDependOnInboundAdapters(outbound,
  inbound)`. `HexagonalRules.of(domain, application, adapter)` keeps its three rules, so current callers see no
  change.
- A module without layers opts out of the hexagon by overriding `hexagonal()` to return `false`. The four
  hexagonal tests then end as aborted (shown as skipped), not as passed, so the report says that they did not
  check anything. The `PlatformArchRules` tests still run.
- The rules are `@ArchTest` members of the abstract class, which the ArchUnit JUnit 5 engine runs for the
  subclass. The engine collects `@ArchTest` fields and methods from the whole class hierarchy and creates the
  instance from the annotated subclass, so an overridden package method is what the inherited test reads.
  `AbstractArchitectureTestTest` proves it on ArchUnit 1.5.0: it runs subclasses through the JUnit Platform
  launcher, and the engine reports 11 tests for a subclass that declares none. Inheritance was therefore kept
  over the alternatives, plain JUnit `@Test` methods over a `ClassFileImporter` result or rules that a
  consumer lists itself, which would lose the per-rule report or put the list back into every repository.
- Adoption at the bump to the release that contains this class:
  - Azimuth replaces `HexagonalArchitectureTest` with a subclass on `AzimuthApplication`.
  - Training replaces the body of `ArchitectureTest` with a subclass on `TrainingApplication`.
  - Touchstone adds a subclass in `:app` with `hexagonal()` returning `false` and keeps its classes where they
    are. It analyses the package `pl.seniordeveloper.touchstone` without `DoNotIncludeJars`, because its
    modules reach the `:app` test classpath as jars.

## Consequences

- One class holds the architecture rules of every consumer, and a new rule reaches them all with a bump.
- A consumer cannot leave out a single inherited rule or freeze its violations with `FreezingArchRule`.
  A repository that needs that keeps composing `PlatformArchRules` and `HexagonalRules` itself, as before.
- Azimuth gains rules it did not check before: the `PlatformArchRules` rules and
  `applicationReachesAdaptersThroughPorts`. Its adoption has to fix or exclude what they find first.
- The tests of `platform-test-fixtures` run deliberately violating subclasses through the launcher. The
  `test` task excludes those nested classes, because it would otherwise run them directly and fail.
- `junit-platform-launcher` moves from `testRuntimeOnly` to `testImplementation` in `platform-test-fixtures`;
  no artifact is added.

## Revisit when

A consumer needs to freeze or leave out a single rule of the shared test, or ArchUnit stops running `@ArchTest`
members inherited from a superclass.
