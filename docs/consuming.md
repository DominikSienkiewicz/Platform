# Consuming the platform in a product repository

Everything below is what a consuming repository declares. Nothing here needs to be copied
into the platform itself.

## Backend — `settings.gradle.kts`

`mavenLocal()` is listed first, so after `publishToMavenLocal` in the platform a consumer
builds against the local version without touching GitHub. The GitHub Packages repository is
added **only** when credentials are present (CI, or a local build that pushes), which keeps
an offline build from failing on an unreachable registry.

```kotlin
pluginManagement {
    repositories {
        mavenLocal()
        gradlePluginPortal()
        mavenCentral()
        val u = providers.gradleProperty("gpr.user").orElse(providers.environmentVariable("GITHUB_ACTOR")).orNull
        val k = providers.gradleProperty("gpr.key").orElse(providers.environmentVariable("GITHUB_TOKEN")).orNull
        if (u != null && k != null) maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/DominikSienkiewicz/Platform")
            credentials { username = u; password = k }
        }
    }
}
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}
dependencyResolutionManagement {
    repositories {
        mavenLocal()
        mavenCentral()
        val u = providers.gradleProperty("gpr.user").orElse(providers.environmentVariable("GITHUB_ACTOR")).orNull
        val k = providers.gradleProperty("gpr.key").orElse(providers.environmentVariable("GITHUB_TOKEN")).orNull
        if (u != null && k != null) maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/DominikSienkiewicz/Platform")
            credentials { username = u; password = k }
        }
    }
    versionCatalogs {
        create("libs") { from("pl.seniordeveloper:platform-catalog:1.0.0") }
    }
}
```

## Backend — `build.gradle.kts`

Only domain dependencies belong here. Toolchain, formatting, linting, the test split and
the BOMs all arrive with the convention plugins.

```kotlin
plugins {
    alias(libs.plugins.spring.boot)
    alias(libs.plugins.spring.dependency.management)
    id("seniordev.java-conventions") version "1.0.0"
    id("seniordev.quality-conventions") version "1.0.0"
    id("seniordev.spring-modulith-conventions") version "1.0.0"
}

group = "pl.seniordeveloper"
version = "0.0.1-SNAPSHOT"

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation(libs.resilience4j.spring.boot4)
    implementation(libs.bucket4j.core)
    implementation(libs.shedlock.spring)
    runtimeOnly("org.postgresql:postgresql")
}

pitest { targetClasses.set(listOf("pl.seniordeveloper.<module>.*")) }
```

A consumer's `build.gradle.kts` drops from roughly 80 lines to roughly 15 purely domain
ones.

## Frontend

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
