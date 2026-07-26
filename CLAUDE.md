# CLAUDE.md — Platform (root)

Kontekst dla agentów AI. To repo to **współdzielona platforma** (build/jakość/wersje/frontend)
konsumowana przez osobne repo produktowe: Attestate, Azimuth, BookOfStyling, Pragma, SkillSprintPlus
(wszystkie 5 konsumują convention pluginy + katalog + kanon frontendu).

## Czym to jest

Publikujemy wersjonowane artefakty do **GitHub Packages** (Maven + npm) i pnpm-owe paczki frontendu.
Cel: zlikwidować drift configów między repo, mając jedno źródło prawdy. Nie kopiuj configów — zmień tu,
opublikuj, podbij pin w repo konsumenta.

## Układ

| Katalog | Artefakt |
|---|---|
| `gradle/build-logic/` | convention pluginy `seniordev.{java,quality,spring-modulith}-conventions` + settings plugin `seniordev.settings-conventions` (foojay + repozytoria). Podział: `java` = Spotless/Checkstyle/JaCoCo+gate/`platformDependencyCheck`; `quality` = PIT/SpotBugs/CycloneDX/**SonarCloud**; `spring-modulith` = BOM-y + deps testowe + split testów |
| `gradle/catalog/` | publikowany version catalog `pl.seniordeveloper:platform-catalog` (+ **bundle'e**: `modulith-web`, `modulith-web-tests`, `dev-docker-compose` — zamiast powielanych inline starterów) |
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` (Testcontainers + bazy testów + guardy migracji Liquibase/Flyway) |
| `gradle/security-starter/` | `pl.seniordeveloper:platform-security-starter` — parametryzowalny SecurityFilterChain + CORS (`platform.security.*`/`platform.cors.*`, opt-in `@ConditionalOnMissingBean`) |
| `frontend/packages/*` | `@dominiksienkiewicz/{tsconfig,eslint-config,tailwind-preset,vitest-config,ui,versions,api-client,query}` (`api-client` = wrapper fetch; `query` = QueryClient+provider) |
| `frontend/packages/versions/` | **kanon wersji frontendu** (`versions.json`) + biny: `platform-versions-check` (guard w `frontend-ci`) oraz `platform-bump` (jedno źródło logiki bumpu platformy; repo wołają przez stub) |
| `.github/workflows/` | reusable CI (`backend-ci`/`frontend-ci`/`sonar`/`security-scan`/`scorecard`/`roadmap-unblock`/`deploy`) + publish na tag `v*` |
| `scripts/` | `deploy-remote.sh` — kanon logiki on-box deployu (scp+run przez `deploy.yml`) |
| `default.json` | preset Renovate (org); `templates/` — kanon editorconfig/gitignore/Dockerfile/CODEOWNERS/PR/sdkmanrc + `bump-version.sh` (wersja warstwy app) + `roadmap/` (kanon toolkitu roadmap→Issues/Projects v2; repo konsumują `scripts/**`, trzymają tylko `roadmap-config.sh`) |

## Zasady (twarde)

1. **Wersje bibliotek/pluginów → `gradle/catalog`.** Jedyny wyjątek: BOM-y/narzędzia powielone w
   `build-logic` (oznaczone komentarzem "lustro gradle/catalog") — bo precompiled script plugin nie
   czyta zewnętrznego katalogu w czasie kompilacji. Bump = zmień OBA miejsca.
   **Egzekwowane**: task `platformDependencyCheck` (w `java-conventions`, wpięty w `check`) failuje
   build konsumenta, gdy zadeklarowana zależność ma jawną wersję spoza katalogu lub inną niż katalog.
   Bez wersji = zarządzane BOM-ami platformy (OK). Nowa biblioteka = najpierw wpis tu + `./release.sh`.
2. **Convention plugin nie dodaje zależności biznesowych** (security, jOOQ, resilience4j, modele AI).
   To deklaruje konsument przez `libs`. Convention = toolchain + jakość + taksonomia testów.
3. **`seniordev.spring-modulith-conventions` nie aplikuje pluginu Spring Boot** — robi to konsument
   (`alias(libs.plugins.spring.boot)`). Convention tylko importuje BOM-y + deps testowe + split testów.
4. **SpotBugs report-only** dopóki JDK 25 bytecode-support narzędzi nie jest zielony. Nie przełączaj
   `ignoreFailures=false` globalnie bez weryfikacji.
5. **GitHub Packages npm:** scope = nazwa ownera repo (lowercase). Zmiana ownera = zmiana scope + `.npmrc`.
6. **Wersje WSZYSTKICH zależności frontendu → `frontend/packages/versions/versions.json`**
   (frameworki, toolchain i zależności domenowe — tanstack, radix itd.). Konsumenci pinują EXACT
   (bez `^`/`~`); guard `platform-versions-check` w `frontend-ci` działa STRICT: zależność bez wpisu
   w kanonie albo z inną wersją = czerwony build. `platform-bump` (bin pakietu `versions`) nakłada kanon.
   Governance obejmuje `dependencies`, `devDependencies` **oraz `overrides`** (płaskie i zagnieżdżone,
   np. `overrides.next.postcss` — tam żyją piny CVE paczek transytywnych). Wyjątek: referencje npm
   w formie `"$nazwa"` (np. `"typescript": "$typescript"`) — rozwija je npm, guard i bump ich nie ruszają.
   Nowa biblioteka w repo = najpierw wpis w kanonie + `./release.sh`. Uwaga: kanon trzyma WERSJE — o tym,
   CZY repo używa danej biblioteki, decyduje repo (zasada 2 bez zmian).
7. **Nadpisania CVE nad BOM-em Boota** (propercje `tomcat.version`/`netty.version`/`postgresql.version`
   przez `ext` w `spring-modulith-conventions`) — **USUNIĘTE** przy bumpie na Boot 4.1.0 (BOM dogonił fixy).
   Przy kolejnym bumpie Boota sprawdź propercje BOM-a i dodaj pin tylko jeśli CVE wróci.
8. **SonarCloud żyje w `quality-conventions`** — repo NIE deklarują inline `id("org.sonarqube")` ani
   bloku `sonar{}`. `projectKey` per-repo przez property `sonarProjectKey` w `gradle.properties`
   (fallback `DominikSienkiewicz_<rootProject.name>`). Wersja pluginu = katalog + lustro `build-logic`.
9. **Bundle'e katalogu** grupują powielane startery (Boot/Modulith). Konsument: `libs.bundles.modulith.web`
   (+ `.tests`, + `dev.docker.compose`). Członkowie są `withoutVersion()` — wersje z BOM-ów.

## Wersjonowanie

Wszystkie artefakty = jeden `platformVersion` (build-logic `gradle.properties` + catalog `version("platform")`).
Publikacja na tag `vX.Y.Z`. Bump = jeden PR tu + bump pinu w repo konsumentach (Dependabot/Renovate).

**`./release.sh` wymaga message jako 1. argumentu** (Conventional Commits, po angielsku, zero atrybucji AI) —
bez niego skrypt odmawia (`Użycie: ./release.sh "commit message" [X.Y.Z] [-y]`). Formy:
- `./release.sh "fix: opis"` — patch +0.0.1 od aktualnej wersji
- `./release.sh "feat: opis" 1.2.0` — konkretna wersja
- `./release.sh "..." 1.2.0 -y` — pomiń potwierdzenie (lub `ASSUME_YES=1`)

## Czego NIE robić

- ❌ Nie dodawaj zależności domenowych do convention pluginów.
- ❌ Nie wprowadzaj wersji biblioteki poza `catalog` (poza udokumentowanym lustrem w build-logic).
- ❌ Nie commituj `public/r/` (output `shadcn build`) ani poświadczeń (`gpr.key`, tokeny).
