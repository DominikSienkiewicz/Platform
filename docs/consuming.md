# Consuming the platform in a product repository

Everything below is what a consuming repository declares. Nothing here needs to be copied
into the platform itself.

## Backend

Start from [`templates/jvm/java-library`](../templates/jvm/java-library) for a pure
library or [`templates/jvm/spring-app`](../templates/jvm/spring-app) for a minimal
Spring application. These are the inputs to `PlatformConsumerFunctionalTest`, which
publishes the current plugins and catalog to an isolated local Maven repository and
then compiles, lints and tests consumers through Gradle TestKit. The Spring check
also packages `bootJar` and starts an application context. No database is needed.

Copy the selected directory to the product repository. Copy `gradlew`, `gradlew.bat`
and `gradle/wrapper/` from `gradle/catalog/` to give it the same pinned Gradle distribution.
The template is pinned to the latest Platform release: `release.sh` bumps its
`platformVersion` together with every other version file. Keep `platformVersion` in the
consumer's `gradle.properties` on an **already published** release. Add your own
package name, group and project name, then replace the example code. For these standalone
JVM layouts, update `platformVersion` directly; the existing `platform-bump` command
targets product repositories with `backend/` and `frontend/` directories.

The settings plugin and catalog read the same `platformVersion` property. The project
applies the Java / quality / Spring convention plugins without repeating a version:
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

For local Platform development, set `-PplatformRepository=file:///absolute/maven/repository`
explicitly. Both plugin resolution and ordinary dependencies put this repository before
remote repositories. For `publishToMavenLocal`, point it to your Maven local repository.
Without the property, resolution uses Maven Central / Gradle Plugin Portal and GitHub
Packages; provide `gpr.user` / `gpr.key` or `GITHUB_ACTOR` / `GITHUB_TOKEN` for private artifacts.
An authenticated remote lookup may still occur when an artifact is missing locally.

The reusable backend CI workflow uses its `gpr_token` secret when supplied, otherwise
its automatic `GITHUB_TOKEN`. Callers must allow `contents: read` and `packages: read`.
The token must also have access to Platform's packages: these scopes alone do not
provide access across repositories. Grant the consuming repository Actions read
access where the package registry supports it, or pass a `gpr_token` with
`read:packages` and access to Platform's private packages.

Pass `gradle-task` as one line of whitespace-separated task arguments, for example
`lint test :app:integrationTest :app:bootJar`. Wildcard characters are passed
literally to Gradle; the input does not interpret shell quoting or commands.

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
CI even though Platform builds its own packages with pnpm.

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

`src/app/globals.css`:

```css
@import "@dominiksienkiewicz/tailwind-preset/theme.css";
@import "tailwindcss";
@source "../../node_modules/@dominiksienkiewicz/ui";
```

Components from the private registry:

```bash
npx shadcn@latest add https://ui.seniordeveloper.pl/r/button.json
```

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

Postgres with pgvector, and optionally Ollama:

```bash
cp infra/.env.example infra/.env && (cd infra && docker compose up -d)
```

## Strict frontend CI

Existing callers retain optional checks. New consumers should opt into the complete
contract explicitly:

```yaml
jobs:
  frontend:
    uses: DominikSienkiewicz/Platform/.github/workflows/frontend-ci.yml@v1
    with:
      strict: true
```

Strict mode requires nonempty `lint`, `typecheck`, `test` and `build` scripts and the
`@dominiksienkiewicz/versions` guard. `run-e2e: true` additionally requires `test:e2e`.
Missing checks fail the job instead of producing a successful partial pipeline.

## Security starter CORS

`platform.cors.allowed-origins` opts into the Platform CORS source. The security
chain preserves Spring Security’s precedence for a user `CorsFilter` named `corsFilter`.
Otherwise it uses an explicit application source in preference to MVC infrastructure,
regardless of its bean name. Without an explicit source, MVC's existing CORS mapping
remains the fallback; without MVC or CORS configuration, the starter does not add a
CORS filter. An application-provided `SecurityFilterChain` still replaces the
Platform chain. Multiple explicit sources require an unambiguous primary source
or an application-owned chain; the starter does not silently choose one.
