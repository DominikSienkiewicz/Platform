# CLAUDE.md — Platform (root)

Kontekst dla agentów AI. To repo to **współdzielona platforma** (build/jakość/wersje/frontend)
konsumowana przez osobne repo produktowe: Attestate, SkillSprintPlus, BookOfStyling.

## Czym to jest

Publikujemy wersjonowane artefakty do **GitHub Packages** (Maven + npm) i pnpm-owe paczki frontendu.
Cel: zlikwidować drift configów między repo, mając jedno źródło prawdy. Nie kopiuj configów — zmień tu,
opublikuj, podbij pin w repo konsumenta.

## Układ

| Katalog | Artefakt |
|---|---|
| `gradle/build-logic/` | convention pluginy `seniordev.{java,quality,spring-modulith}-conventions` + settings plugin `seniordev.settings-conventions` (foojay + repozytoria) |
| `gradle/catalog/` | publikowany version catalog `pl.seniordeveloper:platform-catalog` |
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` (Testcontainers + bazy testów) |
| `frontend/packages/*` | `@dominiksienkiewicz/{tsconfig,eslint-config,tailwind-preset,vitest-config,ui,versions}` |
| `frontend/packages/versions/` | **kanon wersji frontendu** (`versions.json`) + biny: `platform-versions-check` (guard w `frontend-ci`) oraz `platform-bump` (jedno źródło logiki bumpu platformy; repo wołają przez stub) |
| `.github/workflows/` | reusable CI (`backend-ci`/`frontend-ci`/`sonar`/`security-scan`/`scorecard`/`roadmap-unblock`/`deploy`) + publish na tag `v*` |
| `scripts/` | `deploy-remote.sh` — kanon logiki on-box deployu (scp+run przez `deploy.yml`) |
| `default.json` | preset Renovate (org); `templates/` — kanon editorconfig/gitignore/Dockerfile/CODEOWNERS/PR/sdkmanrc (logika `platform-bump` → bin pakietu `versions`) |

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
   Nowa biblioteka w repo = najpierw wpis w kanonie + `./release.sh`. Uwaga: kanon trzyma WERSJE — o tym,
   CZY repo używa danej biblioteki, decyduje repo (zasada 2 bez zmian).
7. **Nadpisania CVE nad BOM-em Boota** żyją w `spring-modulith-conventions` (propercje
   `tomcat.version`/`netty.version`/`postgresql.version` przez `ext`) — usuwaj przy bumpie Boota,
   gdy BOM dogoni fixy.

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
