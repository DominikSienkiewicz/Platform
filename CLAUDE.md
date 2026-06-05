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
| `gradle/build-logic/` | convention pluginy `seniordev.{java,quality,spring-modulith}-conventions` |
| `gradle/catalog/` | publikowany version catalog `pl.seniordeveloper:catalog` |
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` (Testcontainers + bazy testów) |
| `frontend/packages/*` | `@dominiksienkiewicz/{tsconfig,eslint-config,tailwind-preset,vitest-config,ui}` |
| `.github/workflows/` | reusable CI (`backend-ci`/`frontend-ci`/`scorecard`) + publish na tag `v*` |
| `default.json` | preset Renovate (org); `templates/` — kanon editorconfig/gitignore/Dockerfile/CODEOWNERS/PR/sdkmanrc |

## Zasady (twarde)

1. **Wersje bibliotek/pluginów → `gradle/catalog`.** Jedyny wyjątek: BOM-y/narzędzia powielone w
   `build-logic` (oznaczone komentarzem "lustro gradle/catalog") — bo precompiled script plugin nie
   czyta zewnętrznego katalogu w czasie kompilacji. Bump = zmień OBA miejsca.
2. **Convention plugin nie dodaje zależności biznesowych** (security, jOOQ, resilience4j, modele AI).
   To deklaruje konsument przez `libs`. Convention = toolchain + jakość + taksonomia testów.
3. **`seniordev.spring-modulith-conventions` nie aplikuje pluginu Spring Boot** — robi to konsument
   (`alias(libs.plugins.spring.boot)`). Convention tylko importuje BOM-y + deps testowe + split testów.
4. **SpotBugs report-only** dopóki JDK 25 bytecode-support narzędzi nie jest zielony. Nie przełączaj
   `ignoreFailures=false` globalnie bez weryfikacji.
5. **GitHub Packages npm:** scope = nazwa ownera repo (lowercase). Zmiana ownera = zmiana scope + `.npmrc`.

## Wersjonowanie

Wszystkie artefakty = jeden `platformVersion` (build-logic `gradle.properties` + catalog `version("platform")`).
Publikacja na tag `vX.Y.Z`. Bump = jeden PR tu + bump pinu w repo konsumentach (Dependabot/Renovate).

## Czego NIE robić

- ❌ Nie dodawaj zależności domenowych do convention pluginów.
- ❌ Nie wprowadzaj wersji biblioteki poza `catalog` (poza udokumentowanym lustrem w build-logic).
- ❌ Nie commituj `public/r/` (output `shadcn build`) ani poświadczeń (`gpr.key`, tokeny).
