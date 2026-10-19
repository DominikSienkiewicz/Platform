# Consuming the platform in a product repository

Everything below is what a consuming repository declares. Nothing here needs to be copied
into the platform itself. Every task, property and default the plugins add is listed in
[reference.md](reference.md).

## Prerequisites

- **JDK 25 for the Gradle daemon.** Platform's plugins are compiled for Java 25. A backend copied from
  `templates/jvm/*` carries `gradle/gradle-daemon-jvm.properties`, so the wrapper starts from any JDK and Gradle
  selects or downloads a Java 25 for the daemon itself. Without that file, copy
  [`templates/.sdkmanrc`](../templates/.sdkmanrc) to the repository root and run `sdk env install`, or point
  `JAVA_HOME` at a JDK 25. Regenerate the file with `./gradlew updateDaemonJvm --jvm-version=25`; on Linux,
  check that the x86-64 URL names a glibc Temurin build, not an Alpine one.
- **JDK 27 as the toolchain.** `seniordev.java-conventions` compiles for Java 27. Locally Foojay can
  provision it; otherwise register an installed JDK with `org.gradle.java.installations.paths`.
- **A classic personal access token with `read:packages`.** GitHub Packages requires
  authentication even for public packages, for both Maven and npm.
  - Gradle: in `~/.gradle/gradle.properties`, `gpr.user=<your GitHub login>` and
    `gpr.key=<the token>`. The `pluginManagement` block of the templates stops a build without them, or
    without `-PplatformRepository`, with "No GitHub Packages credentials" and both options, before Gradle
    reports the 401 as a missing plugin; `--offline` skips that check.
  - npm: `export GITHUB_TOKEN=<the token>` in your shell profile.
  - CI: a repository secret `GPR_TOKEN` with the same token.

## Quickstart

To start a new repository, render it from the canon instead of copying the pieces below by hand. From a
Platform checkout:

```bash
scripts/new-consumer.sh --name order-service --package pl.example.orders --kind spring-app --frontend next --out ../order-service
```

