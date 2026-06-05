# Releasing Platform

Artefakty wersjonowane **deliberate**: jedna wersja w `gradle/build-logic/gradle.properties`
(`platformVersion`) — ta sama lokalnie (mavenLocal), na GitHub Packages i w pinach konsumentów.
`release.yml` publikuje **tę** wersję, wyzwalany **świadomie** (tag `v*` lub workflow_dispatch),
publikuje Maven + npm i przycina do **3 najnowszych**. Bump = zmiana `platformVersion` + tag.
(Auto-bump na każdy push został wycofany — kłócił się z dokładnymi pinami + local-first + keep-3.)

Reusable workflows w repo konsumenckich wskazują **`@v1`** (ruchomy tag majora w gicie — niezależny od
wersji artefaktów). Konsumenci trzymają DOKŁADNE piny artefaktów; Renovate je podbija.

## Setup jednorazowy

```bash
# 1) Sekret repo: PAT (classic) z read:packages + delete:packages — do pruningu pakietów konta.
#    Settings → Secrets and variables → Actions → New secret: PACKAGES_ADMIN_TOKEN
# 2) Ruchomy tag v1 dla reusable workflows konsumentów (raz):
git tag -f v1 && git push -f origin v1
```

## Wydanie (świadome)

```bash
cd Platform
# 1) bump platformVersion w 3 plikach gradle.properties (build-logic, catalog, test-fixtures)
#    + version("platform", ...) w gradle/catalog/build.gradle.kts   (lustro)
git add -A && git commit -m "release: platform X.Y.Z" && git push
# 2) wyzwól publikację (jedno z dwóch):
git tag vX.Y.Z && git push origin vX.Y.Z        # albo: Actions → Release → Run workflow
git tag -f v1  && git push -f origin v1          # przesuń ruchomy major dla reusable workflows
```

Pierwsza publikacja `1.0.0`: bez bumpu — po prostu **Actions → Release → Run workflow** (weźmie
`platformVersion=1.0.0` z gradle.properties i opublikuje na GitHub Packages).

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
