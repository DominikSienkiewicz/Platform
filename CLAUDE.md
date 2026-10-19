# CLAUDE.md — Platform (root)

Kontekst dla agentów AI. To repo to **współdzielona platforma** (build/jakość/wersje/frontend)
konsumowana przez osobne repo produktowe: Attestate (`Attestate_io`), Azimuth, BookOfStyling
(`BookOfStyling_com`), SkillSprintPlus (`SkillSprintPlus_com`), Touchstone (wszystkie 5 konsumują
convention pluginy + katalog; 4 z frontendem — bez Touchstone — także kanon frontendu). Lista = `scripts/consumers.txt`
(ta sama co sekcja Consumers w README); adopcję i piny pokazuje lokalny `scripts/consumer-audit.sh` (tylko GET).

## Czym to jest

Publikujemy wersjonowane artefakty do **GitHub Packages** (Maven + npm) i pnpm-owe paczki frontendu.
Cel: zlikwidować drift configów między repo, mając jedno źródło prawdy. Nie kopiuj configów — zmień tu,
opublikuj, podbij pin w repo konsumenta.

## Układ

| Katalog | Artefakt |
|---|---|
| `gradle/build-logic/` | convention pluginy `seniordev.{java,quality,spring-modulith}-conventions` + settings plugin `seniordev.settings-conventions` (foojay + repozytoria). Podział: `java` = Spotless/Checkstyle/JaCoCo+gate (`platformCoverageDataCheck`)/`platformDependencyCheck`/`platformRuntimeImageCheck` (ostatni `FROM` Dockerfile'a ≥ toolchain); `quality` = PIT/SpotBugs/CycloneDX/**SonarCloud**; `spring-modulith` = BOM-y + deps testowe + split testów |
| `gradle/catalog/` | publikowany version catalog `pl.seniordeveloper:platform-catalog` (+ **bundle'e**: `modulith-web`, `modulith-web-tests`, `dev-docker-compose` — zamiast powielanych inline starterów) |
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` (Testcontainers + bazy testów + guardy migracji Liquibase/Flyway) |
| `gradle/security-starter/` | `pl.seniordeveloper:platform-security-starter` — parametryzowalny SecurityFilterChain + CORS (`platform.security.*`/`platform.cors.*`, opt-in `@ConditionalOnMissingBean`) |
| `frontend/packages/*` | `@dominiksienkiewicz/{tsconfig,eslint-config,prettier-config,tailwind-preset,vitest-config,ui,versions,api-client,query}` (`prettier-config` = Prettier + sortowanie klas Tailwind, wymagany `format:check` w strict `frontend-ci`; `api-client` = wrapper fetch; `query` = QueryClient+provider — oba `private`, niepublikowane do pierwszego adoptera, ostatnie wydanie 1.5.31) |
| `frontend/packages/versions/` | **kanon wersji frontendu** (`versions.json`) + biny: `platform-versions-check` (guard w `frontend-ci`) oraz `platform-bump` (jedno źródło logiki bumpu platformy; repo wołają przez stub) i `platform-templates-check` (raport dryfu kopii z `templates/manifest.json` względem kanonu przypiętego wydania; tylko raport, exit 0; odpala go `platform-bump`) |
| `.github/workflows/` | 10 reusable (`backend-ci`/`frontend-ci`/`sonar`/`scorecard`/`security-scan`/`semgrep`/`container-scan`/`deploy`/`roadmap-unblock`/`platform-bump` — kanał bumpu z Decyzji 5: bin + PR) + własne: `ci`, `release` (publish na tag `vX.Y.Z`, patrz `RELEASING.md`), `cleanup-packages`, `self-scan` (Scorecard + Semgrep na samej Platform), `canon-cve-scan` (CVE w kanonie i BOM-ach; projekt `gradle/canon-probe`, reakcja: `docs/versions.md` „CVE response”) |
| `scripts/` | `deploy-remote.sh` — kanon logiki on-box deployu (scp+run przez `deploy.yml`); `changelog-section.sh` — sekcja wersji z `CHANGELOG.md` (dla `release.sh` i `release.yml`); `cleanup-packages.sh` — ręczne sprzątanie pakietów z wymaganym `--protect` i domyślnym dry-runem; `repo-settings.sh` — ustawienia GitHuba jako kod (`--check` tylko GET, `--apply` bez DELETE; rulesety w `.github/rulesets/`), uruchamia właściciel |
| `default.json` | preset Renovate (org) — tylko GitHub Actions i obrazy Docker; reguły kanonów Platform w `renovate.json` (pilnuje `templates/tests/renovate-config.test.sh`); `templates/` — kanon editorconfig/gitignore/Dockerfile/CODEOWNERS/PR/sdkmanrc + `bump-version.sh` (wersja warstwy app) + `platform-bump.sh` i `merge.sh` (stuby konsumenta — kopiowane do **`<repo>/scripts/`**, nie do roota; `platform-bump` dochodzi stamtąd do roota przez `cd "$(dirname "$0")/.."`, a pilnuje tego `templates/tests/platform-bump.test.sh`. Sama Platform trzyma `merge.sh` w roocie jako cienki wrapper `exec` na ten szablon — nie jest konsumentem) + `roadmap/` (kanon toolkitu roadmap→Issues/Projects v2, *experimental* — stabilny jest tylko kontrakt markera (Decyzja 11); repo konsumują `scripts/**` i formularz issue, trzymają tylko `roadmap-config.sh`) |

## Zasady (twarde)

1. **Wersje bibliotek/pluginów → `gradle/catalog`.** `build-logic` dołącza ten sam
   `libs.versions.toml` przez swoje `settings.gradle.kts`, więc marker-artefakty pluginów biorą wersje
   z kanonu — bump = JEDNO miejsce. Jedyny wyjątek: LUSTRA wersji w ŹRÓDŁACH convention pluginów
   (toolVersion checkstyle/jacoco/spotbugs, `googleJavaFormat("…")`, toolchain, pitest, wersje BOM-ów
   Spring/JUnit, lombok, archunit — pełna tabela w `docs/versions.md`, sekcja „Mirrored literals”) —
   precompiled script plugin nie czyta katalogu w czasie kompilacji, więc tam wersja stoi w kodzie
   i przy bumpie zmieniasz oba miejsca. Rozjazd wywala `PlatformToolVersionMirrorTest`
   / `PlatformCatalogMirrorTest` w build-logic.
   **Egzekwowane**: task `platformDependencyCheck` (w `java-conventions`, wpięty w `check`) failuje
   build konsumenta, gdy zadeklarowana zależność albo constraint ma jawną wersję spoza katalogu lub inną
   niż katalog — w każdym deklarowalnym kubełku (`api`/`implementation`/`compileOnly(Api)`/`runtimeOnly`/
   `annotationProcessor`, `developmentOnly`, `testAndDevelopmentOnly` i ich warianty `test*`/`testFixtures*`/
   własnych source setów), także dla artefaktów `pl.seniordeveloper`. Bez wersji = zarządzane BOM-ami
   platformy (OK). Komunikaty bramki są po angielsku i podają alias `libs.…` albo konkretną akcję.
   Nowa biblioteka = najpierw wpis tu + `./release.sh`. Po każdej zmianie tego, co moduły Platform pobierają
   (bump katalogu, nowa biblioteka, plugin): `scripts/write-verification-metadata.sh` — build-logic, test-fixtures
   i security-starter mają `gradle/verification-metadata.xml`, weryfikowane strict (docs/versions.md).
2. **Convention plugin nie dodaje zależności biznesowych** (security, jOOQ, resilience4j, modele AI).
   To deklaruje konsument przez `libs`. Convention = toolchain + jakość + taksonomia testów.
3. **`seniordev.spring-modulith-conventions` nie aplikuje pluginu Spring Boot** — robi to konsument
   (`alias(libs.plugins.spring.boot)`). Convention tylko importuje BOM-y + deps testowe + split testów.
4. **SpotBugs report-only** do spełnienia OBU kryteriów z `docs/adr/0005-spotbugs-report-only.md`:
   (1) SpotBugs czyta class-file toolchainu bez „Unsupported class file major version” — mierzy to
   TestKit w build-logic, spełnione 2026-10-18 dla JDK 27; (2) `spotbugsMain` każdego konsumenta
   przechodzi z `ignoreFailures=false`. Nie przełączaj `ignoreFailures=false` globalnie przed (2).
5. **GitHub Packages npm:** scope = nazwa ownera repo (lowercase). Zmiana ownera = zmiana scope + `.npmrc`.
6. **Wersje WSZYSTKICH zależności frontendu → `frontend/packages/versions/versions.json`**
   (frameworki, toolchain i zależności domenowe — tanstack, radix itd.). Konsumenci pinują EXACT
   (bez `^`/`~`); guard `platform-versions-check` w `frontend-ci` działa STRICT: zależność bez wpisu
   w kanonie albo z inną wersją = czerwony build. `platform-bump` (bin pakietu `versions`) nakłada kanon.
   Governance obejmuje `dependencies`, `devDependencies`, `optionalDependencies` **oraz `overrides`**
   (płaskie i zagnieżdżone, np. `overrides.openapi-typescript.js-yaml` — tam żyją piny CVE paczek
   transytywnych); `peerDependencies` aplikacji świadomie poza nią. Piny `@dominiksienkiewicz/*` poza
   `overrides` muszą być EXACT i równe wydaniu zainstalowanej paczki `versions`. Wyjątek:
   referencje npm w formie `"$nazwa"` (np. `"typescript": "$typescript"`) — rozwija je npm, guard
   i bump ich nie ruszają. Nowa biblioteka w repo = najpierw wpis w kanonie + `./release.sh`. Uwaga:
   kanon trzyma WERSJE — o tym, CZY repo używa danej biblioteki, decyduje repo (zasada 2 bez zmian).
   Własny workspace `frontend/` podlega tej samej zasadzie: `dependencies`/`devDependencies` każdej paczki
   = kanon, `eslint-config` i `ui` mają też dokładne peery, pozostałe peery to zakresy dopuszczające kanon
   (pilnuje `packages/versions/test/self-canon.test.mjs`; szczegóły w `docs/versions.md`).

   **Override to ostateczność, nie domyślne lekarstwo na CVE w tranzytywnej.** npm zostawia raz
   rozwiązaną paczkę tranzytywną na wersji z lockfile'a, dopóki ta spełnia zakres — caret, który
   *mógłby* sięgnąć po łatkę, po cichu tego nie robi, więc skan świeci na czerwono bez żadnego dryfu
   w manifeście. Domyślna naprawa to `npm update <paczka> --package-lock-only` + commit lockfile'a.
   Override zakładaj tylko wtedy, gdy rodzic pinuje DOKŁADNĄ podatną wersję (`@redocly/openapi-core`
   → `js-yaml@4.3.0`), i zdejmuj go, gdy upstream się naprawi — piny `postcss`/`sharp` przeżyły
   w czterech repo o wydanie dłużej, niż były potrzebne. Uwaga: `platform-bump` NIE usuwa override'a,
   który wypadł z kanonu — zostawia go nietkniętego, a guard zgłosi wtedy „paczka bez wpisu w kanonie".
   Kasowanie takiego pinu w konsumentach jest ręczne i musi iść w tym samym wydaniu co zmiana kanonu.
7. **Nadpisania ponad BOM-em Boota**: Boot 4.1.1 zarządza Netty 4.2.17.Final i PostgreSQL
   42.7.13 — usunięto starsze piny CVE. Nie przywracaj ich bez sprawdzenia BOM-a.
   Nadpisanie zgodności `lombok.version` 1.18.48 pozostaje, bo BOM ma 1.18.46 niezgodne
   z javac 27. Nadpisania CVE `tomcat.version` 11.0.27, `jackson-bom.version` 3.1.8
   i `jackson-2-bom.version` 2.21.8 wróciły, bo Boot 4.1.1 (najnowszy) zarządza podatnymi 11.0.24,
   3.1.5 i 2.21.5 — wykrył to `canon-cve-scan.yml`; lustra w katalogu pilnuje
   `PlatformCveOverrideMirrorTest`, zdejmij je, gdy BOM Boota dojdzie do poprawek. `spring-modulith-core` 2.1.1 nadal ciągnie ArchUnit 1.4.2, więc zarządzana
   zależność ArchUnit 1.5.0 pozostaje na wszystkich konfiguracjach, także runtime.
   Usuń te nadpisania dopiero, gdy upstream zapewni zgodne wersje. Lustra pilnuje
   `PlatformToolVersionMirrorTest`. Polityka nadpisań (ostateczność, warunek usunięcia przy każdym):
   `docs/adr/0008-overrides-are-a-last-resort.md`; tag `integration` to kontrakt (ADR-0009), `AI_AGENT` — ADR-0010.
8. **SonarCloud żyje w `quality-conventions`** — repo NIE deklarują inline `id("org.sonarqube")` ani
   bloku `sonar{}`. `projectKey` per-repo przez property `sonarProjectKey` w `gradle.properties`
   (fallback `DominikSienkiewicz_<rootProject.name>`). Wersja pluginu = `sonarqube` w katalogu.
9. **Bundle'e katalogu** grupują powielane startery (Boot/Modulith). Konsument: `libs.bundles.modulith.web`
   (+ `.tests`, + `dev.docker.compose`). Członkowie są `withoutVersion()` — wersje z BOM-ów.

## Wersjonowanie

Wszystkie artefakty = jeden `platformVersion` (build-logic `gradle.properties` + catalog `version("platform")`).
Ta sama wartość stoi w każdym `gradle/*/gradle.properties`, `templates/jvm/*/gradle.properties`
i `frontend/packages/*/package.json` — bumpuje je `release.sh`, a rozjazd albo `getOrElse("X.Y.Z")`
w skrypcie builda wywala `templates/tests/platform-version-sync.test.sh`. Placeholder `platform`
w `libs.versions.toml` jest celowo nierozwiązywalny.
Publikacja na tag `vX.Y.Z`. Bump = jeden PR tu + bump pinu w repo konsumentach przez `scripts/platform-bump.sh` albo reusable `platform-bump.yml` (Decyzja 5; preset Renovate obejmuje tylko GitHub Actions i obrazy Docker).

**Kontrakt wydania: `docs/adr/0002-release-and-versioning-contract.md`.** Akcja konsumenta = MINOR w linii
1.x, reszta = PATCH, MAJOR zarezerwowany. Notatki = `CHANGELOG.md`: każda wersja ma sekcję
`## [X.Y.Z] - YYYY-MM-DD` z obowiązkowym `### Consumer action required` (`None.`, gdy nic). Przed wydaniem
zmień `## [Unreleased]` na sekcję wersji i zmerguj to zwykłą drogą.

**`./release.sh` wymaga message jako 1. argumentu** (angielski Conventional Commit, zero atrybucji AI) —
trafia do BODY commita `chore(release): platform X.Y.Z` (`Użycie: ./release.sh "commit message" [X.Y.Z] [-y]`). Formy:
- `./release.sh "fix: opis"` — patch +0.0.1 od aktualnej wersji
- `./release.sh "feat: opis" 1.2.0` — konkretna wersja (obowiązkowa dla `feat`/`!:`/`BREAKING CHANGE`)
- `./release.sh "..." 1.2.0 -y` — pomiń potwierdzenie (lub `ASSUME_YES=1`)

Skrypt odmawia, gdy drzewo robocze nie jest czyste, gałąź ≠ `main`, `HEAD` ≠ `origin/main`, message nie jest
angielskim Conventional Commit, brakuje sekcji wersji w CHANGELOG albo patch miałby akcję konsumenta.
Commituje wyłącznie pliki wersji i tworzy annotated tag z treścią sekcji. `release.yml` publikuje dopiero po
zielonym CI (`verify` = `ci.yml`) na otagowanym commicie, a ruchomy `v1` przesuwa job `move-v1` (tylko do
przodu) — nie pchaj `v1` ręcznie. Ekstrakcja sekcji: `scripts/changelog-section.sh`; refusals pilnuje
`templates/tests/release-contract.test.sh`.

## Czego NIE robić

- ❌ Nie dodawaj zależności domenowych do convention pluginów.
- ❌ Nie wprowadzaj wersji biblioteki poza `catalog` (poza lustrami z tabeli w `docs/versions.md`).
- ❌ Nie commituj `public/r/` (output `shadcn build`) ani poświadczeń (`gpr.key`, tokeny).

## Język

Po polsku tylko CLAUDE.md oraz komentarze w kodzie i workflowach. Cała reszta po angielsku: README,
`docs/**`, RELEASING.md, README w `templates/**` i `infra/`, szablony PR, opisy paczek i inputów
workflowów, komunikaty bramek (Decyzja 8; README, sekcja „Documentation language”).

## Lokalne koncepcje

Nowe koncepcje, propozycje funkcji, plany i analizy zapisuj w ignorowanym
`docs/concepts/`. Utrzymywana dokumentacja techniczna oraz przyjęte ADR-y
pozostają wersjonowane w pozostałej części `docs/`.