Then provide the credentials: `GPR_TOKEN` as a repository secret for CI, and `gpr.user`/`gpr.key` and
`GITHUB_TOKEN` locally ([Prerequisites](#prerequisites)); run `npm install` once in `frontend/` and commit
the `package-lock.json` it writes. Once the public `DominikSienkiewicz/platform-example` repository exists,
every release regenerates it from this command ([RELEASING.md](../RELEASING.md#what-releaseyml-does)).

It writes `backend/` (the starter with your package, group and name, the Gradle wrapper and the
`platformVersion=` pin), a `ci.yml` caller of `backend-ci.yml` at the exact tag with `packages: read`
and an explicit `gpr_token`, the scripts of `templates/` and the root files. `--kind java-library` gives
a plain library, `--platform-version X.Y.Z` another release. `--frontend next` adds `frontend/`: a
Next.js app in the `src/` layout whose `package.json` pins every dependency at the canon and every
`@dominiksienkiewicz/*` package at the release, with the strict scripts, `.npmrc`, the configs below, and a
`frontend-ci.yml` caller with `strict: true`. It creates no git repository and no GitHub setting. The steps below describe what it renders, and how to add Platform to an existing
repository.

Backend, for a new repository started from a template:

1. Copy a starter and the pinned Gradle wrapper (`<platform>` is a clone of this repository):

   ```bash
   cp -R <platform>/templates/jvm/spring-app my-service && cp -R <platform>/gradle/catalog/{gradlew,gradlew.bat,gradle} my-service/
   ```

2. Find the latest Platform release and set it as `platformVersion` in `my-service/gradle.properties`
   (1.5.31 or newer, the first release that supports `platformRepository`):

   ```bash
   git ls-remote --tags --refs https://github.com/DominikSienkiewicz/Platform 'v*.*.*' | sed 's#.*/v##' | sort -V | tail -1
   ```

3. Check the wiring, then run the full build:

   ```bash
   cd my-service && ./gradlew platformDependencyCheck && ./gradlew check
   ```

4. Add the backend CI caller from [CI](#ci) and set the `GPR_TOKEN` secret:

   ```bash
   gh secret set GPR_TOKEN
   ```

Frontend:

1. Copy [`templates/npmrc`](../templates/npmrc) to `frontend/.npmrc`.
2. Install the version canon at the Platform version you pin:

   ```bash
   cd frontend && npm install --save-dev --save-exact @dominiksienkiewicz/versions@<version>
   ```

3. Check the dependencies against the canon:

   ```bash
   npx platform-versions-check
   ```

4. Add the frontend CI caller from [CI](#ci) with `strict: true`.

## Verify

- Backend: `./gradlew lint` resolves the settings plugin and the catalog and runs the formatter check
  and the linters without tests (`./gradlew format` fixes the formatting); `./gradlew check` runs every
  gate. In CI, `lint-task: lint` on `backend-ci.yml` runs the same first.
- Frontend: `(cd frontend && npx platform-versions-check)`.

## Backend

Start from [`templates/jvm/java-library`](../templates/jvm/java-library) for a pure
library or [`templates/jvm/spring-app`](../templates/jvm/spring-app) for a minimal
Spring application. These are the inputs to `PlatformConsumerFunctionalTest`, which
publishes the current plugins and catalog to an isolated local Maven repository and
then runs the consumer CI entry point through Gradle TestKit: `build cyclonedxBom`, plus
`pitest` for the library, with Checkstyle, Spotless, SpotBugs, JaCoCo and the platform gates
included. The Spring check also starts the packaged `bootJar` from its own classpath, so a
dependency missing only at runtime fails it. No database is needed.

The template is pinned to the latest Platform release: `release.sh` bumps its
`platformVersion` together with every other version file. Keep `platformVersion` in the
consumer's `gradle.properties` on an **already published** release. Add your own
package name, group and project name, then replace the example code. In a product repository
with `backend/` and `frontend/`, `scripts/platform-bump.sh` bumps both the literal pins in
`backend/settings.gradle.kts` and a `platformVersion=` pin in `backend/gradle.properties`, and fails
when it finds no pin. A standalone JVM repository without `frontend/` cannot run the stub yet, so
update `platformVersion` there directly.

`settings.gradle.kts` reads `platformVersion` once, for the settings plugin and the catalog:

```kotlin
pluginManagement {
    repositories {
        providers.gradleProperty("platformRepository").orNull?.let { maven { url = uri(it) } }
        gradlePluginPortal()
        mavenCentral()
        maven {
            url = uri("https://maven.pkg.github.com/DominikSienkiewicz/Platform")
            credentials {
                username = providers.gradleProperty("gpr.user").orElse(providers.environmentVariable("GITHUB_ACTOR")).orNull
                password = providers.gradleProperty("gpr.key").orElse(providers.environmentVariable("GITHUB_TOKEN")).orNull
            }
        }
    }
}

plugins {
    id("seniordev.settings-conventions") version providers.gradleProperty("platformVersion").get()
}

dependencyResolutionManagement {
    versionCatalogs {
        create("libs") {
            from("pl.seniordeveloper:platform-catalog:${providers.gradleProperty("platformVersion").get()}")
        }
    }
}

rootProject.name = "my-service"
```

The project applies the Java / quality / Spring convention plugins without repeating a version:
the settings plugin has already loaded their shared implementation. The Spring Boot
plugin still comes from `alias(libs.plugins.spring.boot)`.

```kotlin
plugins {
    alias(libs.plugins.spring.boot)
    id("seniordev.java-conventions")
    id("seniordev.quality-conventions")
    id("seniordev.spring-modulith-conventions")
}

dependencies {
    implementation(libs.boot.starter.webmvc)
    implementation(libs.modulith.starter.core)
}
```

To try an unreleased Platform change, publish it locally and pass
`-PplatformRepository=file:///absolute/maven/repository`; see
[local development](local-development.md). Both plugin resolution and ordinary dependencies put
that repository first. Without the property, resolution uses Maven Central, the Gradle Plugin
Portal and GitHub Packages, with the credentials from [Prerequisites](#prerequisites). An
authenticated remote lookup may still occur when an artifact is missing locally.

## Database migrations

Schemas move forward only: a released changeset or migration is never edited, a change is a new file.
`scripts/bump-version.sh db new-migration <slug>` creates the next Liquibase changeset as
`db/changelog/changes/NNNN-<slug>.yaml` and includes it in the master. The reusable `deploy.yml` tags the
migrate image with the highest four-digit prefix in that directory, so the name is part of the deploy
contract: `AbstractLiquibaseChangelogTest` fails on a file outside `NNNN-<slug>.yaml`, on two files with one
prefix and on a file no changeset of which reaches the master. Flyway applications name migrations
`V<n>__<description>.sql`, which `AbstractFlywayMigrationTest` checks ([reference](reference.md#test-fixtures)).

`spring-modulith-starter-jpa` (also in the `modulith-web` bundle) stores event publications in the
`event_publication` table, and no Spring Modulith artifact creates it. Without the table the registry does
not persist publications, so events are not republished after a failure. Copy the canonical migration:

| Migration tool | Template | Copy to |
|---|---|---|
| Liquibase | [`templates/db/liquibase/modulith-event-publication.yaml`](../templates/db/liquibase/modulith-event-publication.yaml) | `db/changelog/changes/NNNN-modulith-event-publication.yaml`, included in the master |
| Flyway | [`templates/db/flyway/V__modulith_event_publication.sql`](../templates/db/flyway/V__modulith_event_publication.sql) | `db/migration/V<n>__modulith_event_publication.sql` |

Both use `CREATE TABLE IF NOT EXISTS`, so a database where the table was created by hand takes them
without an error. They cover the completion modes `UPDATE` (the default) and `DELETE`; `ARCHIVE` also needs
an `event_publication_archive` table. Platform's CI validates both templates with Hibernate against the
entity of the catalog's Spring Modulith version, and `AbstractSchemaValidationIT` does the same for the
application's own migrations ([reference](reference.md#test-fixtures)).

## CI

Call the reusable workflows by the exact tag of your Platform pin and pass the token explicitly.
[docs/reusable-workflows.md](reusable-workflows.md) lists what every workflow needs.

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
permissions:
  contents: read
  packages: read
jobs:
  backend:
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@vX.Y.Z
    with:
      working-directory: . # "backend" for a repository with backend/ and frontend/
    secrets:
      gpr_token: ${{ secrets.GPR_TOKEN }}
  frontend:
    uses: DominikSienkiewicz/Platform/.github/workflows/frontend-ci.yml@vX.Y.Z
    with:
      strict: true
    secrets:
      gpr_token: ${{ secrets.GPR_TOKEN }}
```

`strict: true` requires nonempty `lint`, `typecheck`, `test`, `build` and `format:check` scripts and
the `@dominiksienkiewicz/versions` guard, runs `format:check` before lint, and runs
`platform-openapi-check` when `package.json` configures `platform.openapi`; `run-e2e: true` additionally requires `test:e2e`, and uploads
`playwright-report/` and `test-results/` (HTML report, traces, screenshots) as the artifact
`playwright-report-<run id>`, kept for seven days, whether the tests pass or fail. Missing
checks fail the job instead of producing a successful partial pipeline. Existing callers without
`strict` keep the optional checks.

A repository with a committed OpenAPI spec adds the breaking-change gate as a pull request job,
`api-contract.yml` with `spec-path`; its snippet and triggers are in
[reusable-workflows.md](reusable-workflows.md#api-contractyml).

Pass `gradle-task` as one line of whitespace-separated task arguments, for example
`lint test :app:integrationTest :app:bootJar`. Wildcard characters are passed
literally to Gradle; the input does not interpret shell quoting or commands.

## Dependency version governance

`seniordev.java-conventions` wires `platformDependencyCheck` into `check`. A dependency or
dependency constraint without a version is left to the Platform BOMs. One with an explicit
version must match the catalog, so declare it through `libs.<alias>`. The check covers every
declarable bucket: `api`, `implementation`, `compileOnly`, `compileOnlyApi`, `runtimeOnly`,
`annotationProcessor`, `developmentOnly`, `testAndDevelopmentOnly`, and their `test*`,
`testFixtures*` and custom source set variants. It also covers `pl.seniordeveloper` artifacts,
whose canon is the Platform version you pin. Each failure line names the fix: the `libs.…` alias
to use, a BOM-managed version to remove, or a library that must first be added to the Platform
catalog and released.

A version set through a BOM property (`extra["jackson-bom.version"]`) or a resolution rule
(`useVersion`, `force`) bypasses that check. `platformBomOverrideCheck` warns about the first,
`platform-bump` lists both after every bump, and
[versions.md](versions.md#what-platformdependencycheck-does-not-see) says how to remove them.

## Runtime image

`check` runs `platformRuntimeImageCheck`. It reads the final `FROM` of the project's
`Dockerfile`, or of the root project's in a multi-module build, and fails when that JVM image
runs an older Java than the toolchain the bytecode is compiled for (Java 27). Move the final
`FROM` to the image in [`templates/Dockerfile.backend`](../templates/Dockerfile.backend). A
build without a Dockerfile, a non-JVM image or an image taken from a build argument is skipped
with a log line. A repository-local test that compares the class-file version with the
Dockerfile is redundant once the consumer pins a Platform release that runs this gate.

The template also declares how the container reports health and sizes its heap:

- `HEALTHCHECK` sends `GET /actuator/health/liveness` through bash's `/dev/tcp`, because the image has
  neither curl nor wget, and treats only HTTP 200 as healthy. When the liveness group does not exist
  (404, `management.endpoint.health.probes.enabled` is off) it falls back to `/actuator/health`. The port
  is `MANAGEMENT_SERVER_PORT`, then `SERVER_PORT`, then 8080; the endpoint must answer without
  authentication, as the security starter's default `permitted-paths` allow. The application gets 60 s
  to start; after that, six failed probes 10 s apart mark the container unhealthy.
  [`deploy-remote.sh`](../scripts/deploy-remote.sh) waits for `healthy` only when a container has a
  healthcheck, and a `healthcheck:` in the compose file replaces this one, so delete the compose-level
  check of the backend service.
- `JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"` sizes the heap from the
  container's memory limit and ends the process on `OutOfMemoryError`, so the restart policy starts a
  fresh one. A compose `environment:` entry replaces the whole variable, not one flag.

[`templates/tests/dockerfile-backend.test.sh`](../templates/tests/dockerfile-backend.test.sh) runs the
probe from the Dockerfile against a stub HTTP server for each of these cases.

## Coverage threshold

`check` runs `jacocoTestCoverageVerification` on the coverage of `test` and `integrationTest`
together. Set the threshold in the consumer's `gradle.properties`, for example
`coverageMinimum=0.80`. It is a decimal between 0 and 1 and defaults to 0.00; any other value
fails the build. The threshold is static: raise it yourself as coverage grows. The typed
`platform { coverage { minimum.set("0.80".toBigDecimal()) } }` sets the same threshold and wins over the
property ([reference](reference.md#the-platform-block)). `check` prints the effective value and where it
came from (`Coverage gate: minimum=0.80 (source: coverageMinimum)`). When the
threshold is above 0, `platformCoverageDataCheck` fails `check` if neither test task produced
JaCoCo data, so a module without tests cannot pass the gate by being skipped.

## Agent resource profile

`AI_AGENT=1` or `AI_AGENT=true` bounds test resources for coding agents: one fork, a 2 GiB heap and four
cached Spring contexts per test task, one test task at a time in a build, and two Gradle and Vitest workers.
Each value has a knob, and an explicit property applies in every mode. The contract table, the
`scripts/agent-gradle.sh` launcher with its machine-wide test slots, and the preflight check before
dispatching agents are in [agent-profile.md](agent-profile.md).

## Frontend

Install the packages with npm and commit `package-lock.json`: the reusable `frontend-ci` runs
`npm ci` and `platform-bump` refreshes the lockfile with npm, so a consumer on pnpm or Yarn fails
CI even though Platform builds its own packages with pnpm. Pin every other dependency at the
exact version the canon gives, and every `@dominiksienkiewicz/*` package at one exact version: the
release of `@dominiksienkiewicz/versions` you install. `platform-versions-check` governs
`dependencies`, `devDependencies`, `optionalDependencies` and `overrides`; an application's
`peerDependencies` are deliberately left out.

`tsconfig.json` (`"@/*": ["./*"]` in a layout without `src/`):

```json
{
  "extends": "@dominiksienkiewicz/tsconfig/next.json",
  "compilerOptions": { "paths": { "@/*": ["./src/*"] } },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts", ".next/dev/types/**/*.ts"],
  "exclude": ["node_modules"]
}
```

The preset sets compiler options and the `next` plugin only. TypeScript resolves `include`, `exclude`
and `paths` of an extended config against that config's directory, which is
`node_modules/@dominiksienkiewicz/tsconfig`, so the consumer declares them.

`eslint.config.mjs`:

```js
export { default } from "@dominiksienkiewicz/eslint-config/next";
```

The config package declares `eslint`, `eslint-config-next` and `next` as peer
dependencies; take their versions from `@dominiksienkiewicz/versions`.

Prettier (*incubating*), in `package.json`, with `prettier`, `prettier-plugin-tailwindcss` and
`@dominiksienkiewicz/prettier-config` in `devDependencies` at the canon versions:

```json
{
  "prettier": "@dominiksienkiewicz/prettier-config",
  "scripts": {
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  }
}
```

Strict `frontend-ci` requires `format:check`. The plugin sorts Tailwind class lists, so the first
`npm run format` in a repository that formatted without it rewrites many `className` values; commit
that diff on its own.

OpenAPI types (*incubating*): with `@dominiksienkiewicz/openapi` and `openapi-typescript` in
`devDependencies` at the canon versions, name the committed spec and the generated file, and commit
what `platform-openapi-gen` writes. Strict `frontend-ci` then fails on stale types. The whole flow,
backend test and breaking-change gate included, is in [api-contracts.md](api-contracts.md).

```json
{
  "platform": { "openapi": { "spec": "../contract/openapi.yaml", "output": "src/api/schema.d.ts" } },
  "scripts": { "gen:api": "platform-openapi-gen", "gen:api:check": "platform-openapi-check" }
}
```

`globals.css` (`app/globals.css`, or `src/app/globals.css` in a `src/` layout):

```css
@import "@dominiksienkiewicz/tailwind-preset/theme.css";
@import "tailwindcss";
```

The component registry `@dominiksienkiewicz/ui` is *incubating*: it has no hosted endpoint, and no
consumer has adopted it. If you install it, also add an `@source` line that points from
`globals.css` to the package, so Tailwind sees its classes: `@source "../node_modules/@dominiksienkiewicz/ui";`
in `app/globals.css`, or `@source "../../node_modules/@dominiksienkiewicz/ui";` in `src/app/globals.css`.
Use the `shadcn` version from `@dominiksienkiewicz/versions` (`npx shadcn@4.10.0 …`), never an
unpinned one.

`vitest.config.ts`:

```ts
import { defineConfig, mergeConfig } from "vitest/config";
import { fileURLToPath } from "node:url";
import { baseConfig } from "@dominiksienkiewicz/vitest-config";

export default mergeConfig(
  baseConfig,
  defineConfig({
    resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  }),
);
```

## Verifying provenance

Every release from 1.6.0 on carries GitHub artifact attestations: SLSA build provenance that ties
each published jar, the catalog TOML and each npm tarball to the `release.yml` run and commit that
built it in `DominikSienkiewicz/Platform`. Verify a file you downloaded before you trust it:

```bash
npm pack @dominiksienkiewicz/versions@X.Y.Z
```

```bash
gh attestation verify dominiksienkiewicz-versions-X.Y.Z.tgz --repo DominikSienkiewicz/Platform
```

A Maven artifact works the same way, for example `platform-test-fixtures-X.Y.Z.jar` from the Gradle
cache (`~/.gradle/caches/modules-2/files-2.1/pl.seniordeveloper/`). A file without an attestation was
published before 1.6.0 or not by Platform's CI.

`platform-bump` checks the package it downloads this way before it uses it, for every target from
1.6.0 on: an attestation that does not verify stops the bump with nothing changed. Without `gh`
installed it only warns; `--skip-provenance "<reason>"` bumps anyway and logs the reason.

## Development environment

Copy [`infra/`](../infra) from Platform to the repository root; it runs Postgres with pgvector,
and optionally Ollama:

```bash
cp infra/.env.example infra/.env && (cd infra && docker compose up -d)
```

## Catalog bundles (*incubating*)

The catalog groups the Spring starters every product backend declares into three bundles. Their members
carry no version, so the Platform BOMs decide it, as before:

```kotlin
// Before: one line per starter, the same in every repository
implementation("org.springframework.boot:spring-boot-starter-actuator")
implementation("org.springframework.boot:spring-boot-starter-data-jpa")
implementation("org.springframework.boot:spring-boot-starter-validation")
implementation("org.springframework.boot:spring-boot-starter-webmvc")
implementation("org.springframework.modulith:spring-modulith-starter-core")
implementation("org.springframework.modulith:spring-modulith-starter-jpa")

// After
implementation(libs.bundles.modulith.web)
testImplementation(libs.bundles.modulith.web.tests) // actuator, data-jpa, validation and webmvc test starters
developmentOnly(libs.bundles.dev.docker.compose)    // spring-boot-docker-compose and Spring AI's
```

Keep any starter outside these lists on its own line. The bundles stay *incubating* until a first
backend adopts them; that pull request removes the label in README.md.

## Adopting the observability and web starters (*incubating*)

`implementation(libs.platform.observability.starter)` replaces the `management:` block most backends
write by hand: probes on, `health` and `info` exposed, details only when authorized, and an `application`
tag on every metric. Keep only what differs, such as `platform.observability.prometheus=true` where a
scraper reads `/actuator/prometheus` (BookOfStyling, Azimuth), and drop a separate
`micrometer-registry-prometheus` line, which the starter brings. `libs.bundles.observability.modulith`
adds the Spring Modulith actuator and observability modules.

`implementation(libs.platform.web.starter)` replaces a hand-written `@ControllerAdvice` for errors; the
shapes it answers with are in the [reference](reference.md#web-starter-incubating). An application with its
own `ResponseEntityExceptionHandler` keeps it, because the starter backs off. Both starters stay
*incubating* until the first application adopts them; that pull request removes the label in README.md.

## Adopting the security starter (*incubating*)

Add `implementation(libs.platform.security.starter)`, delete the application's own `SecurityConfig`, and
express its behaviour as properties. The two configurations the
starter was written from map like this:

| Application | Properties | Then |
|---|---|---|
| permit-all, stateless API with CORS (BookOfStyling) | `platform.security.mode=permit-all`, `platform.security.stateless=true`, `platform.security.csrf=false`, `platform.cors.allowed-origins=${app.cors.allowed-origins}` | delete `SecurityConfig` |
| authenticated with HTTP Basic (SkillSprintPlus) | none: these are the defaults | delete `SecurityConfig` |

Both variants are covered by `PlatformSecurityAutoConfigurationTest`, and the starter's chain takes
precedence over Spring Boot's default web security (`PlatformSecurityBootAutoConfigurationTest`). The
starter stays *incubating* until the first application adopts it; that pull request removes the label.

## Security starter CORS

`platform.cors.allowed-origins` opts into the Platform CORS source. The security
chain preserves Spring Security’s precedence for a user `CorsFilter` named `corsFilter`.
Otherwise it uses an explicit application source in preference to MVC infrastructure,
regardless of its bean name. Without an explicit source, MVC's existing CORS mapping
remains the fallback; without MVC or CORS configuration, the starter does not add a
CORS filter. An application-provided `SecurityFilterChain` still replaces the
Platform chain. Multiple explicit sources require an unambiguous primary source
or an application-owned chain; the starter does not silently choose one, and the context fails
to start without a `@Primary` one. `platform.cors.allowed-origins=*` fails at startup while
`allow-credentials` is `true`, the default: Spring rejects that pair, and before it did so only
on the first CORS request.

`platform.security.permitted-paths` replaces the default list instead of adding to it. Repeat
`/actuator/health`, `/actuator/health/**` and `/actuator/info` when you set it, or the deploy health
gate gets 401.

## Troubleshooting

Run `frontend/node_modules/.bin/platform-doctor` from the repository first (`--offline` skips the
GitHub Packages calls). It checks the preconditions below without changing anything, names each one
by its ID with the fix, and exits 1 when one fails. `--gradle` adds the checks only Gradle can make,
through the `platformDoctor` task of `seniordev.settings-conventions` (PD080-PD082), which also runs on
its own as `./gradlew platformDoctor`; resolving the toolchain may provision a JDK, as any build would:

| ID | Checks |
|---|---|
| PD001 | the command runs inside a git repository |
| PD010 | the `java` on PATH is 25 or newer, which Gradle needs to load Platform's plugins |
| PD011 | the Gradle wrapper exists and is executable |
| PD020 | every Platform pin (settings plugin, catalog, `platformVersion=`, `@dominiksienkiewicz/*`) is the same release |
| PD021 | the reusable workflow references are that exact release (`@v1` warns) |
| PD030 | where the GitHub Packages credentials come from (never their value) |
| PD031 | the pinned catalog resolves with them: 401, 403 and 404 each name their cause |
| PD040 | `frontend/.npmrc` points `@dominiksienkiewicz` at GitHub Packages |
| PD041 | Node is 22.13 or newer |
| PD042 | `frontend/package-lock.json` is committed, as `npm ci` needs |
| PD043 | npm resolves the pinned `@dominiksienkiewicz/versions` |
| PD050 | `.secrets.local` is ignored when the repository deploys |
| PD060 | `backend/Dockerfile` runs Java 27 or newer for a release with the 27 toolchain |
| PD070 | whether `AI_AGENT` is on |
| PD080 | (`platformDoctor`) the settings plugin, the catalog's `platform` version and `platformVersion` are the same release |
| PD081 | (`platformDoctor`) the root project's Java toolchain resolves to an installation |
| PD082 | (`platformDoctor`) `coverageMinimum` is a decimal between 0 and 1; unset warns, because the gate then accepts any coverage |
| PD083 | (`--gradle`) `./gradlew platformDoctor` ran at all; an older pin has no such task |

Gate failures carry a code, such as `[PLAT-DEP-001]`, and a link to its section of [gates.md](gates.md) at
the release that produced it.

| Symptom | Cause | Fix |
|---|---|---|
| `No GitHub Packages credentials, so the Platform plugins cannot resolve` | Neither `gpr.user`/`gpr.key` nor `GITHUB_ACTOR`/`GITHUB_TOKEN` is set, and there is no `-PplatformRepository` | Set `gpr.user` and `gpr.key` in `~/.gradle/gradle.properties` ([Prerequisites](#prerequisites)) |
| `Received status code 401 from server: Unauthorized` for `maven.pkg.github.com` | Gradle has no token, or the token lacks `read:packages` | Set `gpr.user` and `gpr.key` in `~/.gradle/gradle.properties` ([Prerequisites](#prerequisites)) |
| `UnsupportedClassVersionError` … `class file version 69.0` while the plugins load | Gradle runs on a JDK older than 25 | Run Gradle on JDK 25 or newer (`sdk env`, or `JAVA_HOME`) |
| `No matching toolchains found for requested specification` with `languageVersion=27` | No JDK 27 is installed or registered | Install a JDK 27 and register it with `org.gradle.java.installations.paths`; on glibc Linux avoid Foojay's Alpine build ([versions](versions.md)) |
| `Dependency versions outside the Platform canon (platformDependencyCheck)` | An explicit version differs from the catalog, or the library is not in it | Follow the action on each line: use the `libs.…` alias; for "the Platform BOMs manage it at …", drop the version (or override the BOM property, which `platformBomOverrideCheck` reports); for "no Platform BOM manages it", add the library to the catalog first |
| `The Platform pins diverge: seniordev.settings-conventions is …, platform-catalog is …` | `settings.gradle.kts` pins the settings plugin and the catalog to different releases | Run `scripts/platform-bump.sh <version>`, or read both pins from `platformVersion` as the [settings snippet](#backend) shows |
| `platformRuntimeImageCheck` … `Change the final FROM to the image in templates/Dockerfile.backend` | The Dockerfile runs an older Java than the toolchain | Use the final `FROM` of `templates/Dockerfile.backend` |
| `coverageMinimum=… needs JaCoCo execution data` | A coverage threshold is set, but no test task ran | Add tests to the module, or set `coverageMinimum=0` for it |
| `platform-versions-check: versions that differ from the Platform canon` | A frontend dependency differs from the canon named in the report's first line | In `frontend/`, `npx platform-versions-check --fix` rewrites the drift to the installed canon offline (then `npm install --package-lock-only`); to move to a newer canon, run the `scripts/platform-bump.sh <version>` the report prints from the repository root |
| npm `E401` or `E403` for `@dominiksienkiewicz/*` | `.npmrc` lacks the registry lines, or `GITHUB_TOKEN` is missing or lacks `read:packages` | Copy `templates/npmrc` to `frontend/.npmrc` and export the token |
| `No matching variant of pl.seniordeveloper:platform-catalog` | The release is incomplete in GitHub Packages | Pin the previous version and report it; see the idempotency rules in [RELEASING.md](../RELEASING.md) |
| `Dependency verification failed` after a bump | `gradle/verification-metadata.xml` misses checksums of the new versions | Run `scripts/platform-bump.sh` again; it regenerates the metadata in two passes |
| CI run ends with `startup_failure`, "is requesting 'packages: read', but is only allowed …" | The caller grants a reusable workflow fewer permissions than it requests | Grant the permissions listed in [reusable-workflows.md](reusable-workflows.md) |
