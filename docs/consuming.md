# Consuming the platform in a product repository

Everything below is what a consuming repository declares. Nothing here needs to be copied
into the platform itself. Every task, property and default the plugins add is listed in
[reference.md](reference.md).

## Prerequisites

- **JDK 25 or newer to run Gradle.** Platform's plugins are compiled for Java 25. Copy
  [`templates/.sdkmanrc`](../templates/.sdkmanrc) to the repository root and run `sdk env install`,
  or point `JAVA_HOME` at a JDK 25.
- **JDK 27 as the toolchain.** `seniordev.java-conventions` compiles for Java 27. Locally Foojay can
  provision it; otherwise register an installed JDK with `org.gradle.java.installations.paths`.
- **A classic personal access token with `read:packages`.** GitHub Packages requires
  authentication even for public packages, for both Maven and npm.
  - Gradle: in `~/.gradle/gradle.properties`, `gpr.user=<your GitHub login>` and
    `gpr.key=<the token>`.
  - npm: `export GITHUB_TOKEN=<the token>` in your shell profile.
  - CI: a repository secret `GPR_TOKEN` with the same token.

## Quickstart

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

- Backend: `./gradlew platformDependencyCheck` resolves the settings plugin and the catalog and runs
  the dependency governance; `./gradlew check` runs every gate.
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

`strict: true` requires nonempty `lint`, `typecheck`, `test` and `build` scripts and the
`@dominiksienkiewicz/versions` guard; `run-e2e: true` additionally requires `test:e2e`. Missing
checks fail the job instead of producing a successful partial pipeline. Existing callers without
`strict` keep the optional checks.

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

## Runtime image

`check` runs `platformRuntimeImageCheck`. It reads the final `FROM` of the project's
`Dockerfile`, or of the root project's in a multi-module build, and fails when that JVM image
runs an older Java than the toolchain the bytecode is compiled for (Java 27). Move the final
`FROM` to the image in [`templates/Dockerfile.backend`](../templates/Dockerfile.backend). A
build without a Dockerfile, a non-JVM image or an image taken from a build argument is skipped
with a log line. A repository-local test that compares the class-file version with the
Dockerfile is redundant once the consumer pins a Platform release that runs this gate.

## Coverage threshold

`check` runs `jacocoTestCoverageVerification` on the coverage of `test` and `integrationTest`
together. Set the threshold in the consumer's `gradle.properties`, for example
`coverageMinimum=0.80`. It is a decimal between 0 and 1 and defaults to 0.00; any other value
fails the build. The threshold is static: raise it yourself as coverage grows. `check` prints
the effective value (`Coverage gate: minimum=0.80 (source: coverageMinimum)`). When the
threshold is above 0, `platformCoverageDataCheck` fails `check` if neither test task produced
JaCoCo data, so a module without tests cannot pass the gate by being skipped.

## Agent resource profile

Only `AI_AGENT=1` or `AI_AGENT=true` opts in. Java test tasks use one fork, a 2 GiB
maximum heap and at most four cached Spring contexts. A shared Gradle build service
serializes test tasks across projects in the same build. This does not coordinate
separate Gradle invocations or agents: run the machine preflight before dispatching them.

Copy [`templates/agent-gradle.sh`](../templates/agent-gradle.sh) to
`scripts/agent-gradle.sh` and invoke `AI_AGENT=1 bash scripts/agent-gradle.sh <tasks>`.
It runs `./gradlew` from the repository root, or `backend/gradlew` from `backend/` when the
root has no wrapper. The launcher adds `--max-workers=2 --no-parallel` before Gradle starts. Settings plugins
cannot reliably resize services that Gradle already created. Without `AI_AGENT`, the
launcher passes through the ordinary Gradle defaults. The Vitest preset likewise caps
workers at two only in agent mode. See [HTTP client and frontend budget](http-client-and-agent-budget.md).

## Frontend

