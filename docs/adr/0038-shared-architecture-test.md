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
- The class has no switch to freeze violations or leave out a single inherited rule. The owner rejected an opt-in
  `FreezingArchRule` switch on 2026-11-20: it would add API that every later release has to keep, and the
  adopting repositories fix what the rules find instead.
- The five package methods are independent. Overriding `adapterPackages()` does not move the defaults of
  `inboundAdapterPackages()` and `outboundAdapterPackages()`, so a consumer with other adapter names overrides
  all three. Because empty layers pass, a pattern that matches nothing passes silently.
- Adoption at the bump to the release that contains this class:
  - Azimuth replaces `HexagonalArchitectureTest` with a subclass on `AzimuthApplication` and fixes the
    violations first. It imports its test classes, like Training, so the field-injection and generic-exception
    rules check them too.
  - Training replaces the body of `ArchitectureTest` with a subclass on `TrainingApplication`.
  - Touchstone adds a subclass in `:app` with `hexagonal()` returning `false` and keeps its classes where they
    are. It analyses the package `pl.seniordeveloper.touchstone` without `DoNotIncludeJars`, because its
    modules reach the `:app` test classpath as jars.

## Consequences

- One class holds the architecture rules of every consumer, and a new rule reaches them all with a bump.
- A consumer cannot leave out a single inherited rule or freeze its violations. Azimuth, Training and Touchstone
  adopt the class as it is. A future consumer that needs a freeze or a partial set composes `PlatformArchRules`
  and `HexagonalRules` in its own test, as the [reference](../reference.md#test-fixtures) shows, until this decision is revisited.
- Azimuth gains rules it did not check before: the `PlatformArchRules` rules and
  `applicationReachesAdaptersThroughPorts`. Its adoption fixes the violations these rules report. Excluding the
  test classes with `ImportOption.DoNotIncludeTests` is not the way out: it also leaves
  `CONTAINER_TESTS_ARE_TAGGED_INTEGRATION` with nothing to check.
- The import options decide what the platform rules see. With the test classes imported, `NO_FIELD_INJECTION` and
  `NO_GENERIC_EXCEPTIONS` also check the tests, and only then does `CONTAINER_TESTS_ARE_TAGGED_INTEGRATION` have
  classes to check.
- The tests of `platform-test-fixtures` run deliberately violating subclasses through the launcher. The
  `test` task excludes those nested classes, because it would otherwise run them directly and fail; a
  consumer-style subclass in another package, `archconsumer.CanonArchitectureTest`, runs in `test` directly.
- `junit-platform-launcher` moves from `testRuntimeOnly` to `testImplementation` in `platform-test-fixtures`;
  no artifact is added.

## Revisit when

A consumer needs to freeze or leave out a single rule of the shared test, or ArchUnit stops running `@ArchTest`
members inherited from a superclass.
