# Platform — współdzielona platforma dla repo organizacji

Jedyne źródło prawdy dla **konfiguracji buildu, jakości, wersji i frontendu**, konsumowane przez
osobne repozytoria produktowe (**Attestate**, **SkillSprintPlus**, **BookOfStyling**, kolejne).

Powód istnienia: trzy repo wyrosły z jednego szablonu i się rozjechały (drift). Zamiast kopiować
configi między repo, **publikujemy wersjonowane artefakty** i konsumujemy je jak każdą zależność.
To jedyna czysta droga cross-repo — `buildSrc` / composite build działają tylko wewnątrz jednego repo.

> Registry docelowe: **GitHub Packages** (Maven + npm). Frontend: **pnpm workspaces**.

---

## Co tu jest

| Ścieżka | Artefakt | Publikacja |
|---|---|---|
| `gradle/build-logic/` | 3 convention pluginy (`seniordev.*-conventions`) | GitHub Packages (Maven) |
| `gradle/catalog/` | publikowany version catalog (`pl.seniordeveloper:platform-catalog`) | GitHub Packages (Maven) |
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` (Testcontainers + bazy testów) | GitHub Packages (Maven) |
| `frontend/packages/tsconfig/` | `@dominiksienkiewicz/tsconfig` | GitHub Packages (npm) |
| `frontend/packages/eslint-config/` | `@dominiksienkiewicz/eslint-config` | GitHub Packages (npm) |
| `frontend/packages/tailwind-preset/` | `@dominiksienkiewicz/tailwind-preset` (CSS-first `@theme`) | GitHub Packages (npm) |
| `frontend/packages/ui-registry/` | `@dominiksienkiewicz/ui` — prywatne shadcn registry | GitHub Packages + HTTP JSON |
| `frontend/packages/vitest-config/` | `@dominiksienkiewicz/vitest-config` (jsdom + Testing Library) | GitHub Packages (npm) |
| `infra/` | szablon `docker-compose` (pgvector + Ollama opcjonalnie) | kopiowalny / submodule |
| `.github/workflows/` | **reusable CI** (`backend-ci`, `frontend-ci`, `sonar`, `scorecard`) + **security** (`security-scan` SBOM+Grype, `semgrep` SAST, `container-scan` Grype+Snyk) + publish-gradle/npm | wołane przez repo `uses: …@v1` |
| `default.json` | **preset Renovate** organizacji | repo: `extends: github>DominikSienkiewicz/Platform` |
| `templates/` | kanon `.editorconfig` / `.gitignore` / `Dockerfile.backend` (SoT — sync ręczny) | kopiowane do repo |

### Convention pluginy

| Plugin | Co wnosi | Skąd 1:1 |
|---|---|---|
| `seniordev.java-conventions` | toolchain 26, Spotless (Google Java Format), Checkstyle (maxWarnings=0), JaCoCo (pokrycie sumowane z `test` **i** `integrationTest`) + bramka z **ratchetem** | BookOfStyling |
| `seniordev.quality-conventions` | PIT (mutation), SpotBugs (report-only na JDK25), CycloneDX (SBOM) | BookOfStyling / SkillSprintPlus |
| `seniordev.spring-modulith-conventions` | BOM-y (Boot/Modulith/Spring AI **GA**), wspólne deps testowe (Modulith-test, Testcontainers, ArchUnit), **enforced junit-bom**, **taksonomia unit ‖ integration** | Attestate (split) + SkillSprintPlus (junit pin) |

---

## Co naprawia względem stanu obecnego

| Problem w repo | Gdzie był | Fix w platformie |
|---|---|---|
| `resilience4j-spring-boot3` na Spring Boot 4 | SkillSprintPlus | catalog: `resilience4j-spring-boot4:2.4.0` |
| Spring AI na milestone `2.0.0-M8` | wszystkie 3 | catalog + convention: `springAi = 2.0.0` (GA) |
| Brak ESLint na FE | BookOfStyling | `@dominiksienkiewicz/eslint-config` (core-web-vitals + ts) |
| Drift formatera (googleJavaFormat ‖ sam importOrder ‖ brak) | wszystkie 3 | jeden `seniordev.java-conventions` |
| `@types/node` ^24 ‖ ^25 | SkillSprintPlus vs reszta | ujednolicone przez konsumpcję wspólnego tsconfig |

---

## Bootstrap (lokalnie)

Wymagania dla frontendu: Node.js >= 22.13 (repo używa Node 24) oraz pnpm 11.18.0.

```bash
# Gradle — publikacja do lokalnego repo (smoke test bez registry):
cd gradle/build-logic && ./gradlew publishToMavenLocal
cd ../catalog        && ./gradlew publishToMavenLocal

