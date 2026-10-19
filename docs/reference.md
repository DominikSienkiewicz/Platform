# Conventions reference

What the Platform plugins add to a consumer build, which knobs a consumer can turn, and what the
defaults are. How to wire a repository is in [consuming.md](consuming.md); the reusable workflows
are in [reusable-workflows.md](reusable-workflows.md).

## Properties and environment variables

| Name | Where | Default | Effect | Read in |
|---|---|---|---|---|
| `platformVersion` | `gradle.properties` | — | the Platform release the settings plugin and the catalog resolve | the consumer's `settings.gradle.kts` |
| `platformRepository` | `-P` or `gradle.properties` | unset | puts that Maven repository first for dependencies, and for plugins in a `pluginManagement` that reads it as the templates do; the only way to test an unreleased Platform ([ADR-0003](adr/0003-local-platform-resolution.md)) | [seniordev.settings-conventions](../gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts), the consumer's `pluginManagement` |
| `gpr.user`, `gpr.key` | `~/.gradle/gradle.properties` | unset | GitHub Packages credentials (classic PAT with `read:packages`) | [seniordev.settings-conventions](../gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts) |
| `GITHUB_ACTOR`, `GITHUB_TOKEN` | environment | unset | fallback credentials for GitHub Packages, used on CI | [seniordev.settings-conventions](../gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts) |
| `coverageMinimum` | `gradle.properties` or `-P` | `0.00` | JaCoCo coverage threshold on `check`, a decimal between 0 and 1 | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |
| `sonarProjectKey` | `gradle.properties` | `DominikSienkiewicz_<rootProject.name>` | SonarQube Cloud project key | [seniordev.quality-conventions](../gradle/build-logic/src/main/kotlin/seniordev.quality-conventions.gradle.kts) |
| `AI_AGENT` | environment | unset | `1` or `true` bounds test resources for coding agents (one fork, 2 GiB heap, four cached Spring contexts); see [consuming.md](consuming.md#agent-resource-profile) | [seniordev.java-conventions](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts) |

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

## seniordev.java-conventions

Source: [`seniordev.java-conventions.gradle.kts`](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts); Checkstyle rules in
[`platform-checkstyle/`](../gradle/build-logic/src/main/resources/platform-checkstyle/).

| Task or setting | On `check` | Knob | Default |
|---|---|---|---|
| Java toolchain | — | none | Java 27 |
| `spotlessCheck` | yes | none | google-java-format 1.36.1, unused imports removed |
| `checkstyleMain`, `checkstyleTest` | yes | `@SuppressWarnings("checkstyle:<checkname>")` on a declaration, with the check name in lower case | Platform rules, `maxWarnings = 0` |
| `jacocoTestReport`, `jacocoTestCoverageVerification` | yes | `coverageMinimum` | 0.00, coverage of `test` and `integrationTest` together |
| `platformCoverageDataCheck` | yes | `coverageMinimum` | fails when the threshold is above 0 and no test produced JaCoCo data |
| `platformDependencyCheck` | yes | none | every explicit dependency version must match the catalog; a library outside the catalog is told apart by whether a Platform BOM manages it |
| `platformPinCheck` | yes | none | the settings plugin and `platform-catalog` are the same release; a mismatch also warns at configuration time |
| `lint` | no | a project's own `lint` task wins | `spotlessCheck`, every Checkstyle task, `platformDependencyCheck` and `platformPinCheck`, without tests |
| `format` | no | a project's own `format` task wins | `spotlessApply` |
| `platformRuntimeImageCheck` | yes | none | the final `FROM` of `Dockerfile` (project or root) must run Java 27 or newer; skipped when there is no Dockerfile or the image is not a JVM image |
| test tasks | — | `AI_AGENT` | JUnit Platform |

Their failure messages and fixes are in [consuming.md](consuming.md#troubleshooting). The tasks are
compatible with the configuration cache, which Platform's TestKit suite runs with
`--warning-mode=fail` (Decision 10); consumers opt in with `org.gradle.configuration-cache=true`.

## seniordev.quality-conventions

Source: [`seniordev.quality-conventions.gradle.kts`](../gradle/build-logic/src/main/kotlin/seniordev.quality-conventions.gradle.kts).

| Task or setting | On `check` | Knob | Default |
|---|---|---|---|
| `pitest` | no | `pitest { targetClasses.set(listOf("com.example.*")) }` | the plugin's default, the project's `group` followed by `.*`; PIT 1.30.0, JUnit 5 plugin 1.2.3 |
| `spotbugsMain`, `spotbugsTest` | yes, report-only | `spotbugs { ignoreFailures.set(false) }` to make findings fail | findings are reported, not failed ([ADR-0005](adr/0005-spotbugs-report-only.md)) |
| `cyclonedxBom` | no | none | an SBOM of `runtimeClasspath` only, the input of `security-scan.yml` |
| `sonar` | no | `sonarProjectKey` | organisation `dominiksienkiewicz`, coverage from `jacocoTestReport` |

## seniordev.spring-modulith-conventions

Source: [`seniordev.spring-modulith-conventions.gradle.kts`](../gradle/build-logic/src/main/kotlin/seniordev.spring-modulith-conventions.gradle.kts).

Imports the Spring Boot, Spring Modulith and Spring AI BOMs and adds the shared test dependencies
(Modulith test, Testcontainers, ArchUnit, the JUnit launcher). It does not apply the Spring Boot
plugin: the consumer adds `alias(libs.plugins.spring.boot)`.

| Task | On `check` | Knob | Default |
|---|---|---|---|
| `test` | yes | `@Tag("integration")` moves a test out | runs every test without the `integration` tag |
| `platformBomOverrideCheck` | yes, warns only | none | lists every BOM version property (`*.version`) set outside the platform; see [versions.md](versions.md#what-platformdependencycheck-does-not-see) |
| `integrationTest` | yes | `@Tag("integration")` | runs only tests tagged `integration`; tag every Testcontainers test, or it runs in the fast `test` and needs Docker there |

## Security starter (*incubating*)

`pl.seniordeveloper:platform-security-starter` registers a `SecurityFilterChain` and CORS in a servlet web
application unless the application defines its own. It is ordered before Spring Boot's default web and
management security, which back off when it is present. No consumer has adopted it yet, so treat these as provisional. Source:
[`PlatformSecurityProperties`](../gradle/security-starter/src/main/java/pl/seniordeveloper/platform/security/PlatformSecurityProperties.java)
and [`PlatformCorsProperties`](../gradle/security-starter/src/main/java/pl/seniordeveloper/platform/security/PlatformCorsProperties.java).

| Property | Default | Effect |
|---|---|---|
| `platform.security.mode` | `AUTHENTICATED` | `AUTHENTICATED` requires authentication for everything not permitted; `PERMIT_ALL` permits every request |
| `platform.security.stateless` | `false` | `true` disables the HTTP session |
| `platform.security.csrf` | `true` | CSRF protection |
| `platform.security.http-basic` | `true` | HTTP Basic authentication |
| `platform.security.permitted-paths` | `/actuator/health`, `/actuator/health/**`, `/actuator/info` | paths that never require authentication; a value replaces the defaults, so repeat the health paths |
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
after itself or uses its own schema. `@PostgresIntegrationTest` below imports it.

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
