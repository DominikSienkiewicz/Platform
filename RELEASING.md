# Releasing Platform

Wersjonowanie: jeden `platformVersion` (build-logic + catalog + test-fixtures). Wydanie = tag `vX.Y.Z`.
Reusable workflows w repo konsumenckich wskazują **`@v1`** (ruchomy tag majora) — utrzymuj go obok release'u.

## 1. Commit (tag musi wskazywać commit ZE zmianami)

```bash
cd Platform
git add -A
git commit -m "feat: platform 1.0.0 (build-logic, catalog, test-fixtures, FE packages, reusable CI, renovate)"
```

## 2. (Opcjonalnie) smoke lokalny — bez GitHuba

```bash
./buildAndPublishLocal.sh            # publishToMavenLocal + pnpm install
```

## 3. Tag + push

```bash
git tag -a v1.0.0 -m "Platform 1.0.0"   # release → triggeruje publish-gradle + publish-npm
git tag -f v1                            # ruchomy major → na niego wskazują callery CI konsumentów
git push origin main --follow-tags
git push -f origin v1
```

Tag `v1.0.0` uruchamia `.github/workflows/publish-{gradle,npm}.yml` → artefakty lądują w GitHub Packages
(Maven: convention plugins + catalog + test-fixtures; npm: 5 paczek `@dominiksienkiewicz/*`).

## 4. Konsumenci (Attestate / SkillSprintPlus / BookOfStyling)

- Commit + push własnych zmian (migracja na platformę).
- CI (`ci.yml`) woła reusable `@v1` i resolvuje artefakty:
  - Gradle: `GITHUB_ACTOR`/`GITHUB_TOKEN` (z `secrets: inherit`). **Prywatne paczki cross-repo** mogą
    wymagać PAT (`read:packages`) jako sekret `gpr-token` przekazany do reusable workflow — automatyczny
    `GITHUB_TOKEN` nie zawsze czyta pakiety innego repo.
  - npm: `.npmrc` (`${GITHUB_TOKEN}`) — ten sam warunek.
- Lokalnie (bez GitHuba): `mavenLocal` + `npm run platform:link` (patrz README „Local-first").

## 5. Kolejne wydania

```bash
# bump platformVersion w: gradle/build-logic/gradle.properties, gradle/catalog/gradle.properties,
#                         gradle/test-fixtures/gradle.properties, version("platform", ...) w catalog
git commit -am "chore: platform 1.0.1" && git tag -a v1.0.1 -m "Platform 1.0.1" && git tag -f v1
git push origin main --follow-tags && git push -f origin v1
```

Renovate (preset `default.json`) podbije piny `@dominiksienkiewicz/*` / `pl.seniordeveloper:catalog`
w repo konsumenckich; ref `@v1` w callerach łapie patch/minor automatycznie.
