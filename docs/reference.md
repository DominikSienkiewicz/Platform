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

## seniordev.settings-conventions

Source: [`seniordev.settings-conventions.settings.gradle.kts`](../gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts).

Applied in `settings.gradle.kts` with the Platform version. It applies the Foojay toolchain
resolver and declares the dependency repositories: `platformRepository` when set, then Maven
Central and GitHub Packages with the credentials above. The consumer still declares
`pluginManagement` repositories (to resolve this plugin), the catalog pin and `rootProject.name`.

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
| `platformDependencyCheck` | yes | none | every explicit dependency version must match the catalog |
| `platformRuntimeImageCheck` | yes | none | the final `FROM` of `Dockerfile` (project or root) must run Java 27 or newer; skipped when there is no Dockerfile or the image is not a JVM image |
| test tasks | — | `AI_AGENT` | JUnit Platform |

Their failure messages and fixes are in [consuming.md](consuming.md#troubleshooting).

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
| `integrationTest` | yes | `@Tag("integration")` | runs only tests tagged `integration`; tag every Testcontainers test, or it runs in the fast `test` and needs Docker there |

## Security starter (*incubating*)

`pl.seniordeveloper:platform-security-starter` registers a `SecurityFilterChain` and CORS unless the
application defines its own. No consumer has adopted it yet, so treat these as provisional. Source:
[`PlatformSecurityProperties`](../gradle/security-starter/src/main/java/pl/seniordeveloper/platform/security/PlatformSecurityProperties.java)
and [`PlatformCorsProperties`](../gradle/security-starter/src/main/java/pl/seniordeveloper/platform/security/PlatformCorsProperties.java).

| Property | Default | Effect |
|---|---|---|
| `platform.security.mode` | `AUTHENTICATED` | `AUTHENTICATED` requires authentication for everything not permitted; `PERMIT_ALL` permits every request |
| `platform.security.stateless` | `false` | `true` disables the HTTP session |
| `platform.security.csrf` | `true` | CSRF protection |
| `platform.security.http-basic` | `true` | HTTP Basic authentication |
| `platform.security.permitted-paths` | `/actuator/health`, `/actuator/health/**`, `/actuator/info` | paths that never require authentication |
| `platform.cors.allowed-origins` | empty | setting it opts into the Platform CORS source; see [consuming.md](consuming.md#security-starter-cors) |
| `platform.cors.allowed-methods` | `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS` | allowed methods |
| `platform.cors.allowed-headers` | `*` | allowed headers |
| `platform.cors.allow-credentials` | `true` | whether credentials are allowed |

## Test fixtures

`pl.seniordeveloper:platform-test-fixtures` (`testImplementation(libs.platform.test.fixtures)`). Source:
[`gradle/test-fixtures`](../gradle/test-fixtures/src/main/java/pl/seniordeveloper/platform/testing/); the
published sources jar shows the same examples in the IDE.

`PlatformPostgresContainer` starts one PostgreSQL with pgvector, wired through `@ServiceConnection`.
It needs Docker, so tag the test `integration`:

```java
@Tag("integration")
@SpringBootTest
@Import(PlatformPostgresContainer.class)
class OrderRepositoryTest { }
```

The same configuration runs the application locally against a container, from `src/test/java`:

```java
public class TestApplication {
  public static void main(String[] args) {
    SpringApplication.from(Application::main).with(PlatformPostgresContainer.class).run(args);
  }
}
```

`PlatformOllamaContainer` adds Ollama; the consumer also needs `org.testcontainers:testcontainers-ollama`:

```java
@Import({PlatformPostgresContainer.class, PlatformOllamaContainer.class})
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
`AbstractLiquibaseChangelogTest` fails when `db/changelog/db.changelog-master.yaml` is missing or
defines no `databaseChangeLog`. `AbstractFlywayMigrationTest` fails when `db/migration` is missing,
holds no `.sql` file, or holds one not named `V<n>__<description>.sql` or `R__<description>.sql`:

```java
class LiquibaseChangelogTest extends AbstractLiquibaseChangelogTest { }

class FlywayMigrationTest extends AbstractFlywayMigrationTest { }
```
