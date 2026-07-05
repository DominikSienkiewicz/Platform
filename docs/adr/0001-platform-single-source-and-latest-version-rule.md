# ADR-0001: Platform jako jedyne źródło współdzielonych artefaktów + reguła „najnowsza-w-portfolio"

## Status

Accepted — 2026-07-05

## Kontekst

Portfolio to pięć repo produktowych (Attestate, Azimuth, BookOfStyling, Pragma, SkillSprintPlus) konsumujących współdzielone repo **Platform**. Platform publikuje już convention pluginy Gradle (`seniordev.*`), version catalog (`pl.seniordeveloper:platform-catalog`), test-fixtures (`platform-test-fixtures`) oraz paczki npm frontendu (`@dominiksienkiewicz/*`).

Mimo to audyt (2026-07) wykazał, że część elementów była nadal kopiowana „w tle" między repo — z realnym dryfem wersji:

- pin Platformy w **4 wariantach**: `1.3.5` / `1.3.12` / `1.4.1` / `1.4.3`,
- Gradle wrapper w **3**: `9.3.1` / `9.5.1` / `9.6.1` (w tym sama Platform za konsumentami),
- Sonar plugin w **2**: `7.2.3.7755` (Pragma) vs `7.3.1.8318`,
- Node (frontend Dockerfile) w **2**: `22-slim` vs `24-alpine`.

Repo forkowały też skrypty, które Platform już serwuje: SkillSprintPlus trzymał martwy `scripts/deploy-remote.sh`, mimo że reusable `deploy.yml@v1` dostarcza kanon; `platform-bump.sh` miał 3 różne wersje (BoS/SSP nadal z grubą logiką przeniesioną wcześniej do bina `@dominiksienkiewicz/versions`); Azimuth ręcznie odtworzył `PlatformPostgresContainer`, dryfując obraz na `pgvector/pgvector:pg16` zamiast kanonicznego `:0.8.2-pg18`.

Dryf wersji między repo to **koszt bez korzyści**: rozbieżny graf zależności, niepowtarzalne buildy, klasa błędów „u mnie działa".

## Decyzja

1. **Każdy element powielany między ≥2 repo jest wynoszony do Platform i konsumowany** (catalog / convention plugin / test-fixtures / paczka npm / template) — nigdy kopiowany. Fork skryptu/configu, który Platform już posiada, jest traktowany jak dług do usunięcia.
2. **Reguła najnowszej-w-portfolio:** gdy to samo narzędzie/biblioteka ma różne wersje między repo, obowiązuje **najnowsza**. Ląduje w Platform jako jedyne źródło (catalog / `versions.json` / mirror build-logic), a wszystkie repo konsumują ją przez pin Platformy. Wyjątki muszą być **udokumentowane** (np. toolchain `build-logic` celowo na Java 25 — spójność targetu Kotlin/Java, patrz komentarz w `gradle/build-logic/build.gradle.kts`).
3. **Zmiany wersji spływają przez release Platformy + `platform-bump` w repo** — nie przez ręczny edit per-repo. Nowa biblioteka = najpierw wpis w Platform + `./release.sh`, dopiero potem `platform-bump.sh` w konsumencie.

## Zakres wdrożenia — P0 (2026-07-05)

| Obszar | Akcja | Repo |
| --- | --- | --- |
| Re-sync forków | `platform-bump.sh` → template (5/5 identyczne) | Attestate, Azimuth, BoS, SSP |
| | usunięto osierocony `deploy-remote.sh` | SSP |
| | `backend/Dockerfile` → `templates/Dockerfile.backend` | Azimuth, SSP |
| | `setup-gh-deploy.sh` (ujednolicona nazwa) + usunięto stare warianty | BoS, SSP |
| | `merge.sh`, `.secrets.local.example` → template | Azimuth, BoS |
| Reguła najnowszej wersji | pin Platformy → `1.4.3` | 5 repo (settings + FE) |
| | Gradle wrapper → `9.6.1` | 5 repo + Platform (build-logic/catalog/test-fixtures) |
| | Sonar → `7.3.1.8318` | Pragma |
| | Java toolchain → `26` | Pragma |
| | Node (FE Docker) → `24-slim` | Azimuth |
| Konsumpcja fixtures | `libs.platform.test.fixtures` + `@Import(PlatformPostgresContainer)` (koniec `pg16`) | Azimuth |
| Kanon FE | carety → EXACT; `react-hook-form`/`react-markdown`/`remark-gfm` dodane do `versions.json` | Pragma + Platform |

## Świadome wyłączenia (nie P0)

- **Attestate → `tailwind-preset`:** nie jest drop-in — preset nie ma tokenów `--popover` ani bloku `@theme inline`, ma inny dark `--primary` i dokłada `--color-brand`/fonty. Najpierw harmonizacja presetu (zmiana w Platform + release), potem migracja.
- **Pragma inline Spring AI `2.0.0-M2` / Modulith `2.0.3`:** stale vs katalog; bump wchodzi razem z migracją Pragmy na convention pluginy (P1) — nie na ślepo (ryzyko API-break milestone→GA).
- **`lucide-react 0.577 → 1.17` (Pragma):** major bump zgodny z regułą, wymaga smoke-testu ikon.
- **`.sdkmanrc` `25` vs toolchain `26`:** wartość jednolita między repo (nie dryf *między projektami*); decyzja `25↔26` osobno (dostępność Temurin 26).

## Konsekwencje

- (+) Jeden graf zależności, powtarzalne buildy, mniejsza powierzchnia forka.
- (+) Governance wymuszony narzędziowo: `platformDependencyCheck` (Gradle) i `platform-versions-check` (npm) failują build przy wersji spoza kanonu.
- (−) Zmiana wersji wymaga cyklu **release + bump** — świadomy koszt za spójność.
- (−) Pin repo bywa chwilowo za publikowanym HEAD Platformy (normalny flow, domykany przez Renovate/`platform-bump`).

## Następne (P1)

Bundle'e version-catalogu (kręgosłup web+modulith powielany w 4 konsumentach), Sonar wyniesiony do `seniordev.quality-conventions` (koniec inline `id("org.sonarqube")` + bloków `sonar{}`), paczki `@dominiksienkiewicz/api-client` (4 zdryfowane wrappery fetch) i `@dominiksienkiewicz/query` (współdzielony QueryClient + provider).
