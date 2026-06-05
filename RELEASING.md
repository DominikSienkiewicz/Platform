# Releasing Platform

Artefakty wersjonowane **automatycznie**: każdy push do `main` zmieniający `gradle/**` lub
`frontend/packages/**` uruchamia `release.yml`, który nadaje wersję **`1.0.<run_number>`**
(major.minor z `gradle/build-logic/gradle.properties`, patch = numer runu — zawsze unikalny, więc
nigdy nie ma 409), publikuje Maven + npm i przycina do **3 najnowszych** wersji.

Reusable workflows w repo konsumenckich wskazują **`@v1`** (ruchomy tag majora w gicie — niezależny od
wersji artefaktów). Konsumenci trzymają DOKŁADNE piny artefaktów; Renovate je podbija.

## Setup jednorazowy

```bash
# 1) Sekret repo: PAT (classic) z read:packages + delete:packages — do pruningu pakietów konta.
#    Settings → Secrets and variables → Actions → New secret: PACKAGES_ADMIN_TOKEN
# 2) Ruchomy tag v1 dla reusable workflows konsumentów (raz):
git tag -f v1 && git push -f origin v1
```

## Codzienna praca (wydanie = push)

```bash
cd Platform
git add -A && git commit -m "feat: <zmiana platformy>"
git push        # release.yml: wersja 1.0.N → publish (Maven + npm) → prune (keep 3)
```

Lokalny smoke przed pushem (opcjonalnie, bez GitHuba):

```bash
./buildAndPublishLocal.sh && (cd ../SkillSprintPlus/backend && ./gradlew test)
```

## Bump major/minor

Patch jest automatyczny (run_number). Major/minor zmieniasz **tylko** w
`gradle/build-logic/gradle.properties` (`platformVersion=1.1.0` → kolejne release'y = `1.1.<run_number>`).

## Konsumenci (Attestate / SkillSprintPlus / BookOfStyling)

- Dokładne piny: `pl.seniordeveloper:catalog:1.0.X`, `id("seniordev.*-conventions") version "1.0.X"`,
  `@dominiksienkiewicz/*` (npm). Renovate (preset `default.json` + customManagery) otwiera PR-y
  podbijające je — powtarzalność zachowana (commit = znana wersja).
- CI (`ci.yml`) woła reusable `@v1`. Resolucja artefaktów: Gradle przez `GITHUB_ACTOR`/`GITHUB_TOKEN`
  (`secrets: inherit`), npm przez `${GITHUB_TOKEN}` w `.npmrc`. **Prywatne paczki cross-repo** mogą
  wymagać PAT (`read:packages`) jako sekret `gpr-token` przekazany do reusable.
- Renovate potrzebuje dostępu do prywatnego registry GitHub Packages (hostRules z tokenem
  `read:packages`) — inaczej nie zobaczy nowych wersji do bumpu.
- Lokalnie (bez GitHuba): `mavenLocal` + `npm run platform:link` (README „Local-first").

## Retencja pakietów

Przycinanie do **3 najnowszych** dzieje się w DWÓCH miejscach:
- `release.yml` (krok `prune`) — po każdym publish,
- `cleanup-packages.yml` — co 6h (siatka bezpieczeństwa / publish ręczne).

Oba wymagają sekretu `PACKAGES_ADMIN_TOKEN` (PAT classic: `read:packages` + `delete:packages`) —
automatyczny `GITHUB_TOKEN` NIE zarządza pakietami konta użytkownika. Filtr ogranicza czyszczenie do
pakietów Platform (`pl.seniordeveloper*`, `seniordev.*`, `@dominiksienkiewicz/*`).

⚠️ `keep=3` + auto-publish: pilnuj, by Renovate nadążał. Jeśli konsument pinuje wersję, która wypadnie
z top-3, zanim Renovate ją podbije — jego build straci zależność. Path-filter (publish tylko przy
realnej zmianie platformy) ogranicza częstotliwość; przy bardzo częstych zmianach rozważ `keep=5`.
