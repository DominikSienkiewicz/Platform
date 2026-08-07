# Releasing Platform

Model: **publish-only + deliberate versioning**. GitHub Packages to **jedyne źródło prawdy**
(Maven + npm). Jedna wersja `platformVersion` w `gradle/build-logic/gradle.properties` — ta sama
na GitHub Packages i w pinach konsumentów. `release.yml` publikuje **tę** wersję, wyzwalany
**świadomie** (tag `v*` lub `workflow_dispatch`). Brak auto-bumpu i brak auto-prune.

Reusable workflows w repo konsumenckich wskazują **`@v1`** (ruchomy tag majora w gicie — niezależny
od wersji artefaktów). Konsumenci trzymają **DOKŁADNE** piny; podbija je `platform-bump.sh` lub Renovate.

Aktualna wersja: **1.1.0**.

## Setup jednorazowy (raz na maszynę / repo)

```bash
# A) Lokalne poświadczenia do GitHub Packages (Gradle czyta je automatycznie):
#    ~/.gradle/gradle.properties
gpr.user=DominikSienkiewicz
gpr.key=<PAT classic: read:packages>          # do publikacji dodaj też write:packages

# B) npm lokalnie — token w env (project .npmrc czyta ${GITHUB_TOKEN}):
export GITHUB_TOKEN=<PAT: read:packages>       # w ~/.zshrc lub sourcowanym, gitignorowanym pliku

# C) Sekrety w repo konsumentów (CI): GPR_TOKEN = PAT (read:packages).
# D) Ruchomy tag v1 dla reusable workflows (raz):
git tag -f v1 && git push -f origin v1
```

## Wydanie (świadome) — jedną komendą

```bash
cd Platform
./release.sh "fix: opis zmiany"          # patch +0.0.1 od aktualnej wersji
./release.sh "feat: opis" 1.2.0          # konkretna wersja
```

`release.sh` bumpuje `platformVersion` we wszystkich miejscach (3× gradle.properties + lustro
defaultu w catalogu), commituje TWOIM message, taguje `vX.Y.Z`, pcha branch + tag (Release publikuje
Maven+npm) i przesuwa ruchomy `v1`. Pyta o potwierdzenie (tag = wersja immutable); `-y` pomija pytanie.

Ręcznie (równoważnie):

```bash
# bump platformVersion w 3 gradle.properties + getOrElse("X.Y.Z") w gradle/catalog/build.gradle.kts
git add -A && git commit -m "release: platform X.Y.Z" && git push
git tag vX.Y.Z && git push origin vX.Y.Z        # albo: Actions → Release → Run workflow
git tag -f v1  && git push -f origin v1          # ruchomy major dla reusable workflows
```

Release publikuje Maven (`catalog`, `build-logic`, `test-fixtures`) + npm (5 paczek) w wersji
`platformVersion`. Publish jest **idempotentny** (istniejąca wersja = 409 tolerowane), więc re-run
jest bezpieczny. Wersje są **immutable** — nie nadpiszesz istniejącej; błąd w wydaniu = nowa wersja.

## Konsumenci — jak skorzystać z nowej wersji

```bash
cd <Attestate|SkillSprintPlus|BookOfStyling>
./platform-bump.sh            # podbija piny (catalog + pluginy + npm) do najnowszej z GitHub Packages
# albo: ./platform-bump.sh 1.2.0   (konkretna wersja)
git add -A && git commit -m "build: Platform -> X.Y.Z" && git push
```

`platform-bump.sh` odpytuje GitHub Packages o najnowszą wersję `catalog`, podmienia piny w
`backend/settings.gradle.kts`, `backend/build.gradle.kts` i `frontend/package.json`, oraz regeneruje
`package-lock.json`. Token bierze z `GPR_TOKEN`/`GITHUB_TOKEN` lub `gpr.key`.

Na koniec regeneruje też zamrożony stan backendu: `gradle.lockfile`, a w repo z włączoną weryfikacją
zależności — `gradle/verification-metadata.xml`. Ten drugi wariant leci z `--refresh-dependencies`,
więc **trwa wyraźnie dłużej** (pełne pobranie metadanych). To celowe: przy ciepłym cache Gradle nie
dotyka plików `.module`, ich checksumy nie trafiłyby do metadanych, a CI na zimnym cache wywaliłby się
na `Dependency verification failed`. Skrypt nie commituje — diff zostaje do recenzji.

Pierwszy build po bumpie pobiera artefakty z GitHub Packages **raz** i cache'uje je w
`~/.gradle/caches` (Gradle) / `node_modules` + lockfile (npm). Kolejne buildy idą z cache — bez sieci.
**Nie ma `mavenLocal` ani `npm link`** (publish-only: zero driftu local↔CI).

## Retencja pakietów

Brak auto-prune (ani w `release.yml`, ani z crona). Storage Packages jest współdzielony z Actions,
ale przy tej skali (KB–MB) nieistotny. Sprzątanie świadome:
**Actions → Cleanup old package versions → Run workflow** (`keep`, domyślnie 10). Wymaga sekretu
`PACKAGES_ADMIN_TOKEN` (PAT classic: `read:packages` + `delete:packages`). ⚠️ Nie kasuj wersji, którą
któryś konsument jeszcze pinuje.