# Frontend:
cd frontend && pnpm install
pnpm --filter @dominiksienkiewicz/ui build   # generuje public/r/*.json (shadcn)
```

Do publikacji na GitHub Packages ustaw poświadczenia (lokalnie w `~/.gradle/gradle.properties`):

```properties
gpr.user=TWOJ_GITHUB_LOGIN
gpr.key=ghp_xxx   # PAT z zakresem read:packages / write:packages
gpr.owner=DominikSienkiewicz
gpr.repo=Platform
```

Dla publikacji paczek frontendu pnpm 11 wymaga tokenu w zaufanym `~/.npmrc`
(nie w commitowanym `frontend/.npmrc`):

```properties
//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
```

> ⚠️ Dla **GitHub Packages npm** scope (`@dominiksienkiewicz`) musi równać się właścicielowi repo
> GitHub (lowercase). Jeśli owner jest inny — zmień scope w paczkach i `.npmrc`.

---

## Konsumpcja w repo produktowym (Attestate / SkillSprintPlus / BookOfStyling)

### Backend — `backend/settings.gradle.kts`

```kotlin
// LOCAL-FIRST: mavenLocal() wygrywa (po `publishToMavenLocal` w Platform → build bierze lokalne,
// bez GitHuba). GitHub Packages dodawany TYLKO gdy są poświadczenia (CI / build z pushem).
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
        create("libs") { from("pl.seniordeveloper:platform-catalog:1.0.0") }   // współdzielony katalog
    }
}
```

### Backend — `backend/build.gradle.kts` (przykład: SkillSprintPlus)

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
    // tylko zależności DOMENOWE tego repo — toolchain/format/lint/test-split/BOM-y w convention plugins
    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation(libs.resilience4j.spring.boot4)   // FIX: poprawny wariant SB4
    implementation(libs.bucket4j.core)
    implementation(libs.shedlock.spring)
    runtimeOnly("org.postgresql:postgresql")
}

pitest { targetClasses.set(listOf("pl.seniordeveloper.skillsprintplus.*")) }
```

`backend/build.gradle.kts` kurczy się z ~80 linii do ~15 czysto domenowych.

### Frontend

`tsconfig.json`:

```json
{ "extends": "@dominiksienkiewicz/tsconfig/next.json" }
```

`eslint.config.mjs`:

```js
export { default } from "@dominiksienkiewicz/eslint-config/next";
```

Pakiet konfiguracyjny wymaga peer dependencies `eslint`, `eslint-config-next` i `next`;
ich wersje należy pobierać z `@dominiksienkiewicz/versions`.

`src/app/globals.css`:

```css
@import "@dominiksienkiewicz/tailwind-preset/theme.css";
@import "tailwindcss";
@source "../../node_modules/@dominiksienkiewicz/ui";
```

Komponenty z prywatnego registry:

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

Środowisko dev (Postgres+pgvector, opcjonalnie Ollama):

```bash
cp infra/.env.example infra/.env && (cd infra && docker compose up -d)
```

---

## Local-first vs GitHub (build lokalny bez GitHuba)

Model: **lokalnie biorę z wersji zbudowanej lokalnie; po pushu/na CI z artefaktów na GitHubie.**