Install the packages with npm and commit `package-lock.json`: the reusable `frontend-ci` runs
`npm ci` and `platform-bump` refreshes the lockfile with npm, so a consumer on pnpm or Yarn fails
CI even though Platform builds its own packages with pnpm. Pin every `@dominiksienkiewicz/*`
package and every other dependency at the exact version the canon gives.

`tsconfig.json`:

```json
{ "extends": "@dominiksienkiewicz/tsconfig/next.json" }
```

`eslint.config.mjs`:

```js
export { default } from "@dominiksienkiewicz/eslint-config/next";
```

The config package declares `eslint`, `eslint-config-next` and `next` as peer
dependencies; take their versions from `@dominiksienkiewicz/versions`.

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

## Development environment

Copy [`infra/`](../infra) from Platform to the repository root; it runs Postgres with pgvector,
and optionally Ollama:

```bash
cp infra/.env.example infra/.env && (cd infra && docker compose up -d)
```

## Security starter CORS

`platform.cors.allowed-origins` opts into the Platform CORS source. The security
chain preserves Spring Security’s precedence for a user `CorsFilter` named `corsFilter`.
Otherwise it uses an explicit application source in preference to MVC infrastructure,
regardless of its bean name. Without an explicit source, MVC's existing CORS mapping
remains the fallback; without MVC or CORS configuration, the starter does not add a
CORS filter. An application-provided `SecurityFilterChain` still replaces the
Platform chain. Multiple explicit sources require an unambiguous primary source
or an application-owned chain; the starter does not silently choose one.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Received status code 401 from server: Unauthorized` for `maven.pkg.github.com` | Gradle has no token, or the token lacks `read:packages` | Set `gpr.user` and `gpr.key` in `~/.gradle/gradle.properties` ([Prerequisites](#prerequisites)) |
| `UnsupportedClassVersionError` … `class file version 69.0` while the plugins load | Gradle runs on a JDK older than 25 | Run Gradle on JDK 25 or newer (`sdk env`, or `JAVA_HOME`) |
| `No matching toolchains found for requested specification` with `languageVersion=27` | No JDK 27 is installed or registered | Install a JDK 27 and register it with `org.gradle.java.installations.paths`; on glibc Linux avoid Foojay's Alpine build ([versions](versions.md)) |
| `Dependency versions outside the Platform canon (platformDependencyCheck)` | An explicit version differs from the catalog, or the library is not in it | Follow the action on each line: use the `libs.…` alias, drop a BOM-managed version, or add the library to the catalog first |
| `platformRuntimeImageCheck` … `Change the final FROM to the image in templates/Dockerfile.backend` | The Dockerfile runs an older Java than the toolchain | Use the final `FROM` of `templates/Dockerfile.backend` |
| `coverageMinimum=… needs JaCoCo execution data` | A coverage threshold is set, but no test task ran | Add tests to the module, or set `coverageMinimum=0` for it |
| `platform-versions-check: DRYF wersji względem kanonu Platform` | A frontend dependency differs from the canon | From the repository root run `scripts/platform-bump.sh <version>` |
| npm `E401` or `E403` for `@dominiksienkiewicz/*` | `.npmrc` lacks the registry lines, or `GITHUB_TOKEN` is missing or lacks `read:packages` | Copy `templates/npmrc` to `frontend/.npmrc` and export the token |
| `No matching variant of pl.seniordeveloper:platform-catalog` | The release is incomplete in GitHub Packages | Pin the previous version and report it; see the idempotency rules in [RELEASING.md](../RELEASING.md) |
| `Dependency verification failed` after a bump | `gradle/verification-metadata.xml` misses checksums of the new versions | Run `scripts/platform-bump.sh` again; it regenerates the metadata in two passes |
| CI run ends with `startup_failure`, "is requesting 'packages: read', but is only allowed …" | The caller grants a reusable workflow fewer permissions than it requests | Grant the permissions listed in [reusable-workflows.md](reusable-workflows.md) |
