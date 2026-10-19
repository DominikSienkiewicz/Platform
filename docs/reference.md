# Conventions reference

What the Platform plugins add to a consumer build, which knobs a consumer can turn, and what the
defaults are. How to wire a repository is in [consuming.md](consuming.md); the reusable workflows
are in [reusable-workflows.md](reusable-workflows.md).

## Properties and environment variables

| Name | Where | Default | Effect | Read in |
|---|---|---|---|---|
| `platformVersion` | `gradle.properties` | — | the Platform release the settings plugin and the catalog resolve | the consumer's `settings.gradle.kts` |
| `platformRepository` | `-P` or `gradle.properties` | unset | puts that Maven repository first for dependencies, and for plugins in a `pluginManagement` that reads it as the templates do; the only way to test an unreleased Platform ([ADR-0003](adr/0003-local-platform-resolution.md)) | [seniordev.settings-conventions](../gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts), the consumer's `pluginManagement` |
| `gpr.user`, `gpr.key` | `~/.gradle/gradle.properties` | unset | GitHub Packages credentials (classic PAT with `read:packages`); an empty or whitespace-only value counts as unset | [seniordev.settings-conventions](../gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts) |
| `GITHUB_ACTOR`, `GITHUB_TOKEN` | environment | unset | fallback credentials for GitHub Packages, used on CI; an empty or whitespace-only value counts as unset | [seniordev.settings-conventions](../gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts) |
| `coverageMinimum` | `gradle.properties` or `-P` | `0.00` | JaCoCo coverage threshold on `check`, a decimal between 0 and 1 | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |
| `sonarProjectKey` | `gradle.properties` | `DominikSienkiewicz_<rootProject.name>` | SonarQube Cloud project key | [seniordev.quality-conventions](../gradle/build-logic/src/main/kotlin/seniordev.quality-conventions.gradle.kts) |
| `platform.javac.werror` | `-P` or `gradle.properties` | `false` | `true` adds `-Werror`: every javac warning fails the compilation, Error Prone's included; a ratchet for a repository that has cleared its warnings | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |
| `platform.deprecations.mode` | `-P` or `gradle.properties` | `warn` | `fail` makes `platformDependencyCheck` fail while a deprecated dependency, property or plugin is in use ([gates](gates.md#plat-depr-001)) | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |
| `AI_AGENT` | environment | unset | `1` or `true` bounds test resources for coding agents (one fork, 2 GiB heap, four cached Spring contexts) and logs one `Platform agent profile:` line per build; see [agent-profile.md](agent-profile.md) | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |
| `platform.agent.testForks`, `platform.agent.testHeap`, `springContextCacheSize` | `-P` or `gradle.properties` | the `AI_AGENT` profile, else Gradle's | `maxParallelForks`, `maxHeapSize` and `spring.test.context.cache.maxSize` of every test task; an explicit value applies with or without `AI_AGENT`; `springContextCacheSize` is an ADR-0007 exception, because Azimuth already sets it ([agent-profile.md](agent-profile.md)) | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |
| `platform.junit.baseline` | `-P` or `gradle.properties` | `true` | `false` stops the conventions from adding the JUnit BOM, Jupiter and the launcher to the tests | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |
| `platform.test.retry`, `PLATFORM_TEST_RETRY` | `-P`, environment | unset (`backend-ci.yml` sets the variable to `detect`) | `detect` applies `org.gradle.test-retry` with one retry and `failOnPassedAfterRetry`: the build stays red, the report shows which tests are flaky; the property wins over the variable, so `-Pplatform.test.retry=off` turns it off | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |
| `CI` | environment | unset | `true` makes `platformQuarantineCheck` fail on an expired quarantine ([gates](gates.md#plat-qua-002)) | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |
| `platform.quarantine.today` | `-P` | today | the date `platformQuarantineCheck` compares with; for Platform's own tests | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |
| `platform.toolchain.override` | `-P` | unset | replaces the Java toolchain of the canon with that version and warns; for the upstream canary and experiments, never for a release | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |
| `platform.staleness.notice` | `-P` or `gradle.properties` | `true` | `false` silences the one-line notice for a Platform release older than the support window ([RELEASING.md](../RELEASING.md#support-policy)) | [seniordev.settings-conventions](../gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts) |
| `platform.staleness.today` | `-P` | today | the date the staleness notice compares with; for Platform's own tests | [seniordev.settings-conventions](../gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts) |

These names are frozen. A new Platform property, task or bin follows the naming rule in
[ADR-0007](adr/0007-public-naming.md): `platform.<area>.<name>` for a Gradle property,
`platform.<area>.*` for a Spring property, `platform<Name>` for a task, `platform-<name>` for a bin.

## seniordev.settings-conventions

Source: [`seniordev.settings-conventions.settings.gradle.kts`](../gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts).

Applied in `settings.gradle.kts` with the Platform version. It applies the Foojay toolchain
resolver and declares the dependency repositories: `platformRepository` when set, then Maven
Central and GitHub Packages with the credentials above. The consumer still declares
`pluginManagement` repositories (to resolve this plugin), the catalog pin and `rootProject.name`.

It also registers `platformDoctor` on the root project: the Gradle-side diagnosis that
`platform-doctor --gradle` runs, compatible with the configuration cache. It prints one line per check
in the bin's format (PD080 pins, PD081 toolchain, PD082 `coverageMinimum`; [consuming.md](consuming.md#troubleshooting))
and fails when one fails.

When its own release is older than 60 days, it logs one line naming the release, its age and
`scripts/platform-bump.sh` ([support policy](../RELEASING.md#support-policy)). The date is that of the tagged
commit, embedded as `platform-release.properties`; the notice never fails a build.

## seniordev.java-conventions

Source: [`seniordev.java-conventions.gradle.kts`](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts); Checkstyle rules in
[`platform-checkstyle/`](../gradle/build-logic/src/main/resources/platform-checkstyle/).

| Task or setting | On `check` | Knob | Default |
|---|---|---|---|
| Java toolchain | — | `platform.toolchain.override` | Java 27 |
| javac warnings | — | `platform.javac.werror` | `-Xlint:all` without `processing` and `serial`, as warnings |
| `spotlessCheck` | yes | none | google-java-format 1.36.1, unused imports removed |
| `checkstyleMain`, `checkstyleTest` | yes | `@SuppressWarnings("checkstyle:<checkname>")` on a declaration, with the check name in lower case | Platform rules, `maxWarnings = 0` |
| `jacocoTestReport`, `jacocoTestCoverageVerification` | yes | `coverageMinimum` | 0.00, coverage of `test` and `integrationTest` together |
| `platformCoverageDataCheck` | yes | `coverageMinimum` | fails when the threshold is above 0 and no test produced JaCoCo data |
| `platformDependencyCheck` | yes | `platform.deprecations.mode` | every explicit dependency version must match the canon embedded in the plugin, the consumer's `libs` catalog must not override it and must exist; a library outside the canon is told apart by whether a Platform BOM manages it. It sees dependencies added in a late `afterEvaluate` too, writes `build/reports/platform/dependency-check.md` (and the job summary in GitHub Actions) and lists deprecated items |
| `platformPinCheck` | yes | none | the settings plugin and `platform-catalog` are the same release; a mismatch also warns at configuration time |
| `platformQuarantineCheck` | yes | `CI`, `platform.quarantine.today` | every test tagged `quarantine` needs `// quarantine: <issue-url> until YYYY-MM-DD` in the three lines above the tag ([PLAT-QUA-001](gates.md#plat-qua-001)); an expired date fails on CI and warns locally ([PLAT-QUA-002](gates.md#plat-qua-002)); writes `build/reports/platform/quarantine.txt` |
| `quarantineTest` | no | `@Tag("quarantine")` | runs only the quarantined tests, with `ignoreFailures`, so they keep reporting; every other test task excludes the tag |
| `lint` | no | a project's own `lint` task wins | `spotlessCheck`, every Checkstyle task, `platformDependencyCheck`, `platformPinCheck` and `platformQuarantineCheck`, without tests |
| `format` | no | a project's own `format` task wins | `spotlessApply` |
| `platformRuntimeImageCheck` | yes | none | the final `FROM` of `Dockerfile` (project or root) must run Java 27 or newer; skipped when there is no Dockerfile or the image is not a JVM image |
| test tasks | — | `AI_AGENT`, `platform.agent.test*`, `springContextCacheSize`, `platform.junit.baseline`, `platform.test.retry` | JUnit Platform with the JUnit BOM, Jupiter and the launcher of the canon; each task passes its name in the system property `platform.test.task` |

Every failure carries a code such as `[PLAT-DEP-001]` and a link to its section of [gates.md](gates.md) in the
docs of that release; the fixes are also in [consuming.md](consuming.md#troubleshooting). The tasks are
compatible with the configuration cache, which Platform's TestKit suite runs with every Gradle deprecation
the conventions cause as a failure (Decision 10); consumers opt in with `org.gradle.configuration-cache=true`.
Every check task declares an output, so an unchanged second build runs none of them again; only
`platformQuarantineCheck` runs every time, because an expiry depends on the day.
Warnings then show when their inputs change, and the reports under `build/reports/platform/` keep them.

## The platform block

`seniordev.java-conventions` and `seniordev.quality-conventions` register one typed extension, `platform`, so the
IDE completes the knobs and a typo fails the build. Every field is optional; an unset field falls back to the
Gradle property in the last column, so `gradle.properties` and `-P` keep working. A field is read when its task is
configured, and setting it afterwards fails instead of being ignored.

```kotlin
platform {
    coverage { minimum.set("0.80".toBigDecimal()) }
    sonar { projectKey.set("DominikSienkiewicz_Orders") }
    mutation { targetPackages.add("pl.example.orders") }
    staticAnalysis { failOnBugs.set(true) }
}
```

| Field | Effect | Unset |
|---|---|---|
| `coverage.minimum` | threshold of `jacocoTestCoverageVerification`, a decimal between 0 and 1 ([PLAT-COV-002](gates.md#plat-cov-002) otherwise) | `coverageMinimum`, then 0.00 |
| `sonar.projectKey` | the SonarQube Cloud project key of the analysis | `sonarProjectKey`, then `DominikSienkiewicz_<rootProject.name>` |
| `mutation.targetPackages` | the packages PIT mutates, each with its subpackages | PIT's default, `<group>.*` |
| `staticAnalysis.failOnBugs` | `true` makes SpotBugs findings fail the build | `false`, report-only ([ADR-0005](adr/0005-spotbugs-report-only.md)) |

## seniordev.quality-conventions

Source: [`seniordev.quality-conventions.gradle.kts`](../gradle/build-logic/src/main/kotlin/seniordev.quality-conventions.gradle.kts).

| Task or setting | On `check` | Knob | Default |
|---|---|---|---|
| `pitest` | no | `platform { mutation { targetPackages } }`, or `pitest { targetClasses.set(listOf("com.example.*")) }` | the plugin's default, the project's `group` followed by `.*`; PIT 1.30.0, JUnit 5 plugin 1.2.3 |
| `spotbugsMain`, `spotbugsTest` | yes, report-only | `platform { staticAnalysis { failOnBugs.set(true) } }`, or `spotbugs { ignoreFailures.set(false) }` | findings are reported, not failed ([ADR-0005](adr/0005-spotbugs-report-only.md)) |
| `cyclonedxBom` | no | none | an SBOM of `runtimeClasspath` only, the input of `security-scan.yml` |
| `sonar` | no | `platform { sonar { projectKey } }`, `sonarProjectKey` | organisation `dominiksienkiewicz`, coverage from `jacocoTestReport`; only in the root project |

SonarQube Cloud analyses a build once, from its root. In a single-module build the root applies this plugin, so
it also applies `org.sonarqube`. In a multi-module build a module that applies this plugin adds its own JaCoCo
report to the analysis of the root, which applies `seniordev.sonar-conventions`; without that, no module has a
`sonar` task.

## seniordev.sonar-conventions

Source: [`seniordev.sonar-conventions.gradle.kts`](../gradle/build-logic/src/main/kotlin/seniordev.sonar-conventions.gradle.kts).

For the root project of a multi-module build, next to modules that apply `seniordev.quality-conventions`:

```kotlin
plugins {
    base
    id("seniordev.sonar-conventions")
}
```

It applies `org.sonarqube` with the organisation and project key of `seniordev.quality-conventions`, and its one
`sonar` task waits for `jacocoTestReport` of every module. Applied anywhere but the root, it fails and says so.

## seniordev.nullness-conventions (opt-in)

Source: [`seniordev.nullness-conventions.gradle.kts`](../gradle/build-logic/src/main/kotlin/seniordev.nullness-conventions.gradle.kts).

Error Prone 2.50.0 with NullAway 0.14.2 in JSpecify mode on `compileJava`. NullAway checks only packages marked
`@NullMarked` (`OnlyNullMarked`), so a repository adopts it one package at a time; it is off for test sources, and
generated code is excluded. Error Prone's other checks keep their default severity, as warnings;
`platform.javac.werror=true` makes them errors with the rest. It is a separate plugin because Error Prone hooks
into javac internals and can lag a new JDK: a toolchain bump must not wait for it in repositories that do not use
it. `PlatformNullnessFunctionalTest` runs it on the canon toolchain.

```kotlin
plugins {
    id("seniordev.java-conventions")
    id("seniordev.nullness-conventions")
}
dependencies {
    implementation(libs.jspecify) // a Spring 7 application has it already
}
```

```java
// src/main/java/pl/example/orders/package-info.java
@NullMarked
package pl.example.orders;

import org.jspecify.annotations.NullMarked;
```

With Lombok, set `lombok.addLombokGeneratedAnnotation = true` in `lombok.config`, so NullAway skips the
generated members.

## seniordev.spring-modulith-conventions

Source: [`seniordev.spring-modulith-conventions.gradle.kts`](../gradle/build-logic/src/main/kotlin/seniordev.spring-modulith-conventions.gradle.kts).

Imports `pl.seniordeveloper:platform-bom` of the same release, which carries the Spring Boot, Spring Modulith,
Spring AI and JUnit BOMs with the Platform floors and overrides ([ADR-0013](adr/0013-catalog-for-aliases-bom-for-constraints.md)), and adds
the shared test dependencies (Modulith test, Testcontainers, ArchUnit, the JUnit launcher). It does not apply the Spring Boot
plugin: the consumer adds `alias(libs.plugins.spring.boot)`.

| Task | On `check` | Knob | Default |
|---|---|---|---|
| `test` | yes | `@Tag("integration")` or `@Tag("model")` moves a test out | runs every test without the `integration` and `model` tags |
| `platformBomOverrideCheck` | yes, warns only | none | lists every BOM version property (`*.version`) set outside the platform; see [versions.md](versions.md#what-platformdependencycheck-does-not-see) |
| `integrationTest` | yes | `@Tag("integration")` | runs only tests tagged `integration`; tag every Testcontainers test, or it runs in the fast `test` and needs Docker there |
| `modelTest` | no | `@Tag("model")` (`@ModelTest`) | runs only tests tagged `model`, on purpose; outside `check` and the coverage sum |

## npm packages

Generated from each `package.json` by `scripts/docs-gen.sh`.

<!-- docs-gen:npm-packages -->
| Package | Directory | Published | Bins | Description |
|---|---|---|---|---|
| `@dominiksienkiewicz/api-client` | `frontend/packages/api-client/` | no (private) | — | Shared fetch wrapper for the frontends: base URL from the environment, JSON bodies, null for 204 and an ApiError carrying the response body. |
| `@dominiksienkiewicz/eslint-config` | `frontend/packages/eslint-config/` | yes | — | Shared ESLint flat config: Next.js core-web-vitals and TypeScript. |
| `@dominiksienkiewicz/openapi` | `frontend/packages/openapi/` | yes | `platform-openapi-check`, `platform-openapi-gen` | Contract-first OpenAPI tooling (incubating): generate TypeScript types from the committed spec and check that they are current. |
| `@dominiksienkiewicz/prettier-config` | `frontend/packages/prettier-config/` | yes | — | Shared Prettier configuration with the Tailwind CSS class sorter (incubating). |
| `@dominiksienkiewicz/query` | `frontend/packages/query/` | no (private) | — | Shared QueryClient (staleTime 60 s, refetchOnWindowFocus off) and a QueryProvider with React Query Devtools. |
| `@dominiksienkiewicz/tailwind-preset` | `frontend/packages/tailwind-preset/` | yes | — | Shared design tokens for Tailwind CSS v4, as a CSS-first @theme. |
| `@dominiksienkiewicz/tsconfig` | `frontend/packages/tsconfig/` | yes | — | Shared TypeScript configurations, base and Next.js. |
| `@dominiksienkiewicz/ui` | `frontend/packages/ui-registry/` | yes | — | shadcn registry (utils, button). |
| `@dominiksienkiewicz/versions` | `frontend/packages/versions/` | yes | `platform-bump`, `platform-doctor`, `platform-templates-check`, `platform-versions-check`, `platform-workflows-check` | The frontend version canon: the exact version of every frontend dependency. Ships the platform-versions-check guard that frontend-ci runs, the platform-bump bin that moves a repository to a Platform release, platform-templates-check, platform-workflows-check and platform-doctor. |
| `@dominiksienkiewicz/vitest-config` | `frontend/packages/vitest-config/` | yes | — | Shared Vitest base configuration with the Testing Library setup for jsdom and React. |
<!-- /docs-gen -->

## Security starter (*incubating*)

`pl.seniordeveloper:platform-security-starter` registers a `SecurityFilterChain` and CORS in a servlet web
application unless the application defines its own. It is ordered before Spring Boot's default web and
management security, which back off when it is present. No consumer has adopted it yet, so treat these as provisional. Source:
[`PlatformSecurityProperties`](../gradle/security-starter/src/main/java/pl/seniordeveloper/platform/security/PlatformSecurityProperties.java)
and [`PlatformCorsProperties`](../gradle/security-starter/src/main/java/pl/seniordeveloper/platform/security/PlatformCorsProperties.java).

| Property | Default | Effect |
|---|---|---|
| `platform.security.mode` | `AUTHENTICATED` | `AUTHENTICATED` requires authentication for everything not permitted; `PERMIT_ALL` permits every request; `JWT` makes the application an OAuth2 resource server that requires a bearer JWT, without a session |
| `platform.security.stateless` | `false` | `true` disables the HTTP session; `JWT` is always stateless |
| `platform.security.csrf` | `ON` | `ON` keeps the token in the session, `OFF` disables CSRF protection (only for an API without cookie authentication), `SPA` hands the token to a browser client in the `XSRF-TOKEN` cookie and accepts it back in `X-XSRF-TOKEN` (Spring Security's `csrf.spa()`); `true` and `false` still mean `ON` and `OFF` |
| `platform.security.jwt.authorities-claim` | unset (`scope`, `scp`) | the JWT claim whose values become authorities, each with the `SCOPE_` prefix |
| `platform.security.http-basic` | `true` | HTTP Basic authentication |
| `platform.security.permitted-paths` | `/actuator/health`, `/actuator/health/**`, `/actuator/info` | paths that never require authentication; a value replaces the defaults, so repeat the health paths |

A 401 or a 403 from the chain is `application/problem+json` in the shape of the web starter, `title`, `status`,
`detail`, `instance`, `message` and `traceId` when tracing set one, with the challenge of the mode in
`WWW-Authenticate`: `Basic realm="Realm"` with HTTP Basic, the RFC 6750 `Bearer` challenge with `JWT`, none
otherwise. `JWT` needs `spring-boot-starter-security-oauth2-resource-server`, which the application declares,
and a `JwtDecoder`, which Spring Boot builds from `spring.security.oauth2.resourceserver.jwt.issuer-uri` (or
`jwk-set-uri`, or `public-key-location`); without either the application fails at startup and names the fix.
Scope rules stay in the application, for example `@PreAuthorize("hasAuthority('SCOPE_orders.read')")`.
| `platform.cors.allowed-origins` | empty | setting it opts into the Platform CORS source; `*` fails at startup while `allow-credentials` is `true`; see [consuming.md](consuming.md#security-starter-cors) |
| `platform.cors.allowed-methods` | `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS` | allowed methods |
| `platform.cors.allowed-headers` | `*` | allowed headers |
| `platform.cors.allow-credentials` | `true` | whether credentials are allowed |

## Observability starter (*incubating*)

`pl.seniordeveloper:platform-observability-starter` brings the actuator and a Prometheus registry, and sets
the operational baseline as defaults of the lowest precedence, so every property of the application
wins. Source: [`PlatformObservabilityEnvironmentPostProcessor`](../gradle/observability-starter/src/main/java/pl/seniordeveloper/platform/observability/PlatformObservabilityEnvironmentPostProcessor.java).

| Default | Value |
|---|---|
| `management.endpoints.web.exposure.include` | `health,info`, plus `prometheus` with `platform.observability.prometheus=true` |
| `management.endpoint.health.probes.enabled` | `true`: `/actuator/health/liveness` and `/readiness`, which the `Dockerfile.backend` HEALTHCHECK probes |
| `management.endpoint.health.show-details` | `when-authorized` |
| `management.metrics.tags.application` | `${spring.application.name}` |

| Property | Default | Effect |
|---|---|---|
| `platform.observability.prometheus` | `false` | exposes `/actuator/prometheus`; metrics leak information, so it is opt-in |
| `platform.observability.public-metrics` | `false` | with `prometheus=true`, adds `/actuator/prometheus` to the default `platform.security.permitted-paths` of the security starter, for a scraper inside the network; an application that sets its own list adds the path itself |
| `platform.observability.json-logs` | `false` | `logging.structured.format.console=ecs` |

The `tracing` feature adds `spring-boot-starter-opentelemetry` (traces and OTLP export):

```kotlin
implementation(libs.platform.observability.starter)
implementation(libs.platform.observability.starter) { capabilities { requireFeature("tracing") } }
implementation(libs.bundles.observability.modulith) // spring-modulith-actuator and -observability
```

## Web starter (*incubating*)

`pl.seniordeveloper:platform-web-starter` answers every error of a Spring MVC application as RFC 9457
`application/problem+json` in one shape, the one `@dominiksienkiewicz/api-client` reads into
`ApiError.problem` ([api-contracts.md](api-contracts.md#errors-problem-details)). It replaces Spring Boot's
`ProblemDetailsExceptionHandler` and backs off when the application defines its own
`ResponseEntityExceptionHandler`. Source: [`PlatformProblemDetailsExceptionHandler`](../gradle/web-starter/src/main/java/pl/seniordeveloper/platform/web/PlatformProblemDetailsExceptionHandler.java).

| Exception | Status | Body |
|---|---|---|
| `@Valid` failure, `jakarta.validation.ConstraintViolationException` | 400 | `errors[]` of `{ pointer, detail }`, the pointer a JSON Pointer such as `#/items/0/quantity` |
| any other Spring MVC exception (404, 405, 415 …) | as Spring MVC | Spring's Problem Details |
| `DataIntegrityViolationException`, optimistic or pessimistic locking failure | 409 | a fixed detail, never the database message |
| anything else | 500 | a fixed detail; the exception goes to the log only |

Every body carries `traceId` when tracing put one in the MDC, and `message`, a copy of `detail` for
clients of the old shape, throughout the 1.x line.

| Property | Default | Effect |
|---|---|---|
| `platform.web.problem-details.enabled` | `true` | `false` hands the errors back to Spring Boot |
| `platform.web.problem-details.legacy-message` | `true` | the `message` member |

## Test fixtures

`pl.seniordeveloper:platform-test-fixtures` (`testImplementation(libs.platform.test.fixtures)`). Source:
[`gradle/test-fixtures`](../gradle/test-fixtures/src/main/java/pl/seniordeveloper/platform/testing/); the
published sources jar shows the same examples in the IDE.

`PlatformSharedPostgresContainer` starts one PostgreSQL with pgvector for the whole JVM and points
`spring.datasource.*` of every context that imports it at that server, through a `DynamicPropertyRegistrar`.
Every cached Spring context shares it, so a suite with many context signatures still runs one container.
The container is not a bean, because Spring Boot stops a container bean when its context closes, and the
context cache closes contexts while others still use them; Ryuk removes it when the JVM exits. It runs
without durability (`fsync`, `synchronous_commit` and `full_page_writes` off, data on tmpfs), which is safe
only in a Testcontainers container, and is reusable across local runs when `~/.testcontainers.properties`
sets `testcontainers.reuse.enable=true`. `PlatformSharedPostgresContainer.container()` returns it for a test
that needs the address. The contexts share one database: a test that expects an empty database cleans up
after itself, uses its own schema, or opts into a database per context with
`@PlatformPostgresDatabasePerContext` (below). `@PostgresIntegrationTest` below imports it.

`AbstractTestcontainersFootprintTest` fails when more than `maximumPostgresContainers()` (1 by default)
Platform PostgreSQL containers of this Testcontainers session run at once, naming the fix. It counts the
containers running when it runs, so order it after the tests that build contexts, with
`junit.jupiter.testclass.order.default=org.junit.jupiter.api.ClassOrderer$OrderAnnotation` in
`src/test/resources/junit-platform.properties`:

```java
@Order(Integer.MAX_VALUE)
class TestcontainersFootprintIT extends AbstractTestcontainersFootprintTest { }
```

`PlatformPostgresContainer` is deprecated: it is a `@ServiceConnection` bean, so each context signature in
the cache starts its own container. It keeps working unchanged. In a dev-time launcher with Spring Boot
DevTools, a restart closes the context and that container with it, so the database starts empty after
every restart, unless the application declares its own container bean with `@RestartScope`. The shared
container lives outside the context and keeps its data across restarts.

Both need Docker, so tag the test `integration`. `@PostgresIntegrationTest` is the three annotations in one:

```java
@PostgresIntegrationTest
class OrderRepositoryTest { }
```

which stands for:

```java
@IntegrationTest // @Tag("integration")
@SpringBootTest
@Import(PlatformSharedPostgresContainer.class)
class OrderRepositoryTest { }
```

`@PlatformPostgresDatabasePerContext` gives every Spring context a database of its own on the same server.
Next to `@PostgresIntegrationTest`, or on a configuration class that `SpringApplicationBuilder` starts, it
runs `CREATE DATABASE ctx_<n>` once per context and points `spring.datasource.url`, `username` and
`password` at that database; the server stays one container per JVM. Closing the context, when the context
cache evicts it or the JVM ends, drops its database. It isolates context signatures, not test classes: test
classes with the same configuration share the cached context and its database, and the migrations run from
an empty database in every context. Without the annotation nothing changes.

```java
@PostgresIntegrationTest
@PlatformPostgresDatabasePerContext
class OrderRepositoryIT { }
```

The annotation imports `PlatformSharedPostgresContainer` ahead of the registrar of the context's database,
and of two registrations of one property the later wins. A context in which something registers
`spring.datasource.url` after it, for example `PlatformSharedPostgresContainer` given as an application
source instead of through `@Import`, fails to start with a message that names the fix.

`@IntegrationTest` and `@ModelTest` carry the tags `integration` and `model`; `PlatformTestTags` holds
their names. When the test task names itself in the system property `platform.test.task`, a platform
container started under `test` prints "WARNING: Testcontainers used in the unit 'test' task … annotate
the test class with @IntegrationTest or @PostgresIntegrationTest". With `platform.test.guard=fail` it
throws instead; a later MINOR release makes that the default.

The same configuration runs the application locally against a container, from `src/test/java`:

```java
public class TestApplication {
  public static void main(String[] args) {
    SpringApplication.from(Application::main).with(PlatformSharedPostgresContainer.class).run(args);
  }
}
```

`PlatformOllamaContainer` adds Ollama; the consumer also needs `org.testcontainers:testcontainers-ollama`:

```java
@Import({PlatformSharedPostgresContainer.class, PlatformOllamaContainer.class})
```

`PlatformImages` holds the image tags those containers use (`PGVECTOR`, `OLLAMA`). The same tags run
in `infra/docker-compose.yml`, and `templates/tests/image-tags-sync.test.sh` fails when they differ.

`AbstractModulithVerificationTest` verifies the Spring Modulith structure without Docker:

```java
class ModulithVerificationTest extends AbstractModulithVerificationTest {
  @Override
  protected Class<?> applicationClass() {
    return MyApplication.class;
  }
}
```

Two Docker-free guards fail the fast `test` when Spring Boot would start without migrations.
`AbstractLiquibaseChangelogTest` parses `db/changelog/db.changelog-master.yaml` with Liquibase, no
database needed, and fails when it is missing, is not valid YAML, or includes a file that does not exist;
the test classpath needs `org.liquibase:liquibase-core`, which every Liquibase application has. Its second
test holds `db/changelog/changes/` to the naming `deploy.yml` tags the migrate image with: every file is
`NNNN-<slug>.yaml`, no two share a prefix, and a changeset of every file reaches the master
([Database migrations](consuming.md#database-migrations)). `AbstractFlywayMigrationTest` checks every
`db/migration` root on the classpath, main, test and jars, with subdirectories, as Flyway scans them: it
fails when there is none or no `.sql` file, on a file not named `V<n>__<description>.sql` or
`R__<description>.sql`, and on two migrations with one version (`V3__a` and `V3__b`, `V1.1` and `V1_1`):

```java
class LiquibaseChangelogTest extends AbstractLiquibaseChangelogTest { }

class FlywayMigrationTest extends AbstractFlywayMigrationTest { }
```

`AbstractSchemaValidationIT` checks the migrations against the entities on a real database: it boots the
application on `PlatformSharedPostgresContainer` with `spring.jpa.hibernate.ddl-auto=validate`, so Liquibase
or Flyway runs first and Hibernate then compares every entity with the schema, Spring Modulith's
`JpaEventPublication` included. A missing table fails the context with Hibernate's message, for example
`missing table [event_publication]`. Put the subclass in the application's package or below it, so
`@SpringBootTest` finds the application. A column type Hibernate cannot compare, such as pgvector without
`hibernate-vector`, is excluded through a schema filter
(`spring.jpa.properties.hibernate.hbm2ddl.schema_filter_provider` in the subclass's `@TestPropertySource`),
with a comment that says why:

```java
class SchemaValidationIT extends AbstractSchemaValidationIT { }
```

`PlatformArchRules` (package `…testing.arch`) is a small set of ArchUnit rules, one field each, so a
consumer takes all of them or a few: no standard streams, no `java.util.logging`, no generic exceptions,
no field injection, `@Transactional` methods that are not private, `@RestController` methods that return
no JPA `@Entity`, and the integration tag on every class that uses a platform container. It needs
`com.tngtech.archunit:archunit-junit5` on the test classpath, which `seniordev.spring-modulith-conventions`
adds; others declare `libs.archunit.junit5`. `HexagonalRules.of(domain, application, adapter)` adds the
ports-and-adapters rules. Freeze the existing violations of a rule with `FreezingArchRule.freeze(rule)`:

```java
@AnalyzeClasses(packagesOf = Application.class, importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {
  @ArchTest ArchTests platform = ArchTests.in(PlatformArchRules.class);

  @ArchTest
  void hexagonal(JavaClasses classes) {
    HexagonalRules.of("..domain..", "..application..", "..adapter..").forEach(rule -> rule.check(classes));
  }
}
```

`AbstractModulithDocumentationTest` writes the Spring Modulith component diagrams (PlantUML) and module
canvases (AsciiDoc) of the same modules to `build/spring-modulith-docs`, which `backend-ci.yml` uploads as
the `module-docs-<run id>` artifact; `spring-modulith-starter-test` already brings the documenter:

```java
class ModulithDocumentationTest extends AbstractModulithDocumentationTest {
  @Override
  protected Class<?> applicationClass() {
    return Application.class;
  }
}
```

After the documenter, which empties the folder first, the same test writes `modules.mmd`: a Mermaid
`flowchart LR` that GitHub renders in a `mermaid` code block, with one node per application module
(labelled with its display name) and one edge per dependency between two modules, labelled `uses` (an
injected bean), `listens to` (an event listener) or `depends on` (any other reference, left out when a more
specific edge joins the same modules). Nodes and edges are sorted by module identifier, so the file only
changes when the modules do. A unit test of `platform-test-fixtures` renders the modules of the `spring-app`
starter the same way and compares them with `docs/diagrams/spring-app-modules.mmd`, the diagram the README
shows.

`AbstractOpenApiContractTest` holds the committed OpenAPI spec to the Spring MVC controllers, both ways
and without Docker ([docs/api-contracts.md](api-contracts.md)). It reports an operation missing from the
spec, a stale one, an operation without `operationId` or `responses`, a duplicate `operationId`, a mapping
without an explicit HTTP method and an unresolved local `$ref`. `/actuator` and `/error` are ignored on
both sides unless `ignoredPathPrefixes()` says otherwise. The test classpath needs `spring-webmvc` and
`tools.jackson.core:jackson-databind`, and `tools.jackson.dataformat:jackson-dataformat-yaml` for a YAML
spec:

```java
class OpenApiContractTest extends AbstractOpenApiContractTest {
  @Override
  protected Path specPath() {
    return Path.of("contract/openapi.yaml");
  }

  @Override
  protected String basePackage() {
    return "pl.seniordeveloper.myapp";
  }
}
```