| Warstwa | Lokalnie (bez GitHuba) | CI / push |
|---|---|---|
| Gradle (pluginy + catalog) | `mavenLocal()` jest pierwszy → po `publishToMavenLocal` build bierze lokalne. Repo GitHub **nie jest nawet dodawane**, gdy brak `gpr.user/gpr.key`. | są `GITHUB_ACTOR`/`GITHUB_TOKEN` → repo GitHub Packages dodane jako fallback. |
| npm (paczki FE) | `npm run platform:link` → symlink do `../../Platform/frontend/packages/*` (żywe źródło lokalne). | deps z registry `^1.0.0` (`.npmrc` scope → GitHub Packages). |

```bash
# Raz, w Platform — buduje i publikuje lokalnie (Gradle → mavenLocal, frontend → pnpm install):
./buildAndPublishLocal.sh                  # (--skip-frontend / --with-registry / --help)
# W repo konsumenta (FE) — lokalne paczki zamiast registry:
npm run platform:link     # przed pracą lokalną
npm run platform:unlink   # przed commitem (wraca na wersje z registry)
```

> Gradle local-first jest **automatyczny** (kolejność repo + brak creds = brak GitHuba).
> npm nie ma natywnego „local-first→fallback", więc lokalnie używamy `npm link` (albo Verdaccio
> dla pełnej transparentności). CI publikuje/konsumuje z GitHub Packages.

---

## Gdzie żyją wersje (po dedupie)

`gradle/catalog/libs.versions.toml` jest jedynym miejscem, w którym deklarujesz wersję biblioteki lub
pluginu. `gradle/build-logic` **dołącza ten sam plik** przez swoje `settings.gradle.kts`
(`versionCatalogs { create("libs") { from(files("../catalog/libs.versions.toml")) } }` — z pliku, bo
opublikowany artefakt `platform-catalog` w czasie kompilacji build-logic jeszcze nie istnieje), więc
marker-artefakty pluginów na classpath build-logic biorą wersje wprost z kanonu. Bump = **jedno miejsce**.

Została jedna, węższa duplikacja: `toolVersion` w ŹRÓDŁACH convention pluginów
(`checkstyle`/`jacoco` w `java-conventions`, `spotbugs` w `quality-conventions`). Precompiled script plugin
nie czyta katalogu w czasie kompilacji, więc te wartości muszą stać w kodzie. Kanon trzyma odpowiedniki
`checkstyle` i `jacoco` — przy ich bumpie zmieniasz oba miejsca. `spotbugs` (toolVersion `4.9.8`) wpisu
w kanonie nie ma; `spotbugsPlugin` to wersja pluginu Gradle, nie samego SpotBugs.

> **Dependency locking:** `gradle/build-logic`, `gradle/test-fixtures` i `gradle/security-starter` mają
> `gradle.lockfile` (powtarzalne rozwiązywanie zależności). Po bumpie którejkolwiek wersji w tych modułach
> **zregeneruj lockfile**: `cd gradle/<moduł> && ./gradlew dependencies --write-locks` i zacommituj diff.
> `gradle/catalog` trzyma lockfile pusty i **napisany ręcznie**: moduł `version-catalog` nie ma
> rozwiązywalnej konfiguracji, więc `--write-locks` kończy się sukcesem, ale pliku nie tworzy. Plik istnieje
> po to, żeby każdy moduł Gradle w repo miał lockfile — nie regeneruj go, nie ma czego zablokować.

---

## Sekwencja rolloutu (niskie ryzyko)

1. **catalog** → `publishToMavenLocal`/registry → podłącz 3 repo (od razu fix Spring AI + resilience4j).
2. **`java-conventions`** → pilotaż na **BookOfStyling** (ma już komplet narzędzi) → potem reszta.
3. Frontend: `tsconfig` + `eslint-config` → `tailwind-preset` → `ui-registry`.

Każdy krok = osobny PR per repo, semver, rollback = pin starej wersji.
