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
| `gradle/build-logic/` | convention pluginy `seniordev.{java,quality,spring-modulith}-conventions` + settings plugin `seniordev.settings-conventions` (foojay + repozytoria + task `platformDoctor`: PD080 piny, PD081 toolchain, PD082 `coverageMinimum`). Podział: `java` = Spotless/Checkstyle/JaCoCo+gate (`platformCoverageDataCheck`)/`platformDependencyCheck`/`platformRuntimeImageCheck` (ostatni `FROM` Dockerfile'a ≥ toolchain)/`platformPinCheck` (settings plugin i katalog z jednego wydania) + taski `lint` (bez testów) i `format`; `quality` = PIT/SpotBugs/CycloneDX/**SonarCloud**; `spring-modulith` = BOM-y + deps testowe + split testów |
| `gradle/catalog/` | publikowany version catalog `pl.seniordeveloper:platform-catalog` (+ **bundle'e**: `modulith-web`, `modulith-web-tests`, `dev-docker-compose` — zamiast powielanych inline starterów) |
| `gradle/bom/` | `pl.seniordeveloper:platform-bom` — java-platform z TEGO SAMEGO TOML-a: importy BOM-ów Boot/Modulith/AI/JUnit, podłogi CVE i nadpisania zgodności z `because` (ADR-0013: katalog = aliasy, BOM = ograniczenia); importują go test-fixtures i security-starter, conventions jeszcze nie (czeka na TestKit `dependencyInsight`). Lista modułów Maven: `gradle/maven-modules.txt` (czytają ją ci/release/skrypty, pilnuje `templates/tests/maven-modules.test.sh`) |
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` (Testcontainers — `PlatformSharedPostgresContainer` = jeden PostgreSQL na JVM poza kontekstem, bo Boot zamyka kontener-bean razem z kontekstem; `PlatformPostgresContainer` deprecated — + `AbstractTestcontainersFootprintTest` + bazy testów + guardy migracji Liquibase/Flyway (Liquibase także kontrakt nazw `NNNN-<slug>.yaml` z `deploy.yml`) + `AbstractSchemaValidationIT` (`ddl-auto=validate`; tabela Modulith z `templates/db/`) + `AbstractOpenApiContractTest` — spec ↔ kontrolery MVC, Decyzja 30 + taksonomia `@IntegrationTest`/`@ModelTest`/`@PostgresIntegrationTest` + `arch.PlatformArchRules`/`HexagonalRules` + `AbstractModulithDocumentationTest`) |
| `gradle/security-starter/` | `pl.seniordeveloper:platform-security-starter` — parametryzowalny SecurityFilterChain + CORS (`platform.security.*`/`platform.cors.*`, opt-in `@ConditionalOnMissingBean`) |
| `gradle/observability-starter/` | `pl.seniordeveloper:platform-observability-starter` — actuator + rejestr Prometheusa; domyślne `management.*` przez `EnvironmentPostProcessor` o NAJNIŻSZYM priorytecie (sondy, `health,info`, `when-authorized`, tag `application`); Prometheus opt-in `platform.observability.prometheus`, `public-metrics` dopisuje go do `platform.security.permitted-paths`; wariant `tracing` = `spring-boot-starter-opentelemetry` |
| `gradle/web-starter/` | `pl.seniordeveloper:platform-web-starter` — RFC 9457 Problem Details dla Spring MVC (400 z `errors[]` `{pointer, detail}`, 409 dla spring-dao, ogólne 500, `traceId` z MDC, `message` w 1.x); złoty `contracts/problem-detail.json` czyta też test api-client, snippet OpenAPI `contracts/problem-detail.openapi.yaml` |
| `frontend/packages/*` | `@dominiksienkiewicz/{tsconfig,eslint-config,prettier-config,tailwind-preset,vitest-config,ui,versions,openapi,api-client,query}` (`prettier-config` = Prettier + sortowanie klas Tailwind, wymagany `format:check` w strict `frontend-ci`; `openapi` = biny `platform-openapi-gen`/`platform-openapi-check` (typy z commitowanego specu, check w strict `frontend-ci`, gdy repo ma `platform.openapi`); `api-client` = wrapper fetch + typowany `createApiClient<paths>()`; `query` = QueryClient+provider — oba `private`, niepublikowane do pierwszego adoptera, ostatnie wydanie 1.5.31) |
| `frontend/packages/versions/` | **kanon wersji frontendu** (`versions.json`) + biny: `platform-versions-check` (guard w `frontend-ci`) oraz `platform-bump` (jedno źródło logiki bumpu platformy; repo wołają przez stub) i `platform-templates-check` (raport dryfu kopii z `templates/manifest.json` względem kanonu przypiętego wydania; tylko raport, exit 0; odpala go `platform-bump`) oraz `platform-workflows-check` (callerzy reusable workflowów kontra `workflow-contract.txt` — kopia snapshotu `templates/tests/fixtures/workflow-contract.txt`, równość pilnuje `test/workflows-check.test.sh`) i `platform-doctor` (diagnoza repo konsumenta, ID `PD0xx`, tylko odczyt; `--gradle` dokłada task `platformDoctor` (PD08x); każde ID ma wiersz w `docs/consuming.md` — pilnuje `test/doctor.test.sh`) |
| `.github/workflows/` | 11 reusable (`backend-ci`/`frontend-ci`/`sonar`/`scorecard`/`security-scan`/`semgrep`/`container-scan`/`deploy`/`roadmap-unblock`/`platform-bump` — kanał bumpu z Decyzji 5: bin + PR/`api-contract` — oasdiff na commitowanym specu, self-test w `ci.yml`) + własne: `ci`, `release` (publish na tag `vX.Y.Z`, patrz `RELEASING.md`), `cleanup-packages`, `self-scan` (Scorecard + Semgrep na samej Platform), `consumer-impact` (PR: `scripts/canon-diff.py` — wpływ na konsumentów + etykieta `consumer-action`), `upstream-canary` (tydzień: Gradle RC na starterze + obraz Temurin toolchainu; jedno issue na nogę, `scripts/upsert-issue.sh`), `ci-budget` (po CI: czas jobów kontra `.github/ci-budgets.json`, tylko ostrzeżenia; nowy job `ci.yml` = nowy budżet, pilnuje `templates/tests/ci-budget.test.sh`), `canon-cve-scan` (CVE w kanonie i BOM-ach; projekt `gradle/canon-probe`, reakcja: `docs/versions.md` „CVE response”) |
| `scripts/` | `deploy-remote.sh` — kanon logiki on-box deployu (scp+run przez `deploy.yml`); `changelog-section.sh` — sekcja wersji z `CHANGELOG.md` (dla `release.sh` i `release.yml`); `cleanup-packages.sh` — ręczne sprzątanie pakietów z wymaganym `--protect` i domyślnym dry-runem; `repo-settings.sh` — ustawienia GitHuba jako kod (`--check` tylko GET, `--apply` bez DELETE; rulesety w `.github/rulesets/`), uruchamia właściciel |
| `default.json` | preset Renovate (org) — tylko GitHub Actions i obrazy Docker; reguły kanonów Platform w `renovate.json` (pilnuje `templates/tests/renovate-config.test.sh`); `templates/` — kanon editorconfig/gitignore/Dockerfile/CODEOWNERS/PR/sdkmanrc + `bump-version.sh` (wersja warstwy app) + `platform-bump.sh` i `merge.sh` (stuby konsumenta — kopiowane do **`<repo>/scripts/`**, nie do roota; `platform-bump` dochodzi stamtąd do roota przez `cd "$(dirname "$0")/.."`, a pilnuje tego `templates/tests/platform-bump.test.sh`. Sama Platform trzyma `merge.sh` w roocie jako cienki wrapper `exec` na ten szablon — nie jest konsumentem) + `roadmap/` (kanon toolkitu roadmap→Issues/Projects v2, *experimental* — stabilny jest tylko kontrakt markera (Decyzja 11); repo konsumują `scripts/**` i formularz issue, trzymają tylko `roadmap-config.sh`) |

## Zasady (twarde)

1. **Wersje bibliotek/pluginów → `gradle/catalog`.** `build-logic` dołącza ten sam
   `libs.versions.toml` przez swoje `settings.gradle.kts`, więc marker-artefakty pluginów biorą wersje
   z kanonu — bump = JEDNO miejsce. Wersje narzucane przez ŹRÓDŁA convention pluginów (toolchain,
   checkstyle/jacoco/spotbugs/pitest, `googleJavaFormat`, BOM-y Spring/JUnit, archunit, lombok i nadpisania
   CVE) task `generatePlatformVersions` w build-logic generuje z katalogu do `PlatformVersions.kt`
   (`internal object`, źródła main) — precompiled script plugin nie czyta katalogu, więc zamiast lustra
   literałów czyta tę stałą (tabela: `docs/versions.md`, „Versions the convention plugins impose”).
   Literał wersji w źródle convention pluginu wywala `PlatformVersionsTest`. Lustra spoza Kotlina zostają:
   domyślny `toolchain-java-version` workflowów (`PlatformToolVersionMirrorTest`) i wrappery Gradle
   (`PlatformGradleVersionMirrorTest`).
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
   w czterech repo o wydanie dłużej, niż były potrzebne. Override, który wypadł z kanonu, usuwa u konsumenta
   migracja `every-drop-stale-overrides` przy każdym `platform-bump` (od wydania z migracjami, zob. niżej);
   wcześniej zostawał nietknięty, a guard zgłaszał „paczka bez wpisu w kanonie".
   **Migracje wydania** (`frontend/packages/versions/migrations/`): akcja konsumenta, którą da się wykonać
   automatycznie, dostaje idempotentną migrację `<SINCE>-<slug>.sh` (bez sieci, z testem before/after
   w `test/migrations/`), a jej wpis w CHANGELOG podaje slug albo „manual". `platform-bump` odpala runner
   z tarballa wydania DOCELOWEGO.
7. **Nadpisania ponad BOM-em Boota**: Boot 4.1.1 zarządza Netty 4.2.17.Final i PostgreSQL
   42.7.13 — usunięto starsze piny CVE. Nie przywracaj ich bez sprawdzenia BOM-a.
   Nadpisanie zgodności `lombok.version` 1.18.48 pozostaje, bo BOM ma 1.18.46 niezgodne
   z javac 27. Nadpisania CVE `tomcat.version` 11.0.27, `jackson-bom.version` 3.1.8
   i `jackson-2-bom.version` 2.21.8 wróciły, bo Boot 4.1.1 (najnowszy) zarządza podatnymi 11.0.24,
   3.1.5 i 2.21.5 — wykrył to `canon-cve-scan.yml`; wersje stoją tylko w katalogu (`PlatformVersions`),
   zdejmij je, gdy BOM Boota dojdzie do poprawek. `spring-modulith-core` 2.1.1 nadal ciągnie ArchUnit 1.4.2, więc zarządzana
   zależność ArchUnit 1.5.0 pozostaje na wszystkich konfiguracjach, także runtime.
   Usuń te nadpisania dopiero, gdy upstream zapewni zgodne wersje; zarządzanie ArchUnit na runtime
   pilnuje `PlatformToolVersionMirrorTest`. Polityka nadpisań (ostateczność, warunek usunięcia przy każdym):
   `docs/adr/0008-overrides-are-a-last-resort.md`; tag `integration` to kontrakt (ADR-0009), `AI_AGENT` — ADR-0010.
8. **SonarCloud żyje w `quality-conventions`** — repo NIE deklarują inline `id("org.sonarqube")` ani
   bloku `sonar{}`. `projectKey` per-repo przez property `sonarProjectKey` w `gradle.properties`
   (fallback `DominikSienkiewicz_<rootProject.name>`). Wersja pluginu = `sonarqube` w katalogu.
   Dotyczy też samej Platform (Decyzja 28): test-fixtures i security-starter aplikują quality-conventions,
   a job `sonar` w `ci.yml` skanuje je, gdy istnieje sekret `SONAR_TOKEN`.
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
- ❌ Nie wprowadzaj wersji biblioteki poza `catalog` (convention pluginy biorą ją z `PlatformVersions`).
- ❌ Nie commituj `public/r/` (output `shadcn build`) ani poświadczeń (`gpr.key`, tokeny).

## Język

Po polsku tylko CLAUDE.md oraz komentarze w kodzie i workflowach. Cała reszta po angielsku: README,
`docs/**`, RELEASING.md, README w `templates/**` i `infra/`, szablony PR, opisy paczek i inputów
workflowów, komunikaty bramek (Decyzja 8; README, sekcja „Documentation language”).

## Lokalne koncepcje

Nowe koncepcje, propozycje funkcji, plany i analizy zapisuj w ignorowanym
`docs/concepts/`. Utrzymywana dokumentacja techniczna oraz przyjęte ADR-y
pozostają wersjonowane w pozostałej części `docs/`.
